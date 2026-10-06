# A 125B model on a V100 with 16 GB of RAM: Strata (October 2026)

[← back to the overview](../README.md)

[Strata](https://github.com/Niko1221/Strata) runs Qwen3.8-Flash-Next -- a mixture-of-experts model with 24,576 small experts,
10 used per token -- on one gaming card, by treating the GPU's memory as a cache for the experts and keeping the rest in
system RAM. It normally asks for 32-64 GB of RAM. Our gateway has **16 GB** (and filling the two free DDR5 slots was quoted
near $1000), but the V100 has 32 GB of VRAM, which turns out to be the part that matters.

**Short version:** the **Coder** version (half the experts, chosen for code) fits entirely on the V100, writes 67-77 tokens/s
at any context up to 128K, scored 158/164 on HumanEval, and became the builder of our local coding agent. The full model
also runs, split across the V100 and the RTX 4070.

## Setup notes

- Volta is an experimental path: CUDA 13 dropped sm_70, so Strata builds a second engine with a CUDA 12.x toolkit
  (setup does it; ~45 s here with CUDA 12.9). Choose the card explicitly: `./setup.sh --family coder --gpu 1 --cuda 12`.
- With 16 GB of RAM, setup's check says no size fits; `--low-ram on` uses the GPU's memory instead. The Coder then holds
  all **12,288** experts on the V100 (11,650 with the vision encoder on); about 8 GB of system RAM stays in use.
- Model files: ~66 GB download for the Coder; the full model's 39 GB main file shares the rest (lookup table, vision encoder).
- Behind [llama-swap](https://github.com/mostlygeek/llama-swap): see Strata's `docs/LLAMA_SWAP.md` (our PR
  [#829](https://github.com/Niko1221/Strata/pull/829)) -- the one trap is a "Host ... is not allowed" refusal when clients use
  a host name (`STRATA_ALLOWED_HOSTS`).

## Speed: the Coder on the V100 alone

Strata's own benchmark script (from the 2x MI50 report), 3 runs each, fresh prompts, 256-token answers, thinking off,
engine 0.1.39. Full report: [Strata PR #823](https://github.com/Niko1221/Strata/pull/823).

| Prompt tokens | Prompt read (tok/s) | Decode (tok/s) | Time to first token |
| ---: | ---: | ---: | ---: |
| 4,096 | 1,233 | 69.3 (67.2–77.1) | 3.4 s |
| 32,768 | 1,580 | 68.6 (64.6–69.0) | 20.8 s |
| 128,000 | 1,394 | 67.1 (65.5–71.6) | 92.0 s |

- **0 MB read from the model files** during any run; the SSD lookup table is touched for ~90 KB per token.
- **The x4 PCIe slot is not a bottleneck here:** 120–150 MB/s into the card during agent work, ~4% of the link.
- For comparison, Strata's own published Coder numbers (other engine versions, so rough): **RTX 5070 12 GB with 64 GB
  RAM, 55 / 43 tok/s** decode (short / 128K) and 2,180 tok/s prompt; **2x MI50, 50 / 46 tok/s** and ~520 prompt. The 2017
  card decodes faster than the 2025 one because 32 GB holds the whole Coder; the 5070 reads prompts faster.

## Correctness

- Long-context recall (Strata's `needle_bench.py`, 32K and 128K, start/middle/end): 6 of 6.
- HumanEval: 158/164 (see [coding quality](coding-quality.md)).
- As a coding agent's builder on 4 real tasks with hidden checks: 12/12 over three rounds, ~30–35 min per round at medium
  thinking ([details](coding-quality.md#local-models-as-a-coding-agents-builder-october-2026)).
- The same four tasks plus a six-phase web app, run three more times on 2026-10-05 (before and after a cleanup of the
  agent's code, and with different sampling): every hidden check passed every time.

- **0.1.40.1 (2026-10-06):** installed side by side with 0.1.39 (model files hard-linked), with
  `"reasoning_loop_recovery": "stop"` (new in 0.1.40, #728) and the 8K reasoning budget: the same baseline passed every
  hidden check (6-13 min a task, six-phase app 21 min), so it became the builder.

## Things we found

- **Images inside a tool result were dropped.** Claude Code-style agents return a screenshot (a Read of a PNG) inside an
  Anthropic `tool_result`; Strata kept only its text, so the model answered about a picture it never saw ("A, B, C, D, E"
  for a dashboard whose rows are "Swap, Net, Disk, Data"). Fixed and tested in our PR
  [#819](https://github.com/Niko1221/Strata/pull/819); another user confirmed it on 4x RTX 5080.
- **A thinking loop:** once in 20 agent jobs, one sentence repeated 1,110 times in a single thought until the 32K output cap
  (~5 min). It started while the model reasoned about that unseen screenshot. A `reasoning_budget_tokens` cap (8K here)
  bounds it: tested directly, a capped thought ends with a wrap-up line and still answers. Reported on
  [#728](https://github.com/Niko1221/Strata/issues/728#issuecomment-5984010954).
- **Claude Code asks for "high" thinking unless told otherwise** (`output_config.effort`); `CLAUDE_CODE_EFFORT_LEVEL=medium`
  was a third faster on one real task, and `low` was slower (more trial and error). One run each.
- **An agent that sends no temperature runs greedy.** Claude Code sends `"temperature": null` (seen by logging its
  requests), and with no `sampling` block in `strata-<model>.json` Strata then decodes greedily -- nothing in the client
  shows it. Greedy vs the Qwen3.8 thinking defaults (`"sampling": {"temperature": 1.0, "top_p": 0.95, "top_k": 20}`) on
  the same five agent jobs (four hidden-test tasks + a six-phase app; greedy twice, sampled once): identical results, no
  runaway thinking in any of the 15 jobs, and the sampled run took about twice as long on the six-phase build (47.5 vs
  24-40 min, prompts up to 97K vs 60K). We kept greedy plus the 8K reasoning budget. Posted on
  [#728](https://github.com/Niko1221/Strata/issues/728#issuecomment-6004214799); 15 jobs are too few to measure a
  ~1-in-20 loop, so this is a data point, not a verdict.
- **Answer room vs context:** Claude Code reserves 32K tokens for each answer. Strata refuses any request where prompt +
  answer room exceeds the context (131,072 here), so a long resumed chat past ~99.5K died for good -- its compaction
  request was refused the same way. `CLAUDE_CODE_MAX_OUTPUT_TOKENS=20000` (thinking is capped at 8K) fixed it: the same
  dead session compacted and finished.
- **Stopping the server stops its engine** (SIGTERM: GPU free in 2 s; closing the terminal: under 1 s). An early suspicion
  that it left the engine running was a check made mid-shutdown; tested before anything was reported.

## Both cards: the full model, V100 + RTX 4070

The full model (all 512 experts per layer, IQ2_XS, ~39 GB) doesn't fit 32 GB but fits 44 GB. Setup rebuilt the engine for
both architectures (`"archs": [70, 89]`) and split the layers itself. Same benchmark, context 131,072, low-RAM mode:

| Card order | Auto split | Decode tok/s 4K / 32K / 128K | Prompt tok/s 4K / 32K / 128K | Recall |
| --- | --- | ---: | ---: | ---: |
| V100 first | V100 layers 0–38, 4070 39–47 | **84.9 / 81.5 / 75.1** | 996 / 1,602 / 1,552 | 6/6 |
| 4070 first | 4070 layers 0–10, V100 11–47 | 79.1 / 83.8 / 77.1 | 985 / 1,535 / 1,533 | 6/6 |

- **Mixed-architecture split works on NVIDIA in both orders**, including prompts far past the 8,192-token chunk -- the case
  that fails on a mixed AMD pair in Strata issue #690.
- A fixed split point changed nothing: in 0.1.39 the automatic split already loads only each card's own layers.
- During long prompts, traffic into the V100 peaks at ~3.6 GB/s -- essentially its whole x4 link (median ~0.4 GB/s), so in
  a split the narrow slot does saturate in bursts while reading prompts; the 4070 peaks at 13.7 GB/s on its x16 slot.
- Against the RTX 5090 community report (same IQ2_XS, 32 GB card + 64 GB RAM: decode 179 / 176 / 165, prompt ~4,300–5,800):
  the 2017 + 2022 pair reaches **~45% of its decode** and ~29% of its prompt speed.
- **But it scored 154/164 on HumanEval**, below the Coder's 158, in the same time -- the full model at 2-bit loses more to
  compression than it gains from keeping every expert, and it ties up both cards. The Coder stays.
