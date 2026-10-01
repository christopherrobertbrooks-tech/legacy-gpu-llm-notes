# the three everyday-assistant tasks (same as jobs.py) on the small MoE models, one llama-server each, -np 1
import json, os, subprocess, time, urllib.request
H = os.path.expanduser("~/pascal-bench"); OUT = f"{H}/jobs"; src = open(f"{H}/jobs.py").read()
TASKS = eval(src.split("TASKS = ")[1].split("\n]\n")[0] + "\n]")
def post(url, body, timeout=900):
    r = urllib.request.Request(url, json.dumps(body).encode(), {"Content-Type": "application/json"})
    return json.load(urllib.request.urlopen(r, timeout=timeout))
ncmoe = open(f"{H}/out/gpt-oss-ncmoe.txt").read().strip()
MODELS = [("lfm2-8b-a1b", "lfm2-8b-a1b-q4", ["-c", "16384"], {}),
          ("granite-4.0-h-tiny", "granite4-htiny-q4", ["-c", "16384"], {}),
          ("gpt-oss-20b (low reasoning)", "gpt-oss-20b-mxfp4", ["-c", "8192"] + (["-ncmoe", ncmoe] if ncmoe else []),
           {"chat_template_kwargs": {"reasoning_effort": "low"}})]
p = f"{OUT}/results.json"; results = json.load(open(p))
env = dict(os.environ, LD_LIBRARY_PATH=f"{H}/lib")
for name, f, extra, body in MODELS:
    if "gpt-oss" in name and not ncmoe: print(name, "skipped: never loaded"); continue
    srv = subprocess.Popen([f"{H}/bin-port/llama-server", "-m", f"{H}/models/{f}.gguf", "-ngl", "99", "-fa", "on", "-np", "1",
                            "--jinja", "--host", "127.0.0.1", "--port", "8097"] + extra, env=env,
                           stdout=open(f"{OUT}/{f}-server.log", "w"), stderr=subprocess.STDOUT)
    try:
        for i in range(150):
            if srv.poll() is not None: break
            try: urllib.request.urlopen("http://127.0.0.1:8097/health", timeout=2); break
            except Exception: time.sleep(2)
        if srv.poll() is not None: print(name, "server failed to start, see", f"{f}-server.log", flush=True); continue
        runs = []
        for t in TASKS:
            s = time.time(); r = post("http://127.0.0.1:8097/v1/chat/completions",
                                      dict({"messages": [{"role": "user", "content": t}], "max_tokens": 1200}, **body))
            tm = r.get("timings", {}); msg = r["choices"][0]["message"]
            runs.append({"secs": round(time.time() - s, 1), "tok_s": round(tm.get("predicted_per_second", 0), 1),
                         "tokens": tm.get("predicted_n"), "reply": msg.get("content"), "reasoning": msg.get("reasoning_content")})
        results["assistant"][name] = runs; json.dump(results, open(p, "w"), indent=1)
        print("assistant", name, [(r["secs"], r["tok_s"]) for r in runs], flush=True)
    finally:
        srv.terminate(); srv.wait(30)
    time.sleep(3)
print("MOE-JOBS-DONE")
