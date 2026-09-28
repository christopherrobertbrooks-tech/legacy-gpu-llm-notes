#!/usr/bin/env bash
# Watts while generating, per model and card. Samples the whole decode-only run
# at 100 ms and averages the samples above idle + 40 W, so model loading and the
# tail don't dilute it. (First version sampled a fixed window that small models
# had already finished by -- it measured an idle card.)
set -u
exec 9>/tmp/buyers-bench.lock; flock 9   # waits for run.sh to finish
B=~/bonsai/llama.cpp/build/bin/llama-bench; OUT=~/buyers-bench
idx() { nvidia-smi --query-gpu=index,name --format=csv,noheader | grep "$1" | cut -d, -f1; }
V100=$(idx V100); RTX=$(idx 4070)
for f in $OUT/*.csv; do
  case $f in *.power.csv) continue;; esac
  tag=$(basename $f .csv); card=${tag##*-}; g=$([ $card = V100 ] && echo $V100 || echo $RTX)
  path=$(sed -n 2p $f | awk -F'","' '{print $6}'); [ -n "$path" ] || continue
  idle=$(nvidia-smi -i $g --query-gpu=power.draw --format=csv,noheader,nounits | cut -d. -f1)
  nvidia-smi -i $g --query-gpu=power.draw --format=csv,noheader,nounits -lms 100 > $OUT/.w & p=$!
  CUDA_VISIBLE_DEVICES=$g $B -m "$path" -ngl 99 -fa on -p 0 -n 2048 -r 1 -o csv > $OUT/$tag.power.csv 2>/dev/null
  kill $p; w=$(awk -v t=$((idle+40)) '$1>t{s+=$1;n++} END{if(n) printf "%.0f", s/n; else print "?"}' $OUT/.w)
  echo "$w" > $OUT/$tag.watts; echo "$(date +%T) $tag: idle ${idle} W, generating ${w} W"
done
echo "$(date +%T) POWER DONE"
