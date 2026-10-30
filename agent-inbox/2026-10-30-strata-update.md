# Strata update 2026-10-30 — test, don't adopt blind

Target: Niko1221/Strata HEAD `870aedd9e1ebe1c91f94da93b59af17729f6c5c0`
(release 0.2.8, engine 0.1.54), up from last watched `46c152a1310f77cd2f0ce2c7cd213962df14fe83`.
70 new commits; most are SYCL/Arc, Metal, DeepSeek, or GUI work — not relevant to the
CUDA V100 Coder setup. The ones that matter:

1. `cfa197e21a323ea552ac4d6a18f7fb19023d26ed` — Qwen: `--expert-cache auto` now
   prices the ~245 MiB the load allocates after the cache (cuBLAS handles/workspaces,
   verifier buffers), so the VRAM reserve you ask for is actually kept (#4474).
   Before: a card ended ~240 MiB under its reserve.
2. `84c7f43358ac927d39c5233cfce0cb97de0d15de` — CUDA 12 driver floor is now read
   from the engine package, not a constant (#4247, #4188). The CUDA 12.9 builds
   need driver 575.51/576.02; a V100 PC on driver 556–560 was told the engine would
   work and then refused by the feed.
3. `07d5ecfacb4c90cfaf06ba23aa3f96733247c088` + `01d6f7b995649240b87b5be38b5d0be26cb6fc8d`
   (#4051) — arena load waits up to 20 s for the RAM it needs instead of driving a
   short-RAM host into reclaim, and a stale engine is waited on up to 120 s to give
   its memory back before a new engine starts. Relevant to the 16 GB RAM host.

## What to do

- BEFORE pulling anything, record the gateway's currently deployed Strata commit.
  That recorded commit is the exact rollback target. (Last recorded here: engine
  0.1.41, `fb58e0d` — verify on the gateway, do not trust this.)
- Pull the update in a testable way only. Never change llama-swap's live config
  for a test.
- A/B before/after on the V100 (Coder IQ1_M, low-RAM mode):
  - Free VRAM after load vs `--vram-reserve-mib` (fix 1).
  - Setup/driver check accepting the CUDA 12 engine on the gateway's driver (fix 2).
  - Decode benchmark before/after, plus a clean engine restart (fix 3).
  - HumanEval spot-check only if outputs look off.
- Adopt only if better. ROLL BACK to the recorded deployed commit if slower,
  worse, or flaky.
