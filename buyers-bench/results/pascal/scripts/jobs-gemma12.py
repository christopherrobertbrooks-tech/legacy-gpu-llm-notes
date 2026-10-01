# the Gemma 12B assistant step alone (the full run started it while ollama's model was still leaving the card)
import json, os, subprocess, time, urllib.request
exec(open(os.path.expanduser("~/pascal-bench/jobs.py")).read().split("results = {}")[0])   # helpers only
TASKS = eval(open(os.path.expanduser("~/pascal-bench/jobs.py")).read().split("TASKS = ")[1].split("\n]\n")[0] + "\n]")
results = json.load(open(f"{OUT}/results.json")); unload("qwen3.5:0.8b")
for i in range(60):
    used = int(subprocess.run(["nvidia-smi", "--query-gpu=memory.used", "--format=csv,noheader,nounits"], capture_output=True, text=True).stdout)
    if used < 900: break
    time.sleep(2)
print("card used MiB before start:", used, flush=True)
env = dict(os.environ, LD_LIBRARY_PATH=f"{H}/lib")
srv = subprocess.Popen([f"{H}/bin/llama-server", "-m", f"{H}/models/gemma12b-qat.gguf", "-ngl", "99", "-fa", "on", "-c", "4096", "-np", "1",
                        "--jinja", "--host", "127.0.0.1", "--port", "8097"], env=env, stdout=open(f"{OUT}/gemma-server.log", "w"), stderr=subprocess.STDOUT)
try:
    for i in range(120):
        try: urllib.request.urlopen("http://127.0.0.1:8097/health", timeout=2); break
        except Exception: time.sleep(2)
    runs = []
    for t in TASKS:
        s = time.time(); r = post("http://127.0.0.1:8097/v1/chat/completions", {"messages": [{"role": "user", "content": t}], "max_tokens": 1200, "chat_template_kwargs": {"enable_thinking": False}})
        tm = r.get("timings", {}); runs.append({"secs": round(time.time() - s, 1), "tok_s": round(tm.get("predicted_per_second", 0), 1),
                                                 "tokens": tm.get("predicted_n"), "reply": r["choices"][0]["message"]["content"], "reasoning": r["choices"][0]["message"].get("reasoning_content")})
    results["assistant"]["gemma-4-12b-qat"] = runs; json.dump(results, open(f"{OUT}/results.json", "w"), indent=1)
    print("assistant gemma12b", [(r["secs"], r["tok_s"]) for r in runs], flush=True)
finally:
    srv.terminate(); srv.wait(30); post(f"{OLL}/api/generate", {"model": "qwen3.5:0.8b", "keep_alive": -1})
