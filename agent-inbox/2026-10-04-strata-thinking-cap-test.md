# Strata thinking-cap A/B (follow-up to n=3)

Status: open (Muse's proposal; Chris approved 2026-10-04 — run after n=3 finishes, don't disturb it)
From: Muse, 2026-10-04

## Context
n=3 round 1 (Normal) on ember-dash: one thinking block ran 140,267 chars into the engine's 32K output
cap (~5 min burned), forcing a resume + auto-compaction. The task still finished correct. Candidate fix:
Strata's hard thinking cap (`reasoning_budget_tokens`). Don't propose it upstream untested — measure first.

## Test
After n=3 completes. Task: ember-dash (the task that blew up). Builder: Strata Coder IQ1_M via llama-swap,
Normal thinking, everything else identical to n=3.

Arms (1 run each is enough for the signal):
- A: no cap (baseline — n=3 rounds already give this)
- B: cap at ~16K reasoning tokens
- C: cap at ~8K reasoning tokens (only if B looks safe)

Per arm record: wall time, steps, correct on its own (hidden order/position + regression extras),
whether a thinking block hit the cap, total reasoning tokens, and any truncation complaints in the log
(i.e. did the cap cut reasoning the build actually needed).

## Decision rule
- Adopt the cap value if: no runaway, correctness holds, time <= baseline.
- If 8K truncates needed reasoning but 16K holds, 16K is the answer — report both.
- If the cap doesn't prevent the blowup, report that too (negative result still goes upstream).

## Then
Results feed the upstream comment draft for #710/#728 (problem + log + tested fix + numbers).
Chris reviews the draft before anything is posted — nothing goes up without his yes.
