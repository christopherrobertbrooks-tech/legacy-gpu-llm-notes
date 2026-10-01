#!/usr/bin/env bash
# Expert pilot (5 probes): Mistral 4 & 8 speed only (2K + 16K prompts), Ornith 1.5 at 8 and 12, Gemma at 6
# (HumanEval temperature 0, strict + fair, plus speed). Same server setup as expert-sweep.sh. Results: sweep/<model>.csv
set -u
cd ~/buyers-bench; S=sweep; mkdir -p $S; PORT=8074; PY=~/ember-voice-train/.venv/bin/python
stop() { P=$(ss -ltnpH "( sport = :$PORT )" | grep -o "pid=[0-9]*" | cut -d= -f2 | sort -u); [ -n "$P" ] && kill $P
         for i in $(seq 30); do [ -z "$(ss -ltnH "( sport = :$PORT )")" ] && break; sleep 1; done; }
trap stop EXIT
curl -s -m 30 http://127.0.0.1:8040/unload > /dev/null; sleep 5
V100="CUDA_DEVICE_ORDER=PCI_BUS_ID CUDA_VISIBLE_DEVICES=1"; BOTH="CUDA_DEVICE_ORDER=PCI_BUS_ID CUDA_VISIBLE_DEVICES=1,0"
speed() { $PY - $PORT <<'PYS'
import json, sys, urllib.request, statistics as st
port = sys.argv[1]
code = open("/home/chris/buyers-bench/humaneval.py").read()
def ask(text, n):
    body = {"messages": [{"role": "user", "content": text}], "temperature": 0, "max_tokens": n, "chat_template_kwargs": {"enable_thinking": False}}
    return json.load(urllib.request.urlopen(urllib.request.Request(f"http://127.0.0.1:{port}/v1/chat/completions", data=json.dumps(body).encode(),
           headers={"Content-Type": "application/json"}), timeout=3600))["timings"]
short = [ask("Explain this script, then rewrite it more clearly:\n\n" + code[:6000] + f"\n(v{i})", 512) for i in range(3)]
long = ask("Summarise these files in five bullet points:\n\n" + "\n\n".join(code for _ in range(5))[:60000] + "\n(long)", 64)
print(f"{st.median(t['prompt_per_second'] for t in short):.0f},{long['prompt_per_second']:.0f},{long['prompt_n']},{st.median(t['predicted_per_second'] for t in short):.1f}")
PYS
}
probe() {  # name env model key "extra" K humaneval(1/0)
  local NAME=$1 ENVV=$2 MODEL=$3 KEY=$4 EXTRA=$5 K=$6 HE=$7
  [ -f $S/$NAME.csv ] || echo "experts,strict,fair,prefill_2k,prefill_long,long_tokens,decode" > $S/$NAME.csv
  env $ENVV setsid nohup ~/bonsai/llama.cpp/build/bin/llama-server -m $MODEL -ngl 99 -c 32768 -np 1 --jinja --cache-ram 0 \
    $EXTRA --override-kv $KEY=int:$K --host 127.0.0.1 --port $PORT > $S/$NAME-e$K-server.log 2>&1 < /dev/null &
  for i in $(seq 150); do curl -sf localhost:$PORT/health > /dev/null && break; sleep 3; done
  if ! curl -sf localhost:$PORT/health > /dev/null; then echo "$K,LOAD-FAILED" >> $S/$NAME.csv; echo "$(date +%T) $NAME e$K LOAD FAILED" >> $S/pilot.log; stop; return; fi
  G=","
  if [ $HE = 1 ]; then
    $PY humaneval_timed.py sweep-$NAME-e$K $PORT x 0 > $S/humaneval-$NAME-e$K.progress 2>&1; mv humaneval-sweep-$NAME-e$K.jsonl $S/ 2>/dev/null
    G=$($PY regrade_dedent.py $S/humaneval-sweep-$NAME-e$K.jsonl | awk '{print $3","$5}' | sed 's|/164||g')
  fi
  SP=$(speed); echo "$K,$G,$SP" >> $S/$NAME.csv; echo "$(date +%T) $NAME e$K: HE $G | speed $SP" >> $S/pilot.log
  stop
}
MI=/mnt/steam/models/mistral4/Mistral-Small-4-119B-2603-UD-IQ2_M.gguf
MX='-fa off -ts 75/25 --chat-template-kwargs {"reasoning_effort":"none"}'
probe mistral4-speed "$BOTH" $MI mistral4.expert_used_count "$MX" 4 0
probe mistral4-speed "$BOTH" $MI mistral4.expert_used_count "$MX" 8 0
OR=/mnt/steam/models/ornith15/Ornith-1.5-35B-Q4_K_M.gguf
OX="-fa on --reasoning off --chat-template-file /mnt/steam/models/ornith15/chat_template.jinja"
probe ornith15 "$V100" $OR qwen35moe.expert_used_count "$OX" 8 1
probe ornith15 "$V100" $OR qwen35moe.expert_used_count "$OX" 12 1
probe gemma "$V100" /home/chris/quant-sweep/gemma-4-26B-A4B-it-UD-Q4_K_M.gguf gemma4.expert_used_count "-fa on --reasoning off" 6 1
echo PILOT-DONE >> $S/pilot.log
