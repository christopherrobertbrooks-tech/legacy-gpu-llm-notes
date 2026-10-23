# Strata update to test: DFlash2 speculative drafting in 0.2.3 (2026-10-23)

## What changed (upstream: Niko1221/Strata)
- Strata 0.2.3 / Terminal 0.2.3.1, engine 0.1.48. New HEAD: `7ddc17a38fe7f31637e895ecfba58c2cd43d65ec`
- DFlash2 speculative drafting is now user-facing and opt-in:
  - `strata launch --drafting auto|mtp|dflash2|off` and the app's Drafting setting
    (`437a60676f22547183281c5a24ffa8642ef73e64`,
     `e890e3076681de7e95972224ddc757ea1927e91e`, `40`/`48` in the 0.2.3 merge train)
  - DFlash2 drafter for Qwen3.8-Flash-Next: Q8_0 pack tool, GPU forward, `--draft dflash2 --draft-model`
    (`7f97c35acaf39835b8587e1a73a90c76516b6d54`), merged onto the combined branch building on CUDA/HIP/Metal
    (`f1b6a2144c84e4ad7857836ed35d5a0a86ce7a37`)
  - Drafter head is reserved before the expert cache is sized (`eebb870922b708d02f6557629e20cae0555151c5`)
- Caveats from the commits themselves: DFlash2 is gated until the engine serves it (the app hides it until then), the drafter is fetched pinned, and the commits carry NO measured V100/CUDA speed numbers. This is a test-it hit, not an adopt-it hit. The other 130-odd commits since the last watch point were TUI/launcher, Windows/Arc/HIP/Metal, agent/chat, docs/version bumps, or off-by-default MTP cost-window experiments — ignore them.

## Instructions for Claude Code
1. BEFORE changing anything, record the currently working commit/engine version in use on ember-gateway. That pre-update state is the exact rollback point. (Watch-side reference only: the watch's previous HEAD was `011c9e600a93bbc9fd451c563501b5831c32bbca`; do not assume that is the working checkout — verify locally.)
2. Pull the update in a testable way (separate checkout / staged engine, not an in-place overwrite of the working setup).
3. First check: does the CUDA engine in 0.2.3 actually serve DFlash2? If the Drafting setting stays hidden / the engine does not serve it, stop — nothing to adopt, report that and roll back.
4. If it serves it, A/B on the usual setup (Coder IQ1_M, V100, low-RAM mode): decode benchmark with `--drafting dflash2` vs the current MTP/auto setting, same prompts, cold restarts. A short HumanEval spot-check as a sanity check that outputs did not change.
5. Adopt ONLY if decode is faster and the spot-check is clean. If slower, broken, or the drafter download/serve check fails, ROLL BACK to the pre-update state recorded in step 1 and report the numbers.
6. Report back: engine serves DFlash2? (yes/no), decode before/after (tok/s), spot-check result, adopted or rolled back.
