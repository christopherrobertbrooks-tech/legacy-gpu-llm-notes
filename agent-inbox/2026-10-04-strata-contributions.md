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
