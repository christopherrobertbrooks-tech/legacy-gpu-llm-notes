# Strata update 2026-11-20: engine 0.1.63 / app 0.2.17 — Volta WMMA back in MMQ-free builds

## What changed
- HEAD now `3142b66b` (was `58ee3227`; 277 commits, mostly 0.2.17 release-candidate lanes). Release: Strata 0.2.17, engine 0.1.63 (commit `01d81206`).
- The one that matters: commit `240aeb98`, PR #6023 — "[Engine] prefill tier sort, Volta WMMA, NVLink P2P peer prefill and stage hand-offs, P2P decode scatter".
  - `STRATA_PF_WMMA=1` (opt-in) re-enables Volta `pf_wmma()` in MMQ-free builds: Volta FP16 tensor-core grouped GEMM for prefill. The MMQ-free engine is what the V100 runs since 0.1.60 (MMQ was the old MoE path on sm_70). The PR explicitly notes IQ1_M layers work with `STRATA_PF_WMMA=1` without the tier-sort flag.
  - Also opt-in: `STRATA_MMQ_TIER_SORT=1` (expert readiness-tier ordering for prefill).
  - The rest of the PR is multi-GPU (NVLink P2P stage hand-off, decode scatter, peer prefill) — not applicable to the single V100.
- Measured by the PR author on 2x V100-SXM2-16GB NVLink, Qwen3.8-Flash-Next-UD-IQ2_XS + DFlash2, 64Ki ctx: prefill 2,498 vs 2,328 tok/s (+7.3%), decode 111.1 vs 100.9 (+10.1%), TTFT -1.8 s. Caveat: dual-card NVLink rig, different model/quant — single PCIe V100 + Coder IQ1_M numbers are unmeasured. Treat as a lead, not a proven gain.
- Also in 0.1.63: `STRATA_ROUTE_TAIL_SKIP` is now off unless set (`96247599`) — a default behavior change on every backend; check it doesn't cost decode speed.
- CUDA 12.0 build note (`bf17993c`): opt-in WideBatch prefill kernels are left out below nvcc 12.1 — confirm which nvcc the gateway engine build uses.

## Test (do not touch the live config until the A/B passes)
- Currently deployed on the gateway: Strata v0.1.41 (`fb58e0d`). That is the rollback point.
- Build/test 0.1.63 (HEAD `3142b66b`) alongside it, same Coder IQ1_M model, same prompts.
- A/B arms: (a) baseline 0.1.41 as-is; (b) 0.1.63 stock; (c) 0.1.63 + `STRATA_PF_WMMA=1`; (d) 0.1.63 + `STRATA_PF_WMMA=1 STRATA_MMQ_TIER_SORT=1`.
- Metrics: prefill tok/s, decode tok/s, TTFT, plus a HumanEval spot-check (greedy, thinking off) on (c)/(d) vs (a) — WMMA changes the numerics path, verify no quality regression.
- Adopt only if faster with no quality loss. Roll back if worse: stay on / return to the deployed v0.1.41 build (`fb58e0d`). Do not leave the gateway on 0.1.63 unless it wins.
