#!/usr/bin/env bash
# Chris 2026-10-01: LFM2-24B-A2B (Q8_0, V100) with an 8B drafting for it on the 4070 vs the 24B alone.
# Same 12 greedy prompts as the DFlash test (dflash_probe2.py, thinking off -- the 24B has none).
set -u; exec 9>/tmp/spec-lfm.lock; flock -n 9 || { echo "already running"; exit 1; }
O=~/buyers-bench/lfm; M=/mnt/steam/models/lfm2; B=~/bonsai/llama.cpp/build/bin; PY=~/ember-voice-train/.venv/bin/python
until grep -q LFM-GW-DONE $O/log 2>/dev/null; do sleep 60; done
until [ "$(stat -c %s $M/LFM2-8B-A1B-Q4_K_M.gguf 2>/dev/null)" = 5044779712 ]; do sleep 30; done
stop() { local P=$(ss -ltnpH "( sport = :8070 )" | grep -o "pid=[0-9]*" | cut -d= -f2 | sort -u); [ -n "$P" ] && kill $P
         for i in $(seq 30); do [ -z "$(ss -ltnH "( sport = :8070 )")" ] && break; sleep 1; done; }
run() {  # label extra-args...
  local L=$1; shift; echo "$(date +%T) == $L" >> $O/spec.log
  CUDA_DEVICE_ORDER=PCI_BUS_ID CUDA_VISIBLE_DEVICES=1,0 setsid nohup $B/llama-server -m $M/LFM2-24B-A2B-Q8_0.gguf -dev CUDA0 -ngl 99 \
    -fa on -c 16384 -np 1 --jinja --cache-ram 0 --host 127.0.0.1 --port 8070 "$@" > $O/spec-$L-server.log 2>&1 < /dev/null &
  for i in $(seq 100); do curl -sf localhost:8070/health > /dev/null && break; sleep 3; done
  if curl -sf localhost:8070/health > /dev/null; then (cd ~/buyers-bench && $PY dflash_probe2.py spec-$L 0 >> $O/spec.log 2>&1)
  else echo "   SERVER FAILED: $(grep -m2 -iE 'error|not supported|incompatible|vocab' $O/spec-$L-server.log | tr '\n' ' ')" >> $O/spec.log; fi
  stop; sleep 3; }
run plain
run draft-lfm2-8b   -md $M/LFM2-8B-A1B-Q4_K_M.gguf   -devd CUDA1 -ngld all --spec-type draft-simple --spec-draft-n-max 8
run draft-lfm25-8b  -md $M/LFM2.5-8B-A1B-Q4_K_M.gguf -devd CUDA1 -ngld all --spec-type draft-simple --spec-draft-n-max 8
$PY ~/buyers-bench/spec-compare.py >> $O/spec.log 2>&1
echo SPEC-DONE >> $O/spec.log
