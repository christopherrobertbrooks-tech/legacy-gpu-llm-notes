#!/usr/bin/env bash
# llama.cpp RPC over Wi-Fi (Chris 2026-10-01, agent-inbox 2026-10-01-llamacpp-rpc.md). Runs from Dev-Console: the 1070 here
# serves as RPC0; llama-bench runs on ember-gateway. Order on the gateway: after the v2 V100 power pass, before DeepSWE.
set -u; exec 9>/tmp/rpc-queue.lock; flock -n 9 || { echo "already running"; exit 1; }
H=~/pascal-bench; LOG=$H/rpc/log; mkdir -p $H/rpc; LAN=192.168.0.53; TS=100.114.197.44
g() { ssh -n ember-gateway "$@" < /dev/null; }
log() { echo "$(date +%T) $*" | tee -a $LOG; }
until g 'grep -q DONE ~/buyers-bench/power-recheck/V100.log 2>/dev/null && grep -q DL-OK /mnt/steam/models/dl-70b.log && grep -q -E "DL-OK|DL-BAD" /mnt/steam/models/laguna/dl.log'; do sleep 60; done
g 'curl -s -m 30 localhost:8040/unload > /dev/null'
log "network (gateway -> this PC, Wi-Fi both ends)"
for ip in $LAN $TS; do
  python3 $H/sink.py $ip >> $LOG 2>&1 & sleep 1
  g "ping -c 30 -q $ip | tail -1; python3 -c \"
import socket; s=socket.create_connection(('$ip',50099),timeout=10); b=b'x'*(1<<20)
for _ in range(200): s.sendall(b)
s.close()\"" >> $LOG 2>&1; wait
done
curl -s localhost:11434/api/generate -d '{"model":"qwen3.5:0.8b","keep_alive":0}' > /dev/null; sleep 5
(cd $H && LD_LIBRARY_PATH=$H/lib setsid nohup bin-rpc/ggml-rpc-server -H $LAN -p 50052 -c > rpc/server.log 2>&1 < /dev/null &)
sleep 4; ss -ltnH "( sport = :50052 )" | grep -q 50052 || { log "rpc-server failed to start"; exit 1; }
B="cd ~/bonsai/llama.cpp/build-rpc/bin && CUDA_DEVICE_ORDER=PCI_BUS_ID CUDA_VISIBLE_DEVICES=1,0 ./llama-bench --rpc $LAN:50052 -ngl 99 -fa on -r 2 -o csv"
C7=/usr/share/ollama/.ollama/models/blobs/sha256-60e05f2100071479f596b964f89f510f057ce397ea22f2833a0cfe029bfc2463
G26=/mnt/steam/models/gemma-4-26B-A4B-it-Q8_0.gguf; L70=/mnt/steam/models/Llama-3.3-70B-Instruct-IQ4_XS.gguf
run() {  # tag model devices tensor-split extra
  local t0=$(date +%s); log "== $1 ($3 ${4:+-ts $4})"
  g "$B -m $2 -dev $3 ${4:+-ts $4} -p 512 -n 128 ${5:-}" > $H/rpc/$1.csv 2> $H/rpc/$1.err
  local n=$(grep -c '^"' $H/rpc/$1.csv); log "   $n rows in $(( $(date +%s) - t0 )) s $( [ $n = 0 ] && grep -m1 -iE 'error|out of memory|fail' $H/rpc/$1.err)"
  grep '^"' $H/rpc/$1.csv | awk -F'","' '{printf "   pp%s tg%s depth %s: %.1f t/s\n", $33, $34, $35, $39}' | tee -a $LOG; }
run coder7b-v100        $C7  CUDA0
run coder7b-v100+1070   $C7  CUDA0/RPC0 1/1
run coder7b-v100+1070-2 $C7  CUDA0/RPC0 1/1           # 2nd load: rpc-server's -c cache should skip the upload
run gemma26bq8-v100      $G26 CUDA0
run gemma26bq8-v100+1070 $G26 CUDA0/RPC0 26/6
run llama70b-v100+4070       $L70 CUDA0/CUDA1       "" "-d 0,8192"
run llama70b-v100+1070       $L70 CUDA0/RPC0  31/7  "-d 0,8192"
run llama70b-v100+4070+1070  $L70 CUDA0/CUDA1/RPC0 30/10/6 "-d 0,8192"
P=$(ss -ltnpH "( sport = :50052 )" | grep -o "pid=[0-9]*" | cut -d= -f2 | sort -u); [ -n "$P" ] && kill $P
curl -s localhost:11434/api/generate -d '{"model":"qwen3.5:0.8b","keep_alive":-1}' > /dev/null
log "swap used $(free -m | awk '/Swap/{print $3}') MiB; RPC-DONE"; g 'touch ~/deepswe-runs/rpc-done'
