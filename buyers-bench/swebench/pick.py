#!/usr/bin/env python3
"""Pick the 20 SWE-bench Verified tasks for our comparison: all from the '<15 min fix' group, spread over
projects (not 20 Django tasks), fixed seed so every model gets exactly the same ones. Writes tasks.json."""
import json, random
from datasets import load_dataset
ds = load_dataset("princeton-nlp/SWE-bench_Verified", split="test")
easy = [r for r in ds if r["difficulty"] == "<15 min fix"]
SHARE = {"django/django": 8, "sympy/sympy": 3, "sphinx-doc/sphinx": 2, "matplotlib/matplotlib": 2,
         "scikit-learn/scikit-learn": 2, "pytest-dev/pytest": 1, "psf/requests": 1, "pydata/xarray": 1}
rng = random.Random(7); out = []
for repo, n in SHARE.items():
    pool = sorted((r for r in easy if r["repo"] == repo), key=lambda r: r["instance_id"])
    out += rng.sample(pool, n)
tasks = [{"instance_id": r["instance_id"], "repo": r["repo"], "problem_statement": r["problem_statement"],
          "image": f"swebench/sweb.eval.x86_64.{r['instance_id']}:latest".lower().replace("__", "_1776_")} for r in out]
json.dump(tasks, open("tasks.json", "w"), indent=1)
print(len(tasks), "tasks:", " ".join(t["instance_id"] for t in tasks))
