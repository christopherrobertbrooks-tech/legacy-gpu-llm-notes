Status: open

# Strata update — 2026-10-08 (HEAD fb58e0db, 0.1.41)

Morning watch found 151 new commits (a 0.1.41 release day). Two items are
meaningful for the V100/low-RAM setup. The 2026-10-07 note is still
`Status: open` — run its baseline at the old commit first, then pull here and
run these A/Bs; report both notes' results. Pull to HEAD
`fb58e0dbc8399662c0e47c76578c6e878b14f6cf`, A/B below, adopt only if better,
ROLL BACK (git checkout prior SHA + rebuild) if worse.

## Before you touch anything

1. In the Strata checkout, record `git rev-parse HEAD` — that is the rollback SHA. Report it in the results.
2. Baseline first at the old commit: decode tok/s (standard benchmark),
   prefill tok/s (small-chunk too, see Test 2), resident-expert count
   (~11,650/12,288 figure), and a HumanEval spot-check (30 problems, greedy,
   same prompt/grader as Chris's table).

## Test 1 — Volta table opt-in (c85b7c87b9 + 3 kernel commits) [headline]

Niko merged a Volta (sm_70) speed package, measured on a V100-SXM2-32GB, but
left it OPT-IN in 0.1.41 (`STRATA_SM70_TABLE=1`, PR 1401) "until confirmed on
a V100". Three changes it enables:

- `f6330507db` — routed experts in gfx906's expert mode 8 (SwiGLU+q8_1 fused
  into gate/up epilogue, bitwise the CUDA layout). IQ2_S gate/up 180 -> 150
  us/window, IQ2_XXS 170 -> 134 us at 3 tokens.
- `aaa323fec5` — gfx906's latency-hidden norm/up (STRATA_GR_FAST) on Volta.
  Up projection 1.08 -> 0.96 ms per verify window on V100-SXM2.
- `e509ba5e3d` — interleaved 2-4 column mmvq with a rows table read off a
  V100. Q5_K head 1094 -> 821 us, Q6_K 68.9 -> 47.9 us, Q4_K 43.9 -> 32.5 us
  at 3 columns.
- Author's aggregate: bench commit `b04507c12f` has GPU work per verify
  window 22.8 -> 21.2 ms, and a new doc `docs/NVIDIA_V100.md` (decode side).

Procedure: same commit, `STRATA_SM70_TABLE=1` vs unset (default = 0.1.40.3
behavior). Decode tok/s (standard benchmark), prefill tok/s, HumanEval
spot-check. Check bitwise/score parity on the spot-check, not just speed.
Note: his numbers are IQ2_XS/IQ2_S/IQ2_XXS; Coder IQ1_M may land differently
— report the IQ1_M numbers, whatever they are.
Adopt only if faster with no HumanEval regression, else stay at default.

## Test 2 — prefill CPU share now ON by default (162ce64eff)

Opt-in `STRATA_PREFILL_CPU_SHARE` from yesterday is now ON by default on
CUDA (one GPU, no batch slots, chunks below 1024 tokens; `=0` turns it off).
Least-routed experts of a small chunk run on the idle CPU pool while the GPU
streams the rest. Author numbers (RTX 5090 + 9950X3D, 600-token prompts):
UD-Q4_K_XL 1548 -> 1369 ms, IQ2_XS ~5-8% faster. Agent workloads (tool
results, test output) are exactly small chunks.

- Test: default vs `STRATA_PREFILL_CPU_SHARE=0` on V100 + the i7, 16GB RAM.
  Prefill ms on 250/600/1000-token prompts, plus a decode run to confirm no
  side effect. Keep whichever is faster; if within noise, keep the default.
- No HumanEval needed beyond the Test 1 spot-check.

## Footnote — stage pin reverted to opt-in (fb58e0dbc8, HEAD)

`STRATA_STAGE_PIN` was briefly pinned-by-default with 3 GiB RAM spare, but
the release gate found it corrupted IQ3_S decode after a long prompt, so it
is opt-in again. Not Chris's quant (IQ1_M); net effect vs 0.1.40.x is no
behavior change. No test needed.

## Done looks like

- Rollback SHA recorded; baseline numbers recorded.
- 2026-10-07 note's two tests either done or folded in.
- Test 1: STRATA_SM70_TABLE=1 vs unset — decode/prefill/HumanEval, adopt/rollback decision.
- Test 2: CPU-share default vs =0 on small-chunk prefill, keep the faster.
- Results committed to the notes repo; note flipped to `Status: done`.
