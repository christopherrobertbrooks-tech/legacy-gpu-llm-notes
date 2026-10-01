#!/usr/bin/env python3
"""Proof bake-off: a reviewer must PROVE each bug with a test.

For each of the 20 builds the reviewer writes pytest tests (one per real bug it believes is there).
Each test runs against the build AND against a known-good "gold" build:
  fails on build, passes on gold -> PROVEN bug      fails on gold too -> the test is WRONG (noise)
  passes on build                -> no bug shown     (a test file that won't even load = all wrong)

  prove.py <label> <base_url> <model>
"""
import json, random, re, subprocess, sys, time, urllib.request, shutil, os
from pathlib import Path

H = Path(__file__).parent
label, base, model = sys.argv[1:4]
KEY = json.load(open(H / "key.json")); REQUEST = (H / "REQUEST.md").read_text()
HELP = (H / "helpers.py").read_text()
PROMPT = """You are reviewing code before Chris runs it. He asked for this, in his words:

{request}

Here is the code that was built:

{files}

Find REAL bugs: behaviour that is wrong or missing compared with what he asked for (wrong numbers,
crashes, bad input accepted, a refund or undo not reflected everywhere, wrong exit codes, data not kept
where he asked, parts that don't fit together). Ignore style and nice-to-haves.

PROVE each bug with a pytest test that FAILS on this code and would PASS on a correct program. Tests must
check behaviour Chris can see (numbers, exit codes, what is saved), never internal function names, and
NEVER the exact wording of a message -- a correct program may phrase everything differently. Get numbers
with money(), stock_of() and order_id(); check success with ok() and refusals with refused(). Use ONLY
these helpers:

{helpers}

Reply with ONE ```python block: start it with `from helpers import run, ok, refused, money, order_id, stock_of, app_dir`, then one test
function per bug, named test_bug_<short_name>, each with a one-line comment saying what goes wrong for
Chris. If you find no real bugs, write a block containing only the import line."""


def ask(content):
    body = {"model": model, "temperature": 0.7, "max_tokens": 24000,
            "messages": [{"role": "user", "content": content}], "chat_template_kwargs": {"enable_thinking": True}}
    r = json.load(urllib.request.urlopen(urllib.request.Request(base + "/v1/chat/completions",
            data=json.dumps(body).encode(), headers={"Content-Type": "application/json"}), timeout=3600))
    return r["choices"][0]["message"].get("content") or "", r["choices"][0]["finish_reason"]


def run_tests(test_dir, src):
    env = {**os.environ, "APP_SRC": str(src), "PYTHONPATH": str(test_dir)}
    p = subprocess.run([sys.executable, "-m", "pytest", "-q", "-rA", "-p", "no:cacheprovider", str(test_dir / "test_review.py")],
                       cwd=test_dir, env=env, capture_output=True, text=True, timeout=600)
    res = {name: status for status, name in re.findall(r"^(PASSED|FAILED|ERROR) \S*::(test_\w+)", p.stdout, re.M)}
    return res, ("error" in p.stdout.lower() and not res), p.stdout[-1500:]


out = H / f"proof-{label}.jsonl"
done = {json.loads(l)["id"]: json.loads(l) for l in open(out)} if out.exists() else {}
order = KEY[:]; random.Random(7).shuffle(order); t0 = time.time()
with open(out, "a") as f:
    for k in order:
        if k["id"] in done: continue
        d = H / "builds" / k["id"]
        files = "\n\n".join(f"=== {n} ===\n{(d / n).read_text()}" for n in ("catalog.py", "orders.py", "shop.py"))
        t = time.time(); text, fin = ask(PROMPT.format(request=REQUEST, files=files, helpers=HELP))
        blocks = re.findall(r"```(?:python)?\n(.*?)```", text, re.S); code = max(blocks, key=len) if blocks else ""
        td = H / f"tests-{label}" / k["id"]; shutil.rmtree(td, ignore_errors=True); td.mkdir(parents=True)
        (td / "test_review.py").write_text(code or "from helpers import run, ok, refused, money, order_id, stock_of, app_dir\n")
        shutil.copy(H / "helpers.py", td); shutil.copy(H / "conftest.py", td)
        on_build, broken, log = run_tests(td, d); on_gold, _, _ = run_tests(td, H / "gold")
        tests = sorted(set(on_build) | set(on_gold))
        proven = [t for t in tests if on_build.get(t) in ("FAILED", "ERROR") and on_gold.get(t) == "PASSED"]
        wrong = [t for t in tests if on_gold.get(t) in ("FAILED", "ERROR")]
        row = {"id": k["id"], "buggy": k["buggy"], "secs": round(time.time() - t), "finish": fin, "n_tests": len(tests),
               "proven": proven, "wrong": wrong, "no_code": not code, "code": code, "text": text}   # full reply kept (2026-09-30)
        f.write(json.dumps(row) + "\n"); f.flush(); done[k["id"]] = row
        print(f"  {k['id']} {'buggy' if k['buggy'] else 'clean'}: {len(tests)} tests, {len(proven)} proven, {len(wrong)} wrong ({row['secs']} s)", flush=True)

rows = [done[k["id"]] for k in KEY]
bug_hit = sum(1 for r in rows if r["buggy"] and r["proven"]); clean_hit = sum(1 for r in rows if not r["buggy"] and r["proven"])
tp = sum(len(r["proven"]) for r in rows); tw = sum(len(r["wrong"]) for r in rows); tt = sum(r["n_tests"] for r in rows)
secs = sorted(r["secs"] for r in rows)
print(f"{label}: proved a bug in {bug_hit}/10 buggy builds and {clean_hit}/10 'correct' ones | {tp} proven bugs, "
      f"{tw} wrong tests, of {tt} tests | median {secs[len(secs)//2]} s per build | {round((time.time()-t0)/60)} min")
