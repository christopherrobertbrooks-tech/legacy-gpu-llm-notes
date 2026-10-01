#!/usr/bin/env python3
"""Apply run_agent.mjs's (newer) patch filter to an existing preds file: drop NEW files that are at the top level,
in a top-level folder the project didn't have, or build output. Top-level entries come from each task's image.
  clean_preds.py preds-gemma.jsonl  ->  preds-gemma.clean.jsonl"""
import json, re, subprocess, sys
src = sys.argv[1]; dst = src.replace(".jsonl", ".clean.jsonl")
tasks = {t["instance_id"]: t for t in json.load(open("tasks.json"))}
JUNK = re.compile(r"(^|/)(_build|build|dist|__pycache__|\.pytest_cache|[^/]+\.egg-info)/|\.pyc$")
with open(dst, "w") as out:
    for line in open(src):
        r = json.loads(line)
        top = set(subprocess.run(["docker", "run", "--rm", "--network", "none", tasks[r["instance_id"]]["image"],
                                  "git", "-C", "/testbed", "ls-tree", "--name-only", "HEAD"], capture_output=True, text=True).stdout.split())
        blocks = re.split(r"(?=^diff --git )", r["model_patch"], flags=re.M)
        keep, dropped = [], []
        for b in blocks:
            m = re.match(r"diff --git a/(\S+)", b)
            if m and "\nnew file mode" in b.split("\n@@")[0]:
                f = m.group(1)
                if "/" not in f or f.split("/")[0] not in top or JUNK.search(f): dropped.append(f); continue
            keep.append(b)
        r["model_patch"] = "".join(keep); r["dropped_files"] = len(dropped)
        out.write(json.dumps(r) + "\n")
        if dropped: print(r["instance_id"], "dropped", len(dropped), "new scratch files, e.g.", dropped[:2])
print("wrote", dst)
