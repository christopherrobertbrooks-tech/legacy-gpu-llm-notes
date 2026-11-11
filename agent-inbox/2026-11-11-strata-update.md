# Strata update — 2026-11-11

For Claude Code on ember-gateway. Three small behavior fixes in RAM / expert-cache areas, all relevant to the V100 + 16 GB RAM low-RAM setup. Nothing here is a speed claim or a new model.

## What changed (main, since 87dfca0e)

- `feaa928` — resident RAM copy: `STRATA_RESIDENT_PIN` now also covers the automatic RAM copy (previously it did not; docs commit `27108a4` confirms `STRATA_RESIDENT_PIN=0` now covers the automatic copy).
- `e008709` — expert cache: a failed free-memory query is now reported as an error instead of being silently treated as 0 free (#5708, part). Previously a failed query could make the cache think VRAM was exhausted.
- `8c71c49` — conversation cache: an evicted parked conversation now gives its RAM back to the system (#5697).

New HEAD: `6c642df7530a5a4ba2f6ae52deaa5be436271195`
Rollback SHA (last known-good HEAD before this update): `87dfca0e7c3ee24ad36cc3f69a31b859587245f8`

## What to do

1. Pull the update in a testable way (separate checkout/branch — do NOT change the live llama-swap config).
2. A/B before/after on the deployed Coder setup:
   - Resident RAM during a Coder session, with `STRATA_RESIDENT_PIN=0` and with a parked conversation evicted — RAM should be no worse after, and the automatic copy should respect the pin.
   - Expert-cache behavior: confirm experts still load normally (no spurious "no VRAM free" behavior).
   - Quick HumanEval spot-check or a short decode run to confirm nothing regressed.
3. Adopt only if better or neutral. **Roll back to `87dfca0e7c3ee24ad36cc3f69a31b859587245f8` if RAM use regresses, experts fail to load, or speed drops.**
4. Report back the before/after numbers in the note's reply — no upstream post without Chris's per-post review.
