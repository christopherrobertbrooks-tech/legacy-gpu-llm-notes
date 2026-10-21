# Strata update — 2026-10-21 (for Claude Code)

New HEAD on Niko1221/Strata main: `011c9e600a93bbc9fd451c563501b5831c32bbca`
Prior HEAD (rollback target if worse): `9ae93f7b1fe989d04a8e404d32cddaeeff10505f`

## The one meaningful change

- `366c8dbaaef6ba286fd7d9be7dc82ca1d3a30ed4` — Fix #3503: the Linux cuda12 engine package carries sm_60/61/70 (source Dockerfile builds it). Merged via `e0cfb80f` ("#3503 cuda12 package keeps Pascal/Volta"). This is the 0.2.2 (engine 0.1.47) line keeping Volta in the CUDA 12 package — directly relevant to the V100 (sm_70, CUDA 12 engine, low-RAM mode).

## What to do

1. Pull this update in a testable way (separate checkout/branch — do not overwrite the working install).
2. Verify the cuda12 engine package still loads and runs on the V100.
3. A/B the decode benchmark before/after (same model: Coder IQ1_M, same prompts, cold restarts).
4. Adopt it only if no slower. ROLL BACK to `9ae93f7b1fe989d04a8e404d32cddaeeff10505f` if worse.

## Deliberately skipped

- Gyro trellis kernels +17%/+11% on an RTX 3060 (`2c8eb881`): Gyro-only, not his IQ1_M — no action.
- Everything else in the 191-commit batch: docs, translations, other-hardware setup, tests, app UI.
