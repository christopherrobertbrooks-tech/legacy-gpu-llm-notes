#!/usr/bin/env bash
# Power-limit sweep on the V100 with Qwen3.6 35B-A3B Q4 (the builder) loaded ONCE in llama-server; the limit is
# changed between rounds. Each round: 6 requests (~2,000-token coding prompt, 512 generated tokens, greedy),
# sampling power / temperature / SM clock / ENFORCED limit every 200 ms. Speeds from the server's own timings.
# Restores 250 W and persistence off at the end, even on error.
set -u
cd ~/buyers-bench; OUT=powerlimit; rm -rf $OUT; mkdir -p $OUT
G=1; M=/mnt/steam/models/qwen36/Qwen3.6-35B-A3B-UD-Q4_K_M.gguf; PORT=8071
restore() {
  P=$(ss -ltnpH "( sport = :$PORT )" | grep -o "pid=[0-9]*" | cut -d= -f2 | sort -u); [ -n "$P" ] && kill $P
  sudo -n nvidia-smi -i $G -pl 250 > /dev/null; sudo -n nvidia-smi -i $G -pm 0 > /dev/null
  echo "$(date +%T) restored 250 W, persistence off" >> $OUT/run.log; }
trap restore EXIT
curl -s -m 30 http://127.0.0.1:8040/unload > /dev/null; sleep 5
sudo -n nvidia-smi -i $G -pm 1 > /dev/null
CUDA_DEVICE_ORDER=PCI_BUS_ID CUDA_VISIBLE_DEVICES=$G setsid nohup ~/bonsai/llama.cpp/build/bin/llama-server -m $M -ngl 99 -fa on \
  -c 8192 -np 1 --jinja --cache-ram 0 --reasoning off --host 127.0.0.1 --port $PORT > $OUT/server.log 2>&1 < /dev/null &
for i in $(seq 100); do curl -sf localhost:$PORT/health > /dev/null && break; sleep 3; done
echo "limit_w,avg_w,max_w,max_temp_c,end_temp_c,avg_sm_mhz,enforced_w,prefill_tok_s,decode_tok_s" > $OUT/summary.csv
for L in 250 200 175 150 125 100; do
  sudo -n nvidia-smi -i $G -pl $L > /dev/null; sleep 2
  nvidia-smi -i $G --query-gpu=power.draw,temperature.gpu,clocks.sm,enforced.power.limit --format=csv,noheader,nounits -lms 200 > $OUT/samples-$L.csv & S=$!
  R=$(~/ember-voice-train/.venv/bin/python - $PORT <<'PY'
import json, sys, urllib.request, statistics as st
port = sys.argv[1]
code = open("/home/chris/buyers-bench/humaneval.py").read()
prompt = "Here is a Python benchmark script:\n\n" + code[:7000] + "\n\nExplain what it does, then rewrite it with clearer structure."
pp, tg = [], []
for i in range(6):
    body = {"messages": [{"role": "user", "content": prompt + f" (variant {i})"}], "temperature": 0, "max_tokens": 512}
    d = json.load(urllib.request.urlopen(urllib.request.Request(f"http://127.0.0.1:{port}/v1/chat/completions",
          data=json.dumps(body).encode(), headers={"Content-Type": "application/json"}), timeout=900))
    t = d["timings"]; pp.append(t["prompt_per_second"]); tg.append(t["predicted_per_second"])
print(f"{st.median(pp):.0f},{st.median(tg):.1f}")
PY
)
  kill $S; wait $S 2>/dev/null
  awk -F', *' -v L=$L -v R="$R" '$1>60 {s+=$1; n++; if($1>mx) mx=$1; c+=$3} {if($2>mt) mt=$2; et=$2; e=$4}
    END {printf "%s,%.0f,%.0f,%d,%d,%.0f,%.0f,%s\n", L, (n?s/n:0), mx, mt, et, (n?c/n:0), e, R}' $OUT/samples-$L.csv >> $OUT/summary.csv
  echo "$(date +%T) $L W done: $R" >> $OUT/run.log
done
echo DONE >> $OUT/run.log
