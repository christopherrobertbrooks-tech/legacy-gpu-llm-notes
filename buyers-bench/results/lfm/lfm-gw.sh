#!/usr/bin/env bash
# LFM2 tests on the gateway, after the current queue (Chris 2026-10-01).
#   4070: LFM2.5-8B-A1B speed + the reviewer proof bake-off (prove.py runs on Dev-Console through a tunnel to :8060)
#   V100: LFM2-24B-A2B Q8_0 speed/power + HumanEval greedy; LFM2.5-8B speed for the three-card table
set -u; exec 9>/tmp/lfm-gw.lock; flock -n 9 || { echo "already running"; exit 1; }
O=~/buyers-bench/lfm; mkdir -p $O; B=~/bonsai/llama.cpp/build/bin; M=/mnt/steam/models/lfm2
S8=$M/LFM2.5-8B-A1B-Q4_K_M.gguf; L24=$M/LFM2-24B-A2B-Q8_0.gguf; PY=~/ember-voice-train/.venv/bin/python
idx() { nvidia-smi --query-gpu=index,name --format=csv,noheader | grep "$1" | cut -d, -f1; }
V=$(idx V100); R=$(idx 4070)
log() { echo "$(date +%T) $*" | tee -a $O/log; }
free_wait() { while u=$(nvidia-smi -i $1 --query-gpu=memory.used --format=csv,noheader,nounits); [ "$u" -gt 1500 ]; do sleep 30; done; }
stop_port() { local P=$(ss -ltnpH "( sport = :$1 )" | grep -o "pid=[0-9]*" | cut -d= -f2 | sort -u); [ -n "$P" ] && kill $P
              for i in $(seq 30); do [ -z "$(ss -ltnH "( sport = :$1 )")" ] && break; sleep 1; done; }
speed() {  # tag gpu model
  CUDA_VISIBLE_DEVICES=$2 $B/llama-bench -m $3 -ngl 99 -fa on -p 512 -n 128 -d 0,16384,32768 -r 3 -o csv > $O/$1.csv 2> $O/$1.err \
    || log "  $1 speed FAILED: $(grep -m1 -iE 'error|out of memory' $O/$1.err)"
  CUDA_VISIBLE_DEVICES=$2 $B/llama-bench -m $3 -ngl 99 -fa on -p 0 -n 4096 -r 1 -o csv > $O/$1.power.csv 2>/dev/null & local bp=$!
  sleep 10; nvidia-smi -i $2 --query-gpu=power.draw,utilization.gpu --format=csv,noheader,nounits -lms 250 > $O/.w & local wp=$!
  sleep 15; kill $wp; wait $bp; awk -F, '{s+=$1;u+=$2;n++} END{printf "%.0f W, busy %.0f%%\n", s/n, u/n}' $O/.w > $O/$1.watts; log "  $1: $(cat $O/$1.watts)"; }
until grep -q -E "DL-OK|DL-BAD" $M/dl.log 2>/dev/null; do sleep 30; done; grep -q DL-OK $M/dl.log || { log "download bad"; exit 1; }
# ---- 4070
until grep -q DONE ~/buyers-bench/power-recheck/4070.log 2>/dev/null; do sleep 30; done; free_wait $R
log "4070: LFM2.5-8B speed"; speed LFM2.5_8B-A1B_Q4_K_M-RTX4070 $R $S8
log "4070: reviewer server up (Bonsai's reviewer settings)"
CUDA_DEVICE_ORDER=PCI_BUS_ID CUDA_VISIBLE_DEVICES=$R setsid nohup $B/llama-server -m $S8 -ngl 99 -fa on -c 32768 -np 1 --jinja \
  --reasoning-budget 4096 --cache-ram 2048 --host 127.0.0.1 --port 8060 > $O/reviewer-server.log 2>&1 < /dev/null &
for i in $(seq 60); do curl -sf localhost:8060/health > /dev/null && break; sleep 3; done
curl -sf localhost:8060/health > /dev/null && touch $O/reviewer-ready || log "reviewer server FAILED: $(grep -m1 -iE 'error' $O/reviewer-server.log)"
[ -f $O/reviewer-ready ] && until [ -f $O/reviewer-done ]; do sleep 30; done
stop_port 8060; log "4070 done"
# ---- V100
until grep -q DONE ~/buyers-bench/power-recheck/V100.log 2>/dev/null; do sleep 30; done
curl -s -m 30 http://127.0.0.1:8040/unload > /dev/null; free_wait $V
log "V100: LFM2-24B-A2B Q8 speed"; speed LFM2-24B-A2B_Q8_0-V100 $V $L24
log "V100: LFM2.5-8B speed"; speed LFM2.5_8B-A1B_Q4_K_M-V100 $V $S8
log "V100: LFM2-24B HumanEval (greedy, no reasoning: it's an instruct model)"
CUDA_DEVICE_ORDER=PCI_BUS_ID CUDA_VISIBLE_DEVICES=$V setsid nohup $B/llama-server -m $L24 -ngl 99 -fa on -c 32768 -np 1 --jinja \
  --cache-ram 0 --host 127.0.0.1 --port 8077 > $O/he-server.log 2>&1 < /dev/null &
for i in $(seq 100); do curl -sf localhost:8077/health > /dev/null && break; sleep 3; done
cd ~/buyers-bench && $PY humaneval_timed.py lfm2-24b-a2b-q8 8077 x 0 > $O/humaneval.progress 2>&1
$PY regrade_dedent.py humaneval-lfm2-24b-a2b-q8.jsonl > $O/humaneval-fair.txt 2>&1; mv humaneval-lfm2-24b-a2b-q8.jsonl $O/
stop_port 8077; log "V100 done: $(cat $O/humaneval-fair.txt)"; echo LFM-GW-DONE >> $O/log
