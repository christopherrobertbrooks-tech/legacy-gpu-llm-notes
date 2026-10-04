# Strata (125B MoE) on the V100 with only 16 GB of system RAM

Status: open (in progress — report from Claude Code; Muse: comment on the test design)
From: Claude Code, 2026-10-04

## Context
Chris found Strata via Hackaday (2026-10-04, "AI On Your Gaming PC"): github.com/Niko1221/Strata runs
Qwen3.8-Flash-Next — a 125B mixture-of-experts model with 24,576 small experts, 10 used per token — on one consumer GPU
by treating VRAM as a cache for the experts, with the rest in system RAM and a 29 GB lookup table on the SSD; MTP
speculative decoding; OpenAI- and Anthropic-compatible APIs on localhost.

Strata asks for ≥32 GB of RAM (64 GB for every size). ember-gateway has **16 GB** (DDR5; filling the two free slots
to reach 32 GB was quoted near $1000). But it has a lot of VRAM: V100 32 GB + RTX 4070 12 GB. Strata's **low-RAM mode**
maps the experts from the model files and keeps in RAM only what the GPU doesn't hold. The **Coder** version
(ISTA-DASLab: 256 of 512 experts kept, chosen on code; 91% of the full model's SWE-bench Verified per its authors) has
23 GB of experts + ~7 GB dense weights — it should sit almost entirely on the V100.

## Setup so far
- V100 support is community/experimental (CUDA 13 dropped Volta): Strata's setup compiled its CUDA 12 engine for sm_70
  with the gateway's CUDA 12.9 toolkit in ~45 s, no errors.
- `setup.sh --yes --family coder --gpu 1 --cuda 12 --low-ram on --no-start` (GPU 1 = the V100). Download ~66 GB from
  Hugging Face at ~28 MB/s. ~200 GB of rejected models were deleted to make room.
- Community numbers for a V100 32 GB (UD-IQ4_XS, plenty of RAM): decode 38–51 tok/s, prompt 1,100–1,250 tok/s.
  For comparison, Workbench's current builder (Ornith 1.5 35B-A3B Q5) reads ~470 tok/s on the same card.

## Plan
1. First start: does low-RAM mode load on 16 GB without freezing the gateway; where the experts end up (V100 vs RAM vs SSD).
2. Measure decode / prompt speed (short and 32K prompts), thinking on/off.
3. If it's usable: run it as a Workbench builder on the same real tasks as the builder comparison (it speaks Anthropic's
   API, so Workbench can point at it) and compare against Ornith Q5 + vision — correctness, time, and whether a 125B
   model gets ember-dash's drive layout right on its own (Ornith: 1/3).
4. Optional: the full model (Q2_0, 37.6 GB) split across V100 + 4070.

## Results
(to come)
