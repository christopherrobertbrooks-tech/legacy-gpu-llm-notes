# Legacy GPU LLM notes — Tesla V100 (sm_70), Pascal GTX 1070, RTX 4070

<!-- DRAFT: Chris to rewrite in his own words -->
<!--
These are measured notes from running local LLM inference on a Tesla V100
(Volta, sm_70) alongside an RTX 4070 (Ada, sm_89), because most projects only
test on newer hardware and the actual behavior on older cards is undocumented.
Nine repos, each a focused question with numbers behind it — some things work
that the docs say shouldn't, some things are slower than expected, and a
couple of early claims turned out to be wrong and got corrected in place.
-->

## Hardware

From [`volta-bonsai/ENVIRONMENT.md`](../volta-bonsai/ENVIRONMENT.md):

- Host: `ember-gateway`, Ubuntu 24.04, i7-13700KF, 15 GB RAM, 24 threads
- GPU 0: NVIDIA GeForce RTX 4070 — compute 8.9 (Ada), 12 GB — control card
- GPU 1: Tesla V100-PCIE-32GB — compute 7.0 (Volta), 32 GB — the subject
- Driver 580.173.02
- CUDA 12.9.86 (`/usr/local/cuda-12.9/bin/nvcc`) — CUDA 13 dropped Volta, so 12.x is required
- The V100 runs its PCIe link downgraded to x4 (Speed 8GT/s), the 4070 at x16

## The table

| Repo | Tested | One-line result |
| :--- | :--- | :--- |
| [volta-bonsai](../volta-bonsai/) | Ternary-Bonsai-2-27B (PQ2_0/PTQ1_0) on V100 vs 4070 | Ternary kernels and vision work on Volta; PQ2_0 decode (50.97 t/s) beats PTQ1_0 (34.40 t/s) on V100, the opposite of the 4070 |
| [volta-gpt-oss](../volta-gpt-oss/) | gpt-oss-20b MXFP4 on V100 | Runs at 143-144 t/s decode despite MXFP4 being documented as requiring compute capability >= 9.0 |
| [volta-deepseek-mla](../volta-deepseek-mla/) | DeepSeek-V2-Lite flash attention, V100 + 4070 | `-fa on` costs 80% of decode on V100 and 52% on 4070 — a model-shape bug, not Volta-specific (corrected) |
| [volta-ik-llama](../volta-ik-llama/) | ik_llama.cpp build + IQK trellis quants on V100 | Builds clean with no source changes on sm_70; IQ4_KT trellis quant runs, 21% smaller for 13% slower decode |
| [volta-dual-card](../volta-dual-card/) | Mixed sm_70/sm_89 layer split (`-sm layer`) | Works with no VRAM leak; helps a MoE model (+5.5% decode) but hurts a dense 27B (-9.6%) — bandwidth-bound |
| [volta-diffusion](../volta-diffusion/) | Dream-v0-Instruct-7B diffusion LM on V100 | Runs; V100 274.1 ms/step vs 4070's 237.6 ms/step (4070 15% faster, compute-bound workload) |
| [volta-bf16](../volta-bf16/) | BF16 vs F16 prefill on V100 (Qwen3-4B) | BF16 costs the V100 77% of prefill (no BF16 hardware on Volta) — convert to F16 first |
| [volta-hadamard](../volta-hadamard/) | Rolling a Hadamard rotation tool for Prism's PQ2_0 format | **In progress** (MoE experiment mid-run). So far: rotation math works and survives quantization, but Prism's own ternary quantizer is a stub — public PQ2_0 cannot be reproduced |
| [ember-voice-lora](../ember-voice-lora/) | Building a LoRA fine-tune dataset from 3,337 logged episodes | Dataset built (508 curated pairs); no model trained yet |

## Findings by question

### Things that work on sm_70 despite being documented otherwise

- **MXFP4 on gpt-oss-20b** — documented as requiring compute capability >= 9.0 (Hopper+); runs on the V100 (7.0) at 143-144 t/s with correct output. [volta-gpt-oss](../volta-gpt-oss/)
- **Ternary kernels (PQ2_0/PTQ1_0)** — greedy output token-identical to an RTX 4070 run; the two packings actually invert their relative speed ranking between the two cards. [volta-bonsai](../volta-bonsai/)
- **Vision on Volta** — verified correct on a dense table with SKU codes, prices, and footnotes; image encode 158-394 ms. [volta-bonsai](../volta-bonsai/)
- **ik_llama.cpp build** — an open upstream issue states Volta is not officially supported; it builds with zero source changes and zero compiler errors, and runs correctly. [volta-ik-llama](../volta-ik-llama/)
- **Diffusion LMs** (`dream` architecture, `llama-diffusion-cli`) — runs on Volta, 274.1 ms/step vs the 4070's 237.6 ms/step. [volta-diffusion](../volta-diffusion/)
- **Mixed-architecture layer split** (sm_70 + sm_89 in one job) — works with no VRAM leak; `-sm layer` on a MoE model beat the V100 alone by 5.5% decode. [volta-dual-card](../volta-dual-card/)

### Performance traps

- **BF16 costs the V100 77% of prefill** — Volta has no BF16 hardware; the identical model in F16 is 4.37x faster at prefill on the same card. Decode is unaffected. [volta-bf16](../volta-bf16/)
- **DeepSeek flash-attention regression** — `-fa on` costs 80% of decode on the V100 and 52% on the RTX 4070, with byte-identical output and no warning. Root cause is the model's attention head shape (192/128, GQA ratio 1), not the GPU — see [Corrections](#corrections) below. [volta-deepseek-mla](../volta-deepseek-mla/)

### Tooling

- **`llama-bench`, not `llama-cli`, for benchmarking** — a ~20-token prompt in `llama-cli` undershot the real prefill number by roughly 6x. [volta-bonsai](../volta-bonsai/)
- **`llama-diffusion-cli` defaults abort** — exactly one of `--diffusion-eps` / `--diffusion-block-length` must be non-zero; both default to zero, so the stock invocation core-dumps before generating anything. [volta-diffusion](../volta-diffusion/)
- **`-ts` is slash-separated, not comma-separated** — `-ts 0,1` silently runs two separate benchmark configs instead of one ratio, and can print a plausible-looking number before failing. [volta-dual-card](../volta-dual-card/)
- **`-sm row` fails to load** on this mixed card pair, independent of memory pressure (confirmed with a model that would need only ~4.8 GiB/card). [volta-dual-card](../volta-dual-card/)

## Corrections

Two claims in these repos were wrong on first pass and were corrected in place. Both were caught by re-running a control rather than trusting the first result — which is why the rest of the numbers here should be trusted more, not less.

1. **DeepSeek flash-attention regression was originally called Volta-specific.** The first commit in `volta-deepseek-mla` attributed the `-fa on` decode collapse to Volta, reasoning it matched FlashMLA's documented Ampere-or-newer floor. Running the RTX 4070 as a control showed it regresses too (-52% decode, vs -80% on the V100). The selector code in `ggml/src/ggml-cuda/fattn.cu` confirmed the real cause: gates on head dimensions and GQA ratio, never on compute capability. See `git -C volta-deepseek-mla log`, commit `455c09b`.

2. **volta-hadamard originally claimed a clean crossover** — rotation hurting perplexity at 4-bit quantization and helping below 4-bit — derived from a single model (Qwen3-4B). Testing a second model (Qwen3-8B) showed the Q3_K_M and Q4_K_M results flip sign between the two models, meaning they were noise at that magnitude. Only the Q2_K result reproduced in both directions: -4.3% on Qwen3-4B, -4.7% on Qwen3-8B. The crossover claim was retracted; the surviving, narrower finding is "rotation improves Q2_K by ~4-5% and does nothing reliable above 2 bits." See `git -C volta-hadamard log`, commit `01acf8d` ("Second model retracts the crossover claim; only Q2_K survives").

## Offer

<!-- DRAFT: Chris to rewrite in his own words -->
<!--
I have this hardware sitting around — a V100, a GTX 1070, and an RTX 4070 —
and most projects only test on newer cards, so behavior on sm_70/Pascal/Ada
often just isn't known. If you need something run on one of these and can
point me at a branch and a command, send it over and I'll run it and post the
output. To be clear about scope: I'm offering to run things and report what
happened, not to review your code, argue about design choices, or defend a
patch — just numbers and logs from real hardware.
-->
