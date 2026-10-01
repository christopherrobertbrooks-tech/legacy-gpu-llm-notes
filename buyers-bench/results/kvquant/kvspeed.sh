#!/usr/bin/env bash
# Replacement for kvquant.sh's speed step: matched K/V types only (the original asked llama-bench for the full
# 3x3 cross product, ~2 h at 32K depth). Qwen f16/f16 is already measured; then writes the done flag the queue waits on.
set -u; cd ~/buyers-bench/kvquant; B=~/bonsai/llama.cpp/build/bin/llama-bench
V="env CUDA_DEVICE_ORDER=PCI_BUS_ID CUDA_VISIBLE_DEVICES=1"
Q=/mnt/steam/models/qwen36/Qwen3.6-35B-A3B-UD-Q4_K_M.gguf; GL=/mnt/steam/models/glimmer/Muse-Glimmer-30B-UD-Q4_K_XL.gguf
cp speed-qwen-f16-partial.csv speed-qwen36.csv
for kv in q8_0 q4_0; do $V $B -m $Q -ngl 99 -fa 1 -p 512 -n 128 -d 32768 -ctk $kv -ctv $kv -r 2 -o csv 2>> speed-qwen36.err | grep '^"' >> speed-qwen36.csv; done
echo "$(head -1 speed-qwen36.csv)" > speed-glimmer.csv
for kv in f16 q8_0 q4_0; do $V $B -m $GL -ngl 99 -fa 1 -p 512 -n 128 -d 32768 -ctk $kv -ctv $kv -r 2 -o csv 2>> speed-glimmer.err | grep '^"' >> speed-glimmer.csv; done
rm -f speed-Qwen3.6-35B-A3B-UD-Q4_K_M.csv speed-Qwen3.6-35B-A3B-UD-Q4_K_M.err
echo KV-DONE > done
