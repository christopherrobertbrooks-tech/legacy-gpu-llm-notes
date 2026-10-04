# Is a used V100 32GB worth it?

[← back to the overview](../README.md)

## Is a used V100 32GB worth it? (measured September 2026)

Same machine, same llama.cpp build (PrismML fork `3ae4f51`, CUDA 12.9),
`llama-bench -ngl 99 -fa on -p 512 -n 128 -d 0,16384,32768 -r 3`, one card
visible at a time. Power is whole-board draw from `nvidia-smi` during a
2,048-token generation. Raw CSVs and scripts: [buyers-bench/](../buyers-bench/).

**Generation speed, tokens/sec** (short prompt → at 32K tokens of context):

| Model | File | V100 32GB | RTX 4070 12GB | Fits a V100 16GB? |
| :--- | ---: | ---: | ---: | :---: |
| Qwen3.5 4B Q8_0 | 4.5 GB | **107** → 93 | 91 → 73 | yes |
| Qwen2.5-Coder 7B Q4_K_M | 4.7 GB | **123** → 69 | 99 → 71 | yes |
| Gemma 4 12B QAT Q4 | 7.0 GB | **70** → 64 | 60 → 54 | yes |
| Ternary Bonsai 2 27B PQ2_0 | 7.2 GB | 51 → 40 | **54** → 43 | yes |
| Gemma 4 26B-A4B MoE Q4_K_M | 16.9 GB | **92** → 84 | doesn't fit | no, just over |
| Gemma 4 26B-A4B MoE Q8_0 | 26.8 GB | **85** → 79 | doesn't fit | no |
| Qwen3.8 27B dense Q8_0 | 29.0 GB | **24** → 22 | doesn't fit | no |

Qwen3.8 27B's 24 t/s here is with `-fa on`, as the rest of this table; [volta-dual-card](https://github.com/christopherrobertbrooks-tech/volta-dual-card)'s
23.07 t/s for the same model is with `-fa 0`. Both are right for their flag.

**Prompt processing, tokens/sec** (pp512, short context) — the 4070 is faster here:

| Model | V100 | RTX 4070 |
| :--- | ---: | ---: |
| Qwen3.5 4B | 4,445 | **5,860** |
| Qwen2.5-Coder 7B | 3,156 | **5,145** |
| Gemma 4 12B | 1,825 | **3,130** |
| Bonsai 2 27B | 758 | **1,266** |
| Gemma 4 26B MoE Q4 / Q8 | 1,320 / 1,022 | — |
| Qwen3.8 27B dense Q8 | 617 | — |

**Power while generating** (idle, nothing loaded: V100 25 W, 4070 13 W):

| Model | V100 | tokens/joule | RTX 4070 | tokens/joule |
| :--- | ---: | ---: | ---: | ---: |
| Qwen3.5 4B | 154 W | 0.69 | 173 W | 0.53 |
| Qwen2.5-Coder 7B | 218 W | 0.56 | 191 W | 0.52 |
| Gemma 4 12B | 178 W | 0.40 | 185 W | 0.32 |
| Bonsai 2 27B | 184 W | 0.28 | 194 W | 0.28 |
| Gemma 4 26B MoE Q4 / Q8 | 135 / 129 W | 0.68 / 0.66 | — | — |
| Qwen3.8 27B dense Q8 | 182 W | 0.13 | — | — |

**Price** (US used market, September 2026 — listings vary widely, check sold
prices, not asking prices): V100 32GB PCIe ~$640–750; V100 16GB PCIe
~$230–540; RTX 3090 24GB ~$1,000–1,350; RTX 4070 ~$485 used / ~$700 new.
Sources: [GPUDojo](https://gpudojo.com/tesla-v100),
[GPUPoet 32GB](https://gpupoet.com/gpu/shop/nvidia-tesla-v100-32gb),
[GPUPoet 16GB](https://gpupoet.com/gpu/shop/nvidia-tesla-v100-16gb),
[BestValueGPU 3090](https://bestvaluegpu.com/history/new-and-used-rtx-3090-price-history-and-specs/),
[BestValueGPU 4070](https://bestvaluegpu.com/history/new-and-used-rtx-4070-price-history-and-specs/).

**What it adds up to:**
- Generation is 15–25% faster than a new 4070 on everything but the ternary
  model — HBM2 bandwidth. Prompt processing is 1.3–1.7× slower.
- 32 GB is the point: the three largest models above don't fit on a 12 GB
  card, and Gemma 4 26B at Q4 misses a 16 GB V100 by a hair. A MoE at 85–92
  t/s that barely slows at 32K context is the sweet spot.
- Dense 27B+ models run, but at ~24 t/s; MoE models are the better fit (below).
- As a **coding agent** it holds a 35B-A3B MoE at 131K context and fixes 18 of
  20 real SWE-bench issues in an hour ([below](coding-quality.md#swe-bench-verified-as-a-coding-agent-20-tasks)).
- The traps are real but solved below: use CUDA 12.x (13 dropped Volta),
  never bf16 (convert to f16), and check flash attention per model.
- It's a passive datacenter card: it needs forced airflow, and the PCIe
  version fits a normal x16 slot.

### MoE models are the V100's sweet spot

A mixture-of-experts model uses only a slice of its weights per token, so it
needs a lot of memory but little compute — exactly what this card has. Gemma 4
26B-A4B (4B active) generates at 92 t/s against 24 t/s for the dense Qwen3.8 27B
on the same card, and barely slows at 32K context. The V100-specific part is the
32 GB: it holds the whole MoE, where a 12 GB card can't load it and a 16 GB V100
misses by a hair. (Not claimed: that it beats other 32 GB+ cards on MoE — that
wasn't measured.)

### Splitting a model across two cards (V100 + 4070 = 44 GB)

A V100 and a 4070 in one box work together in llama.cpp (`-sm layer`), with
no VRAM leak — see [volta-dual-card](https://github.com/christopherrobertbrooks-tech/volta-dual-card).
**Only split when the model doesn't fit on one card**: for a model that fits,
the fastest single card wins (splitting cost a dense 27B 9.6% of its decode).
`-sm row` failed to load on the mixed pair. What 44 GB buys:

| Model | File | Cards | pp512 | tg128 | tg128 deep |
| :--- | ---: | :--- | ---: | ---: | ---: |
| Llama 3.3 70B dense IQ4_XS | 37.9 GB | both | 336 | **16.6** | 15.7 @ 8K |
| Qwen3-Coder-Next 80B-A3B UD-Q3_K_XL | 36.3 GB | both | 557 | **76.5** | 74.8 @ 16K |
| Qwen3.5 122B-A10B UD-IQ2_M | 39.1 GB | both | 484 | **56.3** | 55.1 @ 16K |
| Qwen3-Coder-Next 80B-A3B UD-Q2_K_XL | 26.8 GB | **V100 alone** | 469 | **74.9** | 73.5 @ 16K |
| Qwen3-Coder-Next 80B-A3B UD-IQ3_S | 29.7 GB | **V100 alone** | 465 | 69.1 | 70.7 @ 16K |

The 70B fills 29.7 GB of the V100 and 11.2 GB of the 4070 — about the ceiling —
and draws ~280 W across both cards. System RAM on this box is 16 GB, so nothing
here spills to CPU; everything is fully offloaded (`-ngl 99`).

### Pooling cards across two PCs over Wi-Fi (llama.cpp RPC)

llama.cpp's RPC backend lets one machine use another machine's GPU: run `rpc-server` there, add `--rpc host:port`
here, and the remote card shows up as a device (`RPC0`) that `-dev`/`-ts` can place layers on. Tested: the gateway
(V100 + 4070) using the main PC's GTX 1070 over **Wi-Fi on both ends** (no Ethernet), measured right before the run at
**3.5 ms ping and 19 MB/s** (17 MB/s through Tailscale). Same PrismML build with `-DGGML_RPC=ON`; `llama-bench -fa on
-p 512 -n 128 -r 2`. Raw data: [results/rpc](../buyers-bench/results/rpc).

| Model | Devices | Prompt t/s | Generation t/s | Generation at 8K |
| :--- | :--- | ---: | ---: | ---: |
| Qwen2.5-Coder 7B Q4_K_M | V100 alone | 3,147 | **123** | — |
| | V100 + 1070 over Wi-Fi (1:1) | 481 | 14.2 | — |
| Gemma 4 26B-A4B Q8_0 | V100 alone | 980 | **85** | — |
| | V100 + 1070 over Wi-Fi (26:6) | 638 | 10.1 | — |
| **Llama 3.3 70B IQ4_XS** (37.9 GB) | V100 + 4070, same PC | 328 | **16.5** | **15.6** |
| | V100 + 1070 over Wi-Fi (31:7) | 135 | 7.7 | crashed (CUDA error, V100 full) |
| | V100 + 4070 + 1070 over Wi-Fi | 157 | 8.1 | 6.0 |

- **It works, and it's slow.** Every split loaded and produced output. But any layer across the network makes every
  token wait on it: 70 ms per token for the 7B is far more than one 3.5 ms round trip, so each token makes many trips.
- **It's only worth it for a model that fits nowhere else.** Models that fit one card got 8–9× slower. The 70B ran
  across the V100 and a 1070 in another PC at 7.7 t/s, about reading speed. That's the case RPC exists for, but it's
  half of what the same model does on two cards in one PC.
- **A third card over the network halves a local pair's speed** (16.5 → 8.1 t/s). It adds room for a bigger model or
  more context, not speed.
- **Loading pays the network once:** the remote card's weights are sent over Wi-Fi (~2 min for 2.3 GB). `rpc-server
  -c` caches them on the remote disk, and the second load of the 7B took 44 s instead of 160 s.
- **Practical notes:** in this tree the server target is `ggml-rpc-server`. It prints "This is an experimental feature and
  is not secure!" (no authentication), so bind it to the LAN address and run it only while needed. ik_llama.cpp's
  rpc-server adds `-cpu` to lend the remote PC's system RAM as well; that wasn't tried, because the main PC (24 GB,
  systemd-oomd) has no RAM to spare.
- **Not yet tested: Ethernet.** Both PCs have unused Ethernet ports. Since latency per trip is what costs, a wired
  link should help; how much is an open question.

### KV-cache quantization: how much context does it buy?

llama.cpp can store the conversation memory (the KV cache) at 8 or 4 bits instead of 16: `-ctk q8_0 -ctv q8_0`
or `q4_0`. **A quantized V cache needs flash attention** in this build (`-fa on`); without it the model refuses to
load. Raw data and scripts: [results/kvquant](../buyers-bench/results/kvquant).

**What fits** (does the server load; VRAM in use):

| Model | Card | f16 cache | q8_0 | q4_0 |
| :--- | :--- | :--- | :--- | :--- |
| Qwen3.6 35B-A3B Q4 | V100 | **262K** (26.5 GB) | 262K (24.6 GB) | 262K (23.3 GB) |
| Muse Glimmer 30B dense Q4 | V100 | 131K (16.8 GB) | 131K (16.0 GB) | 131K (15.6 GB) |
| Ternary Bonsai 2 27B PQ2_0 | RTX 4070 12GB | **32K** max | **64K** | **131K** |
| Mistral Small 4 119B UD-IQ2_M | V100 + 4070 | 32K fails | can't be used | can't be used |

- **Qwen3.6 doesn't need it:** it reaches its full trained 262K at f16 on the V100, because few of its layers keep a KV
  cache. Quantizing saves only ~3 GB. Glimmer's sliding-window attention is the same story.
- **On a 12 GB card it's the difference between 32K and 131K.** Bonsai's context grows fourfold.
- **Mistral can't use it on these cards.** Its MLA design keeps K and V as one latent cache, so K alone can't be
  quantized ("does not support different K and V cache types"), and quantizing both needs flash attention, which
  crashes it. What actually stops it at 32K is the **2.2–2.4 GB compute buffer on the 4070**, not the cache.

**What it costs** (Qwen3.6 on the V100):

| KV cache | Perplexity (wikitext-2, 16K-token chunks) | HumanEval (greedy) | Prompt t/s at 32K | Generation t/s at 32K |
| :--- | ---: | ---: | ---: | ---: |
| f16 | 5.3652 ± 0.032 | 153/164 | 638 | 89.4 |
| q8_0 | 5.3699 (+0.09%) | 153/164 | 636 | 76.9 (−14%) |
| q4_0 | 5.3764 (+0.21%) | 157/164 | 633 | 69.5 (−22%) |

Glimmer's generation at 32K: 38.3 → 35.4 → 33.9 t/s.

- **Quality: no measurable loss** at either setting. Both perplexity changes are inside the error bar, and HumanEval
  moved within run-to-run noise.
- **Speed: generation slows** as the cache is unpacked on every token (−14% at q8, −22% at q4 at 32K); prompt reading
  doesn't change.
- **As an agent** (SWE-bench, 20 tasks, Qwen3.6 with a q4_0 cache): **17/20 vs 18/20** at f16. It lost django-11433,
  the borderline task that thinking on/off also decides. It took 103 min vs 60, about 73 min without one task where it
  spent 30 minutes waiting on a helper agent it believed it had started (a task no model has solved). That's roughly a
  third slower, with 1,686 steps vs 1,460.
- **Verdict:** use it where context is the limit (a 12 GB card), not where it isn't (Qwen3.6 on a V100 fits 262K at
  f16, and quantizing there only costs speed and possibly a fix).



### Does the V100's x4 PCIe slot matter? (measured October 2026)

Not for inference with the model resident on the card. Measured with `nvidia-smi dmon -s t` while Strata (125B MoE Coder,
all 12,288 experts on the V100) was working as a coding agent's builder: **120–150 MB/s into the card and 3–19 MB/s out**,
against ~3,900 MB/s for PCIe 3.0 x4 — about 4% of the narrow link. Model loading is limited by the SATA SSD (~0.5 GB/s),
not the slot. x16 would only start to matter for splitting a model across both cards or streaming experts from system RAM,
neither of which this setup does. (The 4070 has the x16 slot and drives the display; the i7-13700KF has no integrated GPU.)
