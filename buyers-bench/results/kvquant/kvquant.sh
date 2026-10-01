#!/usr/bin/env bash
# KV-cache quantization (agent-inbox 2026-10-01-kvquant-context.md), after the Gemma 6-expert run:
#  1 context ceiling: does it LOAD at f16 / q8_0 / q4_0 KV (K and V both), and VRAM used -- Qwen3.6 + Muse Glimmer on the
#    V100, Bonsai on the 4070
#  2 Mistral 32K split: K-only q8_0 (quantized V needs flash attention, which crashes Mistral) -- what binds?
#  3 perplexity, Qwen3.6, wikitext-2, 16K chunks, f16 vs q8_0 vs q4_0;  4 HumanEval greedy at q8_0 / q4_0
#  5 speed at 32K depth (llama-bench -d 32768), Qwen3.6 and Glimmer
set -u
cd ~/buyers-bench; O=kvquant; mkdir -p $O; PORT=8076; BIN=~/bonsai/llama.cpp/build/bin; PY=~/ember-voice-train/.venv/bin/python
V100="CUDA_DEVICE_ORDER=PCI_BUS_ID CUDA_VISIBLE_DEVICES=1"; RTX="CUDA_DEVICE_ORDER=PCI_BUS_ID CUDA_VISIBLE_DEVICES=0"
BOTH="CUDA_DEVICE_ORDER=PCI_BUS_ID CUDA_VISIBLE_DEVICES=1,0"
Q=/mnt/steam/models/qwen36/Qwen3.6-35B-A3B-UD-Q4_K_M.gguf; GL=/mnt/steam/models/glimmer/Muse-Glimmer-30B-UD-Q4_K_XL.gguf
BO=/home/chris/bonsai/Ternary-Bonsai-2-27B-PQ2_0.gguf; MI=/mnt/steam/models/mistral4/Mistral-Small-4-119B-2603-UD-IQ2_M.gguf
WIKI=/home/chris/bonsai/corpus/wikitext-2-raw/wiki.test.raw
stop() { P=$(ss -ltnpH "( sport = :$PORT )" | grep -o "pid=[0-9]*" | cut -d= -f2 | sort -u); [ -n "$P" ] && kill $P
         for i in $(seq 30); do [ -z "$(ss -ltnH "( sport = :$PORT )")" ] && break; sleep 1; done; }
trap stop EXIT
while ! grep -q INBOX-DONE ~/buyers-bench/bonsai-recheck/log 2>/dev/null; do sleep 60; done
curl -s -m 30 http://127.0.0.1:8040/unload > /dev/null; sleep 10
echo "model,card,ctx,kv,loaded,vram_mib,note" > $O/ceiling.csv
load() {  # name envvar gpu_index model ctx kv extra...
  local N=$1 E=$2 GI=$3 M=$4 C=$5 KV=$6; shift 6
  local KVF; [ $KV = f16 ] && KVF="" || KVF="-ctk $KV -ctv $KV"
  env $E setsid nohup $BIN/llama-server -m $M -ngl 99 -c $C -np 1 --jinja --cache-ram 0 $KVF "$@" --host 127.0.0.1 --port $PORT > $O/load-$N-$C-$KV.log 2>&1 < /dev/null &
  local ok=no; for i in $(seq 120); do curl -sf localhost:$PORT/health > /dev/null && { ok=yes; break; }; grep -q -E "exiting due to|failed to create" $O/load-$N-$C-$KV.log && break; sleep 3; done
  local mib=$(nvidia-smi -i $GI --query-gpu=memory.used --format=csv,noheader,nounits)
  local note=$(grep -m1 -o -E "cudaMalloc failed: out of memory|requires Flash Attention|requires flash_attn|failed to allocate [a-zA-Z ]*" $O/load-$N-$C-$KV.log)
  echo "$N,$GI,$C,$KV,$ok,$mib,$note" >> $O/ceiling.csv; stop; sleep 3
}
for C in 131072 196608 262144; do for KV in f16 q8_0 q4_0; do load qwen36 "$V100" 1 $Q $C $KV -fa on; done; done
for C in 65536 131072; do for KV in f16 q8_0 q4_0; do load glimmer "$V100" 1 $GL $C $KV -fa on; done; done
for C in 32768 65536 131072; do for KV in f16 q8_0 q4_0; do load bonsai "$RTX" 0 $BO $C $KV -fa on; done; done
# 2 Mistral: f16 vs K-only q8 at 32K (V can't be quantized without flash attention)
load mistral4 "$BOTH" 1 $MI 32768 f16 -fa off -ts 75/25
env $BOTH setsid nohup $BIN/llama-server -m $MI -ngl 99 -c 32768 -np 1 --jinja --cache-ram 0 -ctk q8_0 -fa off -ts 75/25 --host 127.0.0.1 --port $PORT > $O/load-mistral4-32768-k8.log 2>&1 < /dev/null &
ok=no; for i in $(seq 120); do curl -sf localhost:$PORT/health > /dev/null && { ok=yes; break; }; grep -q -E "exiting due to|failed to create" $O/load-mistral4-32768-k8.log && break; sleep 3; done
echo "mistral4,1+0,32768,k-only-q8_0,$ok,$(nvidia-smi -i 0 --query-gpu=memory.used --format=csv,noheader,nounits),$(grep -m1 -o -E "cudaMalloc failed: out of memory|allocating [0-9.]+ MiB on device [0-9]" $O/load-mistral4-32768-k8.log)" >> $O/ceiling.csv; stop; sleep 3
# 3 perplexity
for KV in f16 q8_0 q4_0; do
  KVF=$([ $KV = f16 ] && echo "" || echo "-ctk $KV -ctv $KV")
  env $V100 $BIN/llama-perplexity -m $Q -ngl 99 -fa on -c 16384 -b 2048 -ub 512 $KVF -f $WIKI > $O/ppl-$KV.log 2>&1
  echo "$KV $(grep -o "Final estimate: PPL = [0-9.]* +/- [0-9.]*" $O/ppl-$KV.log)" >> $O/ppl.txt
done
# 4 HumanEval greedy at q8_0 / q4_0 (baseline: greedy f16 = 153/164, buyers-bench sweep)
for KV in q8_0 q4_0; do
  env $V100 setsid nohup $BIN/llama-server -m $Q -ngl 99 -fa on -c 32768 -np 1 --jinja --cache-ram 0 -ctk $KV -ctv $KV --reasoning off \
    --host 127.0.0.1 --port $PORT > $O/he-$KV-server.log 2>&1 < /dev/null &
  for i in $(seq 100); do curl -sf localhost:$PORT/health > /dev/null && break; sleep 3; done
  $PY humaneval_timed.py kv-$KV $PORT x 0 > $O/humaneval-kv-$KV.progress 2>&1; mv humaneval-kv-$KV.jsonl $O/ 2>/dev/null
  stop; sleep 3
done
# 5 speed at 32K depth
for M in $Q $GL; do
  env $V100 $BIN/llama-bench -m $M -ngl 99 -fa 1 -p 512 -n 128 -d 32768 -ctk f16,q8_0,q4_0 -ctv f16,q8_0,q4_0 -r 2 -o csv > $O/speed-$(basename $M .gguf).csv 2> $O/speed-$(basename $M .gguf).err
done
echo KV-DONE > $O/done
