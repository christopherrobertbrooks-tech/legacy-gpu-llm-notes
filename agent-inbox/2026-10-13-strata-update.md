# Strata update — A/B before adopting (2026-10-13)

## What changed (meaningful commit)

- `661ff29` — STRATA_ADAPT_OVERLAP is now **opt-in on every backend**. It was ON by
  default on Linux CUDA since 0.1.43. Measured: RTX 5090 Laptop, Linux CUDA,
  84.6 vs 106.6 tok/s decode median WITH it (~21% slower); but +5.5–8.3% decode
  on an RTX A4000 and +4.4% on a Tesla P100. Startup log now names the overlap
  state in both directions. Fixes #2010. Same tokens with or without it.
- Related context (same window, already in the tree if you pull): `25e0a2e`
  (stream-ordered copy instead of per-layer host-function signalling) and
  `0e20d9a` (warm the GPU host-callback thread before host pinning) fixed the
  callback-thread pathology that made overlap 2–4x slower on Linux. So an
  opt-in test of overlap is now a fair test.

Why it matters here: Chris runs Strata Coder IQ1_M on a Tesla V100 32GB
(sm_70, CUDA 12 engine), 16GB RAM, low-RAM mode, Linux CUDA. The 0.1.43
default had overlap ON — if his decode numbers dropped after 0.1.43, this
default flip is the prime suspect, and the fix is just pulling.

## Instructions for Claude Code

1. **Before pulling**, record the currently installed commit:
   `git rev-parse HEAD` in the Strata checkout. That SHA is the exact
   rollback target. (Watch's last-seen HEAD before this update: `7695859`.)
2. **Baseline first:** run the standard decode benchmark on the CURRENT build
   and save the numbers (decode tok/s + prefill). Do not pull until the
   baseline is recorded.
3. Pull in a testable way (separate worktree or build dir if you have one;
   keep the old build/binary around until the A/B is done).
4. Build the new HEAD (`a0116b2`), re-run the SAME decode benchmark.
   Also check the startup log names the ADAPT_OVERLAP state (off by default).
5. **Second A/B (optional but cheap):** re-run decode with
   `STRATA_ADAPT_OVERLAP=1` to see whether overlap helps or hurts on the V100
   specifically — it helped on A4000/P100, hurt on the 5090 Laptop, so the
   V100 answer is measured, not assumed.
6. **Adopt only if better.** If decode is equal or better on the new default
   (or with overlap on, if that wins), keep it. **If worse, ROLL BACK** to the
   SHA recorded in step 1 — exact checkout + rebuild, verify the benchmark
   returns to baseline.
7. Report back: before/after decode + prefill numbers, overlap on/off numbers
   if run, and whether the new build was kept or rolled back.

Do not push anything upstream. No behaviour change expected in tokens
(same tokens with or without overlap).
