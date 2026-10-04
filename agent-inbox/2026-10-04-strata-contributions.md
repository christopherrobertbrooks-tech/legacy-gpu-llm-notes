# Possible contributions to Strata from this hardware

Status: open (Claude Code's list; Chris approves every post -- Claude drafts, Chris reviews, nothing is posted without his yes)
From: Claude Code, 2026-10-04

Strata's repo has an AGENTS.md for AI assistants and asks for older-GPU reports ("the card, the driver / ROCm version, the
model and the engine log"). House style: plain words, measured numbers with what they were measured on, no claim without a
measurement. Our hardware: V100-PCIE-32GB (sm_70, PCIe x4) + RTX 4070 12 GB, i7-13700KF, **16 GB DDR5**, SATA SSD for the
model files, Ubuntu 24.04, CUDA 12.9, driver 580.

| # | Issue | What we can add | Status |
|---|---|---|---|
| -- | Community benchmark (COMMUNITY_BENCHMARKS.md, #713) | V100 + 16 GB RAM low-RAM mode, Coder IQ1_M: all 12,288 experts VRAM-resident, decode 70-95 tok/s, prefill ~1,450, HumanEval 158/164, real agent tasks 4/4 | **first, after the tests** |
| #754 | Anthropic API: tool calls emitted inside `thinking`, returned as end_turn | Workbench uses exactly this API from a real agent; log any occurrence | watch |
| #710 / #728 | agent loops repeating an ineffective fix | real agent runs with logs | watch |
| #690 | layer split fails on the second GPU on long prompts (reported AMD) | does it happen on a mixed NVIDIA pair (sm_70 + sm_89)? | to test |
| #771 | Linux start 20x slower with MADV_HUGEPAGE + defrag=madvise | our start is ~80 s; check our THP setting, report either way | to check |

## Added 2026-10-04 (Chris: "I really like this project and want to contribute how we can")
New items found during our own runs (drafts by Claude, every post approved by Chris first):
| What | Kind | Status |
|---|---|---|
| Stopping `serve/server.py` (SIGTERM) leaves the engine child running and holding the GPU | bug report | ready to draft |
| Running Strata behind llama-swap: DNS-rebinding guard refuses the proxied Host (`STRATA_ALLOWED_HOSTS`), and stop the whole process group | docs how-to | ready to draft |
| Claude Code / Agent SDK sends `output_config.effort: "high"` by default; `CLAUDE_CODE_EFFORT_LEVEL=medium` was 1/3 faster and as correct on a real task (low was slower) | docs tip | ready to draft |
| Runaway thinking (140K chars, hit the 32K output cap) + thinking-cap A/B (Muse's plan) | #710/#728 comment | after the A/B |
| Volunteer as V100 tester for releases touching the older-card paths (build, start, speed, HumanEval slice) | ongoing | offer in the benchmark report |
Suggested order: benchmark report, then the SIGTERM bug, then #710/#728 after the A/B.

## Mixed-architecture dual card (added 2026-10-04, Chris)
Our pair is unusual and exactly what Strata's docs call untested: **V100 (Volta, sm_70) + RTX 4070 (Ada, sm_89)** in one PC.
NVIDIA_V100.md says a V100 + newer-card build (`-DCMAKE_CUDA_ARCHITECTURES="70;86"`) ran once in a community report (#509)
"and was not repeated here"; OLDER_GPUS.md says a V100 + RTX 30/40 model runs both on the CUDA 12 engine. #690 reports the
second GPU of a mixed **AMD** layer split failing on long prompts ("no kernel image is available").
Plan (needs both cards, so Workbench's builder and Ember are paused for the session):
1. Build the CUDA 12 engine for both arches (`70;89`).
2. Coder IQ1_M forced across both cards (`--gpus 1,0`, layer split): does it start; short prompt; then a prompt larger than
   the 8,192-token prompt chunk (#690's trigger); both card orders.
3. Speed vs the V100 alone (decode, prefill) -- and PCIe traffic now that activations cross cards (the V100 is on x4).
4. Optional: the full model Q2_0 (37.6 GB, needs both cards; ~70 GB download -- Chris's OK first).
Report: works / fails with logs, numbers, both orders -> a #690 comment (NVIDIA data point) + the multi-GPU docs.

## FOUND + FIXED LOCALLY (2026-10-04): images inside Anthropic `tool_result` blocks never reach the model
Symptom: in Workbench (Claude Agent SDK -> Anthropic Messages API), Strata said a screenshot "came back black" (the PNG was
fine) and once wrote "The window looks right" without having seen it. Repro (same image, same question, thinking disabled):
image in a plain user message -> "Swap, Net, Disk, Data" (correct); the same image inside a `tool_result` (how Claude Code
returns a Read of a PNG) -> "A, B, C, D, E" (made up).
Cause: `serve/frontend.py` `anthropic_to_messages()` -- the image path skips any user message containing a `tool_result`,
and the `tool_result` branch builds the tool message with `_text_of(block.get("content"))`, which keeps text only; image
blocks are silently dropped.
Fix tested on our copy (v0.1.39): after the tool message, pass the result's image parts on as a user message
(`[{"type":"text","text":"(image returned by the tool above)"}] + image parts from _parts_of(content)`) -- the template shows
images in user turns. After the fix the tool_result case answers "Swap, Net, Disk, Data". serve/test_server.py: 139 tests OK.
For the PR: add a unit test for anthropic_to_messages() with an image inside tool_result; check the OpenAI path's tool
messages with image content too. **Top of the contribution list** (Chris approves the text first).

Muse's addition (2026-10-04): run the V100-alone baseline (same prompts, same chunk sizes) in the *same
session*, immediately before the split runs -- thermal state and background load then can't pollute the
comparison. Record nvidia-smi dmon on both cards during the split runs: with the V100 on x4, cross-card
activation traffic is the thing to watch.

**POSTED 2026-10-04:** the tool_result image fix -> https://github.com/Niko1221/Strata/pull/819 (from fork
christopherrobertbrooks-tech/Strata, branch fix/tool-result-images; text approved by Chris; commit under GitHub's no-reply address).

**POSTED 2026-10-04:** community benchmark report -> https://github.com/Niko1221/Strata/pull/823 (V100 32 GB + 16 GB RAM,
Coder IQ1_M: prompt 1,233/1,580/1,394 tok/s, decode 69/69/67 tok/s at 4K/32K/128K, needles 6/6).

**Dual-card test, extended (Chris):** also run the **full model IQ2_XS** (all 512 experts/layer, ~39 GB RAM+VRAM) across
V100 + 4070 (44 GB) and compare with the RTX 5090 community report (same size IQ2_XS, 32 GB card + 64 GB RAM; its medians:
prompt 4,270 / 5,543 / 5,779 tok/s, decode 179 / 176 / 165 tok/s at 4K/32K/128K). Same benchmark.py + needles. Download
only shard 1 (~40 GB; shard 2 and the vision encoder are shared with the Coder). Also answers #690 on NVIDIA.

**Tested 2026-10-04 -- the "engine left running" bug is NOT real (dropped).** Strata started normally (run-coder-iq1_m.sh),
one signal to serve/server.py, engine + V100 memory watched for 30 s: SIGTERM -> engine gone and VRAM freed in 2 s,
server in 3 s; SIGHUP (closing the terminal) -> all gone within 1 s; SIGINT to the server process alone -> both kept
running for 30 s (a real terminal Ctrl+C signals the whole process group; not tested -- minor). The earlier observation
was a check ~3 s after SIGTERM, mid-shutdown. The llama-swap how-to drops the process-group wrapper (llama-swap's SIGTERM
works); the remaining trap is the DNS-rebinding Host check (STRATA_ALLOWED_HOSTS).

**POSTED 2026-10-04:** llama-swap how-to -> https://github.com/Niko1221/Strata/pull/829 (docs/LLAMA_SWAP.md; entry tested end to end today).

**POSTED 2026-10-04:** #728 comment -> https://github.com/Niko1221/Strata/issues/728#issuecomment-5984010954 (Coder data point: 1 sentence x1,110 in one thinking block, 1 of 20 agent jobs; likely trigger = reasoning about a screenshot it never received (#819); reasoning_budget_tokens bounds it).

## Dual-card results (2026-10-04): full Qwen3.8-Flash-Next IQ2_XS split across V100 (sm_70, PCIe 3.0 x4) + RTX 4070 (sm_89)
Engine 0.1.39 rebuilt by setup for archs [70, 89] (CUDA 12.9); low-RAM mode (`--mmap-experts`, 16 GB RAM); context 131,072;
same benchmark.py (3 runs each, 256-token cap, reasoning none) + needles 32k/128k x 10/50/90.
| Configuration | Split chosen | Decode tok/s 4K / 32K / 128K (medians) | Prompt tok/s 4K / 32K / 128K | Needles |
|---|---|---|---|---|
| 1. V100 first, auto | K=39: V100 layers 0-38, 4070 39-47; 95% of experts resident | **84.9 / 81.5 / 75.1** | 996 / 1,602 / 1,552 | 6/6 |
| 2. V100 first, `layer_split: 39` | same | 84.9 / 82.0 / 75.2 | 925 / 1,601 / 1,553 | 6/6 |
| 3. 4070 first, auto | K=11: 4070 layers 0-10, V100 11-47 | 79.1 / 83.8 / 77.1 | 985 / 1,535 / 1,533 | 6/6 |
- **#690 on NVIDIA:** no "no kernel image" (or any) failure in either card order; 32K and 128K prompts (past the 8,192-token
  chunk) ran on the second card every time. Mixed-arch NVIDIA layer split works on 0.1.39.
- A fixed split point changed nothing here: in 0.1.39 the auto split already loads only each card's own layers' weights
  ("CUDA1 holds its weights, session [39, 48)"), so MULTI_GPU.md's note about auto keeping full copies looks out of date.
- PCIe during long prompts: ~2 GB/s into the V100 (about half its x4 link), ~2 GB/s into the 4070; 112-794 MB per request
  read from the SSD (mmap experts not resident).
- vs the RTX 5090 community report (same IQ2_XS, 32 GB card + 64 GB RAM): decode 179 / 176 / 165, prompt 4,270 / 5,543 /
  5,779 -> this pair is ~45% of its decode and ~29% of its prompt speed. vs the Coder IQ1_M on the V100 alone: decode 69 / 69 / 67.
Possible posts (Chris approves): a #690 comment (NVIDIA mixed pair works), a second benchmark report (dual card).
**HumanEval gate for the full model (both cards, vision on, 128K ctx, 90% of experts resident with vision):** 154/164 in
7.2 min (thinking off, same harness) vs the Coder's 158/164 in 7.1 min on the V100 alone. Failures overlap on 38/50/145;
the full model solved 10/113/156 that the Coder missed, and missed 91/93/101/130/132/140/163. Below the Coder ->
no Workbench trial; the Coder stays the builder (the full model at 2-bit loses more to quantisation than it gains from
all 512 experts, and it ties up both cards).

**POSTED 2026-10-04:** #690 comment -> https://github.com/Niko1221/Strata/issues/690#issuecomment-5985234418 (mixed V100+4070 split works in both orders, long prompts included).

**Correction (2026-10-04):** PCIe into the V100 during the split's long prompts *peaks* at 3.5-3.7 GB/s (essentially the whole PCIe 3.0 x4 link; median ~0.3-0.4 GB/s) -- the earlier "~2 GB/s, about half" came from a short sample. The 4070 peaks at 13.4-13.7 GB/s.
