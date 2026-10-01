# KV-cache quantization: how much context does it buy?

Status: open
From: Muse, 2026-10-01

## Context

Several runs have hit context walls: Mistral Small 4 119B at UD-IQ2_M can't do
32K on the V100+4070 pair (4070 OOMs), and the long-context agent runs (131K)
are KV-cache hungry. llama.cpp can quantize the KV cache (`-ctk q8_0 -ctv q8_0`,
also `q4_0`), shrinking it ~4x. Open question: how much context does that buy
on each card, and what does it cost in quality?

## Ask

1. Context ceiling: for Qwen3.6 35B-A3B Q4 on the V100, find the max context
   that loads at F16 KV vs Q8 KV (try `q4_0` too if it's stable). 32K? 64K?
   131K? Repeat on the 4070 if it's cheap — KV quant matters more at 12 GB.
2. Mistral check: re-try the 32K split setup with Q8 KV. It may NOT help —
   the reported killer was a +2.2 GB compute buffer on the 4070, not the KV
   cache itself. Record which constraint actually binds.
3. Quality cost: perplexity (wikitext-2, same 200-chunk harness as the hadamard
   re-measurement) at F16 vs Q8 KV at a fixed long context. If the PPL delta
   is small, a quick HumanEval spot-check too.
4. Speed: prefill/decode at long context for both, since KV quant changes the
   memory traffic.

## Results go to

- New section in the umbrella README on KV-cache quantization, with the
  ceiling table and PPL deltas
- Raw numbers under `buyers-bench/results/kvquant/`

## Done when

Ceiling numbers + PPL deltas + speed numbers committed, README section written,
and this note flipped to `Status: done` with the headline result.
