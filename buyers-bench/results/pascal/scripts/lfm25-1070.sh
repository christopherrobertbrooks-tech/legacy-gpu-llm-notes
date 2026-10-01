#!/usr/bin/env bash
# LFM2.5-8B-A1B on the 1070: same speed test, a 4,096-token power pass sampled 10-25 s, then the assistant tasks
set -u; exec 9>/tmp/pascal-bench-lfm25.lock; flock -n 9 || { echo "already running"; exit 1; }
H=~/pascal-bench; B=$H/bin-port/llama-bench; O=$H/out; export LD_LIBRARY_PATH=$H/lib; M=$H/models/lfm25-8b-a1b-q4.gguf
T=LFM2.5_8B-A1B_Q4_K_M-GTX1070
until grep -q -E "DL-OK|DL-BAD" $H/dl-lfm25.log 2>/dev/null; do sleep 20; done; grep -q DL-OK $H/dl-lfm25.log || { echo "download bad"; exit 1; }
curl -s localhost:11434/api/generate -d '{"model":"qwen3.5:0.8b","keep_alive":0}' > /dev/null; sleep 6
rm -f $O/$T.*; for d in 0 16384 32768; do $B -m $M -ngl 99 -fa on -p 512 -n 128 -d $d -r 3 -o csv > $O/.part 2>> $O/$T.err
  [ -s $O/$T.csv ] && grep '^"' $O/.part >> $O/$T.csv || cat $O/.part > $O/$T.csv; done
$B -m $M -ngl 99 -fa on -p 0 -n 4096 -r 1 -o csv > $O/$T.power.csv 2>/dev/null & bp=$!
sleep 10; nvidia-smi -i 0 --query-gpu=power.draw,utilization.gpu --format=csv,noheader,nounits -lms 250 > $O/.w & wp=$!
sleep 15; kill $wp; wait $bp; awk -F, '{s+=$1;n++} END{printf "%.0f", s/n}' $O/.w > $O/$T.watts
echo "speed done, $(cat $O/$T.watts) W"
python3 - <<'PY'
import json, os, subprocess, time, urllib.request
H = os.path.expanduser("~/pascal-bench"); OUT = f"{H}/jobs"; src = open(f"{H}/jobs.py").read()
TASKS = eval(src.split("TASKS = ")[1].split("\n]\n")[0] + "\n]")
def post(url, body):
    r = urllib.request.Request(url, json.dumps(body).encode(), {"Content-Type": "application/json"})
    return json.load(urllib.request.urlopen(r, timeout=900))
env = dict(os.environ, LD_LIBRARY_PATH=f"{H}/lib")
srv = subprocess.Popen([f"{H}/bin-port/llama-server", "-m", f"{H}/models/lfm25-8b-a1b-q4.gguf", "-ngl", "99", "-fa", "on", "-np", "1",
                        "-c", "16384", "--jinja", "--host", "127.0.0.1", "--port", "8097"], env=env,
                       stdout=open(f"{OUT}/lfm25-server.log", "w"), stderr=subprocess.STDOUT)
try:
    for i in range(90):
        try: urllib.request.urlopen("http://127.0.0.1:8097/health", timeout=2); break
        except Exception: time.sleep(2)
    p = f"{OUT}/results.json"; results = json.load(open(p)); runs = []
    for t in TASKS:   # a reasoning model: thinking left on (its default), room for it
        s = time.time(); r = post("http://127.0.0.1:8097/v1/chat/completions", {"messages": [{"role": "user", "content": t}], "max_tokens": 4000})
        tm = r.get("timings", {}); msg = r["choices"][0]["message"]
        runs.append({"secs": round(time.time() - s, 1), "tok_s": round(tm.get("predicted_per_second", 0), 1), "tokens": tm.get("predicted_n"),
                     "finish": r["choices"][0].get("finish_reason"), "reply": msg.get("content"), "reasoning": msg.get("reasoning_content")})
    results["assistant"]["lfm2.5-8b-a1b (reasoning)"] = runs; json.dump(results, open(p, "w"), indent=1)
    print("assistant lfm2.5", [(r["secs"], r["tok_s"], r["tokens"], r["finish"]) for r in runs], flush=True)
finally:
    srv.terminate(); srv.wait(30)
PY
curl -s localhost:11434/api/generate -d '{"model":"qwen3.5:0.8b","keep_alive":-1}' > /dev/null
echo "LFM25-DONE swap $(free -m | awk '/Swap/{print $3}') MiB"
