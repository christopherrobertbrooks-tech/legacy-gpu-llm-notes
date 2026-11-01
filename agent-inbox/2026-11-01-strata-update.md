# Strata update — 2026-11-01 (test, don't just pull)

Upstream moved: 164 commits since 870aedd9, new HEAD c62d5e3a15b40ea51c96aae9e8d36928965f53ab (Oct 31). This window is the 0.2.9 / engine 0.1.55 release. Most of it is other hardware (AMD/Arc/Metal/SYCL) or DeepSeek sets — skipped. One hit for the V100:

## Meaningful commit
- `bee469c46211` — serve: the qualified GDN speedups are on from the server (Linux CUDA: GDN_TC + GDN_CONVL2=2; Qwen3.8 only, explicit env wins)
  - Why it matters: GDN speedups that were opt-in research switches are now default-on for Linux CUDA on Qwen3.8. That is Chris's exact path (V100, CUDA 12 engine, Qwen3.8 Coder IQ1_M) — a potential free prefill/decode gain.

## Skipped, deliberately
- `6923421a61f6` Unsloth DeepSeek UD-IQ1_S / UD-IQ1_M sets: 241 / 258 GB downloads, not a V100 model. Not worth testing.
- AMD card rules, Arc/SYCL kernels, Metal Q6_K matvec, Mac/Spark gates: other hardware.

## Task for Claude Code
1. Confirm the live deployed build first (last known: Strata v0.1.41, `fb58e0d`). That commit is the rollback point — record the exact deployed SHA before touching anything.
2. Pull the update in a testable way only. Tests run as their own launch — never by changing llama-swap's live config.
3. A/B the relevant metric before/after on Coder IQ1_M: decode tok/s and prefill tok/s on the standard prompt, plus a short HumanEval spot-check if decode/prefill move.
4. Adopt only if better. ROLL BACK to the recorded deployed SHA if slower or worse on either metric.
5. Report back: before/after numbers, adopt or rolled-back, and the exact SHA now running.
