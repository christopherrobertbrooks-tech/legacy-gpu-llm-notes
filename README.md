# Legacy GPU LLM notes — Tesla V100 (sm_70), Pascal GTX 1070, RTX 4070

These are measured notes from running local LLM inference on a Tesla V100
(Volta, sm_70) and a GTX 1070 (Pascal, sm_61), with an RTX 4070 (Ada, sm_89)
as a control card. Most projects only test on newer hardware, so what
actually happens on these cards is largely undocumented. Each repo below is
one focused question with numbers behind it. Some things work that the docs
say shouldn't; some are much slower than expected; and two early claims
turned out to be wrong and were corrected in place.

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

## Is a used V100 32GB worth it? (measured September 2026)

Same machine, same llama.cpp build (PrismML fork `3ae4f51`, CUDA 12.9),
`llama-bench -ngl 99 -fa on -p 512 -n 128 -d 0,16384,32768 -r 3`, one card
visible at a time. Power is whole-board draw from `nvidia-smi` during a
2,048-token generation. Raw CSVs and scripts: [buyers-bench/](buyers-bench/).

**Generation speed, tokens/sec** (short prompt → at 32K tokens of context):

| Model | File | V100 32GB | RTX 4070 12GB | Fits a V100 16GB? |
| :--- | ---: | ---: | ---: | :---: |
| Qwen3.5 4B Q8_0 | 4.5 GB | **107** → 93 | 91 → 73 | yes |
| Qwen2.5-Coder 7B Q4_K_M | 4.7 GB | **123** → 69 | 99 → 71 | yes |
| Gemma 4 12B QAT Q4 | 7.0 GB | **70** → 64 | 60 → 54 | yes |
| Ternary Bonsai 2 27B PQ2_0 | 7.2 GB | 51 → 40 | **54** → 43 | yes |
| Gemma 4 26B-A4B MoE Q4_K_M | 16.9 GB | **92** → 84 | doesn't fit | no, just over |
| Gemma 4 26B-A4B MoE Q8_0 | 26.8 GB | **85** → 79 | doesn't fit | no |
| Qwen3.8 27B dense Q8_0 | 29.0 GB | **24** → 22 | doesn't fit | no |

**Prompt processing, tokens/sec** (pp512, short context) — the 4070 is faster here:

| Model | V100 | RTX 4070 |
| :--- | ---: | ---: |
| Qwen3.5 4B | 4,445 | **5,860** |
| Qwen2.5-Coder 7B | 3,156 | **5,145** |
| Gemma 4 12B | 1,825 | **3,130** |
| Bonsai 2 27B | 758 | **1,266** |
| Gemma 4 26B MoE Q4 / Q8 | 1,320 / 1,022 | — |
| Qwen3.8 27B dense Q8 | 617 | — |

**Power while generating** (idle, nothing loaded: V100 25 W, 4070 13 W):

| Model | V100 | tokens/joule | RTX 4070 | tokens/joule |
| :--- | ---: | ---: | ---: | ---: |
| Qwen3.5 4B | 154 W | 0.69 | 173 W | 0.53 |
| Qwen2.5-Coder 7B | 218 W | 0.56 | 191 W | 0.52 |
| Gemma 4 12B | 178 W | 0.40 | 185 W | 0.32 |
| Bonsai 2 27B | 184 W | 0.28 | 194 W | 0.28 |
| Gemma 4 26B MoE Q4 / Q8 | 135 / 129 W | 0.68 / 0.66 | — | — |
| Qwen3.8 27B dense Q8 | 182 W | 0.13 | — | — |

**Price** (US used market, September 2026 — listings vary widely, check sold
prices, not asking prices): V100 32GB PCIe ~$640–750; V100 16GB PCIe
~$230–540; RTX 3090 24GB ~$1,000–1,350; RTX 4070 ~$485 used / ~$700 new.
Sources: [GPUDojo](https://gpudojo.com/tesla-v100),
[GPUPoet 32GB](https://gpupoet.com/gpu/shop/nvidia-tesla-v100-32gb),
[GPUPoet 16GB](https://gpupoet.com/gpu/shop/nvidia-tesla-v100-16gb),
[BestValueGPU 3090](https://bestvaluegpu.com/history/new-and-used-rtx-3090-price-history-and-specs/),
[BestValueGPU 4070](https://bestvaluegpu.com/history/new-and-used-rtx-4070-price-history-and-specs/).

**What it adds up to:**
- Generation is 15–25% faster than a new 4070 on everything but the ternary
  model — HBM2 bandwidth. Prompt processing is 1.3–1.7× slower.
- 32 GB is the point: the three largest models above don't fit on a 12 GB
  card, and Gemma 4 26B at Q4 misses a 16 GB V100 by a hair. A MoE at 85–92
  t/s that barely slows at 32K context is the sweet spot.
- Dense 27B+ models run, but at ~24 t/s; MoE models are the better fit (below).
- The traps are real but solved below: use CUDA 12.x (13 dropped Volta),
  never bf16 (convert to f16), and check flash attention per model.
- It's a passive datacenter card: it needs forced airflow, and the PCIe
  version fits a normal x16 slot.

### MoE models are the V100's sweet spot

A mixture-of-experts model uses only a slice of its weights per token, so it
needs a lot of memory but little compute — exactly what this card has. Gemma 4
26B-A4B (4B active) generates at 92 t/s against 24 t/s for the dense Qwen3.8 27B
on the same card, and barely slows at 32K context. The V100-specific part is the
32 GB: it holds the whole MoE, where a 12 GB card can't load it and a 16 GB V100
misses by a hair. (Not claimed: that it beats other 32 GB+ cards on MoE — that
wasn't measured.)

### Splitting a model across two cards (V100 + 4070 = 44 GB)

A V100 and a 4070 in one box work together in llama.cpp (`-sm layer`), with
no VRAM leak — see [volta-dual-card](https://github.com/christopherrobertbrooks-tech/volta-dual-card).
**Only split when the model doesn't fit on one card**: for a model that fits,
the fastest single card wins (splitting cost a dense 27B 9.6% of its decode).
`-sm row` failed to load on the mixed pair. What 44 GB buys:

| Model | File | Cards | pp512 | tg128 | tg128 deep |
| :--- | ---: | :--- | ---: | ---: | ---: |
| Llama 3.3 70B dense IQ4_XS | 37.9 GB | both | 336 | **16.6** | 15.7 @ 8K |
| Qwen3-Coder-Next 80B-A3B UD-Q3_K_XL | 36.3 GB | both | 557 | **76.5** | 74.8 @ 16K |
| Qwen3.5 122B-A10B UD-IQ2_M | 39.1 GB | both | 484 | **56.3** | 55.1 @ 16K |
| Qwen3-Coder-Next 80B-A3B UD-Q2_K_XL | 26.8 GB | **V100 alone** | 469 | **74.9** | 73.5 @ 16K |
| Qwen3-Coder-Next 80B-A3B UD-IQ3_S | 29.7 GB | **V100 alone** | 465 | 69.1 | 70.7 @ 16K |

The 70B fills 29.7 GB of the V100 and 11.2 GB of the 4070 — about the ceiling —
and draws ~280 W across both cards. System RAM on this box is 16 GB, so nothing
here spills to CPU; everything is fully offloaded (`-ngl 99`).

## Coding quality

### HumanEval (164 problems, greedy, thinking off)

The grader passes all 164 reference solutions and fails a `return None` stub on
all 164; as a calibration, Qwen2.5-Coder-7B Q4 scores 86.0% against its published
88.4% (bf16).

| Model | Quant | Cards | HumanEval |
| :--- | :--- | :--- | ---: |
| Gemma 4 26B-A4B MoE | Q4_K_M | V100 | 97.6% |
| Gemma 4 26B-A4B MoE | Q8_0 | V100 | 97.0% |
| Qwen3.8 27B dense | Q8_0 | V100 | 95.1% |
| Gemma 4 12B | QAT Q4 | V100 | 94.5% |
| Qwen3-Coder-Next 80B-A3B | UD-Q3_K_XL | both | 94.5% |
| Qwen3-Coder-Next 80B-A3B | UD-Q2_K_XL (2-bit) | V100 | 92.7% |
| Qwen3.5 122B-A10B | UD-IQ2_M (2-bit) | both | 92.1% |
| Qwen3-Coder-Next 80B-A3B | UD-IQ3_S | V100 | 90.9% |
| Ternary Bonsai 2 27B | PQ2_0 | V100 | 89.6% |
| Qwen2.5-Coder 7B | Q4_K_M | V100 | 86.0% |
| Llama 3.3 70B dense | IQ4_XS | both | 85.4% |
| Qwen3.5 4B | Q8_0 | V100 | 82.3% |

**Read this for quantisation loss, not for ranking models.** HumanEval is from
2021 and 2026 models have almost certainly seen it: nine of twelve land between
89% and 98%. Within one model it is still a fair comparison — Coder-Next loses
about 2 points from 3-bit to 2-bit (±2 points is single-run noise at n=164), and
Gemma 4 26B shows no difference between Q4 and Q8.

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
| [volta-hadamard](https://github.com/christopherrobertbrooks-tech/volta-hadamard) | A Hadamard rotation tool for Prism's PQ2_0 format | Rotating weights improves llama.cpp's own Q2_K by **17.8%** on Qwen3-4B (wikitext-2, 200 chunks, clear of the error bars). The benefit tracks how much damage Q2_K did: a MoE model that Q2_K barely hurt saw nothing. Prism's own public ternary quantizer is a stub |

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

## Offer

I have this hardware sitting here — a Tesla V100, a GTX 1070, and an RTX 4070
— and most projects only test on newer cards, so behaviour on sm_70, Pascal
and Ada often just isn't known. If you need something run on one of these,
point me at a branch and a command and I'll run it and post the output.

To be clear about scope: I'm offering to run things and report exactly what
happened — numbers and logs from real hardware. I'm not offering to review
your code, argue about design, or defend a patch.
