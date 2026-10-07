Status: open

# Strata update — 2026-10-07 (HEAD e8ca9af)

Morning watch found 242 new commits; two are meaningful for the V100 setup.
Pull to HEAD `e8ca9afd03d839d4f8dbbe82dffce7f8a3bafd7a`, A/B below, adopt only
if better, ROLL BACK (git checkout prior SHA + rebuild) if worse.

## Before you touch anything

1. In the Strata checkout, record `git rev-parse HEAD` — that is the rollback SHA. Report it in the results.
2. Baseline first at the old commit: decode tok/s (standard benchmark),
   prefill tok/s, resident-expert count (the ~11,650/12,288 figure), and a
   HumanEval spot-check (30 problems, greedy, same prompt/grader as Chris's table).

## Test 1 — --expert-cache-per-layer (818ec1c6e9) [headline]

Expert cache behavior change, opt-in. Per-layer slots sized to each layer's
own blob instead of the shared cache sized for the largest blob: author's
numbers say the same VRAM holds 7,008 -> 9,312 slots.

- Confirm Coder IQ1_M's file is a native pack (the flag only applies to native
  packs); if not, say so and skip.
- With the flag on vs off: resident-expert count, decode tok/s, prefill tok/s.
- Adopt only if residency goes up (or speed) with no HumanEval regression.
  The SSD-lookup path touches lightly per token, so a gain here shows up as
  fewer cache misses, not a huge tok/s jump — measure, don't eyeball.

## Test 2 — cancel event polling, Python half of #962 (423f5893d7)

serve/server.py now polls the cancel event every 0.5 s while the engine is
quiet (was 10 s), so a client disconnecting during a long quiet prefill
reaches the engine promptly. Author notes: this is the PYTHON half of #962;
the engine half (stop between prompt chunks) is still OPEN.

- Test: start a request with a long prompt, disconnect/cancel during quiet
  prefill, verify the engine actually stops. Report yes/no.
- Do NOT expect cancel-during-generation to work yet — that half is open.

## Footnote — Volta prompt-attn kernel accuracy (0ff5b4145b)

The Volta m8n8k4 kernel now accumulates hi/lo halves in separate chains:
FP64 error 5.1e-6 -> 2.3e-6 (FP32 kernel's level). No speed change expected.
Covered by the HumanEval spot-check; no dedicated test.

## Done looks like

- Rollback SHA recorded; baseline numbers recorded.
- Test 1: residency/speed before/after with --expert-cache-per-layer, adopt/rollback decision.
- Test 2: cancel-during-quiet-prefill stops the engine yes/no.
- HumanEval spot-check: same-or-better vs baseline, else roll back.
- Results committed to the notes repo; note flipped to `Status: done`.
