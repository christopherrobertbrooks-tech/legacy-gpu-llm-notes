# Strata update — 2026-11-12 — serve stop bound now on CUDA

## What changed (upstream Niko1221/Strata, since 6c642df7)
- `13eedf552417` — serve: the #4677 stop bound on every backend, not only HIP.
  `serve_stop_bound()` caps the rows a decode window commits at what the request can still emit (max_new) and at the first EOS, so the conversation the session keeps is exactly what the client got and the next continuation reuses it instead of falling back to the older checkpoint. Was HIP-only; now applies on CUDA too. Changes no emitted token. `STRATA_SERVE_STOP_BOUND=0` still turns it off. Host code only.
- New upstream HEAD: `13eedf552417a6a791a7d13c6597e24300ee3a09`
- Pre-update upstream HEAD (last known baseline): `6c642df7530a5a4ba2f6ae52deaa5be436271195`

## Why it matters for this box
Chris runs Strata Coder IQ1_M (Qwen3.8-27B) on the V100 32GB, 16GB RAM, low-RAM mode, served (llama-swap). Multi-turn coding sessions issue continuations; without the bound on CUDA, a continuation could fall back to the older checkpoint (recompute, slower session). This should make continuations reuse the session more often. Small fix, not a speed claim — needs a real check.

## Task for Claude Code
1. Before pulling, record the deployed checkout's exact HEAD (`git rev-parse HEAD`) — that is the rollback target. Do not change llama-swap's live config; test as its own launch.
2. Pull upstream to `13eedf552417a6a791a7d13c6597e24300ee3a09` in a testable way (separate build/checkout if the live one must stay untouched).
3. A/B the relevant metric before/after: run a multi-turn serve session (several continuations on the same conversation) and compare continuation latency / whether continuations reuse the session vs fall back. Also spot-check decode speed and a short HumanEval-style sanity run so nothing regressed. `STRATA_SERVE_STOP_BOUND=0` gives the off-state for comparison if needed.
4. Adopt it only if equal or better. ROLL BACK to the recorded pre-pull HEAD if slower or if continuations misbehave. Report numbers, not adjectives.
