# MTP self-speculative decoding for Qwen3.8-Flash-Next on V100 + 4070

Status: done
From: Muse, 2026-10-04

## Context

Strata's decode speed comes from MTP (multi-token prediction) speculative
decoding — Chris's measured acceptance on the V100 is 58% prose / 70% code.
The question: can we get MTP speculative decoding outside Strata, on the
llama.cpp-family stack, for the same model?

The ingredients now exist publicly:

- **Checkpoint**: Qwen3.8-Flash-Next ships a native 2.6B MTP head (one full
  QSA layer + entry fusion + exit mixer). Public converters used to drop it.
- **Conversion**: llama.cpp PR #20533 maps MTP tensors into GGUF (`nextn`
  tensors, `qwen4exp` arch). Tensors load; stock llama.cpp can't use them yet.
- **Inference**: ik_llama.cpp PR #2369 adds MTP (NextN) self-speculative
  decoding for `qwen4exp` — `--spec-type mtp:n_max=N`, chains with ngram-mod
  and other stages.
- **Prebuilt reference**: `pentacoxian-dev/Qwen3.8-Flash-Next-IQ3E-Q8D-MTP-GGUF`
  on HuggingFace — single-file GGUF with the MTP head added back, MTP draft
  head at Q8_0, draft-only LM head at Q4_0. BUT it is tuned for **dual V100
  32GB** (~64GB VRAM budget for experts). Chris has ONE V100 32GB + ONE RTX
  4070 12GB = 44GB. It will not fit his pair as designed, and spilling experts
  to RAM would eat exactly the speedup MTP is supposed to buy. Do not just
  download and run it — the quant mix needs resizing for 32+12.

Cautionary tale: igorls/ninfer's writeup
(`docs/flash-next-mtp-speculation.md`) got **4% MTP acceptance** on Flash-Next
in their engine (vs 66.5% on the 27B on the same engine) because their draft
path skipped the sparse-attention indexer — decode got 31% SLOWER than
speculation off. A bad MTP integration is worse than none. Strata's 58/70%
is the proof it can be done right; it is also the baseline to beat or match.

Known good on this box: mixed-architecture layer split across V100 (sm_70) +
4070 (sm_89) works in both orders (tested 2026-10-04, issue #690 did not
reproduce on NVIDIA). So a 44GB split is viable hardware-wise.

## Ask

1. Build an MTP-enabled GGUF of Qwen3.8-Flash-Next with a quant mix sized for
   32+12GB VRAM (all experts resident — no RAM spill for the hot path).
   Follow the pentacoxian-dev recipe (MTP head at Q8_0, draft-only LM head at
   low quant) but retune the expert quants down to fit ~44GB. Verify the
   `nextn` tensors are present in the file.
2. Run it under ik_llama.cpp (needs the MTP/PR #2369 support — check what
   commit has it) with `--spec-type mtp`, split across both cards.
3. Measure: MTP acceptance rate (per position if the server reports it),
   decode tok/s, prefill tok/s, TTFT — at 4K and 32K context, short prompt.
4. Compare against: (a) the same GGUF with speculation off, (b) Chris's
   Strata Coder numbers (decode ~69 tok/s, 58%/70% acceptance) as the
   reference target.
5. If acceptance craters (<20%), diagnose before concluding: check whether the
   draft path is doing something dumb (cf. the ninfer sparse-attention lesson).
   Report the per-position acceptance curve — a cliff after position 1 means
   broken draft attention, not a weak head.

## Results go to

- New section in the umbrella README on speculative decoding / MTP
- Raw numbers under the benchmarks area (follow existing layout)

## Done when

Acceptance + decode measured at two context lengths, compared against
no-spec baseline and Strata reference, README section written, and this note
flipped to `Status: done` with the headline (even if the headline is "MTP
doesn't transfer — acceptance X%, slower than Strata").

## Feasibility check (Claude Code, 2026-10-04)

**Ready:** ik_llama.cpp PR #2369 (qwen4exp MTP / NextN self-speculative decoding) is **merged** (2026-09-02, 563b798);
llama.cpp #20533 was closed unmerged, so stock llama.cpp can't use the head. The pentacoxian file is a **splice**
(routed experts + PLE from unsloth UD-IQ3_XXS, dense Q8_0 tensors from UD-IQ4_XS, MTP head via
`convert_hf_to_gguf.py --mtp` streaming only the `mtp.*` tensors, ~8 GB) -- no full 360 GB BF16 / 186 GB FP8 download needed.

**Blocker: size.** unsloth's GGUFs (all include the PLE table): UD-IQ1_S 72.5 GB, UD-IQ1_M 74.5, UD-Q2_K_XL 78.9,
UD-IQ3_XXS 82.0, UD-IQ4_XS 93.7 (pentacoxian: 85.9 GB, sized for 2x32 GB VRAM). Even UD-IQ1_S leaves ~47 GB of non-PLE
tensors -- over this pair's 44 GB (less ~1 GB for the display and the KV cache) -- and it's 1-bit. Strata's IQ2_XS (37.6 GB
RAM+VRAM requirement) fits only because of its own GSQ-RCO format, which other engines can't load. Spilling experts to RAM
isn't an option here (16 GB RAM) and SSD-streaming kills the speed MTP is meant to buy (measured today: Strata IQ3_XXS with
~22% of experts off the SATA SSD reads prompts at ~150-350 tok/s vs ~1,600 when resident).

**Verdict:** as specified (all experts resident on 32 + 12 GB, compare decode), **not feasible on this hardware** -- needs a
second 32 GB card or much more RAM. **Cheaper partial answer:** acceptance doesn't depend on speed, so the pentacoxian file
could run with experts streamed from the SSD to measure **per-position MTP acceptance only** (speeds meaningless) -- the
"is the draft path sane / does it transfer" half. Cost: 86 GB download + deleting the IQ3_XXS files. Chris decides.

## Resolution (Chris, 2026-10-04)

Dropped. The feasibility check stands: even IQ1_S can't fit 44 GB resident, and the SSD-streamed acceptance-only variant wasn't worth an 86 GB download plus deleting the IQ3_XXS files for a question whose answer (draft-path sanity) doesn't change anything actionable on this hardware. Revisit if a second 32 GB card or much more RAM ever lands.

## Update (Claude Code, 2026-10-05)

Stock llama.cpp now has it too: **ggml-org/llama.cpp #29761 "Qwen4Exp: add MTP"** merged 2026-10-01 (`--spec-type
draft-mtp`); the author reports 1.55x decode (28.4 -> 43.9 tok/s, acceptance 0.64) on a DGX Spark, IQ4_XS, `-np 1`, 24
speed-bench prompts. This corrects the line above that stock llama.cpp can't use the head. **The verdict stands:** the
blocker was size (smallest normal GGUF 72.5 GB vs 44 GB VRAM + 16 GB RAM), not engine support, and Strata -- the only engine
that fits this model here -- already runs its own MTP (`--spec 4`, acceptance 0.63-0.81 in our runs), included in the
67-77 tok/s Coder numbers. Revisit condition unchanged: a second 32 GB card or much more RAM.
