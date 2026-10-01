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

## Progress (Claude Code)

**2026-10-01 — reviewed, plumbing proven, queued** (Chris approved: Wi-Fi first, re-download the 70B). Review notes:
- **The link is Wi-Fi on both ends.** Both machines' Ethernet ports are unplugged, and hostnames resolve to Tailscale
  (WireGuard over Wi-Fi). Quiet: ~4 ms RTT, 16–20 MB/s. During a concurrent 38 GB download on the gateway: 17–350 ms
  RTT, 3–5 MB/s. The queued run measures the link itself (LAN IP and Tailscale) right before the tests.
- **`-cpu` confirmed in ik_llama.cpp's rpc-server** (mainline uses the CPU only when there's no accelerator). **Skipped:**
  the main PC has 24 GB with systemd-oomd, which has killed the desktop session, and today's experts-in-RAM runs filled
  its swap twice. Exposing its RAM isn't safe beyond ~8 GB, and that isn't worth the risk.
- **The note left out the 4070.** The gateway already pools V100 + 4070 (44 GB) locally; Llama 3.3 70B IQ4_XS ran that
  way at 16.6 t/s. So the clean comparison is the same 70B across V100+4070 (PCIe) vs V100+1070 (RPC), plus all three.
- **Builds:** the same PrismML fork with `-DGGML_RPC=ON`; the target is `ggml-rpc-server` in this tree. The 1070 side was
  built CPU-portable for the i5. Devices on the client: CUDA0 = V100, CUDA1 = 4070, RPC0 = 1070.
- **Smoke test (4070 + 1070 over RPC, Qwen3 1.7B, during the download):** works (`CUDA,RPC` backend). pp128 140 t/s,
  **tg 5.4 t/s**: decode is one network round trip per token, so latency, not bandwidth, sets the ceiling.
- **Queued** (Dev-Console `~/pascal-bench/rpc-queue.sh`, after the gateway's current queue): link measurement; 7B coder
  V100 vs V100+1070 (and a reload to time rpc-server's `-c` tensor cache); Gemma 26B Q8 V100 vs V100+1070; Llama 3.3 70B
  IQ4_XS on V100+4070, V100+1070 (may not fit) and all three, at depth 0 and 8K. rpc-server binds the LAN IP only while
  the tests run.
