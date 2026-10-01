#!/usr/bin/env python3
"""HumanEval pass@1 for DiffusionGemma (llama.cpp PR #24423) -- same grader, prompt and problems as humaneval.py.

The PR has no OpenAI-style server, so this keeps ONE llama-diffusion-cli loaded in conversation mode and feeds it
the problems one per line (local DG_ESCAPED patch: \\n escapes + an end marker), /clear between problems so each is
answered fresh -- the same single-turn setup humaneval.py uses.

  humaneval_dg.py <label> <model.gguf> [first N problems]
Decoding: the model's own entropy-bound defaults, fixed seed. Thinking off (template default), -n 1536 like humaneval.py.
"""
import json, os, subprocess, sys, time
src = open(os.path.expanduser("~/buyers-bench/humaneval.py")).read()
exec(src[:src.index('if sys.argv[1] == "selftest":')])       # PROBS, run_tests, extract (ask() unused)

label, model = sys.argv[1], sys.argv[2]
limit = int(sys.argv[3]) if len(sys.argv) > 3 else len(PROBS)
CLI = os.path.expanduser("~/diffusiongemma/llama.cpp/build/bin/llama-diffusion-cli")
THINK = os.environ.get("DG_THINK") == "1"          # thinking ON: more room, and grade only what follows the thought
NPRED = os.environ.get("DG_N", "3072" if THINK else "1536")
env = {**os.environ, "DG_ESCAPED": "1", **({} if THINK else {"DG_NOTHINK": "1"}), "CUDA_DEVICE_ORDER": "PCI_BUS_ID", "CUDA_VISIBLE_DEVICES": os.environ.get("GPU", "1")}
ERRF = os.path.expanduser(f"~/buyers-bench/humaneval-{label}.stderr"); err = open(ERRF, "w")
import re
def steps_since(pos):   # refinement passes and blocks this answer used, from the CLI's own progress log
    with open(ERRF, errors="replace") as fh: fh.seek(pos); t = fh.read()
    blocks = re.findall(r"diffusion step: (\d+)/\d+", t)
    starts = [i for i, b in enumerate(blocks) if b == "0"]
    ends = [int(blocks[j - 1]) + 1 for j in starts[1:]] + ([int(blocks[-1]) + 1] if blocks else [])
    return len(starts), sum(ends)
proc = subprocess.Popen([CLI, "-m", model, "-ngl", "99", "-cnv", "-n", NPRED, "--seed", "1"] + os.environ.get("DG_EXTRA", "").split(),
                        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=err, text=True, bufsize=1, env=env)

def reply(msg):
    esc = msg.replace("\\", "\\\\").replace("\n", "\\n").replace("\t", "\\t")
    proc.stdin.write(esc + "\n"); proc.stdin.flush()
    buf = []
    while True:
        line = proc.stdout.readline()
        if not line: raise RuntimeError("diffusion-cli exited -- see the .stderr file")
        if line.strip() == "<<<DG_END>>>": break
        buf.append(line)
    text = "".join(buf)
    return text[text.index("> ") + 2:] if text.lstrip().startswith(">") else text

out = os.path.expanduser(f"~/buyers-bench/humaneval-{label}.jsonl")
ok = 0; t0 = time.time()
with open(out, "w") as f:
    for i, p in enumerate(PROBS[:limit]):
        t = time.time(); err.flush(); pos = os.path.getsize(ERRF)
        text = reply("Complete this Python function. Reply with the whole function in one ```python block, nothing else.\n\n" + p["prompt"])
        secs = time.time() - t; blocks, steps = steps_since(pos)
        full = text
        if "<channel|>" in text: text = text.split("<channel|>")[-1]      # the answer after the thinking
        elif THINK and "<|channel>thought" in text: text = ""             # still thinking when it ran out of room: no answer
        passed = run_tests(extract(text, p), p); ok += passed
        f.write(json.dumps({"task": p["task_id"], "pass": passed, "secs": round(secs, 2), "blocks": blocks, "steps": steps,
                            "chars": len(full), "reply": full}) + "\n"); f.flush()
        proc.stdin.write("/clear\n"); proc.stdin.flush()
        print(f"{i+1}/{limit} {p['task_id']} {'PASS' if passed else 'fail'} {secs:.1f}s {blocks} blocks {steps} passes  running {ok}/{i+1}", flush=True)
proc.stdin.write("/exit\n"); proc.stdin.flush(); proc.wait(timeout=60)
print(f"{label}: {ok}/{limit} pass@1 ({100*ok/limit:.1f}%) in {(time.time()-t0)/60:.1f} min")
