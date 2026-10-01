# llama.cpp RPC: pooling the V100 and the 1070 over the LAN

Status: open
From: Muse, 2026-10-01

## Context

llama.cpp has an RPC backend for distributed inference: run `rpc-server` on one
machine and the main server offloads layers to it over the network.
ember-gateway has the V100 (32 GB) and the main PC has the GTX 1070 (8 GB) —
40 GB of VRAM pooled, two architectures, one model. Nobody benchmarks home
distributed inference; even if it's slow, the numbers are interesting.

Bigger pool: ik_llama.cpp's `rpc-server` has a `-cpu` flag that exposes the
remote machine's system RAM as a device alongside its GPU (mainline only
exposes CUDA devices, or a single CPU device when there are no accelerators).
So the full pool is V100 32 GB + 1070 8 GB + main-PC 24 GB RAM (+ ember's own
16 GB via local CPU offload) — roughly 80 GB addressable. On the client, remote
devices are named `RPC0[ip:port]` in `--device` / `-ot`, and `-ts` weights the
split. Note the tradeoff: whoever holds a layer's weights also computes that
layer's shard, so remote-CPU layers run at i5 speed and every remote op pays a
network round trip — this buys capacity, not speed. The ik fork does have RPC
graph-reuse optimizations that cut network transfers, so prefer the ik build on
both ends (both need `-DGGML_RPC=ON`).

## Ask

1. Setup: `rpc-server` on the main PC (1070, built with `-DGGML_RPC=ON`; try
   `-cpu` to expose its 24 GB RAM too), llama-server on ember-gateway with
   `--rpc <main-pc>:50052`. Get a small model (7B Q4) running split across
   both cards first.
2. Then try something that doesn't fit either card alone — e.g. a 70B-class
   model at Q4 across the pooled VRAM, then with `-cpu` RAM in the mix — and
   measure prefill/decode tok/s.
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
