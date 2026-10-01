#!/usr/bin/env python3
"""dflash_probe2.py <label> <think 0|1>  -- 8 short (HumanEval) + 4 long coding prompts, greedy, against :8070.
   dflash_probe2.py compare <think 0|1>   -- plain vs dflash for that thinking setting."""
import json, os, sys, urllib.request, statistics as st
H = os.path.expanduser("~/buyers-bench")
if sys.argv[1] == "compare":
    th = sys.argv[2]; a = json.load(open(f"{H}/df2-plain-t{th}.json")); b = json.load(open(f"{H}/df2-dflash-t{th}.json"))
    for kind in ("short", "long"):
        A = [x for x in a if x["kind"] == kind]; B = [y for y in b if y["kind"] == kind]
        sa, sb = st.median(x["tps"] for x in A), st.median(y["tps"] for y in B)
        acc = st.median(y["accept"] for y in B if y["accept"] is not None)
        wall_a, wall_b = sum(x["secs"] for x in A), sum(y["secs"] for y in B)
        print(f"thinking {'ON ' if th=='1' else 'off'} {kind:5}: {sa:6.1f} -> {sb:6.1f} tok/s (x{sb/sa:.2f}), total time {wall_a:5.0f}s -> {wall_b:5.0f}s, draft acceptance {acc:.2f}")
    sys.exit()
label, think = sys.argv[1], sys.argv[2] == "1"
src = open(f"{H}/humaneval.py").read(); exec(src[:src.index('if sys.argv[1] == "selftest":')])
P = [("short", p["task_id"], "Complete this Python function. Reply with the whole function in one ```python block, nothing else.\n\n" + p["prompt"]) for p in PROBS[10:18]]
P += [("long", "cli", "Write a complete Python command-line program that tracks Etsy orders in a JSON file next to the script: add, list, mark shipped, delete, and a report of unshipped totals. Validate every input. Include argparse and docstrings."),
      ("long", "electron", "Write the three files of a small Electron app (main.js, preload.js, renderer.js) that keeps a to-do list in a JSON file, using contextIsolation and ipcMain.handle. Full code for each file."),
      ("long", "tests", "Write a thorough pytest test file for a function parse_price(text) that accepts '12.50', '$3', ' 7 ' and refuses '', '-1', 'abc', '1e3', 'nan'. At least 15 tests with clear names."),
      ("long", "explain", "Explain, with code examples, how Python's asyncio event loop schedules coroutines, tasks and futures. Be thorough.")]
out = []
for kind, name, text in P:
    body = {"messages": [{"role": "user", "content": text}], "temperature": 0, "max_tokens": (3072 if think else 1536) if kind == "long" else (2048 if think else 512),
            "chat_template_kwargs": {"enable_thinking": think}}
    import time; t0 = time.time()
    d = json.load(urllib.request.urlopen(urllib.request.Request("http://127.0.0.1:8070/v1/chat/completions", data=json.dumps(body).encode(),
          headers={"Content-Type": "application/json"}), timeout=1800))
    t = d.get("timings", {})
    acc = (t["draft_n_accepted"] / t["draft_n"]) if t.get("draft_n") else None
    out.append({"kind": kind, "name": name, "tps": t.get("predicted_per_second", 0), "n": t.get("predicted_n"), "accept": acc, "secs": time.time() - t0,
                "text": d["choices"][0]["message"].get("content") or ""})
    print(kind, name, round(out[-1]["tps"], 1), "tok/s", t.get("predicted_n"), "tok", f"accept {acc:.2f}" if acc is not None else "", flush=True)
json.dump(out, open(f"{H}/df2-{label}-t{int(think)}.json", "w"))
