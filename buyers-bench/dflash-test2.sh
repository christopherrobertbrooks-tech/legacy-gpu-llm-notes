#!/usr/bin/env bash
# DFlash on Qwen3.6 (the builder), V100 alone: plain vs z-lab drafter, thinking off and on.
cd ~/buyers-bench
M=/mnt/steam/models/qwen36/Qwen3.6-35B-A3B-UD-Q4_K_M.gguf; DR=/mnt/steam/models/qwen36/qwen36-dflash-f16.gguf
curl -s -m 30 http://127.0.0.1:8040/unload > /dev/null; sleep 5
run() {  # $1 label, rest = extra flags
  local L=$1; shift
  CUDA_DEVICE_ORDER=PCI_BUS_ID CUDA_VISIBLE_DEVICES=1 setsid nohup ~/bonsai/llama.cpp/build/bin/llama-server -m $M \
    -ngl 99 -c 32768 -np 1 --jinja --reasoning-budget 4096 --host 127.0.0.1 --port 8070 "$@" > df2-$L-server.log 2>&1 < /dev/null &
  for i in $(seq 100); do curl -sf localhost:8070/health > /dev/null && break; sleep 3; done
  for th in 0 1; do ~/ember-voice-train/.venv/bin/python dflash_probe2.py $L $th > df2-$L-t$th.txt 2>&1; done
  local P=$(ss -ltnpH "( sport = :8070 )" | grep -o "pid=[0-9]*" | cut -d= -f2 | sort -u); [ -n "$P" ] && kill $P
  for i in $(seq 30); do [ -z "$(ss -ltnH "( sport = :8070 )")" ] && break; sleep 1; done
}
run plain
run dflash -md $DR --spec-type draft-dflash --spec-draft-n-max 16
for th in 0 1; do ~/ember-voice-train/.venv/bin/python dflash_probe2.py compare $th; done > df2-compare.txt 2>&1
echo DF2-DONE > df2.done
