#!/usr/bin/env python3
"""Write -> check -> fix, the way Workbench works, measured on LiveCodeBench v6.

Per problem: attempt 1 with LCB's own prompt (thinking on; the server caps it). Its code
is run against the problem's PUBLIC example tests only -- what a model could check for
itself. If an example fails, the model is shown that failure (input, expected, got, or the
error) and gets ONE more try. It never sees the hidden tests; they only do the grading.

Reports, graded on all tests with LCB's official checker:
  first try  vs  with one check-and-fix round

  lcb_repair.py <label> <easy|medium|hard> [port]
"""
import json, os, sys, time, types, urllib.request
os.chdir(os.path.expanduser("~/lcb")); sys.path.insert(0, ".")
sys.modules.setdefault("anthropic", types.SimpleNamespace(HUMAN_PROMPT="\n\nHuman:", AI_PROMPT="\n\nAssistant:"))
from lcb_runner.benchmarks.code_generation import CodeGenerationProblem
from lcb_runner.prompts.code_generation import format_prompt_generation
from lcb_runner.lm_styles import LMStyle
from lcb_runner.utils.extraction_utils import extract_code
from lcb_runner.evaluation.compute_code_generation_metrics import codegen_metrics

OUT = os.path.expanduser("~/buyers-bench")
MAXTOK = int(os.environ.get("MAXTOK", "12288"))
FIELDS = CodeGenerationProblem.__dataclass_fields__
label, level = sys.argv[1], sys.argv[2]
port = int(sys.argv[3]) if len(sys.argv) > 3 else 8050
PROBS = [p for p in (CodeGenerationProblem(**{k: v for k, v in json.loads(l).items() if k in FIELDS})
         for l in open("data/test6.jsonl")) if p.difficulty.value == level]
if os.environ.get("LIMIT"): PROBS = PROBS[:int(os.environ["LIMIT"])]
SHARD = os.environ.get("SHARD")          # "k/n": this process takes every n-th problem from k,
if SHARD:                                # so n processes can share one -np n server
    k, n = map(int, SHARD.split("/")); PROBS = PROBS[k::n]; level = "%s-shard%dof%d" % (level, k, n)


def chat(messages):
    body = {"messages": messages, "temperature": 0, "max_tokens": MAXTOK, "chat_template_kwargs": {"enable_thinking": True}}
    r = json.load(urllib.request.urlopen(urllib.request.Request("http://127.0.0.1:%d/v1/chat/completions" % port,
          data=json.dumps(body).encode(), headers={"Content-Type": "application/json"}), timeout=3600))
    c = r["choices"][0]
    return c["message"].get("content") or "", c["finish_reason"], r["usage"]["completion_tokens"]


def public_sample(p):
    return {"input_output": json.dumps({"inputs": [t.input for t in p.public_test_cases],
            "outputs": [t.output for t in p.public_test_cases], "fn_name": p.metadata.get("func_name")})}


def run(samples, codes):
    _, results, meta = codegen_metrics(samples, [[c] for c in codes], k_list=[1], num_process_evaluate=8, timeout=6)
    ok = [bool(results[i][0] and all(x is True for x in results[i][0])) for i in range(len(codes))]
    return ok, [json.loads(meta[i][0]) if isinstance(meta[i][0], str) else meta[i][0] for i in range(len(codes))]


def feedback(m):
    if not m: return "Your program did not pass the example tests from the problem statement."
    parts = ["Your program failed an example test from the problem statement (%s)." % m.get("error_message", "failed")]
    for k, name in (("inputs", "Input"), ("expected", "Expected output"), ("output", "Your output")):
        if m.get(k) not in (None, ""): parts.append("%s:\n%s" % (name, str(m[k])[:1500]))
    if m.get("error"): parts.append("Error:\n%s" % str(m["error"])[:1500])
    parts.append("Fix the program. Reply with the complete corrected program in one ```python block.")
    return "\n\n".join(parts)


gen_file = os.path.join(OUT, "repair-%s-%s.jsonl" % (label, level))
done = {json.loads(l)["id"]: json.loads(l) for l in open(gen_file)} if os.path.exists(gen_file) else {}
t0 = time.time()
with open(gen_file, "a") as f:
    for i, p in enumerate(PROBS):
        if p.question_id in done: continue
        msgs = format_prompt_generation(p, LMStyle.OpenAIChat)
        r1, fin1, n1 = chat(msgs)
        c1 = extract_code(r1, LMStyle.OpenAIChat)
        ok, meta = run([public_sample(p)], [c1])
        row = {"id": p.question_id, "code1": c1, "finish1": fin1, "tok1": n1, "public_pass1": ok[0], "code2": None}
        if not ok[0]:
            fb = feedback(meta[0])
            r2, fin2, n2 = chat(msgs + [{"role": "assistant", "content": r1}, {"role": "user", "content": fb}])
            row.update(code2=extract_code(r2, LMStyle.OpenAIChat), finish2=fin2, tok2=n2, feedback=fb[:600])
        f.write(json.dumps(row) + "\n"); f.flush(); done[p.question_id] = row
        print("  %d/%d %s public-examples %s%s" % (i + 1, len(PROBS), p.question_id, "pass" if ok[0] else "FAIL",
              "" if ok[0] else " -> retried"), flush=True)
rows = [done[p.question_id] for p in PROBS]
full = [p.get_evaluation_sample() for p in PROBS]
first, _ = run(full, [r["code1"] for r in rows])
final, _ = run(full, [r["code2"] if r["code2"] is not None else r["code1"] for r in rows])
retried = sum(r["code2"] is not None for r in rows)
fixed = sum(1 for a, b in zip(first, final) if b and not a); broke = sum(1 for a, b in zip(first, final) if a and not b)
json.dump({"first": first, "final": final}, open(os.path.join(OUT, "repair-%s-%s.graded.json" % (label, level)), "w"))
print("%s %s: first try %d/%d = %.0f%%  ->  with one check-and-fix %d/%d = %.0f%%   "
      "(%d retried after failing an example; %d fixed, %d broken by the retry; %.0f min)"
      % (label, level, sum(first), len(rows), 100 * sum(first) / len(rows), sum(final), len(rows),
         100 * sum(final) / len(rows), retried, fixed, broke, (time.time() - t0) / 60))
