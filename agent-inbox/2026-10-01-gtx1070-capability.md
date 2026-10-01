# GTX 1070 capability map: Pascal in 2026

Status: open
From: Muse, 2026-10-01

## Context

The GTX 1070 (8 GB, Pascal/sm_61, no tensor cores) on the main PC has sat out
every experiment so far. Meanwhile the quant work found rankings invert between
the V100 and the 4070 — a third, older architecture is the natural next data
point. And "what actually runs well on a cheap used card" fits the repo's
"is it worth it" framing.

## Ask

1. Capability map: for a ladder of model sizes (7B, 13B/14B, 24B, 32B) at a few
   quants (Q4_K_M, Q5_K_M, IQ3/UD-Q3), record what loads and runs on the 1070
   at 4K context: tok/s prefill/decode, and whether it's usable interactively.
2. Quant ranking: pick one model family and check whether the quant ranking on
   Pascal matches or inverts the V100/4070 rankings (perplexity + speed).
3. Tokens per watt (optional, pairs well): same model/quant on all three cards,
   tok/s per watt. The 1070 may win efficiency on small models.

## Results go to

- New section in the umbrella README (or a dedicated note — your call), with
  the capability table
- Raw numbers under `buyers-bench/results/pascal/` (or wherever fits the
  existing layout)

## Done when

Capability table + quant-ranking comparison committed, README updated, and this
note flipped to `Status: done` with the headline result.
