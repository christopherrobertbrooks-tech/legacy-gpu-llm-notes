# Strata update — 2026-10-11 (HEAD 7695859aa13a, 0.1.43)

`Status: open` — pull in a scratch build first, baseline at the old commit,
run these A/Bs, adopt only if better, roll back if worse.

Upstream merged 0.1.42, 0.1.42.1 and 0.1.43 since fb58e0db (307 commits, mostly
AMD/Intel/Windows — ignore those). Four matter for the V100 + all-experts-cached
+ 16GB-RAM setup:

1. **#1595 fix landed (eaaa237):** CPU prefill share no longer arms itself when
   the cache holds every expert — Niko's words, Chris's benchmark. Author
   measured +4.8% at 1,000 tokens on a V100; that was overhead his box was
   eating. If the 10-08 note's Test 2 picked a `STRATA_PREFILL_CPU_SHARE`
   override, remove it — the new default behaves the same on his setup.
   10-08 note's Test 2 is answered by upstream; close it.
2. **#1884 fix landed (6ab541f):** tail-skip default stays off when >=90% of the
   experts are cached (`STRATA_TAIL_SKIP_MAX_CACHED` moves the line). This is
   the tail-skip default 0.1.42 flipped on for CUDA serve — the prime suspect in
   his 0.1.41→0.1.42 A/B regression. On his 100%-cached setup it stays off.
3. **Volta prefill GEMM fix (f63a57e, #1757):** BF16 converts the weight in tiles
   when conversion buffers don't fit, instead of falling through to the raw
   cuBLAS call. Long-prompt prefill path on sm_70.
4. **STRATA_ADAPT_OVERLAP on by default for CUDA (f95f2ea, merged 10-11):**
   adaptive-tier copies land while the next decode window runs (`=0` opts out).
   All-resident setup should see ~neutral; verify no regression.

## Plan

0. In the Strata checkout, record `git rev-parse HEAD` BEFORE pulling — that is
   the rollback SHA. Report it in the results.
1. Baseline at the old commit: decode tok/s (standard benchmark), prefill ms at
   250/600/1000-token prompts, TTFT.
2. Pull to HEAD `7695859aa13afb248bdb4d36f9b2e95707db079d` (0.1.43) and rebuild
   the CUDA 12 engine in a scratch dir — do not touch the working install until
   a decision is made.
3. Re-run the same benchmarks. Expect: prefill flat-to-slightly-better (1, 3),
   decode flat-or-better (2 = regression fix, 4 = potential gain).
4. HumanEval spot-check (or token parity on the standard prompts) for the two
   behavior changes (tail-skip guard, adapt overlap). The 10-08 note's Volta
   table Test 1 stays open unless this A/B already covers it.
5. Adopt 0.1.43 only if better-or-flat across decode + prefill + spot-check;
   ROLL BACK to the recorded SHA if worse, and report what regressed.
6. Flip this note to `Status: done`, commit results, and close the 10-08 note's
   Test 2 (superseded by #1 above).
