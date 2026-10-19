# Strata watch 2026-10-19: 0.1.46 Volta perf work staged — A/B when it ships

## What landed upstream
Niko1221/Strata main staged the 0.1.46 engine's Volta/Pascal performance work
(new since the 2026-10-18 watch; repo HEAD `3fa1b524d7700206c5267a6b64926021b0963dc8`):

- `8b3a96779` — Merge f-145-pp-volta into f-146-volta (0.1.46): the community
  Volta/Pascal perf-PR group (35 commits)
- `a6759787c` — Merge f-146-int (b7505b72a, 0.1.46 engine: Volta perf PRs +
  QSA_WARP sm<75 fix) into f-split-146
- `c61364fc8` — qsa prompt attention: STRATA_QSA_WARP=1 only forces the Turing
  kernels on cards that have the Turing MMA (sm_75+)

Why it matters: the V100 is sm_70 (Volta, no Turing MMA). QSA_WARP=1 was
forcing Turing kernels on it — the sm<75 fix corrects that. The 35-commit
community Volta/Pascal perf-PR group targets exactly this card.

Status: 0.1.46 engine is NOT released as of 2026-10-19 (latest released engine
tree is 0.1.45; Gyro minimum is 0.1.45.1). Do NOT build from source just to
chase this — check `strata setup` / the update feed for a 0.1.46 engine first.

## Task (only once 0.1.46 is installable via setup)
1. A/B the decode benchmark on the V100, Coder IQ1_M (Qwen3.8-Flash-Next MoE,
   12,288 experts), low-RAM mode: 0.1.44.1 (current known-good) vs 0.1.46.
   Same prompts, cold restarts.
2. If decode improves: run the usual greedy HumanEval spot-check to confirm no
   quality regression.
3. Adopt 0.1.46 only if better on both. ROLL BACK to the 0.1.44.1 engine if
   worse on either.

Known-good rollback target: Strata engine 0.1.44.1 (Chris's safe version).
Repo HEAD at watch time: `3fa1b524d7700206c5267a6b64926021b0963dc8`.
