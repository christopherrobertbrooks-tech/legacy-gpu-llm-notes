# Strata update — 2026-11-16 (for Claude Code on ember-gateway)

## What changed
Main moved `13eedf55` (Nov 12) → `c7757280` (Nov 16, app 0.2.15). 453 commits, most of it AMD/Windows/Mac/app noise. The ones that matter for the V100 / low-RAM Coder IQ1_M setup:

1. **Engine builds WITHOUT llama.cpp MMQ kernels by default** — `f40f8cac` / merge `5649b9e5` (Nov 14). Strata's own fused + int8 expert kernels take over. `-DSTRATA_MMQ=ON` keeps the old path. The int8 expert kernel now covers IQ1_M gate/up (`e447c5a6`) — that's our exact quant.
2. **KV host DMA on by default on NVIDIA** — `62d2b4dc`, `6aae3034`, `f0356cb2` (Nov 14). Prefill K/V cells reach the host copy by one DMA copy per array. Prefill-speed relevant.
3. **Expert-cache part-way shrink fix** — `28e8d0e0`, `388a1554` (Nov 14). With `--vram-elastic`, a refused shrink no longer leaves experts listed in unmapped slots.
4. **`--kv-grow` no longer faults on a long prompt when the expert cache is at its floor** — `513fd0cf` (Nov 14). Long-prompt crash fix; relevant at 128K context.
5. **Low-RAM setup change** — `9a779fb4` (Nov 14). Setup now compares RAM and the expert arena in one unit for the low-RAM choice.
6. **Packaged engine lags**: app is 0.2.15 but engine packages stay 0.1.60 (`e39a52e3`). Test likely needs a source build from main, not the packaged engine.

## Open question — verify before trusting the A/B
The fused-kernel defaults are documented for sm_86 / sm_120 / sm_75 classes. Whether sm_70 (V100, 80 SMs) actually takes the fused/int8 kernels is NOT clear from the commit messages. Check the start-up lines on the V100 build: the no-MMQ build prints a statement about its prompt kernels. If the V100 build still takes MMQ, this whole batch is a no-op for us — say so and stop.

## Instructions
1. Record the currently deployed Strata SHA first — that is the rollback target. (Watch's pre-change head was `13eedf552417a6a791a7d13c6597e24300ee3a09`; deployed was 0.1.41 `fb58e0d` as of Oct 30 — confirm what is actually live now.)
2. Pull the update in a testable way: separate build/checkout. Do NOT change the live llama-swap config.
3. A/B the same Coder IQ1_M load before/after: decode tok/s, prefill tok/s, TTFT. Plus a HumanEval spot-check (greedy, thinking off).
4. Adopt only if better on speed with no quality drop. **Roll back to the recorded SHA if worse.**
5. Report back: start-up lines (which kernels the V100 build takes), before/after numbers, adopt or rollback.
