"""Real jobs on the GTX 1070, after the speed test: can it be useful as something other than a coder?
1 Ember's eyes: read a made-up error dialog with known text (score = facts read correctly)
2 Etsy helper: write a listing title + 13 tags for a real design (rules checked; Chris judges the wording)
3 Everyday assistant: three ordinary requests, timed
Everything runs on the 1070 through the PC's own ollama (Ember's path) or llama-server. Ends by re-pinning Ember's
eyes model the way it was."""
import base64, io, json, subprocess, time, urllib.request, os, sys
from PIL import Image, ImageDraw, ImageFont
H = os.path.expanduser("~/pascal-bench"); OUT = f"{H}/jobs"; OLL = "http://127.0.0.1:11434"
def post(url, body, timeout=600):
    r = urllib.request.Request(url, json.dumps(body).encode(), {"Content-Type": "application/json"})
    return json.load(urllib.request.urlopen(r, timeout=timeout))
def b64(img): b = io.BytesIO(); img.save(b, "PNG"); return base64.b64encode(b.getvalue()).decode()
def font(n):
    for p in ["/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", "/usr/share/fonts/truetype/ubuntu/Ubuntu-R.ttf"]:
        if os.path.exists(p): return ImageFont.truetype(p, n)
    return ImageFont.load_default()
def ollama(model, prompt, image=None, think=False):
    m = {"role": "user", "content": prompt}
    if image: m["images"] = [image]
    t = time.time(); r = post(f"{OLL}/api/chat", {"model": model, "messages": [m], "stream": False, "think": think,
                                                  "options": {"num_ctx": 4096}})
    secs = time.time() - t; ev = r.get("eval_count", 0); ed = r.get("eval_duration", 1) / 1e9
    return r["message"]["content"], {"secs": round(secs, 1), "tokens": ev, "tok_s": round(ev / ed, 1) if ev else 0,
                                     "load_s": round(r.get("load_duration", 0) / 1e9, 1)}
def unload(model): post(f"{OLL}/api/generate", {"model": model, "keep_alive": 0})
results = {}
def save(): json.dump(results, open(f"{OUT}/results.json", "w"), indent=1)
unload("qwen3.5:0.8b")  # Ember's eyes: free the card for the run; re-pinned at the end
if subprocess.run(["ss", "-ltnH", "( sport = :8097 )"], capture_output=True, text=True).stdout.strip():
    sys.exit("port 8097 is taken")
# 1 -- a dialog with known facts
img = Image.new("RGB", (900, 420), (236, 236, 236)); d = ImageDraw.Draw(img)
d.rectangle([0, 0, 900, 56], fill=(52, 101, 164)); d.text((20, 14), "Deja Dup Backups", font=font(24), fill="white")
d.text((40, 90), "Backup failed", font=font(30), fill=(170, 30, 30))
d.text((40, 145), "The disk /dev/sdc1 (\"Photos-2TB\") is 97% full.", font=font(22), fill="black")
d.text((40, 180), "Only 12.4 GB free; this backup needs 31.8 GB.", font=font(22), fill="black")
d.text((40, 215), "Next automatic attempt: Thursday at 3:45 PM.", font=font(22), fill="black")
for x, lab in [(520, "Retry now"), (700, "Open Disks")]:
    d.rectangle([x, 330, x + 160, 380], outline=(80, 80, 80), fill="white"); d.text((x + 18, 342), lab, font=font(22), fill="black")
img.save(f"{OUT}/dialog.png")
FACTS = ["sdc1", "97", "12.4", "31.8", "3:45", "thursday", "retry now", "open disks"]
Q1 = ("This is a screenshot from my computer. What went wrong, which disk, how full is it, how much space is free and "
      "needed, when is the next try, and what buttons can I press? Answer in plain sentences.")
results["eyes"] = {}
for model in ["qwen3.5:0.8b", "qwen3-vl:4b"]:
    runs = []
    for i in range(3):
        txt, st = ollama(model, Q1, b64(img)); low = txt.lower()
        st["facts"] = sum(f in low for f in FACTS); st["missing"] = [f for f in FACTS if f not in low]; st["reply"] = txt
        runs.append(st)
    results["eyes"][model] = runs; unload(model)
    save(); print("eyes", model, [r["facts"] for r in runs], "/", len(FACTS), [r["secs"] for r in runs], flush=True)
# 2 -- Etsy listing for a real design
lion = Image.open(os.path.expanduser("~/Code/stencil/tools/vinyl-vector-pipeline/03_lion_perfect_final_rendered.png")).convert("RGB")
lion.thumbnail((768, 768))
Q2 = ("I sell digital design files on Etsy for laser engraving and vinyl cutting (SVG/PNG). Write a listing for this "
      "design. Reply with exactly:\nTITLE: <one line, at most 140 characters>\nTAGS: <exactly 13 tags, comma separated, "
      "each at most 20 characters>\nDESCRIPTION: <2-3 short sentences>")
def check(txt):
    title = next((l.split(":", 1)[1].strip() for l in txt.splitlines() if l.upper().startswith("TITLE")), "")
    tags = next((l.split(":", 1)[1] for l in txt.splitlines() if l.upper().startswith("TAGS")), "")
    tags = [t.strip() for t in tags.split(",") if t.strip()]
    return {"title_len": len(title), "title_ok": 0 < len(title) <= 140, "n_tags": len(tags),
            "tags_ok": len(tags) == 13 and all(len(t) <= 20 for t in tags), "long_tags": [t for t in tags if len(t) > 20]}
results["etsy"] = {}
for model in ["qwen3-vl:4b", "qwen3.5:0.8b"]:
    runs = []
    for i in range(2):
        txt, st = ollama(model, Q2, b64(lion)); st.update(check(txt)); st["reply"] = txt; runs.append(st)
    results["etsy"][model] = runs; unload(model)
    save(); print("etsy", model, [(r["title_ok"], r["n_tags"], r["tags_ok"]) for r in runs], [r["secs"] for r in runs], flush=True)
# 3 -- everyday assistant
TASKS = [
  "Reword this so it sounds friendly but firm, keep it short: 'Your order is late because you picked the wrong shipping. Not my fault.'",
  "I'm new to Linux. In plain English and under 120 words: what does it mean when a program says 'permission denied', and what's the usual fix?",
  "Summarise in 3 bullet points: Pascal-generation GPUs like the GTX 1070 lack tensor cores, so matrix maths runs on ordinary CUDA "
  "cores. For language models this mostly hurts reading a long prompt (prefill), while writing the answer (decode) is limited by memory "
  "speed, where the 1070's 256 GB/s is about a third of a modern mid-range card. An 8 GB card fits models up to roughly 12-14 billion "
  "parameters at 4-bit, or larger ternary models.",
]
results["assistant"] = {}
for model in ["qwen3:8b"]:
    runs = []
    for t in TASKS:
        txt, st = ollama(model, t); st["reply"] = txt; runs.append(st)
    results["assistant"][model] = runs; unload(model)
    save(); print("assistant", model, [(r["secs"], r["tok_s"]) for r in runs], flush=True)
# same three on Gemma 12B (llama-server, the buyers-bench weights)
env = dict(os.environ, LD_LIBRARY_PATH=f"{H}/lib")
srv = subprocess.Popen([f"{H}/bin/llama-server", "-m", f"{H}/models/gemma12b-qat.gguf", "-ngl", "99", "-fa", "on", "-c", "8192",
                        "--jinja", "--host", "127.0.0.1", "--port", "8097"], env=env, stdout=open(f"{OUT}/gemma-server.log", "w"),
                       stderr=subprocess.STDOUT)
try:
    for i in range(120):
        try: urllib.request.urlopen("http://127.0.0.1:8097/health", timeout=2); break
        except Exception: time.sleep(2)
    runs = []
    for t in TASKS:
        s = time.time(); r = post("http://127.0.0.1:8097/v1/chat/completions", {"messages": [{"role": "user", "content": t}], "max_tokens": 600})
        tm = r.get("timings", {}); runs.append({"secs": round(time.time() - s, 1), "tok_s": round(tm.get("predicted_per_second", 0), 1),
                                                 "tokens": tm.get("predicted_n"), "reply": r["choices"][0]["message"]["content"]})
    results["assistant"]["gemma-4-12b-qat"] = runs
    save(); print("assistant gemma12b", [(r["secs"], r["tok_s"]) for r in runs], flush=True)
finally:
    srv.terminate(); srv.wait(30)
    post(f"{OLL}/api/generate", {"model": "qwen3.5:0.8b", "keep_alive": -1})
json.dump(results, open(f"{OUT}/results.json", "w"), indent=1)
print("JOBS-DONE", flush=True)
