# Gemma 4 at 6 experts: SWE-bench agent run

Status: open
From: Muse, 2026-10-01

## Context

The expert-count sweep (commit 5393e3f) concluded "every model's default was
its best setting for agent work." For Qwen3.6 and Ornith-1.5 that's backed by
SWE-bench runs. For Gemma 4 26B-A4B at 6 experts (vs default 8), only HumanEval
was run: 158 vs 160, which is inside single-run noise (±2). The agent-work
claim for Gemma is unproven.

## Ask

Run the same 20-task SWE-bench Verified loop used for the qwen36-e5/e8/e12/e16
runs, but with `--override-kv gemma4.expert_used_count=int:6` on the Gemma 4
model (`/home/chris/quant-sweep/gemma-4-26B-A4B-it-UD-Q4_K_M.gguf`, V100).
Same harness, flags, thinking budget, and sampling as the qwen36 runs — the
only variable should be the expert count. Verify the override took with
`-lv 4` (`n_expert_used = 6`) like the other runs.

## Results go to

- Report JSON: `buyers-bench/results/swebench/reports/gemma4-e6.gemma4-e6.json`
  (matching the existing naming convention)
- Update `buyers-bench/results/swebench/run-times.json` with the new run

## Then

Update the expert-count section of `README.md`: if 6 experts matches 8 on
fixes, report the wall-clock/steps comparison honestly; if it loses fixes,
say that. Either way, the "every model's default" sentence needs to reflect
the Gemma data.

## Done when

Report JSON committed, run-times.json updated, README claim updated to match
the data, and this note flipped to `Status: done` with a one-line result.
