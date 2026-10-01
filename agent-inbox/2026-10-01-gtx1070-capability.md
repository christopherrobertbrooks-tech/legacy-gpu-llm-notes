# GTX 1070 capability map: Pascal in 2026

Status: done
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

## Progress (Claude Code)

**2026-10-01 — reviewed and running** (Chris approved). Built llama.cpp (the Prism/Bonsai fork, `3ae4f51`, the
same commit as the V100/4070 buyers-bench runs) for `sm_61` on the gateway and bundled it at `~/pascal-bench/` on
Dev-Console with the CUDA 12.9 runtime libs. Nothing is installed on the frozen machine. Smoke test: Qwen2.5-Coder 7B
Q4_K_M gives pp512 579 t/s and tg64 32 t/s.

Changes from the ask:

- **Correction:** the 1070 hasn't sat out everything. It ran the PR #26404 flash-attention tile-kernel test
  (66/0, in `volta-deepseek-mla/pr26404-test`).
- **Same models as the V100/4070 buyers-bench, not a new 7/14/24/32B × 3-quant ladder.** That makes it a direct
  three-card table, and tokens per watt (item 3) comes along with it. The ladder would need about 12 new downloads,
  and 24B/32B don't fit 8 GB. Models: Qwen3.5 4B Q8_0 (re-downloaded, unsloth), Qwen2.5-Coder 7B Q4_K_M,
  Gemma 4 12B QAT Q4, and Bonsai 27B at PQ2_0 and PTQ1_0. Gemma 26B-A4B Q4 runs with experts in system RAM
  (`-ncmoe`, smallest N that loads).
- **Quant ranking (item 2) = Bonsai PQ2_0 vs PTQ1_0**, the exact pair whose speed ranking flips between the V100 and
  the 4070. Perplexity is skipped: it's a property of the weights and identical across cards. Only speed can invert.
- **Skipped Qwen3.6 35B-A3B in system RAM:** about 15 GB of experts on a 23 GB machine with systemd-oomd, which once
  killed the desktop session. The Gemma run has a free-memory watchdog.
- **Added (Chris's ask): real jobs** to see whether the card is useful as something other than a coder: screenshot
  reading (Ember's vision lane, qwen3.5:0.8b vs qwen3-vl:4b), an Etsy listing draft from a real design, and three
  everyday-assistant requests (qwen3:8b, Gemma 12B).

**2026-10-01 — done.** Write-up: README section "What a GTX 1070 (Pascal, 8 GB) is still good for"; raw data in
`buyers-bench/results/pascal/`. Headline: small MoE models are what an 8 GB Pascal card is for. LFM2 8B-A1B writes at
118 t/s (95 at 32K) at 1.43 tokens per joule, faster than the V100 with any model and the most efficient result on any
of the three cards. Dense models run at about a third of V100 speed. Quant ranking: the 1070 sides with the V100 on
decode (PQ2_0 > PTQ1_0) and with the 4070 on prefill (PQ2_0 ~2×). Real jobs: Qwen3-VL 4B reads a screenshot 8/8 and
drafts Etsy listings within the rules; Gemma 12B and gpt-oss 20B are the best writers. Extras run: Granite 4.0 H Tiny,
gpt-oss 20B and Gemma 26B with experts in system RAM (both fill the 24 GB PC's swap). Found along the way: the
buyers-bench power pass can sample an idle card for fast models (1,024 tokens finish before the 12–22 s window). A
re-measure of the V100/4070 power table is running (`buyers-bench/power-recheck.sh`).
