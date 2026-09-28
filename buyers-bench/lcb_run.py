#!/usr/bin/env python3
"""LiveCodeBench v6 (Jan-Apr 2025, 175 problems) against a running llama-server.

Uses LiveCodeBench's own prompt (OpenAIChat style), code extractor and grader
(codegen_metrics, private tests included); only the model call is ours, because
lcb_runner's inference path needs vLLM, which has no sm_70 build.

  lcb_run.py selftest              grader must fail empty and wrong programs
  lcb_run.py <label> [port]        generate (temp 0) then grade
     THINK=1  thinking on (the server caps it: --reasoning-budget); else off
     MAXTOK   total answer budget, default 16384 (4096 truncated half of the hard
              problems for a model reasoning in code comments)
"""
import json, os, sys, time, urllib.request
os.chdir(os.path.expanduser("~/lcb")); sys.path.insert(0, ".")  # lcb_runner opens files by relative path
import types  # lcb_runner.prompts imports vendor SDKs it doesn't need for this; stub them
for m, attrs in {"anthropic": {"HUMAN_PROMPT": "\n\nHuman:", "AI_PROMPT": "\n\nAssistant:"}}.items():
    sys.modules.setdefault(m, types.SimpleNamespace(**attrs))
from lcb_runner.benchmarks.code_generation import CodeGenerationProblem
from lcb_runner.prompts.code_generation import format_prompt_generation
from lcb_runner.lm_styles import LMStyle
from lcb_runner.utils.extraction_utils import extract_code
from lcb_runner.evaluation.compute_code_generation_metrics import codegen_metrics

OUT = os.path.expanduser("~/buyers-bench")
FIELDS = CodeGenerationProblem.__dataclass_fields__
PROBS = [CodeGenerationProblem(**{k: v for k, v in json.loads(l).items() if k in FIELDS})
         for l in open(os.path.expanduser("~/lcb/data/test6.jsonl"))]


def grade(codes):
    samples = [p.get_evaluation_sample() for p in PROBS]
    metrics, results, _ = codegen_metrics(samples, [[c] for c in codes], k_list=[1], num_process_evaluate=8, timeout=6)
    return [bool(results[i][0] and all(x is True for x in results[i][0])) for i in range(len(PROBS))], metrics


def summary(label, passed):
    by = {}
    for p, ok in zip(PROBS, passed):
        d = p.difficulty.value; by.setdefault(d, [0, 0]); by[d][0] += ok; by[d][1] += 1
    parts = " | ".join("%s %d/%d" % (d, *by[d]) for d in ("easy", "medium", "hard") if d in by)
    return "%s: LiveCodeBench v6 pass@1 %d/%d = %.1f%%  (%s)" % (label, sum(passed), len(PROBS), 100 * sum(passed) / len(PROBS), parts)


if sys.argv[1] == "selftest":
    empty, _ = grade([""] * len(PROBS))
    wrong, _ = grade(["print(42)\n" if not p.starter_code else p.starter_code + "\n        return 42\n" for p in PROBS])
    print("empty programs pass %d, 'print 42' passes %d (both must be ~0)" % (sum(empty), sum(wrong)))
    # ...and must ACCEPT correct programs (LCB ships none, so these are hand-written)
    HAND = {
        "abc387_a": "a, b = map(int, input().split())\nprint((a + b) ** 2)\n",
        "abc387_b": "x = int(input())\nprint(sum(i * j for i in range(1, 10) for j in range(1, 10) if i * j != x))\n",
        "abc388_b": "n, d = map(int, input().split())\ns = [tuple(map(int, input().split())) for _ in range(n)]\n"
                    "for k in range(1, d + 1):\n    print(max(t * (l + k) for t, l in s))\n",
        "3708": "class Solution:\n    def zigzagTraversal(self, grid: List[List[int]]) -> List[int]:\n"
                "        seq = []\n        for i, row in enumerate(grid):\n            seq += row if i % 2 == 0 else row[::-1]\n"
                "        return seq[::2]\n",
    }
    ids = [p.question_id for p in PROBS]
    good, _ = grade([HAND.get(i, "") for i in ids])
    ok_hand = sum(good[ids.index(i)] for i in HAND)
    bug = dict(HAND, abc387_a="a, b = map(int, input().split())\nprint((a + b) ** 2 + 1)\n")
    bad, _ = grade([bug.get(i, "") for i in ids])
    print("hand-written correct solutions pass %d/%d (must be %d); off-by-one variant passes: %s (must be False)"
          % (ok_hand, len(HAND), len(HAND), bad[ids.index("abc387_a")]))
    if ok_hand != len(HAND) or bad[ids.index("abc387_a")]: sys.exit(1)
    print("problems: %d, dated %s .. %s" % (len(PROBS), min(p.contest_date for p in PROBS).date(), max(p.contest_date for p in PROBS).date()))
    sys.exit(0 if sum(empty) == 0 and sum(wrong) < 3 else 1)

THINK = os.environ.get("THINK") == "1"; MAXTOK = int(os.environ.get("MAXTOK", "16384"))
label, port = sys.argv[1], int(sys.argv[2]) if len(sys.argv) > 2 else 8050
gen_file = os.path.join(OUT, "lcb-%s.jsonl" % label)
done = {json.loads(l)["id"]: json.loads(l) for l in open(gen_file)} if os.path.exists(gen_file) else {}
t0 = time.time()
with open(gen_file, "a") as f:
    for i, p in enumerate(PROBS):
        if p.question_id in done: continue
        body = {"messages": format_prompt_generation(p, LMStyle.OpenAIChat), "temperature": 0, "max_tokens": MAXTOK,
                "chat_template_kwargs": {"enable_thinking": THINK}}
        r = json.load(urllib.request.urlopen(urllib.request.Request("http://127.0.0.1:%d/v1/chat/completions" % port,
                data=json.dumps(body).encode(), headers={"Content-Type": "application/json"}), timeout=1800))
        msg = r["choices"][0]["message"]
        row = {"id": p.question_id, "reply": msg.get("content") or "", "reasoning_chars": len(msg.get("reasoning_content") or ""),
               "finish": r["choices"][0]["finish_reason"], "tokens": r["usage"]["completion_tokens"]}
        f.write(json.dumps(row) + "\n"); f.flush(); done[p.question_id] = row
        if i % 25 == 24: print("  generated %d/%d" % (i + 1, len(PROBS)), flush=True)
rows = [done[p.question_id] for p in PROBS]
passed, _ = grade([extract_code(r["reply"], LMStyle.OpenAIChat) for r in rows])
json.dump({"passed": passed}, open(os.path.join(OUT, "lcb-%s.graded.json" % label), "w"))
print(summary(label, passed) + "  [thinking %s, %d-token budget; %.0f s gen, %d empty, %d hit token limit]" % (
      "on" if THINK else "off", MAXTOK, time.time() - t0, sum(not r["reply"].strip() for r in rows), sum(r["finish"] == "length" for r in rows)))
