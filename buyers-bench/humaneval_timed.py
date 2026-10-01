#!/usr/bin/env python3
"""humaneval.py with timing, for regular (one-word-at-a-time) Gemma through llama-swap, thinking off or on.
Same problems, prompt and grader; records seconds and tokens per answer so it lines up with humaneval_dg.py.
  humaneval_timed.py <label> <port> <model> <think 0|1>
Thinking on uses the server's own --reasoning-budget (4096 for gemma), room for 4096 + the answer."""
import json, os, sys, time, urllib.request
src = open(os.path.expanduser("~/buyers-bench/humaneval.py")).read()
exec(src[:src.index('if sys.argv[1] == "selftest":')])
label, port, model, think = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4] == "1"
out = os.path.expanduser(f"~/buyers-bench/humaneval-{label}.jsonl")
ok = 0; t0 = time.time()
with open(out, "w") as f:
    for i, p in enumerate(PROBS):
        body = {"model": model, "messages": [{"role": "user", "content":
                "Complete this Python function. Reply with the whole function in one ```python block, nothing else.\n\n" + p["prompt"]}],
                "temperature": 0, "max_tokens": 6144 if think else 1536, "chat_template_kwargs": {"enable_thinking": think}}
        t = time.time()
        d = json.load(urllib.request.urlopen(urllib.request.Request(f"http://127.0.0.1:{port}/v1/chat/completions",
              data=json.dumps(body).encode(), headers={"Content-Type": "application/json"}), timeout=1200))
        secs = time.time() - t
        m = d["choices"][0]["message"]; text = m.get("content") or ""
        passed = run_tests(extract(text, p), p); ok += passed
        f.write(json.dumps({"task": p["task_id"], "pass": passed, "secs": round(secs, 2), "tokens": d["usage"]["completion_tokens"],
                            "finish": d["choices"][0]["finish_reason"], "thinking_chars": len(m.get("reasoning_content") or ""), "reply": text}) + "\n"); f.flush()
        print(f"{i+1}/164 {p['task_id']} {'PASS' if passed else 'fail'} {secs:.1f}s {d['usage']['completion_tokens']} tok  running {ok}/{i+1}", flush=True)
print(f"{label}: {ok}/164 pass@1 ({100*ok/164:.1f}%) in {(time.time()-t0)/60:.1f} min")
