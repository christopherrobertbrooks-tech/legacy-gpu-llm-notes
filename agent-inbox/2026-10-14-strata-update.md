# Strata update — A/B before adopting (2026-10-14)

281 commits since the last check (`a0116b2`, 0.1.44 era); TWO are meaningful for
your setup. Everything else is Mac/Metal, SYCL/Intel/AMD, docs, tests, or
Pascal-only perf — skipped.

## What changed (meaningful commits)

### 1. New model family: Qwen3.6-35B-A3B — full engine path
- `14ba7a62` — family recognised (GGUF arch `qwen35moe`), geometry/layout from the GGUF
- `1176eb3c` — the engine path: serve protocol, prompt chunks, decode graph
  (native router 256/8, native grouped experts, SiLU-gated GDN step,
  split-K decode over 256-cell chunks, MTP speculative decode from the GGUF
  nextn block, `b5568470`)
- `14817168` — one strata binary runs both families; `strata --families` lists
  what a build runs; setup installs the family (pinned Unsloth GGUF + tokenizer,
  config with `--native/--max-context/--mtp 2`)
- Merged to main via `4cfeaa0f`; shipped in 0.1.44.1 (new HEAD
  `296b59d2`, which is the test target below)

Pinned files in setup.py (all Unsloth, all with the MTP block):
- `Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf` — 22.85 GB (smallest; the only one with a
  shot on a 32 GB V100)
- `Qwen3.6-35B-A3B-UD-Q6_K_XL.gguf` — 32.6 GB (no)
- `Qwen3.6-35B-A3B-Q8_0.gguf` — 37.8 GB (no)

Caveats: no IQ1_M-class quant is pinned yet, so this is a bigger-quant-only
family for now. Setup's RAM guidance: UD-Q4_K_XL wants ~32 GB box RAM; your
ember box has 16 GB + 24 GB swap, so treat the install as an experiment, not
a given.

Why it matters: a genuinely new MoE family with its own engine path and MTP
support — the kind of new-model drop you actually run on the V100. Qwen3.6's
hybrid (GDN + attention) is also a different speed/quality shape than
Flash-Next, worth one measured comparison.

### 2. MTP fix: shared MTP folder kept the wrong draft subset — `c0462733`
- `setup --update` refreshed the draft subset once per installed config, newest
  first, so a folder shared by several configs ended up with the subset of the
  config used LONGEST ago. A config without `draft_vocab` then put the default
  subset over the tuned one of the config in use.
- Measured (RTX 5060 Ti + RTX 3060, IQ3_XXS, greedy 600-token Russian story):
  54.0 / 54.0 tok/s with the wrong subset, 68.7 / 68.6 with the right one
  (1.39 -> 1.90 tokens per window). ~27% decode recovered by the fix.

Why it matters: your Strata decode numbers include Strata's own MTP. If any
of your configs share an MTP folder, your decode may be silently running with
the wrong draft subset right now.

## Instructions for Claude Code

1. **Before pulling**, record the currently installed commit:
   `git rev-parse HEAD` in the Strata checkout. That SHA is the exact
   rollback target. (Watch's last-seen HEAD before this update: `a0116b2`.
   You're expected to be on 0.1.43-era; 0.1.44.1 is the new target.)
2. **Baseline first:** run the standard decode benchmark on the CURRENT build
   and save the numbers (decode tok/s + prefill + tokens-per-window if the
   log shows it). Do not pull until the baseline is recorded.
3. Pull in a testable way (separate worktree or build dir; keep the old
   build/binary around until the A/B is done). Build new HEAD `296b59d2`.
4. Re-run the SAME decode benchmark on your Coder IQ1_M config. If you have
   more than one config sharing an MTP folder, this is the key comparison:
   tokens-per-window should be >= baseline; if it was silently degraded, it
   should now be up.
5. **New-family probe (only if you want it, and RAM allows):** `strata
   --families` should now list `qwen35moe`. Try the setup install of
   Qwen3.6-35B-A3B-UD-Q4_K_XL (22.85 GB file). Serve it, run a short greedy
   generation sanity check, then a small HumanEval spot-check vs your
   Qwen3.8 Coder IQ1_M numbers. This is exploratory — do not displace the
   working config for it.
6. **Adopt only if better.** Keep the new build if decode is equal or better
   on the Coder config. **If worse, ROLL BACK** to the SHA recorded in
   step 1 — exact checkout + rebuild, verify the benchmark returns to
   baseline. The Qwen3.6 family is a side experiment either way; it does not
   justify keeping a slower main build.
7. Report back: before/after decode + prefill + tokens-per-window on the Coder
   config, whether the MTP subset fix changed anything, Qwen3.6 numbers if
   you tried it, and whether the new build was kept or rolled back.

Do not push anything upstream.
