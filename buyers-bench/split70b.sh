#!/usr/bin/env bash
# Llama 3.3 70B IQ4_XS (37.9 GB) split across V100 32GB + RTX 4070 12GB, -sm layer.
# Waits for the download, then the benchmark lock; refuses if a card is busy.
set -u
M=/mnt/steam/models/Llama-3.3-70B-Instruct-IQ4_XS.gguf; B=~/bonsai/llama.cpp/build/bin/llama-bench; OUT=~/buyers-bench
until grep -q "IQ4_XS.gguf$" ~/dl-70b.log 2>/dev/null; do grep -qi "error\|Traceback" ~/dl-70b.log && { echo "download failed"; exit 1; }; sleep 30; done
exec 9>/tmp/buyers-bench.lock; flock -n 9 || { echo "benchmark already running"; exit 1; }
for g in 0 1; do [ $(nvidia-smi -i $g --query-gpu=memory.used --format=csv,noheader,nounits) -lt 1500 ] || { echo "gpu $g busy"; exit 1; }; done
echo "$(date +%T) start"; nvidia-smi --query-gpu=index,power.draw,memory.used --format=csv,noheader -lms 250 > $OUT/.w70 & p=$!
$B -m $M -ngl 99 -fa on -sm layer -p 512 -n 128 -d 0,8192 -r 2 -o csv > $OUT/Llama-3.3-70B_IQ4_XS-split.csv 2> $OUT/Llama-3.3-70B_IQ4_XS-split.err \
  || echo "FAILED: $(grep -m1 -iE 'error|out of memory' $OUT/Llama-3.3-70B_IQ4_XS-split.err)"
kill $p
awk -F', ' '{w=$2+0; m=$3+0; if(m>M[$1])M[$1]=m; if(w>60){S[$1]+=w;N[$1]++}} END{for(g in M) printf "gpu %s: peak %d MiB, mean %.0f W under load\n", g, M[g], S[g]/N[g]}' $OUT/.w70
echo "$(date +%T) DONE"
