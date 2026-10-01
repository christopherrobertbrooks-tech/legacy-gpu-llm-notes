#!/usr/bin/env bash
# Buyer's benchmark on the GTX 1070 (8 GB, Pascal), same settings as buyers-bench/run.sh on the V100/4070:
# llama-bench -ngl 99 -fa on -p 512 -n 128 at depth 0 / 16K / 32K, -r 3, then a 1024-token decode pass while sampling watts.
# Depths run one at a time so an out-of-memory at 32K doesn't lose the rest. The MoE that doesn't fit keeps its
# experts in system RAM (-ncmoe); a watchdog stops the bench if the PC's free memory drops under 2.5 GB.
set -u
exec 9>/tmp/pascal-bench.lock; flock -n 9 || { echo "already running"; exit 1; }
H=~/pascal-bench; B=$H/bin/llama-bench; O=$H/out; export LD_LIBRARY_PATH=$H/lib
MODELS=(
  "Qwen3.5 4B Q8_0|$H/models/qwen35-4b-q8.gguf"
  "Qwen2.5-Coder 7B Q4_K_M|$H/models/coder7b-q4.gguf"
  "Gemma 4 12B QAT Q4|$H/models/gemma12b-qat.gguf"
  "Ternary Bonsai 2 27B PQ2_0|$H/models/bonsai-pq2.gguf"
  "Ternary Bonsai 2 27B PTQ1_0|$H/models/bonsai-ptq1.gguf"
)
avail() { awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo; }
watts() { nvidia-smi -i 0 --query-gpu=power.draw --format=csv,noheader,nounits -lms 250 > $O/.w & local p=$!
          sleep $1; kill $p; awk '{s+=$1;n++} END{printf "%.0f", s/n}' $O/.w; }
wait_free() { while u=$(nvidia-smi -i 0 --query-gpu=memory.used --format=csv,noheader,nounits); [ "$u" -gt 900 ]; do
                echo "$(date +%T) 1070 busy (${u} MiB), waiting"; sleep 30; done; }
guard() { while kill -0 $1 2>/dev/null; do [ "$(avail)" -lt 2500 ] && { echo "   WATCHDOG: free memory $(avail) MiB, stopping"; kill $1; }; sleep 1; done; }
bench() {  # tag args...  -> appends rows to $O/tag.csv
  local tag=$1; shift; for d in 0 16384 32768; do
    $B "$@" -fa on -p 512 -n 128 -d $d -r 3 -o csv > $O/.part 2>> $O/$tag.err & local p=$!; guard $p; wait $p
    if [ -s $O/.part ]; then [ -s $O/$tag.csv ] && tail -n +2 $O/.part >> $O/$tag.csv || cat $O/.part > $O/$tag.csv
    else echo "   depth $d FAILED: $(grep -m1 -iE 'out of memory|failed|error' $O/$tag.err)"; fi
  done; }
echo "llama.cpp: $(cat $H/bin/COMMIT)  driver: $(nvidia-smi --query-gpu=driver_version --format=csv,noheader)"
wait_free; echo "idle W: $(watts 15)"
for m in "${MODELS[@]}"; do
  IFS='|' read -r label path <<<"$m"; tag="$(echo $label | tr ' /' '__')-GTX1070"
  [ -e "$path" ] || { echo "$(date +%T) == $label SKIPPED: model not copied"; continue; }
  wait_free; echo "$(date +%T) == $label"; rm -f $O/$tag.csv $O/$tag.err
  bench $tag -m "$path" -ngl 99
  $B -m "$path" -ngl 99 -fa on -p 0 -n 1024 -r 1 -o csv > $O/$tag.power.csv 2>/dev/null & bp=$!
  sleep 12; w=$(watts 10); wait $bp; echo "   decode W: $w"; echo "$w" > $O/$tag.watts
done
# the MoE that doesn't fit: experts of the first N layers stay in system RAM; find the smallest N that loads
G=$H/models/gemma26b-a4b-q4.gguf; tag=Gemma_4_26B-A4B_MoE_Q4_K_M-GTX1070-ncmoe
if [ ! -e $G ]; then echo "== Gemma 26B-A4B SKIPPED: model not copied"
elif [ "$(avail)" -lt 12000 ]; then echo "== Gemma 26B-A4B SKIPPED: only $(avail) MiB free memory (needs 12000)"
else
  for N in 14 18 22 26 30; do
    wait_free; echo "$(date +%T) == Gemma 26B-A4B Q4, experts of $N layers in RAM (free $(avail) MiB)"
    rm -f $O/.part; $B -m $G -ngl 99 -ncmoe $N -fa on -p 512 -n 128 -r 2 -o csv > $O/.part 2> $O/$tag$N.err & p=$!; guard $p; wait $p
    if grep -q '"' $O/.part; then cp $O/.part $O/$tag$N.csv; echo "   loads at $N"
      rm -f $O/$tag$N.csv; bench $tag$N -m $G -ngl 99 -ncmoe $N; break
    else echo "   $N: $(grep -m1 -iE 'out of memory|failed|error' $O/$tag$N.err)"; fi
  done
fi
echo "$(date +%T) DONE"
