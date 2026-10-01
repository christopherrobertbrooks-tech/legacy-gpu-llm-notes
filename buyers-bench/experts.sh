#!/usr/bin/env bash
# Qwen3.6 35B-A3B Q4 with 8 (as shipped), 4 and 16 active experts (--override-kv, no retraining), V100 alone.
# Same server flags and sampling as the builder entry (temp 0.6, top_p 0.95, top_k 20), thinking off, HumanEval
# with humaneval_timed.py, then a speed probe (3 x 512 tokens greedy, server timings).
set -u
cd ~/buyers-bench; PORT=8072; M=/mnt/steam/models/qwen36/Qwen3.6-35B-A3B-UD-Q4_K_M.gguf
stop() { P=$(ss -ltnpH "( sport = :$PORT )" | grep -o "pid=[0-9]*" | cut -d= -f2 | sort -u); [ -n "$P" ] && kill $P
         for i in $(seq 30); do [ -z "$(ss -ltnH "( sport = :$PORT )")" ] && break; sleep 1; done; }
trap stop EXIT
curl -s -m 30 http://127.0.0.1:8040/unload > /dev/null; sleep 5
for N in 8 4 16; do
  CUDA_DEVICE_ORDER=PCI_BUS_ID CUDA_VISIBLE_DEVICES=1 setsid nohup ~/bonsai/llama.cpp/build/bin/llama-server -m $M -ngl 99 -fa on \
    -c 32768 -np 1 --jinja --cache-ram 0 --temp 0.6 --top-p 0.95 --top-k 20 \
    --override-kv qwen35moe.expert_used_count=int:$N --host 127.0.0.1 --port $PORT > experts-e$N-server.log 2>&1 < /dev/null &
  for i in $(seq 100); do curl -sf localhost:$PORT/health > /dev/null && break; sleep 3; done
  grep -m1 -o "expert_used_count.*" experts-e$N-server.log > experts-e$N-kv.txt
  ~/ember-voice-train/.venv/bin/python humaneval_timed.py qwen36-e$N $PORT x 0 > humaneval-qwen36-e$N.progress 2>&1
  ~/ember-voice-train/.venv/bin/python - $PORT $N >> experts-speed.txt <<'PY'
import json, sys, urllib.request, statistics as st
port, n = sys.argv[1], sys.argv[2]
code = open("/home/chris/buyers-bench/humaneval.py").read()[:6000]
pp, tg = [], []
for i in range(3):
    body = {"messages": [{"role": "user", "content": "Explain this script, then rewrite it more clearly:\n\n" + code + f"\n(v{i})"}],
            "temperature": 0, "max_tokens": 512, "chat_template_kwargs": {"enable_thinking": False}}
    d = json.load(urllib.request.urlopen(urllib.request.Request(f"http://127.0.0.1:{port}/v1/chat/completions", data=json.dumps(body).encode(),
          headers={"Content-Type": "application/json"}), timeout=900))
    pp.append(d["timings"]["prompt_per_second"]); tg.append(d["timings"]["predicted_per_second"])
print(f"experts {n}: prefill {st.median(pp):.0f} tok/s, decode {st.median(tg):.1f} tok/s")
PY
  stop
done
echo EXPERTS-DONE > experts.done
