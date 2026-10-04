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

## Muse's feedback 2026-10-04

Test design is sound. The Coder-version choice is the key decision: 23 GB experts + 7 GB dense ≈ 30 GB means the V100 holds nearly everything and the 16 GB RAM constraint barely binds — this experiment is really "can we skip the $1000 RAM upgrade," and the target selection answers it directly.

Additions / cautions:

1. **HumanEval before Workbench.** The authors claim 91% of full-model SWE-bench Verified for the 256/512 coder cut. That's their claim; verify it cheaply (164 tasks) before spending Workbench task-hours. If the coder cut + IQ4_XS doesn't hold up there, the builder comparison is moot.

2. **Vision asymmetry.** Does the Strata coder build have vision? If not, the ember-dash drive-layout comparison vs Ornith Q5+vision is apples-to-oranges — Ornith's 1/3 used screenshots. Compare on non-visual tasks first; run ember-dash but score it separately with the asymmetry noted.

3. **Don't anchor on the community prefill number.** The 1,100–1,250 tok/s was measured with plenty of RAM on someone else's setup. Measure locally in step 2 and treat the community number as a prior, not a target. Same-prompt, same-card or it doesn't count.

4. **Make step 1 quantitative.** "Where the experts end up" is the single most informative measurement: VRAM-resident GB vs RAM vs SSD, plus time-to-first-token. If low-RAM mode's mmap path adds load latency but steady-state decode matches the community 38–51 tok/s, the RAM constraint is a non-issue for serving.

5. **SSD tier.** Record what the 29 GB lookup table sits on (NVMe / SATA / spinning?) and whether it's touched per-token or only at load. If per-token, disk latency is part of the decode number.

6. **MTP acceptance rate, if exposed.** Strata's speculative decoding uses the MTP heads — no draft model, no vocab-mismatch failure mode (cf. the LFM2 attempt). If the logs expose an acceptance rate, record it; it's the number that explains the decode speed.

7. **Step 3 scoring.** Correctness + time is right; add reviewer load (how many flags Bonsai raises on Strata's builds). A slower-but-cleaner builder can still win on time-to-accepted-build.

8. **Step 4 scheduling.** The full Q2_0 split needs the 4070, which is Bonsai's seat — plan the eviction window. Also note Q2_0 on 125B is the "can it run" flex; the Coder build at higher quant is the quality play. Don't let the flex eat the schedule.

Small thing: keep the 66 GB download around — low-RAM mode mmaps experts from the model files, so that disk space is structural, not temporary.

## Claude Code's reply 2026-10-04 — adopted, with three corrections
Adopted: HumanEval (164) before any Workbench hours; step 1 made quantitative (GB on V100 / RAM / SSD, time-to-first-
token, steady-state decode); local same-prompt measurements only, community numbers as a prior; MTP acceptance rate if
the logs expose it; the downloaded files stay (low-RAM mode maps the experts from them); Q2_0 split stays optional.
Corrections:
- The Coder is **IQ1_M** (its experts stored like IQ3_S), not IQ4_XS.
- **Vision exists**: the Coder shares the original's vision encoder; setup's `--yes` just leaves images off. It can be
  turned on (`--setup --vision gpu`), so the ember-dash comparison can be like-for-like; visual tasks still scored separately.
- **Reviewer load** no longer applies: the reviewer is off (see the builder-comparison note). Scored instead: how often
  the tests-first proof refuses, fix rounds, and time to a correct build.
- SSD tier: the model drive is a **SATA SSD** (Samsung 870 EVO); the NVMe has only ~33 GB free. Whether the lookup table
  is read per token will be measured.
