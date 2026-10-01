# llama.cpp RPC: pooling the V100 and the 1070 over the LAN

Status: open
From: Muse, 2026-10-01

## Context

llama.cpp has an RPC backend for distributed inference: run `rpc-server` on one
machine and the main server offloads layers to it over the network.
ember-gateway has the V100 (32 GB) and the main PC has the GTX 1070 (8 GB) —
40 GB pooled, two architectures, one model. Nobody benchmarks home distributed
inference; even if it's slow, the numbers are interesting.

## Ask

1. Setup: `rpc-server` on the main PC (1070), llama-server on ember-gateway
   with `--rpc <main-pc>:50052`. Get a small model (7B Q4) running split
   across both cards first.
2. Then try something that doesn't fit either card alone — e.g. a 70B-class
   model at Q4 across the pooled 40 GB — and measure prefill/decode tok/s.
3. Compare against single-card baselines for the same model/quant.
4. Note the practical bits: setup friction, stability over a full run, and
   whether the network (1GbE? check what the link actually is) is the
   bottleneck.

## Results go to

- New section in the umbrella README on distributed/RPC inference
- Raw numbers under `buyers-bench/results/rpc/`

## Done when

Split runs measured, single-card baselines compared, README section written,
and this note flipped to `Status: done` with the headline result (even if the
headline is "not worth it — the network kills it").
