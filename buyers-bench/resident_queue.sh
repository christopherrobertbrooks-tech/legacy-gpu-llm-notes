#!/usr/bin/env bash
# After the 70B split bench: speed + HumanEval for each model, in order,
# each waiting for its download. One llama-server at a time on :8050,
# stopped and confirmed dead before the next.
set -u
until grep -qE "QUEUE DONE" ~/buyers-bench-moe.log 2>/dev/null; do sleep 30; done  # after the MoE queue
exec 9>/tmp/buyers-bench.lock; flock 9
BIN=~/bonsai/llama.cpp/build/bin; OUT=~/buyers-bench; M=/mnt/steam/models; PY=~/bonsai/trainvenv/bin/python
V100=$(nvidia-smi --query-gpu=index,name --format=csv,noheader | grep V100 | cut -d, -f1)
RUNS=(  # the models from the speed runs, coding test only (speeds already measured)
  "qwen3.5-4b-Q8_0|$M/Qwen3.5-4B-Q8_0.gguf|v100|n"
  "gemma4-12b-qat-Q4|/mnt/steam/ollama-models/blobs/sha256-faff1a63667fac17ac5e777f47114688fcefea96e220e211aaa8d62c2c4561f1|v100|n"
  "bonsai2-27b-PQ2_0|$HOME/bonsai/Ternary-Bonsai-2-27B-PQ2_0.gguf|v100|n"
  "gemma4-26b-a4b-Q4_K_M|$HOME/quant-sweep/gemma-4-26B-A4B-it-UD-Q4_K_M.gguf|v100|n"
  "gemma4-26b-a4b-Q8_0|$M/gemma-4-26B-A4B-it-Q8_0.gguf|v100|n"
  "qwen3.8-27b-Q8_0|$M/Qwen3.8-27B-Q8_0.gguf|v100|n"
)
for r in "${RUNS[@]}"; do
  IFS='|' read -r label file cards speed <<<"$r"
  until [ -f "$file" ] && ! pgrep -f "[h]f_hub_download.*$(basename $file)" >/dev/null; do
    grep -q "FAILED $(basename $file)" ~/dl-moe.log 2>/dev/null && { echo "skip $label: download failed"; continue 2; }; sleep 60; done
  if [ $cards = v100 ]; then dev=$V100; sm=""; else dev=0,1; sm="-sm layer"; fi
  echo "$(date +%T) == $label ($cards)"
  if [ $speed = y ]; then
    CUDA_VISIBLE_DEVICES=$dev $BIN/llama-bench -m $file -ngl 99 -fa on $sm -p 512 -n 128 -d 0,16384 -r 2 -o csv > $OUT/$label.speed.csv 2> $OUT/$label.speed.err \
      && $PY -c "import csv,sys;[print('   %s d%s %.1f t/s'%('pp512' if int(r['n_prompt']) else 'tg128',r['n_depth'],float(r['avg_ts']))) for r in csv.DictReader(open(sys.argv[1]))]" $OUT/$label.speed.csv \
      || echo "   speed FAILED: $(grep -m1 -iE 'error|memory' $OUT/$label.speed.err)"
  fi
  CUDA_VISIBLE_DEVICES=$dev nohup $BIN/llama-server -m $file -ngl 99 -fa on $sm -c 8192 -np 1 --host 127.0.0.1 --port 8050 > $OUT/$label.server.log 2>&1 &
  sp=$!
  for i in $(seq 120); do curl -sf localhost:8050/health >/dev/null && break; kill -0 $sp 2>/dev/null || break; sleep 5; done
  if curl -sf localhost:8050/health >/dev/null; then $PY $OUT/humaneval.py $label 8050 2>&1 | grep -v "^  "; else echo "   server FAILED: $(grep -m1 -iE 'error|memory' $OUT/$label.server.log)"; fi
  kill $sp; for i in $(seq 30); do kill -0 $sp 2>/dev/null || break; sleep 1; done; kill -0 $sp 2>/dev/null && kill -9 $sp
done
echo "$(date +%T) RESIDENT QUEUE DONE"
