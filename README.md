# Legacy GPU LLM notes — Tesla V100 (sm_70), Pascal GTX 1070, RTX 4070

These are measured notes from running local LLM inference on a Tesla V100
(Volta, sm_70) and a GTX 1070 (Pascal, sm_61), with an RTX 4070 (Ada, sm_89)
as a control card. Most projects only test on newer hardware, so what
actually happens on these cards is largely undocumented. Each repo below is
one focused question with numbers behind it. Some things work that the docs
say shouldn't; some are much slower than expected; and two early claims
turned out to be wrong and were corrected in place.

## Hardware

Two machines. Full spec for the first in
[volta-bonsai/ENVIRONMENT.md](https://github.com/christopherrobertbrooks-tech/volta-bonsai/blob/main/ENVIRONMENT.md).

| | host | CPU | GPU | role |
| :--- | :--- | :--- | :--- | :--- |
| 1 | `ember-gateway`, Ubuntu 24.04 | i7-13700KF, 24 threads | **Tesla V100-PCIE-32GB**, compute 7.0 | the subject |
| 1 | " | " | RTX 4070, 12 GB, compute 8.9 | control card |
| 2 | `dev-console` | i5-7400 | **GeForce GTX 1070**, compute 6.1 | Pascal testing |

- Driver 580.173.02, CUDA 12.9.86 — **CUDA 13 dropped Volta, so 12.x is required**
- The V100 runs its PCIe link downgraded to x4 (8 GT/s); the 4070 at x16

## Is a used V100 32GB worth it? (measured September 2026)

Same machine, same llama.cpp build (PrismML fork `3ae4f51`, CUDA 12.9),
`llama-bench -ngl 99 -fa on -p 512 -n 128 -d 0,16384,32768 -r 3`, one card
visible at a time. Power is whole-board draw from `nvidia-smi` during a
2,048-token generation. Raw CSVs and scripts: [buyers-bench/](buyers-bench/).

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
  20 real SWE-bench issues in an hour ([below](#swe-bench-verified-as-a-coding-agent-20-tasks)).
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
-p 512 -n 128 -r 2`. Raw data: [results/rpc](buyers-bench/results/rpc).

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
load. Raw data and scripts: [results/kvquant](buyers-bench/results/kvquant).

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

## What a GTX 1070 (Pascal, 8 GB) is still good for (measured October 2026)

The 1070 sits in the main PC (i5-7400, 24 GB RAM, driver 580). Same llama.cpp commit as the V100/4070 table above
(PrismML fork `3ae4f51`), built for `sm_61` on the gateway and copied over as a folder with its CUDA 12.9 runtime
libraries, so nothing was installed on that machine. Same `llama-bench` settings. Raw data and scripts:
[buyers-bench/results/pascal](buyers-bench/results/pascal).

**Generation speed, tokens/sec** (short prompt → at 32K tokens of context), with the V100 and 4070 for reference:

| Model | File | GTX 1070 8GB | V100 | RTX 4070 | 1070 prompt t/s | 1070 power |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: |
| **LFM2 8B-A1B MoE** Q4_K_M | 5.0 GB | **118** → 95 | — | — | 1,825 | 56–79 W ¹ |
| LFM2.5 8B-A1B MoE (reasoning) Q4_K_M | 5.2 GB | 108 → 88 | — | **326** → 243 | 1,794 | 142 W |
| Granite 4.0 H Tiny (7B-A1B MoE) Q4_K_M | 4.3 GB | 71 → 58 | — | — | 1,326 | 75 W |
| Qwen3.5 4B Q8_0 | 4.5 GB | 35 → 29 | 107 → 93 | 91 → 73 | 863 | 120 W |
| Qwen2.5-Coder 7B Q4_K_M | 4.7 GB | 32 → 12 | 123 → 69 | 99 → 71 | 567 | 110 W |
| Gemma 4 12B QAT Q4 | 7.0 GB | 22, 16K doesn't fit | 70 → 64 | 60 → 54 | 344 | 122 W |
| Ternary Bonsai 2 27B PQ2_0 | 7.2 GB | 14, 16K doesn't fit | 51 → 40 | 54 → 43 | 148 | 108 W |
| Ternary Bonsai 2 27B PTQ1_0 | 5.9 GB | 8.1 → 7.5 at 16K | 34 | 55 | 77 | 105 W |
| gpt-oss 20B MXFP4, experts of 10 layers in system RAM | 12.1 GB | 20, short context only | — | — | 406 | 77 W |
| Gemma 4 26B-A4B Q4_K_M, experts of 21 layers in RAM | 16.9 GB | 14, short context only | 92 → 84 | — | 257 | — |

Idle, nothing loaded: 11 W. ¹ Two measurements: GPU only 29–48% busy at 113 t/s. LFM2.5 has the same architecture
and quantization and keeps the GPU 98% busy at 101 t/s; the difference is unexplained but repeats. LFM2.5's 4070
number: prompt 11,021 → 8,095 t/s at 32K, the fastest model measured on any card here.

- **Dense models run at about a third of V100 speed**, and the long-context drop is much steeper (the 7B coder falls
  from 32 to 12 t/s at 32K). With no tensor cores, prompt reading is 4–5× slower than the V100.
- **Small MoE models are what this card is for.** LFM2 8B-A1B (about 1.5B parameters active per token) writes at 118 t/s,
  faster than the V100 manages with any model in the table above, and holds 95 t/s at 32K. It's also the most
  efficient result on any card here. The i5-7400 can't keep the card fed on models this
  small (GPU 29–48% busy), which is why it draws only 56–79 W (1.4–2.0 tokens per joule). The newer reasoning-tuned
  LFM2.5 8B-A1B is ~10% slower and draws 142 W (0.72 tok/J), but answers far better (below).
- **Bonsai's two packings rank differently on each card.** Writing: PQ2_0 wins clearly on the 1070 (14.0 vs 8.1 t/s,
  PTQ1_0 at 58%) and on the V100 (PTQ1_0 at 67.5%), while on the 4070 they're even (PTQ1_0 54.7 vs 53.9). Prompt
  reading: PQ2_0 wins about 2× on the 1070 (148 vs 77) and on the 4070, while the V100 is the one card where PTQ1_0
  reads faster ([volta-bonsai](https://github.com/christopherrobertbrooks-tech/volta-bonsai); that margin is being
  re-measured). So the 1070 sides with the V100 on writing and with the 4070 on reading, and no one card predicts the
  others. Perplexity wasn't re-measured; it depends on the weights, not the card.
- **Bigger MoE models run with their experts in system RAM** (`-ncmoe N` = keep the experts of the first N layers on
  the CPU; use the smallest N that loads). gpt-oss 20B at 20 t/s is usable for chat; Gemma 26B at 14 t/s is slow. Both
  fit only a short conversation in the remaining VRAM. **On a 24 GB PC this filled the 8 GB swap file both times**
  (idle programs pushed out to make room). Nothing crashed, and `sudo swapoff -a && sudo swapon -a` pulled it back.

**Real jobs, not just speed.** The question was whether an 8 GB Pascal card is useful as a helper next to the
coding cards. All runs on the 1070.

| Job | Model | Result |
| :--- | :--- | :--- |
| Read a screenshot (made-up backup-error dialog, 8 facts) | Qwen3-VL 4B | **8/8 on all 3 tries**, ~9 s |
| | Qwen3.5 0.8B | 6, 8 and 7 of 8 (misses the buttons), 1–3 s |
| Etsy listing from a design image (title ≤140 chars, 13 tags ≤20 chars) | Qwen3-VL 4B | rules met on both tries, 13–37 s; usable first drafts |
| | Qwen3.5 0.8B | fails (1–5 tags) |
| Three everyday requests (reword a reply, explain an error, summarise) | LFM2 8B-A1B | 0.5–1.1 s each; fast but weak judgement (the "friendly" reword still blamed the customer) |
| | LFM2.5 8B-A1B (thinking on) | 3.5–8.5 s at ~100 t/s; accurate explanation and summary, the reword still blamed the customer |
| | Granite 4.0 H Tiny | 0.9–1.9 s; polite but vague |
| | Qwen3 8B (thinking off) | 3–4 s; the reword was barely changed |
| | Gemma 4 12B (thinking off) | 7–8 s; best writing |
| | gpt-oss 20B (low reasoning) | 11–19 s; best short answers |

**Verdict:** not a coding card, but a useful helper: screen reading with a 4B vision model, quick drafting with
Gemma 12B or gpt-oss 20B, and quick answers from LFM2.5 (or instant ones from LFM2).

**Setup notes for Pascal:**
- **Driver 580 still supports Pascal, and CUDA 12.9 builds for it** (`-DCMAKE_CUDA_ARCHITECTURES=61`). Since the
  binaries are static apart from `libcudart`/`libcublas`, building on another machine and copying a folder works.
- **If you build on a newer CPU, set `-DGGML_NATIVE=OFF`.** A `-march=native` build from the i7-13700KF ran every
  GPU-only test fine, then died with `Illegal instruction` the moment experts ran on the i5-7400's CPU (AVX-VNNI it
  doesn't have).
- **Run `llama-server` with `-np 1` on 8 GB.** The default opens 4 conversation slots, and Gemma 12B then fails to
  allocate its KV cache even at 4K context.
- **Turn thinking off for Gemma 4 as an assistant** (`chat_template_kwargs: {"enable_thinking": false}`), or it
  spends the whole answer budget thinking. That cost one false start here.

## Setting up a used V100 on Linux

What worked on this machine (Ubuntu 24.04, Gigabyte Z790 UD AC, i7-13700KF),
plus the things a new owner trips over. Everything marked *here* is from this
machine: limits and settings read off the card with `nvidia-smi -q`, and the
parts actually fitted.

**Before you buy**
- Get the **PCIe** card. SXM2 V100 modules are often cheaper but plug into a
  server socket and need a separate carrier/adapter board.
- **It has no display outputs.** You need integrated graphics or a second card
  for a monitor (the 13700KF has no iGPU, so the 4070 drives the desktop here).
- Dual-slot, full-height: **266.7 mm (10.5 in) long**, 111 mm tall ([NVIDIA product brief](https://images.nvidia.com/content/tesla/pdf/Tesla-V100-PCIe-Product-Brief.pdf)).
  A cooling shroud on the end makes it longer still — check your case has room.
- 32 GB vs 16 GB: see [Is a used V100 32GB worth it?](#is-a-used-v100-32gb-worth-it-measured-september-2026) — the 16 GB card misses the best MoE models.

**Power** — the card has **one CPU-style 8-pin (EPS) socket**, not a graphics
8-pin — the keying differs, so never force a PCIe plug into it. The product brief's supported options: a CPU
8-pin cable from the PSU, or NVIDIA's dongle **030-0571-000** fed by 2× PCIe
8-pin (or 2× 6-pin, or 8 + 6). Used *here*: a 030-0571-000-pattern adapter, CPU
8-pin male to dual PCIe 8-pin female ([COMeap, 12 cm](https://www.amazon.com/dp/B07M9X68DS))
— its listing names the older K80/M40/P40/P100, but it is the same part the
V100 brief specifies. Max power 250 W (the default limit *here*).

**Cooling** — the heatsink is passive; NVIDIA's brief says it "requires system
air flow". In a desktop that means air **forced through it end to end** — case
fans alone usually aren't enough. Used *here*: a 97 × 33 mm 12 V PWM centrifugal
blower ([GDSTIME 9733](https://www.amazon.com/dp/B0DN5VLDMG)) in a bolt-on
shroud made for Tesla cards ([P40/P100/V100 blower kit for 97×33 fans](https://www.amazon.com/dp/B0DDJM7X4R)).
**Stress testing never went above 70 °C.** The fan plugs into a motherboard
fan header, and the board can't read the GPU's temperature — run it at a fixed
speed or a curve that is already high enough at idle.
- The card's own limits (*here*): normal max 83 °C, throttles at 87 °C, shuts
  down at 90 °C; memory max 85 °C. It idles at 35 °C.
- Watch it under load: `nvidia-smi --query-gpu=temperature.gpu,power.draw --format=csv -l 2`.
- **A power limit gains nothing with MoE models** (measured: Qwen3.6 35B-A3B Q4,
  limit changed between rounds on a loaded server). It only draws ~120–130 W, so
  250 → 125 W changes nothing (577 prefill / 96 decode tok/s, 44–47 °C). At the
  100 W floor: −6% decode, −1% prefill, 20 W less, same temperature. Limits only
  bite for heavy dense or diffusion models; set one with `sudo nvidia-smi -i <index> -pl <watts>`.

**BIOS** — turn **Above 4G Decoding on** and boot in **UEFI** mode (CSM off).
Without it the card shows in `lspci` but the driver reports "No devices were
found" (BAR1 0 MB) ([ServeTheHome](https://www.servethehome.com/nvidia-smi-issues-get-nvidia-cuda-working-grid-tesla-gpus/)).
Check: `nvidia-smi -q | grep -A1 "BAR1 Memory"` shows the full 32768 MiB *here*.
A slot wired x4 is fine — this card runs at **PCIe 3.0 x4** with no effect on
inference speed, only on model load times.

**Driver — the step that bites most people:**
- **The 580 driver series is the last that supports Volta**, and only the
  **proprietary** flavour works. NVIDIA's *open* kernel modules start at Turing,
  and some distributions now default to them — the card then simply isn't found
  ([NVIDIA: open kernel modules](https://docs.nvidia.com/datacenter/tesla/driver-installation-guide/latest/kernel-modules.html)).
- Ubuntu: `sudo apt install nvidia-driver-580` — **not** `nvidia-driver-580-open`.
- **Hold it** so an upgrade can't move you to a series without Volta:
  `sudo apt-mark hold nvidia-driver-580 nvidia-dkms-580 nvidia-utils-580 nvidia-compute-utils-580 nvidia-kernel-common-580 nvidia-kernel-source-580`
- With Secure Boot on, the DKMS module must be signed (MOK enrolment) or it
  won't load; Secure Boot is off *here*.
- Check: `nvidia-smi` lists `Tesla V100-PCIE-32GB`, and `modinfo nvidia | grep license`
  says `NVIDIA` (proprietary). ECC is on by default *here*.

**CUDA** — use **12.x** (12.9 *here*); **CUDA 13 dropped Volta**. From NVIDIA's
repository: `sudo apt install cuda-toolkit-12-9`. nvcc lands in
`/usr/local/cuda-12.9/bin` and isn't on PATH — pass it explicitly. nvcc 12.9
already warns that offline compilation for pre-sm_75 cards will be removed in a
future release.

**llama.cpp**
```
cmake -B build -DCMAKE_BUILD_TYPE=Release -DGGML_CUDA=ON \
  -DCMAKE_CUDA_COMPILER=/usr/local/cuda-12.9/bin/nvcc \
  -DCMAKE_CUDA_ARCHITECTURES=70        # "70;89" if a newer card shares the box
cmake --build build -j 4               # nvcc is memory-hungry: low -j on 16 GB RAM
```
With a second card, give the V100 a job by itself:
`CUDA_DEVICE_ORDER=PCI_BUS_ID CUDA_VISIBLE_DEVICES=<V100 index>`.

**First things to know once it runs**
- **Run MoE models** — Gemma 4 26B-A4B or Qwen3.6 35B-A3B at Q4 fit with 131K
  context and generate at 92–98 tok/s ([why](#moe-models-are-the-v100s-sweet-spot)).
- **Never run BF16 weights** — convert to F16 first; BF16 costs 77% of prefill
  ([volta-bf16](https://github.com/christopherrobertbrooks-tech/volta-bf16)).
- **Check flash attention per model** — it is fine for most, catastrophic for
  DeepSeek-V2-Lite ([Performance traps](#performance-traps)).
- **vLLM has no sm_70 build** that worked here; llama.cpp (and ik_llama.cpp) do.
- For a coding agent, keep **thinking on** and skip DFlash ([SWE-bench](#swe-bench-verified-as-a-coding-agent-20-tasks)).

## Coding quality

### HumanEval (164 problems, greedy, thinking off)

The grader passes all 164 reference solutions and fails a `return None` stub on
all 164; as a calibration, Qwen2.5-Coder-7B Q4 scores 86.0% against its published
88.4% (bf16).

| Model | Quant | Cards | HumanEval |
| :--- | :--- | :--- | ---: |
| Gemma 4 26B-A4B MoE | Q4_K_M | V100 | 97.6% |
| Gemma 4 26B-A4B MoE | Q8_0 | V100 | 97.0% |
| Muse Glimmer 30B dense | UD-Q4_K_XL | V100 | 96.3% ¶ |
| Qwen3.8 27B dense | Q8_0 | V100 | 95.1% |
| Gemma 4 12B | QAT Q4 | V100 | 94.5% |
| Qwen3-Coder-Next 80B-A3B | UD-Q3_K_XL | both | 94.5% |
| Qwen3.6 35B-A3B MoE | UD-Q4_K_M | V100 | 94.5% † |
| Ornith-1.0 35B-A3B MoE | Q4_K_M | V100 | 94.5% † |
| Qwen3-Coder-Next 80B-A3B | UD-Q2_K_XL (2-bit) | V100 | 92.7% |
| Qwen3.5 122B-A10B | UD-IQ2_M (2-bit) | both | 92.1% |
| DiffusionGemma 26B-A4B (diffusion LM) | Q8_0 | both | 92.1% ‡ |
| Qwen3-Coder-Next 80B-A3B | UD-IQ3_S | V100 | 90.9% |
| Ternary Bonsai 2 27B | PQ2_0 | V100 | 89.6% |
| DiffusionGemma 26B-A4B (diffusion LM) | Q4_K_M | V100 | 89.0% ‡ |
| Qwen2.5-Coder 7B | Q4_K_M | V100 | 86.0% |
| Llama 3.3 70B dense | IQ4_XS | both | 85.4% |
| LFM2 24B-A2B MoE (no reasoning) | Q8_0 | V100 | 84.8% |
| Qwen3.5 4B | Q8_0 | V100 | 82.3% |
| GLM-4.7-Flash 30B-A3B MoE | Q4_K_M | V100 | 81.1% † |
| Mistral Small 4 119B-A6B MoE | UD-IQ2_M (2-bit) | both | 83.5% § |

† Run through llama-swap at the **maker's recommended sampling** (temperature
0.6–1.0), not greedy. Re-running Gemma 4 26B Q4 the same way (temperature 0.7)
scored exactly its greedy 97.6%. ‡ The diffusion model's own decoder defaults,
seed 1 — see [DiffusionGemma](#diffusiongemma-26b-a4b-on-the-v100-llamacpp-pr-24423) below.
§ Temperature 0.3 (Mistral gives a 0.0–0.7 range for reasoning off); "fair" score,
64.0% strict — it indents whole answers ([details](#changing-how-many-experts-a-moe-uses-4-models)).
¶ Greedy, with reasoning on at Meta's lowest setting (`Reasoning strength: low` in the system prompt; median
~1,000 characters of reasoning per answer) — 42 minutes for the set. See the SWE-bench note below.

**Read this for quantisation loss, not for ranking models.** HumanEval is from
2021 and 2026 models have almost certainly seen it: most of these land between
89% and 98%. Within one model it is still a fair comparison — Coder-Next loses
about 2 points from 3-bit to 2-bit (±2 points is single-run noise at n=164), and
Gemma 4 26B shows no difference between Q4 and Q8. **It also ranks agent work
wrongly:** Gemma 4 26B tops this table but came third of four on real bug fixes
([SWE-bench](#swe-bench-verified-as-a-coding-agent-20-tasks) below).

**Thinking on** (Gemma 4 26B Q4, 4,096-token thinking budget): 161/164 (98.2%)
against 160 — but 69 minutes against 6.3. Two of its three misses hit the
6,144-token answer cap mid-thought and pass when given room (163/164).

### LiveCodeBench v6 (175 contest problems, Jan–Apr 2025) — Gemma 4 26B-A4B Q4

[LiveCodeBench](https://livecodebench.github.io/) problems come from LeetCode,
AtCoder and Codeforces and are graded on hidden tests with LCB's own checker.
Its inference path needs vLLM (no sm_70 build), so generation goes through
llama-server and grading through `lcb_runner` unchanged. The grader was checked
both ways first: empty and wrong programs pass 0/175; four hand-written correct
solutions (stdin and LeetCode-style) pass 4/4; an off-by-one variant fails.

Settings: thinking on, capped at 4,096 tokens (`--reasoning-budget 4096`), 12K
answer budget, temperature 0. **Check-and-fix** mirrors a write-test-fix coding
loop: the first answer is run against the problem statement's *public example*
tests only; if one fails, the model is shown that failure (input, expected, got)
and gets one retry. It never sees the hidden tests.

| Difficulty | First try | With one check-and-fix | Retries: fixed / broken |
| :--- | ---: | ---: | ---: |
| Easy (43) | 100% | **100%** | 0 / 0 |
| Medium (52) | 73% | **79%** | 3 / 0 |
| Hard (80) | 41% | **49%** | 6 / 0 |
| **Overall (175)** | **65.1%** | **70.3%** | 9 / 0 |

- **Google's published figure is 77.1%** ([model card](https://huggingface.co/google/gemma-4-26B-A4B-it)),
  single attempt, with thinking unrestricted and their recommended sampling
  (temperature 1.0, top_p 0.95, top_k 64). The comparable number here is the
  first-try 65.1%. Gemma used the full 4K thinking budget on every medium problem
  (shortest answer 4,530 tokens), so the cap is the likely main difference.
- **Thinking budget is the big lever**: an earlier run at 1K thinking / 8K answers,
  no retry, scored 54.3% overall (medium 56%). 4K thinking took medium to 73%.
- **Q8 bought nothing**: Q8_0 on the same 52 medium problems scored exactly the
  same (73% → 79%), 18% slower.
- **Contamination caveat**: these problems predate Gemma 4, so it may have seen
  some. The within-model gains (budget, check-and-fix) are the most trustworthy
  numbers; the absolute score probably reads somewhat high.
- **A non-thinking model does poorly here**: Qwen3-Coder-Next with thinking off
  reasons inside code comments on hard problems and hit the answer cap on ~half
  of them at 4K; doubling to 8K rescued only 2 of 19. Run abandoned — good at
  everyday code (HumanEval above), wrong tool for contest problems.
- Throughput: 4 parallel streams on one V100 (`-np 4`, 19.2 GB) — easy took
  65 min, hard ~100 min.

### SWE-bench Verified as a coding agent (20 tasks)

HumanEval asks for one function from scratch. [SWE-bench Verified](https://www.swebench.com/)
gives a real GitHub issue and the whole repository; the fix is graded on the
project's own hidden tests. Each model ran as an **agent**, through the same
engine as Claude Code (Claude Agent SDK 0.3.283, `claude_code` preset), pointed at
llama-server on the V100 — so these numbers are what a local model does in that
kind of tool, not in a harness tuned for the benchmark.

- **Tasks:** 20 from the "<15 min fix" group, spread over 8 projects (8 django,
  3 sympy, 2 each sphinx / matplotlib / scikit-learn, 1 each pytest / requests /
  xarray), fixed seed. 20 is a small sample: read a 1–2 task gap as a hint.
- **Rules:** each task in its own SWE-bench container with **no network** (the
  first trial run reached the internet, so a model could have fetched the real
  fix); web tools off; Python and tests run *inside* the container through a
  small wrapper ([`tx`](buyers-bench/swebench/tx)); 30-minute / 100-step limit.
- **Grading:** the official `swebench` 5.0.2 harness. New scratch files and folders
  the agent created outside the project's own source tree are dropped before
  grading (one patch was 32,791 lines of a Sphinx `_build/`), the same for every
  model. Everything at Q4 on the V100 alone, 131K context, each maker's
  recommended sampling, 4,096-token thinking budget.

| Model (Q4, V100) | Thinking on | Thinking off | HumanEval |
| :--- | :--- | :--- | ---: |
| **Qwen3.6 35B-A3B MoE** | **18/20 — 60 min** | 16/20 — 57 min | 94.5% |
| **Ornith-1.5 35B-A3B MoE** | **18/20 — 79 min** | 16/20 — 49 min | — |
| Ornith-1.0 35B-A3B MoE | 17/20 — 99 min | — | 94.5% |
| Gemma 4 26B-A4B MoE | 16/20 — 149 min | 11/20 — 98 min | 97.6% |
| GLM-4.7-Flash 30B-A3B MoE | 12/20 — 185 min | 10/16 vs 10/16 on (stopped) | 81.1% |
| Muse Glimmer 30B dense | 0/2 — stopped, both hit the 30-min limit | — | 96.3% |

- **HumanEval does not predict this.** Gemma 4 leads HumanEval and is third here;
  Qwen3.6 and Ornith-1.5 are behind it on HumanEval and lead here. They fixed
  the **same** 18 tasks; two tasks beat every model.
- **Ornith's "self-improving" agent training didn't beat the plain Qwen MoE** in
  this tool — 1.5 tied Qwen3.6 (and was slower), 1.0 was one task behind.
- **Thinking is worth two fixes for both leaders** — and the same two
  (django-11433, requests-1724). It costs Qwen3.6 only 5% of the time: it thinks
  briefly on an agent step (median 87 characters; 37% of everything it wrote,
  never near the budget). Ornith-1.5 and Gemma think far more (≈⅔ of their
  output), so switching it off saves them 40% — and Gemma falls apart without
  it (9 tasks hit the step limit, 5 produced nothing).
- **Muse Glimmer (Meta, 28B dense, reasoning strength high) is too slow to be an agent on a V100.**
  It scores 96.3% on HumanEval, but both tasks it tried hit the 30-minute limit with no fix. On the second
  (django-11951, fixed by 12 of the 14 earlier runs; Qwen3.6 took 68 steps in 2 minutes) it took 70 steps
  in 30. Each step pulled in ~14K new tokens (it reads whole source files instead of searching them), at
  ~760 t/s prefill for a dense model on this card — ~25 s before it writes anything — and it filled the
  131K context every ~5 steps, forcing a compaction. Its prompt cache worked; the cost is the model's
  reading habit times dense prefill. Run stopped after two tasks; speed is pp512 717 / tg128 39 t/s.
  [Raw data](buyers-bench/results/glimmer).
- **Most of an agent step is re-reading the growing context** (prefill), not
  writing — which is why thinking off, and speculative decoding (below), buy
  so little here.
- Raw grading reports, per-task times and steps, and the scripts:
  [results/swebench](buyers-bench/results/swebench), [swebench/](buyers-bench/swebench).

### Code reviewer test: prove each bug with a failing test (20 builds)

Workbench's second check uses a model on the 4070 to review the builder's code. This tests that seat. 20 builds of the
same small three-part program (an Etsy inventory/orders CLI), 10 of which fail some of 12 hidden tests. The reviewer
sees the request and the code, never the tests, and must **prove** each bug it claims with a pytest test. Each test
runs on the build and on a known-good build: fails on the build and passes on the good one = a proven bug; fails on
both = a wrong test. Same prompt and settings for every model (`--reasoning-budget 4096`, temperature 0.7, 32K
context, 4070). Scripts and logs: [results/reviewer](buyers-bench/results/reviewer).

| Reviewer (4070) | Buggy builds with a proven bug | Proven bugs | Wrong tests | Time per build |
| :--- | ---: | ---: | ---: | ---: |
| **Ternary Bonsai 2 27B** PQ2_0 | **8/10** | **25** | 34 of 68 | 95 s |
| Ornith-9B Q6 (stopped after 7 builds) | 2/5 | 3 | 25 of 34 | ~80 s, 7 min on some |
| Gemma 4 12B QAT | 1/10 | 2 | 22 of 114 | 82 s |
| LFM2.5 8B-A1B Q4_K_M | 1/10 | 3 | 29 of 33 | **16 s** |

- **Bonsai stays the reviewer.** It's the only one that finds and proves bugs reliably. It also "proved" a difference in
  5 of the 10 builds that pass the hidden tests; those may be real gaps the hidden tests don't cover.
- **LFM2.5 is 6× faster and nearly useless here.** On 9 builds it dropped the required code block, and the code it did
  write calls helpers with invented signatures, adds a pytest argument that can't resolve, and once isn't valid
  Python. Fluent and fast isn't the same as careful.

### LFM2 / LFM2.5 (Liquid AI): fast, not careful

Liquid AI's on-device family: hybrid MoE models (short-convolution plus a few attention layers) with very few active
parameters. They're the fastest models measured on every card here. Raw data: [results/lfm](buyers-bench/results/lfm),
[results/pascal](buyers-bench/results/pascal).

| Model | Card | Generation t/s (short → 32K) | Prompt t/s |
| :--- | :--- | ---: | ---: |
| LFM2 24B-A2B Q8_0 (25.4 GB, 2.3B active) | V100 | **149 → 133** | 1,618 |
| LFM2.5 8B-A1B Q4_K_M (1.5B active, reasoning) | RTX 4070 | **326 → 243** | 11,021 |
| LFM2.5 8B-A1B Q4_K_M | V100 | 273 → 238 | 3,857 |
| LFM2.5 8B-A1B Q4_K_M | GTX 1070 | 108 → 88 | 1,794 |
| LFM2 8B-A1B Q4_K_M | GTX 1070 | 118 → 95 | 1,825 |

For scale: Qwen3.6 35B-A3B, the agent leader, generates ~95 t/s on the V100.

- **The 24B is fast and decent, not a top coder:** HumanEval 139/164 (84.8%, greedy; it's an instruct model with no
  reasoning mode), against Qwen3.6's 153 and Gemma 26B's 160, at 1.5× Qwen3.6's speed and at Q8. Its trained context
  is 32K, so it can't take on the 131K agent runs above.
- **The 8B is a weak judge.** As a code reviewer, LFM2.5 proved a bug in 1 of 10 buggy builds, against Bonsai's 8
  ([reviewer test](#code-reviewer-test-prove-each-bug-with-a-failing-test-20-builds)). As an everyday assistant it was
  accurate on plain questions (explaining an error, summarising) in 3.5–8.5 s with reasoning on. But asked to make a
  blaming customer reply friendly, every LFM2 variant kept the blame.
- **The 8B can't draft for the 24B.** Speculative decoding (8B on the 4070 guessing tokens for the 24B on the V100)
  is impossible, because the two use different vocabularies: llama.cpp refuses with "the target and draft vocabs are
  not compatible" (BOS token id 1 vs 124,894) and serves the 24B undrafted. Same family doesn't mean same tokenizer.
- **Power:** the 1070 numbers are in its section. The V100 and 4070 readings for these models caught the card still
  loading and are being re-measured.
- **Where it fits:** the job it was built for, a fast inner-loop model for tool calls, routing and quick replies, and
  the best everyday model for an 8 GB Pascal card. It's not a builder and not a reviewer.

### DiffusionGemma 26B-A4B on the V100 (llama.cpp PR #24423)

DiffusionGemma is Google's Gemma 4 26B-A4B turned into a block-diffusion LM: it
fills a 256-token block over several refinement passes instead of one token at a
time. llama.cpp support is the unmerged [PR #24423](https://github.com/ggml-org/llama.cpp/pull/24423);
it builds and runs on sm_70 (`-DCMAKE_CUDA_ARCHITECTURES=70`). The PR has no
OpenAI-style server, so HumanEval ran through one `llama-diffusion-cli` process in
conversation mode, with a small **local, not upstream** patch to feed multi-line
prompts and mark the end of each reply ([humaneval_dg.py](buyers-bench/humaneval_dg.py)).

| DiffusionGemma | HumanEval | Whole run | Typical answer |
| :--- | ---: | ---: | ---: |
| Q4_K_M, thinking off | 89.0% (146) | 10 min | 2.5 s |
| Q4_K_M, thinking on | 89.6% (147) | 62 min | 15.6 s |
| **Q8_0, thinking off** (split, see below) | **92.1% (151)** | 16 min | 3.1 s |
| *Gemma 4 26B-A4B, same test* | *97.6% / 97.0%* | *6.3 min* | *1.6 s* |

- **Speed is about the same as autoregressive Gemma on this card.** One pass over
  a 256-token block takes ~0.33 s and blocks settle in 3–17 passes (the
  entropy-bound decoder stops early), so effective throughput is ~88–136 tok/s
  against Gemma's 92. Diffusion is compute-bound and the V100 is short on compute
  — its big speed claims are for datacentre cards.
- **Q4 costs it ~3 points where autoregressive Gemma loses nothing.** Plausibly
  because every refinement step acts on the logits' confidence, so quantisation
  error compounds. (Sampling isn't greedy here — treat ±3 as suggestive.)
- **Thinking adds almost nothing**: it fixed 8 problems, broke 7, and made answers
  ~8× slower; 8 times it was still thinking when it ran out of room.
- **A known diffusion weakness showed up:** 3 answers stopped at the first block
  boundary mid-docstring instead of continuing into a second block.
- **Memory:** Q4 at `-n 1536` used 23.3 GB — ~15.7 GB of weights plus ~7.5 GB of
  working space (whole-block logits). **Q8 does not fit the V100 alone.** Split
  with the 4070 it ran out of memory with the V100 listed first; listing the 4070
  first (`CUDA_VISIBLE_DEVICES=0,1 -ts 12/88`) puts the last layer and its big
  buffer on the V100, and it ran.

### DFlash speculative decoding on the V100

[DFlash](https://github.com/ggml-org/llama.cpp/issues?q=dflash) is a small
block-diffusion **drafter** (6 layers, ~0.8 GB) that reads the target model's
hidden states and proposes 16 tokens at once for the target to verify. It is in
recent llama.cpp (`-md draft.gguf --spec-type draft-dflash --spec-draft-n-max 16`).
The drafters ship as BF16 safetensors; convert them to **F16** for the V100:
`convert_hf_to_gguf.py <draft dir> --target-model-dir <dir with the target's
config + tokenizer> --outtype f16`.

Qwen3.6 35B-A3B Q4 + [z-lab's drafter](https://huggingface.co/z-lab/Qwen3.6-35B-A3B-DFlash),
greedy, V100 alone ([raw](buyers-bench/results/dflash/qwen3.6-compare.txt)):

| | tok/s, plain → DFlash | Speed-up | Drafts accepted |
| :--- | ---: | ---: | ---: |
| Thinking off, short answers (code) | 96 → **209** | **2.2×** | 74% |
| Thinking off, long answers | 95 → 114 | 1.2× | 34% |
| Thinking on, short answers | 96 → 118 | 1.2× | 35% |
| Thinking on, long answers | 96 → 96 | 1.0× | 27% |

- **The drafter predicts code well and thinking/prose badly** (an all-prose
  "explain" prompt: 17% accepted, slower than plain).
- **As a coding agent it was 40% slower:** 6 SWE-bench tasks, all fixed either
  way, 20.1 min with DFlash against 14.5 without (2.9 vs 2.3 s per step). Agent
  steps are mostly prefill of a long context, which DFlash can't speed up and the
  drafter adds to. Use it for short, thinking-off answers, not for agents.
- Greedy output is **not byte-identical** with DFlash (6 of 12 diverged, usually
  early, from batched-verification arithmetic flipping near-ties) — but every
  diverged HumanEval answer still passed.
- Ornith-1.5 35B-A3B with its own drafter showed the same pattern: 1.9× on short
  answers, slower on long ones ([raw](buyers-bench/results/dflash/ornith-1.5-compare.txt)).

### Changing how many experts a MoE uses (4 models)

A MoE's active-expert count is just a number in the GGUF, and llama.cpp can
override it at load — no retraining (this is all the community "A6B" variants
do): `--override-kv qwen35moe.expert_used_count=int:N` (`gemma4.` / `mistral4.`
for those models). The server doesn't log it at normal verbosity; `-lv 4` shows
`n_expert_used = N`, which is how these runs were checked. Memory doesn't change —
every expert is loaded either way; only the compute per token does.

**Qwen3.6 35B-A3B Q4** (256 experts, default 8), V100; HumanEval greedy, prefill at
~2K / ~5K-token prompts ([raw](buyers-bench/results/experts)); SWE-bench as above
(20 tasks, thinking on, the same 18 fixed wherever 18 is shown):

| Active experts | 3 | 4 | 5 | 6 | **8 (default)** | 12 | 16 |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| HumanEval | 140 | 148 | 155 | 154 | 153 | — | 154 † |
| Prefill tok/s, ~2K / ~5K | 930 / 982 | 824 / 852 | 739 / 760 | 676 / 696 | 585 / 598 | — | 447 † |
| Decode tok/s | 103.5 | 100.7 | 99.4 | 98.1 | 94.6 | — | 85.4 † |
| **SWE-bench fixed** | — | — | 18/20 | — | **18/20** | 18/20 | **15/20** |
| SWE-bench time / steps | — | — | 89 min / 1,997 | — | **60 min / 1,460** | 63 min / 1,581 | 64 min / 1,453 |

† separate run at the maker's sampling, not greedy.

- **Fewer experts read faster but take more agent steps:** 5 experts matched the
  default on HumanEval and read 26% faster, then needed 37% more steps on SWE-bench
  and took 50% longer for the same fixes.
- **More experts cost time and, at 16, fixes** — 16 looked as good as 8 on
  HumanEval and lost 3 of 18 on SWE-bench.
- **Ornith-1.5 35B-A3B** (same design): 12 experts scored 148 vs 145 on HumanEval
  (greedy), then fixed the same 18 SWE-bench tasks in 121 min instead of 79.
- **Gemma 4 26B-A4B** (128 experts, default 8): 6 experts scored 158 vs 160 on HumanEval, then **fixed 14
  SWE-bench tasks instead of 16**, in 130 min / 1,242 steps instead of 149 min / 1,600. It lost three
  (requests-1724, sphinx-9281, and matplotlib-13989, where it produced an empty patch) and gained one
  (sphinx-7889). Unlike Qwen, Gemma took *fewer* steps with fewer experts. It was 13% quicker and less
  accurate, not slower.
- **Every model's default was its best setting for agent work.** Six changed settings were tested on SWE-bench (Qwen3.6
  at 5, 12 and 16; Ornith-1.5 at 12; Gemma at 6), and none fixed more than the default. HumanEval didn't predict
  it: it pointed the wrong way for Qwen at 5 and 16 and for Ornith at 12, and only Gemma's small dip agreed. That's
  the same lesson as DFlash and thinking off.

**Mistral Small 4 119B-A6B** (128 experts, default 4) at **UD-IQ2_M (37.6 GB)**,
split V100 + 4070 (`CUDA_VISIBLE_DEVICES=<V100>,<4070> -ts 75/25`), reasoning off,
temperature 0.3 ([raw](buyers-bench/results/mistral4)):

| Active experts | HumanEval strict | HumanEval fair | Prefill (~2K prompt) | Decode |
| :--- | ---: | ---: | ---: | ---: |
| 2 | 53.7% (88) | 68.3% (112) | 135 | 64.5 |
| **4 (default)** | 64.0% (105) | **83.5% (137)** | 118 | 58.1 |
| 8 | 84.8% (139) | 84.8% (139) | 94 | 48.6 |

- **At 4 experts it indents every answer** — the whole function shifted right, so
  Python rejects it before the logic is tested. "Fair" removes that indentation
  only when the reply is a complete, shifted `def` (body-only answers are meant to
  be indented; a blanket dedent wrongly cost other models up to 16 points), and
  changed no other model's score ([regrade_dedent.py](buyers-bench/regrade_dedent.py)).
  **At 8 experts the quirk disappears.** At 2-bit it trails Qwen3.6 at 4-bit by ~10
  points; Qwen3.5 122B at 2-bit held 92.1%.
- **It can't be a coding agent on this pair of cards:** `-fa on` crashes it (MLA,
  key/value 320/256), and without flash attention a **32K** context runs the 4070
  out of memory (+2.2 GB of compute buffer); 16K fits. Agents need 30K–130K.

## The table

| Repo | Tested | Result |
| :--- | :--- | :--- |
| [volta-bonsai](https://github.com/christopherrobertbrooks-tech/volta-bonsai) | Ternary-Bonsai-2-27B (PQ2_0/PTQ1_0), V100 vs 4070 | Ternary kernels and vision both work on Volta; PQ2_0 decode (50.97 t/s) beats PTQ1_0 (34.40 t/s) on the V100 — the opposite ranking to the 4070 |
| [volta-gpt-oss](https://github.com/christopherrobertbrooks-tech/volta-gpt-oss) | gpt-oss-20b MXFP4 on V100 | 143–144 t/s decode, despite MXFP4 being documented as needing compute capability ≥ 9.0 |
| [volta-deepseek-mla](https://github.com/christopherrobertbrooks-tech/volta-deepseek-mla) | DeepSeek-V2-Lite flash attention, V100 + 4070 + GTX 1070 | `-fa on` costs 80% of decode on the V100 and 52% on the 4070 — a model-shape bug, not Volta-specific (corrected). Also: PR #26404's suggested tile-kernel patch passes 66/0 on both Pascal and Volta |
| [volta-ik-llama](https://github.com/christopherrobertbrooks-tech/volta-ik-llama) | ik_llama.cpp build + IQK trellis quants, V100 | Builds clean with no source changes on sm_70; IQ4_KT runs, 21% smaller for 13% slower decode |
| [volta-dual-card](https://github.com/christopherrobertbrooks-tech/volta-dual-card) | Mixed sm_70 + sm_89 layer split (`-sm layer`) | Works, no VRAM leak; helps a MoE model (+5.5% decode) and hurts a dense 27B (−9.6%) |
| [volta-diffusion](https://github.com/christopherrobertbrooks-tech/volta-diffusion) | Dream-v0-Instruct-7B diffusion LM, V100 | Runs; 274.1 ms/step vs the 4070's 237.6 ms/step |
| [volta-bf16](https://github.com/christopherrobertbrooks-tech/volta-bf16) | BF16 vs F16 prefill, V100 (Qwen3-4B) | BF16 costs the V100 77% of its prefill — Volta has no BF16 hardware. Convert to F16 first |
| [volta-hadamard](https://github.com/christopherrobertbrooks-tech/volta-hadamard) | A Hadamard rotation tool for Prism's PQ2_0 format | Rotating weights improves llama.cpp's own Q2_K by **17.8%** on Qwen3-4B (wikitext-2, 200 chunks, clear of the error bars). The benefit tracks how much damage Q2_K did: a MoE model that Q2_K barely hurt saw nothing. Prism's own public ternary quantizer is a stub |

## Findings by question

### Works on sm_70 / sm_61 despite documentation saying otherwise

- **MXFP4** — documented as requiring compute capability ≥ 9.0 (Hopper+). Runs on the V100 (7.0) at 143–144 t/s with correct output. [volta-gpt-oss](https://github.com/christopherrobertbrooks-tech/volta-gpt-oss)
- **Ternary kernels (PQ2_0 / PTQ1_0)** — greedy output token-identical to an RTX 4070 run. The two packings invert their relative speed ranking between the two cards. [volta-bonsai](https://github.com/christopherrobertbrooks-tech/volta-bonsai)
- **Vision on Volta** — correct on a dense table with SKU codes, prices and footnotes, including leading zeros. Image encode 158–394 ms. [volta-bonsai](https://github.com/christopherrobertbrooks-tech/volta-bonsai)
- **ik_llama.cpp** — an open upstream issue states Volta is not officially supported. It builds with zero source changes and runs correctly. [volta-ik-llama](https://github.com/christopherrobertbrooks-tech/volta-ik-llama)
- **Diffusion LMs** (`dream`, via `llama-diffusion-cli`) — run on Volta at 274.1 ms/step. [volta-diffusion](https://github.com/christopherrobertbrooks-tech/volta-diffusion)
- **DiffusionGemma (llama.cpp PR #24423)** — builds for sm_70 and runs; 89.0% HumanEval at Q4, 92.1% at Q8. [DiffusionGemma](#diffusiongemma-26b-a4b-on-the-v100-llamacpp-pr-24423)
- **DFlash drafters** — convert to F16 and run on sm_70; 2.2× on short thinking-off code. [DFlash](#dflash-speculative-decoding-on-the-v100)
- **Mixed-architecture layer split** (sm_70 + sm_89 in one job) — works, no VRAM leak; beat the V100 alone by 5.5% decode on a MoE model. [volta-dual-card](https://github.com/christopherrobertbrooks-tech/volta-dual-card)
- **Flash-attention tile kernel on Pascal** — built for `sm_61;sm_70` and verified with `cuobjdump` to contain both. `test-backend-ops -o FLASH_ATTN_EXT -p "hsk=192"` gives **66 OK / 0 FAIL on the GTX 1070 and 66/0 on the V100**, covering GQA ratios 1, 4 and 5 — the non-multiples of 8 that previously hit a hard abort. [volta-deepseek-mla/pr26404-test](https://github.com/christopherrobertbrooks-tech/volta-deepseek-mla/tree/main/pr26404-test)

### Performance traps

- **BF16 costs the V100 77% of prefill.** Volta has no BF16 hardware; the identical model in F16 is 4.37× faster at prefill on the same card. Decode is unaffected. [volta-bf16](https://github.com/christopherrobertbrooks-tech/volta-bf16)
- **DeepSeek flash-attention regression.** `-fa on` costs 80% of decode on the V100 and 52% on the 4070, with byte-identical output and no warning. The cause is the model's attention head shape (192/128, GQA ratio 1), not the GPU — see [Corrections](#corrections). [volta-deepseek-mla](https://github.com/christopherrobertbrooks-tech/volta-deepseek-mla)
  **GLM-4.7-Flash**, also MLA (`deepseek2` arch, key/value 576/512), is **not** caught by it: `-fa on` is −7% decode, +7% prefill. Measure per model.
- **DFlash slows a coding agent down** (−40% on SWE-bench tasks) even though it doubles short thinking-off answers. [DFlash](#dflash-speculative-decoding-on-the-v100)
- **Mistral Small 4 (`mistral4`, MLA 320/256) crashes with `-fa on`,** and without it can't reach a 32K context across 44 GB. [Experts](#changing-how-many-experts-a-moe-uses-4-models)
- **Changing a MoE's expert count never beat the default as an agent** — fewer experts add steps, more add cost. [Experts](#changing-how-many-experts-a-moe-uses-4-models)

### Tooling gotchas

- **Use `llama-bench`, not `llama-cli`, to benchmark.** A ~20-token prompt in `llama-cli` undershot the real prefill number by roughly 6×.
- **`llama-diffusion-cli` defaults abort.** Exactly one of `--diffusion-eps` / `--diffusion-block-length` must be non-zero, and both default to zero, so the stock invocation core-dumps before generating anything.
- **`-ts` is slash-separated, not comma-separated.** `-ts 0,1` silently runs two separate benchmark configs instead of one ratio, and can print a plausible-looking number before failing.
- **`-sm row` fails to load** on this mixed card pair, independent of memory pressure (confirmed with a model needing only ~4.8 GiB/card).
- **Claude Code–style agents send a second system message after the user turn** (the environment block: working directory, platform). Templates with `raise_exception('System message must be at the beginning.')` — Ornith's recommended template, both 1.0 and 1.5 — refuse **every** request with HTTP 500. Render non-first system messages in place instead. Qwen3.6, GLM and Gemma accept it as shipped.
- **Agents ignore a server-side "thinking off" unless the server forces it.** The Agent SDK sends `thinking: {type: adaptive}` on every request; `--reasoning off --reasoning-budget 0` overrides it.
- **Docker 29 keeps images in `/var/lib/containerd`, not `data-root`.** Twenty SWE-bench images (47 GB) filled a root disk despite `daemon.json` pointing elsewhere; relocate `/var/lib/containerd` before pulling.

## Corrections

Two claims in these repos were wrong on the first pass and were corrected in
place. Both were caught by running a control rather than trusting the first
result. They are listed here on purpose: they are the reason to trust the other
numbers, not a reason to doubt them.

1. **The DeepSeek flash-attention regression was first called Volta-specific.**
   The initial commit attributed the `-fa on` decode collapse to Volta, since it
   matched FlashMLA's documented Ampere-or-newer floor. Running the RTX 4070 as a
   control showed it regresses too — −52% decode, against −80% on the V100. The
   selector in `ggml/src/ggml-cuda/fattn.cu` confirmed the real cause: it gates
   on head dimensions and GQA ratio, never on compute capability.
   (`volta-deepseek-mla`, commit `455c09b`.)

2. **volta-hadamard first claimed a clean crossover** — rotation hurting
   perplexity at 4-bit and helping below it — from a single model (Qwen3-4B).
   A second model (Qwen3-8B) showed the Q3_K_M and Q4_K_M results flip sign
   between models, so they were noise. The crossover claim was retracted.

   Then the measurement itself turned out to be the weak part. Those runs used
   20 chunks of an unsaved corpus and recorded no error bars, so nothing from
   them could be trusted in either direction. Re-run on wikitext-2 at 200
   chunks with error bars, Qwen3-4B Q2_K goes 36.1895 → 29.7360: **−17.8%**,
   cleanly separated — four times the effect originally reported. The first
   number was understated, not invented, but it was not evidence either way.
   (`volta-hadamard`, commits `01acf8d` and `fc58596`.)

A third thing worth stating plainly: a `-fa` before/after diff of which
individual test cases newly pass was **not** established, because the unpatched
control sits at a different commit whose harness emits different case strings.
The two logs are not comparable and an attempted diff produced meaningless
"regressions".

## Offer

I have this hardware sitting here — a Tesla V100, a GTX 1070, and an RTX 4070
— and most projects only test on newer cards, so behaviour on sm_70, Pascal
and Ada often just isn't known. If you need something run on one of these,
point me at a branch and a command and I'll run it and post the output.

To be clear about scope: I'm offering to run things and report exactly what
happened — numbers and logs from real hardware. I'm not offering to review
your code, argue about design, or defend a patch.
