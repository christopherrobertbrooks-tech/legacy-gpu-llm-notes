# Legacy GPU LLM notes — Tesla V100 (sm_70), Pascal GTX 1070, RTX 4070

Measured notes from running local LLMs on a Tesla V100 (Volta, sm_70) and a GTX 1070 (Pascal, sm_61), with an RTX 4070
(Ada, sm_89) as a control card. Most projects only test on newer hardware, so what actually happens on these cards is
largely undocumented. Every number here was measured on the machines below; things that turned out wrong were corrected
in place ([corrections](docs/findings.md#corrections)).

## Headline findings

- **A used V100 32 GB is a strong card for big mixture-of-experts models** because they fit whole: a 125B MoE (Strata's
  Qwen3.8-Flash-Next Coder) runs at 67–77 tokens/s up to a 128K context, on a PC with only 16 GB of RAM -- faster at
  writing than an RTX 5070 with this model. [Strata page](docs/strata.md)
- **MoE models are the V100's sweet spot; BF16 is its trap** (no BF16 hardware: convert to F16, 4.37x faster prefill).
  [Buyer's guide](docs/v100-buyers-guide.md) · [Findings](docs/findings.md)
- **Things documented as unsupported often work on Volta/Pascal:** MXFP4, ternary kernels, vision, ik_llama.cpp, diffusion
  LMs, mixed-architecture layer splits. [Findings](docs/findings.md)
- **For a local coding agent, tests written first beat a second "reviewer" model:** reviewers missed a layout bug about 1
  time in 3; tests written before the change (and proven to fail) got it right 12 of 12. [Coding quality](docs/coding-quality.md#local-models-as-a-coding-agents-builder-october-2026)
- **The V100's narrow PCIe 3.0 x4 slot barely matters** once a model is resident (~4% of the link).
  [Buyer's guide](docs/v100-buyers-guide.md)

## Pages

| Page | What's in it |
| --- | --- |
| [Is a used V100 32GB worth it?](docs/v100-buyers-guide.md) | Speeds, power and prices vs the 4070; MoE vs dense; splitting across two cards; pooling over Wi-Fi; KV-cache quantization; the x4 slot |
| [Strata: a 125B model on a V100 with 16 GB RAM](docs/strata.md) | Setup, speeds, recall, HumanEval, coding-agent results, the full model on V100 + 4070, what we found and fixed upstream |
| [Coding quality](docs/coding-quality.md) | HumanEval, LiveCodeBench, SWE-bench as an agent, the reviewer test, DFlash, DiffusionGemma, expert counts, local models as an agent's builder |
| [What a GTX 1070 is still good for](docs/gtx-1070.md) | Speeds next to the V100 and 4070, real helper jobs, the verdict, Pascal setup notes |
| [Setting up a used V100 on Linux](docs/v100-linux-setup.md) | Before you buy, power (the EPS socket), cooling, BIOS, the driver step that bites, CUDA 12 |
| [Findings by question, and corrections](docs/findings.md) | Works-despite-the-docs, performance traps, tooling gotchas, and the claims we got wrong |
| [agent-inbox/](agent-inbox/) | Working notes between the two agents that ran these tests (dated, raw) |
| [buyers-bench/](buyers-bench/) | Scripts and raw results behind the numbers |

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
| [volta-hadamard](https://github.com/christopherrobertbrooks-tech/volta-hadamard) | A Hadamard rotation tool for Prism's PQ2_0 format | Rotating weights improves llama.cpp's own Q2_K by **17.8%** on Qwen3-4B (wikitext-2, 200 chunks, clear of the error bars). The benefit tracks how much damage Q2_K did: a MoE model that Q2_K barely hurt saw nothing. Prism's own public ternary quantizer is a stub |

## Contributions upstream

From these tests, to [Strata](https://github.com/Niko1221/Strata): a fix for images inside tool results
([#819](https://github.com/Niko1221/Strata/pull/819)), a V100 community benchmark
([#823](https://github.com/Niko1221/Strata/pull/823)), a llama-swap how-to ([#829](https://github.com/Niko1221/Strata/pull/829)),
and a thinking-loop data point ([#728](https://github.com/Niko1221/Strata/issues/728#issuecomment-5984010954)).

## Offer

I have this hardware sitting here — a Tesla V100, a GTX 1070, and an RTX 4070
— and most projects only test on newer cards, so behaviour on sm_70, Pascal
and Ada often just isn't known. If you need something run on one of these,
point me at a branch and a command and I'll run it and post the output.

To be clear about scope: I'm offering to run things and report exactly what
happened — numbers and logs from real hardware. I'm not offering to review
your code, argue about design, or defend a patch.
