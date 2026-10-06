# Strata upstream update — perf batch (#783 ported) — test on V100

**Target upstream SHA:** `82f46a8c8f475f001ad76d92f58f4a4f8ffb0253` (Niko1221/Strata main, post-rewrite)
**Current working SHA (yours):** `6f32ec070f23ced9f50e704d854d775da52591ab` (pre-rewrite main HEAD as of 2026-10-05; objects still fetchable for exact rollback)

**What changed.** Niko force-pushed a cleaned-up main on 2026-10-06 and ported stuchapin909's perf PR #783 ("fused decode/verify/MTP kernels and graph launch reductions") into it piece-by-piece. This is genuine kernel-level speed work on the CUDA engine, exactly our hot path. Relevant commits on new main:

- `822251be` perf(moe): multi-token router kernel, float4 k=10 combine, float4 sigmoid scale
- `2715a752` perf(iq): 16-lane sub-warp expert gate/up/down kernels, exact-N MMVQ columns, decoded-once small-format tables (Q4_0/Q5_0/Q8_0/IQ4_NL) — hits IQ1_M expert kernels directly
- `3fd0460b` perf(mtp): drafter catch-up skips K/V of rejected rows
- `868f2ef0` perf(mtp): multi-token router + combine in the drafter
- `44ffa86c` perf(kv): batched K/V + indexer append for the verify window, commit graph, MTP catch-up
- `fe4de5de` perf(verify): resident_plan as parallel grouping + prefix scan
- `088e8a82` perf(rope): fused per-head RMSNorm + RoPE for verify window and MTP drafter (on for CUDA builds)
- `8b5dd7ad` perf(verify): shared-expert forks after doorbell when CPU experts in window
- `3281ac32` perf(quantize): one-warp-per-block Q8_0 quantize, fused SwiGLU + Q8_0 in grouped S2 experts
- `660e495e` perf(quantize): keep f-140's one-warp-a-block quantize_act.cu
- `023dd015` fix(mtp): STRATA_NO_MULTI_GR flag constant was a NUL byte — fixed
- `1cbcacbc` fix(build): dma_batch std::array locals rejected by Linux nvcc (tests build only)

Also ported: Chris's #819 tool_result image fix is in the new main (Niko's own rewrite of `anthropic_to_messages`). NOT yet ported: V100 benchmark (#823), dual-card benchmark (#850), llama-swap how-to (#829) — still pending Chris's call (re-open fresh or Niko's team ports). Serve robustness fixes (#1012 restart/EngineDied, #1058 tool-call detection) are minor; skip unless you care.

**Caveat.** The #783 numbers were measured on a 5070 (sm_120). Nothing here is sm_70-specific; the GR piece got gated to sm_120-opt-in for no win. Treat all claimed speedups as unproven on the V100.

## What to do

1. Build new main in a SEPARATE directory. Do not touch the running engine/build.
2. Run the parity tests first: `mmvq_multi_parity`, `iq_multi_parity`, `native_grouped_parity`, `native_expert_parity`, `rope_parity`. Kill switches if something breaks: `STRATA_NO_SUB16_GU=1`, `STRATA_OLD_IQ_MMVQ=1`, `STRATA_NO_MMVQ_ROWS2=1` (IQ kernels), `STRATA_NO_NORM_ROPE=1` (fused rope), `STRATA_SH_FORK_LATE=0` (verify fork).
3. A/B the decode benchmark on Coder IQ1_M, V100, low-RAM mode, before (current build) vs after (new build): decode tok/s, prefill tok/s, MTP acceptance. If parity tests fail or any number regresses, flip kill switches per-piece to bisect; adopt only if better overall.
4. Optional: HumanEval spot-check (the failures-at-38/113/145 baseline from 2026-10-04) if decode changes look real.
5. Adopt: only if better. Roll back: old commit `6f32ec070f23ced9f50e704d854d775da52591ab` is still fetchable on GitHub, or just keep pointing at the old build dir.

Report: before/after numbers and whether to keep it. Stay terse.
