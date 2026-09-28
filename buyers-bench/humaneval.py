#!/usr/bin/env python3
"""HumanEval pass@1 (greedy) against a running llama-server.

  humaneval.py selftest            -- the grader must pass all 164 reference
                                      solutions and fail a broken one, or no
                                      score it gives means anything
  humaneval.py <label> [port]      -- score the model on :port (default 8050)

Generated code runs in an isolated-mode (-I) subprocess in a scratch
dir and a 10 s limit.
"""
import json, os, re, subprocess, sys, tempfile, time, urllib.request
import pyarrow.parquet as pq

DATA = os.path.expanduser("~/buyers-bench/humaneval.parquet")
PROBS = pq.read_table(DATA).to_pylist()


def run_tests(code, p):
    prog = code + "\n\n" + p["test"] + "\n\ncheck(%s)\n" % p["entry_point"]
    with tempfile.TemporaryDirectory() as d:
        f = os.path.join(d, "t.py"); open(f, "w").write(prog)
        try:
            r = subprocess.run([sys.executable, "-I", f], cwd=d, capture_output=True, timeout=10)
            return r.returncode == 0
        except subprocess.TimeoutExpired:
            return False


def extract(text, p):
    m = re.findall(r"```(?:python|py)?\n(.*?)```", text, re.S)
    code = max(m, key=len) if m else text
    if "def %s" % p["entry_point"] not in code:   # body only: glue onto the prompt
        code = p["prompt"] + code
    # keep the prompt's imports even if the model dropped them
    imports = "\n".join(l for l in p["prompt"].splitlines() if l.startswith(("import ", "from ")))
    return imports + "\n" + code


def ask(port, prompt):
    body = {"messages": [{"role": "user", "content":
            "Complete this Python function. Reply with the whole function in one ```python block, nothing else.\n\n" + prompt}],
            "temperature": 0, "max_tokens": 1536, "chat_template_kwargs": {"enable_thinking": False}}
    r = urllib.request.urlopen(urllib.request.Request("http://127.0.0.1:%d/v1/chat/completions" % port,
          data=json.dumps(body).encode(), headers={"Content-Type": "application/json"}), timeout=600)
    d = json.load(r); return d["choices"][0]["message"]["content"] or "", d["usage"]["completion_tokens"]


if sys.argv[1] == "selftest":
    good = sum(run_tests(p["prompt"] + p["canonical_solution"], p) for p in PROBS)
    bad = sum(run_tests(p["prompt"] + "    return None\n", p) for p in PROBS)
    print("reference solutions pass %d/%d (must be %d); 'return None' passes %d (must be ~0)" % (good, len(PROBS), len(PROBS), bad))
    sys.exit(0 if good == len(PROBS) and bad < 3 else 1)

label, port = sys.argv[1], int(sys.argv[2]) if len(sys.argv) > 2 else 8050
out = os.path.expanduser("~/buyers-bench/humaneval-%s.jsonl" % label)
ok = toks = 0; t0 = time.time()
with open(out, "w") as f:
    for i, p in enumerate(PROBS):
        text, n = ask(port, p["prompt"]); toks += n
        passed = run_tests(extract(text, p), p); ok += passed
        f.write(json.dumps({"task": p["task_id"], "pass": passed, "reply": text}) + "\n")
        if i % 40 == 39: print("  %d/%d  pass %d" % (i + 1, len(PROBS), ok), flush=True)
print("%s: HumanEval pass@1 %d/%d = %.1f%%  (%.0f s, %d tokens)" % (label, ok, len(PROBS), 100 * ok / len(PROBS), time.time() - t0, toks))
