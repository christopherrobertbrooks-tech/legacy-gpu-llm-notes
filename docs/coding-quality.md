# Coding quality on these cards

[← back to the overview](../README.md)

## Coding quality

### HumanEval (164 problems, greedy, thinking off)

The grader passes all 164 reference solutions and fails a `return None` stub on
all 164; as a calibration, Qwen2.5-Coder-7B Q4 scores 86.0% against its published
88.4% (bf16).

| Model | Quant | Cards | HumanEval |
| :--- | :--- | :--- | ---: |
| Gemma 4 26B-A4B MoE | Q4_K_M | V100 | 97.6% |
| Gemma 4 26B-A4B MoE | Q8_0 | V100 | 97.0% |
| Muse Glimmer 30B dense | UD-Q4_K_XL | V100 | 96.3% ¶ |
| Qwen3.8-Flash-Next **Coder** 125B MoE (half the experts), via [Strata](strata.md) | IQ1_M | V100 | 96.3% ‖ |
| Qwen3.8 27B dense | Q8_0 | V100 | 95.1% |
| Gemma 4 12B | QAT Q4 | V100 | 94.5% |
| Qwen3-Coder-Next 80B-A3B | UD-Q3_K_XL | both | 94.5% |
| Qwen3.6 35B-A3B MoE | UD-Q4_K_M | V100 | 94.5% † |
| Ornith-1.0 35B-A3B MoE | Q4_K_M | V100 | 94.5% † |
| Qwen3.8-Flash-Next 125B MoE (all experts), via [Strata](strata.md) | IQ2_XS (2-bit) | both | 93.9% ‖ |
| Qwen3-Coder-Next 80B-A3B | UD-Q2_K_XL (2-bit) | V100 | 92.7% |
| Qwen3.5 122B-A10B | UD-IQ2_M (2-bit) | both | 92.1% |
| DiffusionGemma 26B-A4B (diffusion LM) | Q8_0 | both | 92.1% ‡ |
| Qwen3-Coder-Next 80B-A3B | UD-IQ3_S | V100 | 90.9% |
| Ternary Bonsai 2 27B | PQ2_0 | V100 | 89.6% |
| DiffusionGemma 26B-A4B (diffusion LM) | Q4_K_M | V100 | 89.0% ‡ |
| Qwen2.5-Coder 7B | Q4_K_M | V100 | 86.0% |
| Llama 3.3 70B dense | IQ4_XS | both | 85.4% |
| LFM2 24B-A2B MoE (no reasoning) | Q8_0 | V100 | 84.8% |
| Qwen3.5 4B | Q8_0 | V100 | 82.3% |
| GLM-4.7-Flash 30B-A3B MoE | Q4_K_M | V100 | 81.1% † |
| Mistral Small 4 119B-A6B MoE | UD-IQ2_M (2-bit) | both | 83.5% § |

† Run through llama-swap at the **maker's recommended sampling** (temperature
0.6–1.0), not greedy. Re-running Gemma 4 26B Q4 the same way (temperature 0.7)
scored exactly its greedy 97.6%. ‡ The diffusion model's own decoder defaults,
seed 1 — see [DiffusionGemma](#diffusiongemma-26b-a4b-on-the-v100-llamacpp-pr-24423) below.
§ Temperature 0.3 (Mistral gives a 0.0–0.7 range for reasoning off); "fair" score,
64.0% strict — it indents whole answers ([details](#changing-how-many-experts-a-moe-uses-4-models)).
¶ Greedy, with reasoning on at Meta's lowest setting (`Reasoning strength: low` in the system prompt; median
~1,000 characters of reasoning per answer) — 42 minutes for the set. See the SWE-bench note below.
‖ Through Strata's server, `reasoning_effort: none`, temperature 0; 7.1 min (Coder, V100 alone) and 7.2 min (full model
split across both cards). The full model at 2-bit scored below the Coder despite keeping every expert.

**Read this for quantisation loss, not for ranking models.** HumanEval is from
2021 and 2026 models have almost certainly seen it: most of these land between
89% and 98%. Within one model it is still a fair comparison — Coder-Next loses
about 2 points from 3-bit to 2-bit (±2 points is single-run noise at n=164), and
Gemma 4 26B shows no difference between Q4 and Q8. **It also ranks agent work
wrongly:** Gemma 4 26B tops this table but came third of four on real bug fixes
([SWE-bench](#swe-bench-verified-as-a-coding-agent-20-tasks) below).

**Thinking on** (Gemma 4 26B Q4, 4,096-token thinking budget): 161/164 (98.2%)
against 160 — but 69 minutes against 6.3. Two of its three misses hit the
6,144-token answer cap mid-thought and pass when given room (163/164).

### LiveCodeBench v6 (175 contest problems, Jan–Apr 2025) — Gemma 4 26B-A4B Q4

[LiveCodeBench](https://livecodebench.github.io/) problems come from LeetCode,
AtCoder and Codeforces and are graded on hidden tests with LCB's own checker.
Its inference path needs vLLM (no sm_70 build), so generation goes through
llama-server and grading through `lcb_runner` unchanged. The grader was checked
both ways first: empty and wrong programs pass 0/175; four hand-written correct
solutions (stdin and LeetCode-style) pass 4/4; an off-by-one variant fails.

Settings: thinking on, capped at 4,096 tokens (`--reasoning-budget 4096`), 12K
answer budget, temperature 0. **Check-and-fix** mirrors a write-test-fix coding
loop: the first answer is run against the problem statement's *public example*
tests only; if one fails, the model is shown that failure (input, expected, got)
and gets one retry. It never sees the hidden tests.

| Difficulty | First try | With one check-and-fix | Retries: fixed / broken |
| :--- | ---: | ---: | ---: |
| Easy (43) | 100% | **100%** | 0 / 0 |
| Medium (52) | 73% | **79%** | 3 / 0 |
| Hard (80) | 41% | **49%** | 6 / 0 |
| **Overall (175)** | **65.1%** | **70.3%** | 9 / 0 |

- **Google's published figure is 77.1%** ([model card](https://huggingface.co/google/gemma-4-26B-A4B-it)),
  single attempt, with thinking unrestricted and their recommended sampling
  (temperature 1.0, top_p 0.95, top_k 64). The comparable number here is the
  first-try 65.1%. Gemma used the full 4K thinking budget on every medium problem
  (shortest answer 4,530 tokens), so the cap is the likely main difference.
- **Thinking budget is the big lever**: an earlier run at 1K thinking / 8K answers,
  no retry, scored 54.3% overall (medium 56%). 4K thinking took medium to 73%.
- **Q8 bought nothing**: Q8_0 on the same 52 medium problems scored exactly the
  same (73% → 79%), 18% slower.
- **Contamination caveat**: these problems predate Gemma 4, so it may have seen
  some. The within-model gains (budget, check-and-fix) are the most trustworthy
  numbers; the absolute score probably reads somewhat high.
- **A non-thinking model does poorly here**: Qwen3-Coder-Next with thinking off
  reasons inside code comments on hard problems and hit the answer cap on ~half
  of them at 4K; doubling to 8K rescued only 2 of 19. Run abandoned — good at
  everyday code (HumanEval above), wrong tool for contest problems.
- Throughput: 4 parallel streams on one V100 (`-np 4`, 19.2 GB) — easy took
  65 min, hard ~100 min.

### SWE-bench Verified as a coding agent (20 tasks)

HumanEval asks for one function from scratch. [SWE-bench Verified](https://www.swebench.com/)
gives a real GitHub issue and the whole repository; the fix is graded on the
project's own hidden tests. Each model ran as an **agent**, through the same
engine as Claude Code (Claude Agent SDK 0.3.283, `claude_code` preset), pointed at
llama-server on the V100 — so these numbers are what a local model does in that
kind of tool, not in a harness tuned for the benchmark.

- **Tasks:** 20 from the "<15 min fix" group, spread over 8 projects (8 django,
  3 sympy, 2 each sphinx / matplotlib / scikit-learn, 1 each pytest / requests /
  xarray), fixed seed. 20 is a small sample: read a 1–2 task gap as a hint.
- **Rules:** each task in its own SWE-bench container with **no network** (the
  first trial run reached the internet, so a model could have fetched the real
  fix); web tools off; Python and tests run *inside* the container through a
  small wrapper ([`tx`](../buyers-bench/swebench/tx)); 30-minute / 100-step limit.
- **Grading:** the official `swebench` 5.0.2 harness. New scratch files and folders
  the agent created outside the project's own source tree are dropped before
  grading (one patch was 32,791 lines of a Sphinx `_build/`), the same for every
  model. Everything at Q4 on the V100 alone, 131K context, each maker's
  recommended sampling, 4,096-token thinking budget.

| Model (Q4, V100) | Thinking on | Thinking off | HumanEval |
| :--- | :--- | :--- | ---: |
| **Qwen3.6 35B-A3B MoE** | **18/20 — 60 min** | 16/20 — 57 min | 94.5% |
| **Ornith-1.5 35B-A3B MoE** | **18/20 — 79 min** | 16/20 — 49 min | — |
| Ornith-1.0 35B-A3B MoE | 17/20 — 99 min | — | 94.5% |
| Gemma 4 26B-A4B MoE | 16/20 — 149 min | 11/20 — 98 min | 97.6% |
| GLM-4.7-Flash 30B-A3B MoE | 12/20 — 185 min | 10/16 vs 10/16 on (stopped) | 81.1% |
| Muse Glimmer 30B dense | 0/2 — stopped, both hit the 30-min limit | — | 96.3% |

- **HumanEval does not predict this.** Gemma 4 leads HumanEval and is third here;
  Qwen3.6 and Ornith-1.5 are behind it on HumanEval and lead here. They fixed
  the **same** 18 tasks; two tasks beat every model.
- **Ornith's "self-improving" agent training didn't beat the plain Qwen MoE** in
  this tool — 1.5 tied Qwen3.6 (and was slower), 1.0 was one task behind.
- **Thinking is worth two fixes for both leaders** — and the same two
  (django-11433, requests-1724). It costs Qwen3.6 only 5% of the time: it thinks
  briefly on an agent step (median 87 characters; 37% of everything it wrote,
  never near the budget). Ornith-1.5 and Gemma think far more (≈⅔ of their
  output), so switching it off saves them 40% — and Gemma falls apart without
  it (9 tasks hit the step limit, 5 produced nothing).
- **Muse Glimmer (Meta, 28B dense, reasoning strength high) is too slow to be an agent on a V100.**
  It scores 96.3% on HumanEval, but both tasks it tried hit the 30-minute limit with no fix. On the second
  (django-11951, fixed by 12 of the 14 earlier runs; Qwen3.6 took 68 steps in 2 minutes) it took 70 steps
  in 30. Each step pulled in ~14K new tokens (it reads whole source files instead of searching them), at
  ~760 t/s prefill for a dense model on this card — ~25 s before it writes anything — and it filled the
  131K context every ~5 steps, forcing a compaction. Its prompt cache worked; the cost is the model's
  reading habit times dense prefill. Run stopped after two tasks; speed is pp512 717 / tg128 39 t/s.
  [Raw data](../buyers-bench/results/glimmer).
- **Most of an agent step is re-reading the growing context** (prefill), not
  writing — which is why thinking off, and speculative decoding (below), buy
  so little here.
- Raw grading reports, per-task times and steps, and the scripts:
  [results/swebench](../buyers-bench/results/swebench), [swebench/](../buyers-bench/swebench).

### Code reviewer test: prove each bug with a failing test (20 builds)

Workbench's second check uses a model on the 4070 to review the builder's code. This tests that seat. 20 builds of the
same small three-part program (an Etsy inventory/orders CLI), 10 of which fail some of 12 hidden tests. The reviewer
sees the request and the code, never the tests, and must **prove** each bug it claims with a pytest test. Each test
runs on the build and on a known-good build: fails on the build and passes on the good one = a proven bug; fails on
both = a wrong test. Same prompt and settings for every model (`--reasoning-budget 4096`, temperature 0.7, 32K
context, 4070). Scripts and logs: [results/reviewer](../buyers-bench/results/reviewer).

| Reviewer (4070) | Buggy builds with a proven bug | Proven bugs | Wrong tests | Time per build |
| :--- | ---: | ---: | ---: | ---: |
| **Ternary Bonsai 2 27B** PQ2_0 | **8/10** | **25** | 34 of 68 | 95 s |
| Ornith-9B Q6 (stopped after 7 builds) | 2/5 | 3 | 25 of 34 | ~80 s, 7 min on some |
| Gemma 4 12B QAT | 1/10 | 2 | 22 of 114 | 82 s |
| LFM2.5 8B-A1B Q4_K_M | 1/10 | 3 | 29 of 33 | **16 s** |

- **Bonsai stays the reviewer.** It's the only one that finds and proves bugs reliably. It also "proved" a difference in
  5 of the 10 builds that pass the hidden tests; those may be real gaps the hidden tests don't cover.
- **LFM2.5 is 6× faster and nearly useless here.** On 9 builds it dropped the required code block, and the code it did
  write calls helpers with invented signatures, adds a pytest argument that can't resolve, and once isn't valid
  Python. Fluent and fast isn't the same as careful.

### LFM2 / LFM2.5 (Liquid AI): fast, not careful

Liquid AI's on-device family: hybrid MoE models (short-convolution plus a few attention layers) with very few active
parameters. They're the fastest models measured on every card here. Raw data: [results/lfm](../buyers-bench/results/lfm),
[results/pascal](../buyers-bench/results/pascal).

| Model | Card | Generation t/s (short → 32K) | Prompt t/s |
| :--- | :--- | ---: | ---: |
| LFM2 24B-A2B Q8_0 (25.4 GB, 2.3B active) | V100 | **149 → 133** | 1,618 |
| LFM2.5 8B-A1B Q4_K_M (1.5B active, reasoning) | RTX 4070 | **326 → 243** | 11,021 |
| LFM2.5 8B-A1B Q4_K_M | V100 | 273 → 238 | 3,857 |
| LFM2.5 8B-A1B Q4_K_M | GTX 1070 | 108 → 88 | 1,794 |
| LFM2 8B-A1B Q4_K_M | GTX 1070 | 118 → 95 | 1,825 |

For scale: Qwen3.6 35B-A3B, the agent leader, generates ~95 t/s on the V100.

- **The 24B is fast and decent, not a top coder:** HumanEval 139/164 (84.8%, greedy; it's an instruct model with no
  reasoning mode), against Qwen3.6's 153 and Gemma 26B's 160, at 1.5× Qwen3.6's speed and at Q8. Its trained context
  is 32K, so it can't take on the 131K agent runs above.
- **The 8B is a weak judge.** As a code reviewer, LFM2.5 proved a bug in 1 of 10 buggy builds, against Bonsai's 8
  ([reviewer test](#code-reviewer-test-prove-each-bug-with-a-failing-test-20-builds)). As an everyday assistant it was
  accurate on plain questions (explaining an error, summarising) in 3.5–8.5 s with reasoning on. But asked to make a
  blaming customer reply friendly, every LFM2 variant kept the blame.
- **The 8B can't draft for the 24B.** Speculative decoding (8B on the 4070 guessing tokens for the 24B on the V100)
  is impossible, because the two use different vocabularies: llama.cpp refuses with "the target and draft vocabs are
  not compatible" (BOS token id 1 vs 124,894) and serves the 24B undrafted. Same family doesn't mean same tokenizer.
- **Power:** the 1070 numbers are in its section. The V100 and 4070 readings for these models caught the card still
  loading and are being re-measured.
- **Where it fits:** the job it was built for, a fast inner-loop model for tool calls, routing and quick replies, and
  the best everyday model for an 8 GB Pascal card. It's not a builder and not a reviewer.

### DiffusionGemma 26B-A4B on the V100 (llama.cpp PR #24423)

DiffusionGemma is Google's Gemma 4 26B-A4B turned into a block-diffusion LM: it
fills a 256-token block over several refinement passes instead of one token at a
time. llama.cpp support is the unmerged [PR #24423](https://github.com/ggml-org/llama.cpp/pull/24423);
it builds and runs on sm_70 (`-DCMAKE_CUDA_ARCHITECTURES=70`). The PR has no
OpenAI-style server, so HumanEval ran through one `llama-diffusion-cli` process in
conversation mode, with a small **local, not upstream** patch to feed multi-line
prompts and mark the end of each reply ([humaneval_dg.py](../buyers-bench/humaneval_dg.py)).

| DiffusionGemma | HumanEval | Whole run | Typical answer |
| :--- | ---: | ---: | ---: |
| Q4_K_M, thinking off | 89.0% (146) | 10 min | 2.5 s |
| Q4_K_M, thinking on | 89.6% (147) | 62 min | 15.6 s |
| **Q8_0, thinking off** (split, see below) | **92.1% (151)** | 16 min | 3.1 s |
| *Gemma 4 26B-A4B, same test* | *97.6% / 97.0%* | *6.3 min* | *1.6 s* |

- **Speed is about the same as autoregressive Gemma on this card.** One pass over
  a 256-token block takes ~0.33 s and blocks settle in 3–17 passes (the
  entropy-bound decoder stops early), so effective throughput is ~88–136 tok/s
  against Gemma's 92. Diffusion is compute-bound and the V100 is short on compute
  — its big speed claims are for datacentre cards.
- **Q4 costs it ~3 points where autoregressive Gemma loses nothing.** Plausibly
  because every refinement step acts on the logits' confidence, so quantisation
  error compounds. (Sampling isn't greedy here — treat ±3 as suggestive.)
- **Thinking adds almost nothing**: it fixed 8 problems, broke 7, and made answers
  ~8× slower; 8 times it was still thinking when it ran out of room.
- **A known diffusion weakness showed up:** 3 answers stopped at the first block
  boundary mid-docstring instead of continuing into a second block.
- **Memory:** Q4 at `-n 1536` used 23.3 GB — ~15.7 GB of weights plus ~7.5 GB of
  working space (whole-block logits). **Q8 does not fit the V100 alone.** Split
  with the 4070 it ran out of memory with the V100 listed first; listing the 4070
  first (`CUDA_VISIBLE_DEVICES=0,1 -ts 12/88`) puts the last layer and its big
  buffer on the V100, and it ran.

### DFlash speculative decoding on the V100

[DFlash](https://github.com/ggml-org/llama.cpp/issues?q=dflash) is a small
block-diffusion **drafter** (6 layers, ~0.8 GB) that reads the target model's
hidden states and proposes 16 tokens at once for the target to verify. It is in
recent llama.cpp (`-md draft.gguf --spec-type draft-dflash --spec-draft-n-max 16`).
The drafters ship as BF16 safetensors; convert them to **F16** for the V100:
`convert_hf_to_gguf.py <draft dir> --target-model-dir <dir with the target's
config + tokenizer> --outtype f16`.

Qwen3.6 35B-A3B Q4 + [z-lab's drafter](https://huggingface.co/z-lab/Qwen3.6-35B-A3B-DFlash),
greedy, V100 alone ([raw](../buyers-bench/results/dflash/qwen3.6-compare.txt)):

| | tok/s, plain → DFlash | Speed-up | Drafts accepted |
| :--- | ---: | ---: | ---: |
| Thinking off, short answers (code) | 96 → **209** | **2.2×** | 74% |
| Thinking off, long answers | 95 → 114 | 1.2× | 34% |
| Thinking on, short answers | 96 → 118 | 1.2× | 35% |
| Thinking on, long answers | 96 → 96 | 1.0× | 27% |

- **The drafter predicts code well and thinking/prose badly** (an all-prose
  "explain" prompt: 17% accepted, slower than plain).
- **As a coding agent it was 40% slower:** 6 SWE-bench tasks, all fixed either
  way, 20.1 min with DFlash against 14.5 without (2.9 vs 2.3 s per step). Agent
  steps are mostly prefill of a long context, which DFlash can't speed up and the
  drafter adds to. Use it for short, thinking-off answers, not for agents.
- Greedy output is **not byte-identical** with DFlash (6 of 12 diverged, usually
  early, from batched-verification arithmetic flipping near-ties) — but every
  diverged HumanEval answer still passed.
- Ornith-1.5 35B-A3B with its own drafter showed the same pattern: 1.9× on short
  answers, slower on long ones ([raw](../buyers-bench/results/dflash/ornith-1.5-compare.txt)).

### Changing how many experts a MoE uses (4 models)

A MoE's active-expert count is just a number in the GGUF, and llama.cpp can
override it at load — no retraining (this is all the community "A6B" variants
do): `--override-kv qwen35moe.expert_used_count=int:N` (`gemma4.` / `mistral4.`
for those models). The server doesn't log it at normal verbosity; `-lv 4` shows
`n_expert_used = N`, which is how these runs were checked. Memory doesn't change —
every expert is loaded either way; only the compute per token does.

**Qwen3.6 35B-A3B Q4** (256 experts, default 8), V100; HumanEval greedy, prefill at
~2K / ~5K-token prompts ([raw](../buyers-bench/results/experts)); SWE-bench as above
(20 tasks, thinking on, the same 18 fixed wherever 18 is shown):

| Active experts | 3 | 4 | 5 | 6 | **8 (default)** | 12 | 16 |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| HumanEval | 140 | 148 | 155 | 154 | 153 | — | 154 † |
| Prefill tok/s, ~2K / ~5K | 930 / 982 | 824 / 852 | 739 / 760 | 676 / 696 | 585 / 598 | — | 447 † |
| Decode tok/s | 103.5 | 100.7 | 99.4 | 98.1 | 94.6 | — | 85.4 † |
| **SWE-bench fixed** | — | — | 18/20 | — | **18/20** | 18/20 | **15/20** |
| SWE-bench time / steps | — | — | 89 min / 1,997 | — | **60 min / 1,460** | 63 min / 1,581 | 64 min / 1,453 |

† separate run at the maker's sampling, not greedy.

- **Fewer experts read faster but take more agent steps:** 5 experts matched the
  default on HumanEval and read 26% faster, then needed 37% more steps on SWE-bench
  and took 50% longer for the same fixes.
- **More experts cost time and, at 16, fixes** — 16 looked as good as 8 on
  HumanEval and lost 3 of 18 on SWE-bench.
- **Ornith-1.5 35B-A3B** (same design): 12 experts scored 148 vs 145 on HumanEval
  (greedy), then fixed the same 18 SWE-bench tasks in 121 min instead of 79.
- **Gemma 4 26B-A4B** (128 experts, default 8): 6 experts scored 158 vs 160 on HumanEval, then **fixed 14
  SWE-bench tasks instead of 16**, in 130 min / 1,242 steps instead of 149 min / 1,600. It lost three
  (requests-1724, sphinx-9281, and matplotlib-13989, where it produced an empty patch) and gained one
  (sphinx-7889). Unlike Qwen, Gemma took *fewer* steps with fewer experts. It was 13% quicker and less
  accurate, not slower.
- **Every model's default was its best setting for agent work.** Six changed settings were tested on SWE-bench (Qwen3.6
  at 5, 12 and 16; Ornith-1.5 at 12; Gemma at 6), and none fixed more than the default. HumanEval didn't predict
  it: it pointed the wrong way for Qwen at 5 and 16 and for Ornith at 12, and only Gemma's small dip agreed. That's
  the same lesson as DFlash and thinking off.

**Mistral Small 4 119B-A6B** (128 experts, default 4) at **UD-IQ2_M (37.6 GB)**,
split V100 + 4070 (`CUDA_VISIBLE_DEVICES=<V100>,<4070> -ts 75/25`), reasoning off,
temperature 0.3 ([raw](../buyers-bench/results/mistral4)):

| Active experts | HumanEval strict | HumanEval fair | Prefill (~2K prompt) | Decode |
| :--- | ---: | ---: | ---: | ---: |
| 2 | 53.7% (88) | 68.3% (112) | 135 | 64.5 |
| **4 (default)** | 64.0% (105) | **83.5% (137)** | 118 | 58.1 |
| 8 | 84.8% (139) | 84.8% (139) | 94 | 48.6 |

- **At 4 experts it indents every answer** — the whole function shifted right, so
  Python rejects it before the logic is tested. "Fair" removes that indentation
  only when the reply is a complete, shifted `def` (body-only answers are meant to
  be indented; a blanket dedent wrongly cost other models up to 16 points), and
  changed no other model's score ([regrade_dedent.py](../buyers-bench/regrade_dedent.py)).
  **At 8 experts the quirk disappears.** At 2-bit it trails Qwen3.6 at 4-bit by ~10
  points; Qwen3.5 122B at 2-bit held 92.1%.
- **It can't be a coding agent on this pair of cards:** `-fa on` crashes it (MLA,
  key/value 320/256), and without flash attention a **32K** context runs the 4070
  out of memory (+2.2 GB of compute buffer); 16K fits. Agents need 30K–130K.

### Local models as a coding agent's builder (October 2026)

Single-answer scores rank agent work badly, so the candidates also built **real past jobs inside a local coding agent**
(Claude Agent SDK pointed at llama.cpp / Strata): four tasks in an existing Python/GTK project -- two changes to a
100-test codebase, a new dashboard feature with a layout requirement ("drive bars directly under the Net row, Disk first"),
and a bug fix -- graded by acceptance tests plus hidden checks the agent never saw.

- **The recurring failure was layout, not logic.** Ornith 1.5 35B-A3B, Qwen3.6, Qwen3.8 27B and Gemma 4 26B all passed the
  visible tests, but most put the new bars in the wrong order or place at least once (Ornith: right on its own 1 time in 3).
  Screenshots didn't fix it: the models looked and still didn't notice.
- **A second model as reviewer catches about 2 in 3.** Bonsai 2 27B (4070), Qwen3.6 and Gemma 4 (V100) as reviewers each
  missed the reversed order roughly a third of the time, and the 4070-sized reviewer took 4-7 minutes per look.
- **Tests first, proven to fail, closed the gap.** Making the builder write tests for each requirement *before* changing the
  program, and checking they fail on the old code, got the layout right **12 of 12 times** with no reviewer -- for Ornith as
  well as Strata. The missing piece was the test, not a smarter model.
- **Final pick: Qwen3.8-Flash-Next Coder through [Strata](strata.md)** on the V100: 4/4 per round over 3 rounds (12/12),
  ~30-35 minutes per round of 4 jobs, and the clearest messages to the user. Ornith Q5 under the same rules: 4/4, ~31 min.
- **Thinking level matters, in both directions.** On the dashboard task: high 9.7 min, medium 6.5 min, low 10.1 min (less
  planning bought more trial and error), all correct -- one run each.
