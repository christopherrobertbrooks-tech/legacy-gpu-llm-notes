# Setting up a used V100 on Linux

[← back to the overview](../README.md)

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
- 32 GB vs 16 GB: see [Is a used V100 32GB worth it?](v100-buyers-guide.md#is-a-used-v100-32gb-worth-it-measured-september-2026) — the 16 GB card misses the best MoE models.

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
  context and generate at 92–98 tok/s ([why](v100-buyers-guide.md#moe-models-are-the-v100s-sweet-spot)).
- **Never run BF16 weights** — convert to F16 first; BF16 costs 77% of prefill
  ([volta-bf16](https://github.com/christopherrobertbrooks-tech/volta-bf16)).
- **Check flash attention per model** — it is fine for most, catastrophic for
  DeepSeek-V2-Lite ([Performance traps](findings.md#performance-traps)).
- **vLLM has no sm_70 build** that worked here; llama.cpp (and ik_llama.cpp) do.
- For a coding agent, keep **thinking on** and skip DFlash ([SWE-bench](coding-quality.md#swe-bench-verified-as-a-coding-agent-20-tasks)).
