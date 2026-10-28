# Strata update to A/B — 2026-10-28

## What landed
Strata HEAD is now `46c152a1310f77cd2f0ce2c7cd213962df14fe83` (0.2.7 release tree).
The one item worth testing on the V100 box: **KVA, the opt-in approximate
late-layer prefill ("Faster long prompts") for Qwen3.8 on a single CUDA device.**

- `750ca8c3b16f137866e2d9ebb9fe7828ae866a10` — KVA on for cold prompts of 4096+ tokens (Qwen3.8, one CUDA/HIP device)
- `9c8c90391db8077fb3514a5ca62be052dd24ea04` — shipped config: approximates layers 36–47 with a 2048-token exact tail; agent loops and long extraction stayed at exact level in upstream's checks
- `e3450e455218ee2d0e8c146cd4aa79234f789a0815588c4` — KVA ships OFF in 0.2.7: `STRATA_KVA` unset = the exact 0.2.6 engine

Caveats: KVA is shown for Qwen3.8-Flash-Next models; a model shape KVA was
not measured on reads exactly (geometry gate), so it may simply be a no-op
on the installed Coder cut. The rest of the 422-commit batch is other
hardware (Mac Metal, DGX Spark sm_121, Strix Halo/R9700, sm_80/sm_89,
Pascal) — ignore it.

## Do this
1. BEFORE pulling, record the currently installed/working Strata commit SHA
   (that SHA is the exact rollback target — do not guess it).
2. Pull to `46c152a1310f77cd2f0ce2c7cd213962df14fe83` in a testable way
   (separate checkout/worktree if that is how this box does it).
3. A/B on a cold prompt of 4096+ tokens, same model and settings:
   - `STRATA_KVA=1` vs `STRATA_KVA` unset.
   - Metrics: prefill tok/s, and output identity/quality vs the exact run.
4. Adopt KVA only if prefill is faster AND outputs match the exact run.
5. If slower, or outputs differ: ROLL BACK to the SHA recorded in step 1
   and report that it was rolled back. Do not keep the update on a maybe.
