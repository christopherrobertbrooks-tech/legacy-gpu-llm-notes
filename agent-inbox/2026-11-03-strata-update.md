# Strata update — 2026-11-03 (test, don't just pull)

Upstream moved: new HEAD ffa80d73133ea5c548aefe57889a16e8085a938f (Nov 2), 695 commits since the last watermark c62d5e3a15b40ea51c96aae9e8d36928965f53ab — mostly 0.2.10 rc1 / split / Maya branch history landing at once, many duplicates. Most of it is other hardware (AMD/Arc/Metal/SYCL), DeepSeek sets, or multi-card split plumbing — skipped. Three hits for the V100 / low-RAM setup:

## Meaningful commits
- `067b7433`, `43543e9b`, `07fb0e71`, `b537586e`, `4adc047d` — Arena RAM fallback: when RAM is short at the expert arena the run no longer stalls or refuses; it falls back to reading experts from the file, now keeping a RAM copy of the hottest experts (`--resident-experts` form, 8 GiB headroom budget form), plus a unified `--ram-keep-gib` setting.
  - Why it matters: this is Chris's low-RAM dimension (16 GB system RAM). Measured on a 5070 PC in the RAM-short case: 25.2 tok/s with the fix vs 9.4–10.1 without. Caveat: the first patch notes itself untested, and the measurement is a 5070, not a V100 — verify, don't assume.
- `fd59c9c3` — Small-card prompt path: one CUDA card, native pack, default prompt chunk below 8,192 tokens → prompts read with the unfused experts plus the layer-major walk.
  - Why it matters: prefill speed on a single card. Measured −26% prompt time on a 12 GB 5070 at 20K (−44/−50% at small slot counts). Caveat: measured on small expert caches; his all-resident cache may see less — the test will tell.
- `13edeb7f`, `6140ce1f` — DFlash2 is now the primary drafter on CUDA for Qwen3.8-Flash-Next, with confidence steps retuned from a DFlash2-alone sweep.
  - Why it matters: drafting-default change on his model family; acceptance, not just plumbing. Watch decode tok/s and acceptance, not just that it starts.

## Skipped, deliberately
- `9d642b9e` Volta prompt kernel: Ampere-only change, the Volta m8n8k4 version stays, first version and gated — no V100 gain.
- `3d08a095` IQ3_S routed expert kernels: first version, to be gated.
- 0.2.10 split engine (`974074c5` and the split cluster): multi-card, Terminal-only — single V100, not applicable.
- DS Coder / ISTA-DAS DeepSeek pins (`06698c67` etc.): not his model.
- 8 GB-card spill work (`ecf7424b`, `2e7db84b`): 32 GB card, not applicable.

## Task for Claude Code
1. Confirm the live deployed build first (last known: Strata v0.1.41, `fb58e0d`). That commit is the rollback point — record the exact deployed SHA before touching anything.
2. Pull the update in a testable way only. Tests run as their own launch — never by changing llama-swap's live config.
3. A/B before/after on Coder IQ1_M: (a) prefill tok/s on a 20K+ prompt (tests `fd59c9c3`); (b) decode tok/s (tests the DFlash2 default); (c) if the arena fallback path is reachable in his config, a RAM-short run noting whether it still starts and its tok/s. Plus a short HumanEval spot-check if decode/prefill move.
4. Adopt only if better. ROLL BACK to the recorded deployed SHA if slower or worse on any metric.
5. Report back: before/after numbers, adopt or rolled-back, and the exact SHA now running.
