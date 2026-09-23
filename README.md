# Legacy GPU LLM notes — Tesla V100 (sm_70), Pascal GTX 1070, RTX 4070

> **DRAFT — Chris to rewrite this block in his own words, then delete this line.**
>
> These are measured notes from running local LLM inference on a Tesla V100
> (Volta, sm_70) and a GTX 1070 (Pascal, sm_61), with an RTX 4070 (Ada, sm_89)
> as a control card. Most projects only test on newer hardware, so what
> actually happens on these cards is largely undocumented. Each repo below is
> one focused question with numbers behind it. Some things work that the docs
> say shouldn't; some are much slower than expected; and two early claims
> turned out to be wrong and were corrected in place.

## Hardware

Two machines. Full spec for the first in
[volta-bonsai/ENVIRONMENT.md](https://github.com/christopherrobertbrooks-tech/volta-bonsai/blob/main/ENVIRONMENT.md).

| | host | CPU | GPU | role |
| :--- | :--- | :--- | :--- | :--- |
| 1 | `ember-gateway`, Ubuntu 24.04 | i7-13700KF, 24 threads | **Tesla V100-PCIE-32GB**, compute 7.0 | the subject |
| 1 | " | " | RTX 4070, 12 GB, compute 8.9 | control card |
| 2 | `dev-console` | i5-7400 | **GeForce GTX 1070**, compute 6.1 | Pascal testing |

- Driver 580.173.02, CUDA 12.9.86 — **CUDA 13 dropped Volta, so 12.x is required**
- The V100 runs its PCIe link downgraded to x4 (8 GT/s); the 4070 at x16

## The table

| Repo | Tested | Result |
| :--- | :--- | :--- |
| [volta-bonsai](https://github.com/christopherrobertbrooks-tech/volta-bonsai) | Ternary-Bonsai-2-27B (PQ2_0/PTQ1_0), V100 vs 4070 | Ternary kernels and vision both work on Volta; PQ2_0 decode (50.97 t/s) beats PTQ1_0 (34.40 t/s) on the V100 — the opposite ranking to the 4070 |
| [volta-gpt-oss](https://github.com/christopherrobertbrooks-tech/volta-gpt-oss) | gpt-oss-20b MXFP4 on V100 | 143–144 t/s decode, despite MXFP4 being documented as needing compute capability ≥ 9.0 |
| [volta-deepseek-mla](https://github.com/christopherrobertbrooks-tech/volta-deepseek-mla) | DeepSeek-V2-Lite flash attention, V100 + 4070 + GTX 1070 | `-fa on` costs 80% of decode on the V100 and 52% on the 4070 — a model-shape bug, not Volta-specific (corrected). Also: PR #26404's suggested tile-kernel patch passes 66/0 on both Pascal and Volta |
| [volta-ik-llama](https://github.com/christopherrobertbrooks-tech/volta-ik-llama) | ik_llama.cpp build + IQK trellis quants, V100 | Builds clean with no source changes on sm_70; IQ4_KT runs, 21% smaller for 13% slower decode |
| [volta-dual-card](https://github.com/christopherrobertbrooks-tech/volta-dual-card) | Mixed sm_70 + sm_89 layer split (`-sm layer`) | Works, no VRAM leak; helps a MoE model (+5.5% decode) and hurts a dense 27B (−9.6%) |
| [volta-diffusion](https://github.com/christopherrobertbrooks-tech/volta-diffusion) | Dream-v0-Instruct-7B diffusion LM, V100 | Runs; 274.1 ms/step vs the 4070's 237.6 ms/step |
| [volta-bf16](https://github.com/christopherrobertbrooks-tech/volta-bf16) | BF16 vs F16 prefill, V100 (Qwen3-4B) | BF16 costs the V100 77% of its prefill — Volta has no BF16 hardware. Convert to F16 first |
| [volta-hadamard](https://github.com/christopherrobertbrooks-tech/volta-hadamard) | A Hadamard rotation tool for Prism's PQ2_0 format | **In progress.** The rotation math works and survives quantization; Prism's own public ternary quantizer is a stub, so public PQ2_0 cannot be reproduced |

Also here, not a GPU finding:
[ember-voice-lora](https://github.com/christopherrobertbrooks-tech/ember-voice-lora)
— building a LoRA fine-tuning set from 3,337 logged conversation episodes (508
curated pairs; no model trained yet).

## Findings by question

### Works on sm_70 / sm_61 despite documentation saying otherwise

- **MXFP4** — documented as requiring compute capability ≥ 9.0 (Hopper+). Runs on the V100 (7.0) at 143–144 t/s with correct output. [volta-gpt-oss](https://github.com/christopherrobertbrooks-tech/volta-gpt-oss)
- **Ternary kernels (PQ2_0 / PTQ1_0)** — greedy output token-identical to an RTX 4070 run. The two packings invert their relative speed ranking between the two cards. [volta-bonsai](https://github.com/christopherrobertbrooks-tech/volta-bonsai)
- **Vision on Volta** — correct on a dense table with SKU codes, prices and footnotes, including leading zeros. Image encode 158–394 ms. [volta-bonsai](https://github.com/christopherrobertbrooks-tech/volta-bonsai)
- **ik_llama.cpp** — an open upstream issue states Volta is not officially supported. It builds with zero source changes and runs correctly. [volta-ik-llama](https://github.com/christopherrobertbrooks-tech/volta-ik-llama)
- **Diffusion LMs** (`dream`, via `llama-diffusion-cli`) — run on Volta at 274.1 ms/step. [volta-diffusion](https://github.com/christopherrobertbrooks-tech/volta-diffusion)
- **Mixed-architecture layer split** (sm_70 + sm_89 in one job) — works, no VRAM leak; beat the V100 alone by 5.5% decode on a MoE model. [volta-dual-card](https://github.com/christopherrobertbrooks-tech/volta-dual-card)
- **Flash-attention tile kernel on Pascal** — built for `sm_61;sm_70` and verified with `cuobjdump` to contain both. `test-backend-ops -o FLASH_ATTN_EXT -p "hsk=192"` gives **66 OK / 0 FAIL on the GTX 1070 and 66/0 on the V100**, covering GQA ratios 1, 4 and 5 — the non-multiples of 8 that previously hit a hard abort. [volta-deepseek-mla/pr26404-test](https://github.com/christopherrobertbrooks-tech/volta-deepseek-mla/tree/main/pr26404-test)

### Performance traps

- **BF16 costs the V100 77% of prefill.** Volta has no BF16 hardware; the identical model in F16 is 4.37× faster at prefill on the same card. Decode is unaffected. [volta-bf16](https://github.com/christopherrobertbrooks-tech/volta-bf16)
- **DeepSeek flash-attention regression.** `-fa on` costs 80% of decode on the V100 and 52% on the 4070, with byte-identical output and no warning. The cause is the model's attention head shape (192/128, GQA ratio 1), not the GPU — see [Corrections](#corrections). [volta-deepseek-mla](https://github.com/christopherrobertbrooks-tech/volta-deepseek-mla)

### Tooling gotchas

- **Use `llama-bench`, not `llama-cli`, to benchmark.** A ~20-token prompt in `llama-cli` undershot the real prefill number by roughly 6×.
- **`llama-diffusion-cli` defaults abort.** Exactly one of `--diffusion-eps` / `--diffusion-block-length` must be non-zero, and both default to zero, so the stock invocation core-dumps before generating anything.
- **`-ts` is slash-separated, not comma-separated.** `-ts 0,1` silently runs two separate benchmark configs instead of one ratio, and can print a plausible-looking number before failing.
- **`-sm row` fails to load** on this mixed card pair, independent of memory pressure (confirmed with a model needing only ~4.8 GiB/card).

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
   between models, so they were noise at that magnitude. Only Q2_K reproduced:
   −4.3% on Qwen3-4B and −4.7% on Qwen3-8B. The crossover claim was retracted.
   The surviving, narrower finding is that rotation improves Q2_K by about 4–5%
   and does nothing reliable above 2 bits.
   (`volta-hadamard`, commit `01acf8d`.)

A third thing worth stating plainly: a `-fa` before/after diff of which
individual test cases newly pass was **not** established, because the unpatched
control sits at a different commit whose harness emits different case strings.
The two logs are not comparable and an attempted diff produced meaningless
"regressions".

## Offer

> **DRAFT — Chris to rewrite this block in his own words, then delete this line.**
>
> I have this hardware sitting here — a Tesla V100, a GTX 1070, and an RTX 4070
> — and most projects only test on newer cards, so behaviour on sm_70, Pascal
> and Ada often just isn't known. If you need something run on one of these,
> point me at a branch and a command and I'll run it and post the output.
>
> To be clear about scope: I'm offering to run things and report exactly what
> happened — numbers and logs from real hardware. I'm not offering to review
> your code, argue about design, or defend a patch.
