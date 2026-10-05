# MTP self-speculative decoding for Qwen3.8-Flash-Next on V100 + 4070

Status: open
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
