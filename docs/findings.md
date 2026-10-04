# Findings by question, and corrections

[← back to the overview](../README.md)

## Findings by question

### Works on sm_70 / sm_61 despite documentation saying otherwise

- **MXFP4** — documented as requiring compute capability ≥ 9.0 (Hopper+). Runs on the V100 (7.0) at 143–144 t/s with correct output. [volta-gpt-oss](https://github.com/christopherrobertbrooks-tech/volta-gpt-oss)
- **Ternary kernels (PQ2_0 / PTQ1_0)** — greedy output token-identical to an RTX 4070 run. The two packings invert their relative speed ranking between the two cards. [volta-bonsai](https://github.com/christopherrobertbrooks-tech/volta-bonsai)
- **Vision on Volta** — correct on a dense table with SKU codes, prices and footnotes, including leading zeros. Image encode 158–394 ms. [volta-bonsai](https://github.com/christopherrobertbrooks-tech/volta-bonsai)
- **ik_llama.cpp** — an open upstream issue states Volta is not officially supported. It builds with zero source changes and runs correctly. [volta-ik-llama](https://github.com/christopherrobertbrooks-tech/volta-ik-llama)
- **Diffusion LMs** (`dream`, via `llama-diffusion-cli`) — run on Volta at 274.1 ms/step. [volta-diffusion](https://github.com/christopherrobertbrooks-tech/volta-diffusion)
- **DiffusionGemma (llama.cpp PR #24423)** — builds for sm_70 and runs; 89.0% HumanEval at Q4, 92.1% at Q8. [DiffusionGemma](coding-quality.md#diffusiongemma-26b-a4b-on-the-v100-llamacpp-pr-24423)
- **DFlash drafters** — convert to F16 and run on sm_70; 2.2× on short thinking-off code. [DFlash](coding-quality.md#dflash-speculative-decoding-on-the-v100)
- **Mixed-architecture layer split** (sm_70 + sm_89 in one job) — works, no VRAM leak; beat the V100 alone by 5.5% decode on a MoE model. [volta-dual-card](https://github.com/christopherrobertbrooks-tech/volta-dual-card)
- **Flash-attention tile kernel on Pascal** — built for `sm_61;sm_70` and verified with `cuobjdump` to contain both. `test-backend-ops -o FLASH_ATTN_EXT -p "hsk=192"` gives **66 OK / 0 FAIL on the GTX 1070 and 66/0 on the V100**, covering GQA ratios 1, 4 and 5 — the non-multiples of 8 that previously hit a hard abort. [volta-deepseek-mla/pr26404-test](https://github.com/christopherrobertbrooks-tech/volta-deepseek-mla/tree/main/pr26404-test)

- **A 125B mixture-of-experts model on one V100 with 16 GB of system RAM** (Strata, experimental CUDA 12 path): the Coder
  version is fully VRAM-resident, 67–77 tok/s decode to 128K. [Strata](strata.md)
- **Mixed-architecture layer split in Strata** (sm_70 + sm_89): works in both card orders, long prompts included -- the
  pattern that fails on a mixed AMD pair (Strata #690). [Strata](strata.md#both-cards-the-full-model-v100--rtx-4070)
- **The V100's PCIe 3.0 x4 slot** uses ~4% of its link with a resident MoE model; ~50% only during long-prompt reading
  in a two-card split. [Buyer's guide](v100-buyers-guide.md)

### Performance traps

- **BF16 costs the V100 77% of prefill.** Volta has no BF16 hardware; the identical model in F16 is 4.37× faster at prefill on the same card. Decode is unaffected. [volta-bf16](https://github.com/christopherrobertbrooks-tech/volta-bf16)
- **DeepSeek flash-attention regression.** `-fa on` costs 80% of decode on the V100 and 52% on the 4070, with byte-identical output and no warning. The cause is the model's attention head shape (192/128, GQA ratio 1), not the GPU — see [Corrections](#corrections). [volta-deepseek-mla](https://github.com/christopherrobertbrooks-tech/volta-deepseek-mla)
  **GLM-4.7-Flash**, also MLA (`deepseek2` arch, key/value 576/512), is **not** caught by it: `-fa on` is −7% decode, +7% prefill. Measure per model.
- **DFlash slows a coding agent down** (−40% on SWE-bench tasks) even though it doubles short thinking-off answers. [DFlash](coding-quality.md#dflash-speculative-decoding-on-the-v100)
- **Mistral Small 4 (`mistral4`, MLA 320/256) crashes with `-fa on`,** and without it can't reach a 32K context across 44 GB. [Experts](coding-quality.md#changing-how-many-experts-a-moe-uses-4-models)
- **Changing a MoE's expert count never beat the default as an agent** — fewer experts add steps, more add cost. [Experts](coding-quality.md#changing-how-many-experts-a-moe-uses-4-models)

- **Too little thinking can be slower:** on a real agent task, low effort took longer than medium (more trial-and-fix
  steps). [Coding quality](coding-quality.md#local-models-as-a-coding-agents-builder-october-2026)

### Tooling gotchas

- **Use `llama-bench`, not `llama-cli`, to benchmark.** A ~20-token prompt in `llama-cli` undershot the real prefill number by roughly 6×.
- **`llama-diffusion-cli` defaults abort.** Exactly one of `--diffusion-eps` / `--diffusion-block-length` must be non-zero, and both default to zero, so the stock invocation core-dumps before generating anything.
- **`-ts` is slash-separated, not comma-separated.** `-ts 0,1` silently runs two separate benchmark configs instead of one ratio, and can print a plausible-looking number before failing.
- **`-sm row` fails to load** on this mixed card pair, independent of memory pressure (confirmed with a model needing only ~4.8 GiB/card).
- **Claude Code–style agents send a second system message after the user turn** (the environment block: working directory, platform). Templates with `raise_exception('System message must be at the beginning.')` — Ornith's recommended template, both 1.0 and 1.5 — refuse **every** request with HTTP 500. Render non-first system messages in place instead. Qwen3.6, GLM and Gemma accept it as shipped.
- **Agents ignore a server-side "thinking off" unless the server forces it.** The Agent SDK sends `thinking: {type: adaptive}` on every request; `--reasoning off --reasoning-budget 0` overrides it.
- **Docker 29 keeps images in `/var/lib/containerd`, not `data-root`.** Twenty SWE-bench images (47 GB) filled a root disk despite `daemon.json` pointing elsewhere; relocate `/var/lib/containerd` before pulling.


- **Claude Code asks for `effort: high` on every request** (`output_config.effort`), so local servers that map it think at
  their highest level; `CLAUDE_CODE_EFFORT_LEVEL` changes it. [Strata](strata.md#things-we-found)
- **Images inside an Anthropic `tool_result` can be dropped by a local server** -- the agent then "sees" a screenshot it
  never received. Found in Strata, fixed in PR #819. [Strata](strata.md#things-we-found)

## Corrections

Two claims in these repos were wrong on the first pass and were corrected in
place. Both were caught by running a control rather than trusting the first
result. They are listed here on purpose: they are the reason to trust the other
numbers, not a reason to doubt them.

1. **The DeepSeek flash-attention regression was first called Volta-specific.**
   The initial commit attributed the `-fa on` decode collapse to Volta, since it
   matched FlashMLA's documented Ampere-or-newer floor. Running the RTX 4070 as a
   control showed it regresses too — −52% decode, against −80% on the V100. The
   selector in `ggml/src/ggml-cuda/fattn.cu` confirmed the real cause: it gates
   on head dimensions and GQA ratio, never on compute capability.
   (`volta-deepseek-mla`, commit `455c09b`.)

2. **volta-hadamard first claimed a clean crossover** — rotation hurting
   perplexity at 4-bit and helping below it — from a single model (Qwen3-4B).
   A second model (Qwen3-8B) showed the Q3_K_M and Q4_K_M results flip sign
   between models, so they were noise. The crossover claim was retracted.

   Then the measurement itself turned out to be the weak part. Those runs used
   20 chunks of an unsaved corpus and recorded no error bars, so nothing from
   them could be trusted in either direction. Re-run on wikitext-2 at 200
   chunks with error bars, Qwen3-4B Q2_K goes 36.1895 → 29.7360: **−17.8%**,
   cleanly separated — four times the effect originally reported. The first
   number was understated, not invented, but it was not evidence either way.
   (`volta-hadamard`, commits `01acf8d` and `fc58596`.)

A third thing worth stating plainly: a `-fa` before/after diff of which
individual test cases newly pass was **not** established, because the unpatched
control sits at a different commit whose harness emits different case strings.
The two logs are not comparable and an attempted diff produced meaningless
"regressions".
