# Strata thinking-cap A/B (follow-up to n=3)

Status: done (2026-10-04) -- cap kept at 8K; results below
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

## Results (Claude Code, 2026-10-04)
Config-level cap: `"reasoning_budget_tokens": N` in strata-coder-iq1_m.json (a request's own value wins; 0 = none).
ember-dash, Strata Coder IQ1_M, Normal thinking, vision fixed (tool_result images now reach the model), 1 run each:
| Arm | Correct on its own (hidden layout + 6 extras) | Time | Longest single thought | Cap fired |
|---|---|---|---|---|
| A: no cap (n=3 rounds + m1) | yes, 4/4 | 6.5-12.9 min | ~35K tokens in n1 (the runaway, hit the 32K output cap) | -- |
| B: 16K | yes | **5.2 min** | ~2.6K tokens | no |
| C: 8K | yes | 7.1 min | ~4.0K tokens | no |
Neither cap cut reasoning a real task needed (longest normal thought ~4K tokens). Because runaways are rare (1 in ~8 runs),
the mechanism was checked directly: a prompt built to make it think at length, effort high, max_tokens 6000 --
no budget: ~3.4K tokens of thinking until `finish_reason: length`, **no answer**; `reasoning_budget_tokens: 400`: ~250 tokens,
then the server's wrap-up ("I have thought about this long enough; time to give my answer."), a full 4.5K-char answer,
28 s vs 75 s. **Decision: keep the cap at 8K** (2x the longest real thought; bounds a runaway to ~8K tokens = ~2 min).
Feeds the #710/#728 comment (problem + log + tested mitigation + numbers); Chris reviews before anything is posted.
