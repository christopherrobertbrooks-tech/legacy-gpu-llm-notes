#!/usr/bin/env python3
"""Re-grade HumanEval answers, removing the indentation ONLY when the reply is a complete function shifted right
(Mistral Small 4 indents its whole answer). Body-only answers and column-0 code are untouched.
  regrade_dedent.py humaneval-<label>.jsonl [...]"""
import json, os, sys, textwrap
src = open(os.path.expanduser("~/buyers-bench/humaneval.py")).read()
exec(src[:src.index('if sys.argv[1] == "selftest":')])
P = {p["task_id"]: p for p in PROBS}
import re
def extract_dedent(text, p):
    m = re.findall(r"```(?:python|py)?\n(.*?)```", text, re.S)
    code = max(m, key=len) if m else text
    # only a COMPLETE function shifted right is the quirk; a body-only answer is meant to be indented
    if re.search(r"^\s+def %s\b" % p["entry_point"], code, re.M) and not re.search(r"^def %s\b" % p["entry_point"], code, re.M):
        code = textwrap.dedent(code)
    if "def %s" % p["entry_point"] not in code: code = p["prompt"] + code
    imports = "\n".join(l for l in p["prompt"].splitlines() if l.startswith(("import ", "from ")))
    return imports + "\n" + code
for f in sys.argv[1:]:
    rows = [json.loads(l) for l in open(f)]
    strict = sum(r["pass"] for r in rows)
    fair = sum(run_tests(extract_dedent(r["reply"], P[r["task"]]), P[r["task"]]) for r in rows)
    print(f"{os.path.basename(f):48} strict {strict}/{len(rows)}  dedented {fair}/{len(rows)}")
