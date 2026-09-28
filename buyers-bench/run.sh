#!/usr/bin/env bash
# Buyer's benchmark: popular models on the V100 32GB (and the RTX 4070 where
# they fit), short and long context, plus watts while generating.
# Single instance (flock). Waits if anything else is on the card before a run,
# so a model ollama loads mid-queue can't pollute a number.
#   nohup ./run.sh > run.log 2>&1 &
set -u
exec 9>/tmp/buyers-bench.lock; flock -n 9 || { echo "already running"; exit 1; }
B=~/bonsai/llama.cpp/build/bin/llama-bench
OUT=~/buyers-bench; mkdir -p $OUT
idx() { nvidia-smi --query-gpu=index,name --format=csv,noheader | grep "$1" | cut -d, -f1; }
V100=$(idx V100); RTX=$(idx 4070)
MODELS=(  # label|path|fits on 12 GB
  "Qwen3.5 4B Q8_0|/mnt/steam/models/Qwen3.5-4B-Q8_0.gguf|y"
  "Qwen2.5-Coder 7B Q4_K_M|/mnt/steam/ollama-models/blobs/sha256-60e05f2100071479f596b964f89f510f057ce397ea22f2833a0cfe029bfc2463|y"
  "Gemma 4 12B QAT Q4|/mnt/steam/ollama-models/blobs/sha256-faff1a63667fac17ac5e777f47114688fcefea96e220e211aaa8d62c2c4561f1|y"
  "Ternary Bonsai 2 27B PQ2_0|$HOME/bonsai/Ternary-Bonsai-2-27B-PQ2_0.gguf|y"
  "Gemma 4 26B-A4B MoE Q4_K_M|$HOME/quant-sweep/gemma-4-26B-A4B-it-UD-Q4_K_M.gguf|n"
  "Gemma 4 26B-A4B MoE Q8_0|/mnt/steam/models/gemma-4-26B-A4B-it-Q8_0.gguf|n"
  "Qwen3.8 27B dense Q8_0|/mnt/steam/models/Qwen3.8-27B-Q8_0.gguf|n"
)
wait_free() {  # $1 = gpu index; our own runs are gone by now, so anything here is someone else
  while :; do
    u=$(nvidia-smi -i $1 --query-gpu=memory.used --format=csv,noheader,nounits)
    n=$(nvidia-smi -i $1 --query-compute-apps=pid --format=csv,noheader | wc -l)
    [ "$u" -lt 1500 ] && break
    [ "$1" = "$RTX" ] && [ "$n" -le 1 ] && [ "$u" -lt 1500 ] && break
    echo "$(date +%T) gpu $1 busy (${u} MiB), waiting"; sleep 60
  done
}
watts() {  # $1 gpu, $2 seconds -> mean W
  nvidia-smi -i $1 --query-gpu=power.draw --format=csv,noheader,nounits -lms 250 > $OUT/.w & p=$!
  sleep $2; kill $p; awk '{s+=$1;n++} END{printf "%.0f", s/n}' $OUT/.w
}
echo "llama.cpp: $(git -C ~/bonsai/llama.cpp log -1 --format='%h %s' | cut -c1-70)"
for g in $V100 $RTX; do wait_free $g; echo "idle W gpu $g: $(watts $g 15)"; done
for m in "${MODELS[@]}"; do
  IFS='|' read -r label path small <<<"$m"
  for g in $V100 $RTX; do
    [ "$g" = "$RTX" ] && [ "$small" != y ] && continue
    card=$([ "$g" = "$V100" ] && echo V100 || echo RTX4070); tag="$(echo $label | tr ' /' '__')-$card"
    wait_free $g; echo "$(date +%T) == $label on $card"
    CUDA_VISIBLE_DEVICES=$g $B -m "$path" -ngl 99 -fa on -p 512 -n 128 -d 0,16384,32768 -r 3 -o csv \
      > $OUT/$tag.csv 2> $OUT/$tag.err || echo "   FAILED: $(grep -m1 -iE 'error|out of memory' $OUT/$tag.err)"
    # decode-only pass while sampling power
    CUDA_VISIBLE_DEVICES=$g $B -m "$path" -ngl 99 -fa on -p 0 -n 1024 -r 1 -o csv > $OUT/$tag.power.csv 2>/dev/null &
    bp=$!; sleep 12; w=$(watts $g 10); wait $bp
    echo "   decode W: $w"; echo "$w" > $OUT/$tag.watts
    grep -h '"' $OUT/$tag.csv | awk -F'","' '{print "   " $0}' | cut -c1-0 >/dev/null
  done
done
echo "$(date +%T) DONE"
