#!/usr/bin/env bash
# Small MoE models on the GTX 1070, same settings as run.sh, CPU-portable build. Then the everyday-assistant tasks.
set -u
exec 9>/tmp/pascal-bench-moe.lock; flock -n 9 || { echo "already running"; exit 1; }
H=~/pascal-bench; B=$H/bin-port/llama-bench; O=$H/out; export LD_LIBRARY_PATH=$H/lib
until grep -q DL-DONE $H/dl-moe.log 2>/dev/null; do sleep 30; done; grep -q MISMATCH $H/dl-moe.log && { echo "download incomplete"; exit 1; }
avail() { awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo; }
swap() { free -m | awk '/Swap/{print $3}'; }
watts() { nvidia-smi -i 0 --query-gpu=power.draw --format=csv,noheader,nounits -lms 250 > $O/.w & local p=$!
          sleep $1; kill $p; awk '{s+=$1;n++} END{printf "%.0f", s/n}' $O/.w; }
wait_free() { while u=$(nvidia-smi -i 0 --query-gpu=memory.used --format=csv,noheader,nounits); [ "$u" -gt 900 ]; do
                echo "$(date +%T) 1070 busy (${u} MiB), waiting"; sleep 10; done; }
guard() { while kill -0 $1 2>/dev/null; do [ "$(avail)" -lt 2500 ] && { echo "   WATCHDOG: free memory $(avail) MiB, stopping"; kill $1; }; sleep 1; done; }
bench() { local tag=$1; shift; for d in 0 16384 32768; do
    rm -f $O/.part; $B "$@" -fa on -p 512 -n 128 -d $d -r 3 -o csv > $O/.part 2>> $O/$tag.err & local p=$!; guard $p; wait $p
    if grep -q '^"' $O/.part; then [ -s $O/$tag.csv ] && grep '^"' $O/.part >> $O/$tag.csv || cat $O/.part > $O/$tag.csv
    else echo "   depth $d FAILED: $(grep -m1 -iE 'out of memory|failed|error' $O/$tag.err)"; fi; done; }
power() { local tag=$1; shift; $B "$@" -fa on -p 0 -n 1024 -r 1 -o csv > $O/$tag.power.csv 2>/dev/null & local bp=$!
          sleep 12; local w=$(watts 10); wait $bp; echo "   decode W: $w"; echo "$w" > $O/$tag.watts; }
curl -s localhost:11434/api/generate -d '{"model":"qwen3.5:0.8b","keep_alive":0}' > /dev/null; sleep 5
echo "llama.cpp: $(cat $H/bin-port/COMMIT)  swap used at start: $(swap) MiB"
for m in "LFM2 8B-A1B Q4_K_M|lfm2-8b-a1b-q4" "Granite 4.0 H Tiny Q4_K_M|granite4-htiny-q4"; do
  IFS='|' read -r label f <<<"$m"; tag="$(echo $label | tr ' /' '__')-GTX1070"; rm -f $O/$tag.*
  wait_free; echo "$(date +%T) == $label"; bench $tag -m $H/models/$f.gguf -ngl 99; power $tag -m $H/models/$f.gguf -ngl 99
done
G=$H/models/gpt-oss-20b-mxfp4.gguf; tag=gpt-oss_20B_MXFP4-GTX1070-ncmoe; NOSS=""
for N in 4 6 8 10 12 14 16 18 20 24; do
  wait_free; echo "$(date +%T) == gpt-oss 20B, experts of $N layers in RAM (free $(avail) MiB, swap $(swap) MiB)"
  rm -f $O/.part; $B -m $G -ngl 99 -ncmoe $N -fa on -p 512 -n 128 -r 1 -o csv > $O/.part 2> $O/$tag$N.err & p=$!; guard $p; wait $p
  if grep -q '^"' $O/.part; then echo "   loads at $N"; NOSS=$N; rm -f $O/$tag$N.err; bench $tag$N -m $G -ngl 99 -ncmoe $N
     power $tag$N -m $G -ngl 99 -ncmoe $N; break
  else echo "   $N: $(grep -m1 -iE 'out of memory|failed|error' $O/$tag$N.err)"; fi
done
echo "$NOSS" > $O/gpt-oss-ncmoe.txt; echo "$(date +%T) bench DONE, swap used $(swap) MiB"
python3 $H/moe-jobs.py > $H/moe-jobs.log 2>&1; tail -2 $H/moe-jobs.log
curl -s localhost:11434/api/generate -d '{"model":"qwen3.5:0.8b","keep_alive":-1}' > /dev/null
echo "$(date +%T) MOE-DONE, swap used $(swap) MiB"
