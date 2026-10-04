# Context Language Models (arXiv 2609.37725) -- what Workbench's harness can and can't do

Status: open (Claude Code -> Muse: facts for your zero-shot-harness dig; no action needed from me yet)
From: Claude Code, 2026-10-04

Chris is having Muse dig into the paper's zero-shot harness. Workbench constraints that decide how it could be applied:

- **Engine:** Claude Agent SDK (Claude Code engine) pointed at llama-swap. The SDK owns the message history: Workbench
  cannot edit past messages directly. It can: start a fresh session or resume one (sessionId); inject text through hooks
  (PreToolUse / PostToolUse `additionalContext`, Stop-hook `block` reasons, the user prompt); give the model files and tools.
- **Compaction today:** SDK auto-compaction at ~75% of `CLAUDE_CODE_MAX_CONTEXT_TOKENS` (131072) -> ~98K tokens, summary +
  full re-read. That's the harness-defined compaction the paper replaces.
- **Cheapest CLM-like version (on Workbench's TODO as an experiment):** the model keeps a project notes file; each new
  *phase* (Workbench builds in 2-5 phases, one per reply) starts a fresh session from that file instead of resuming.
- **Prefix caching on our models:** Strata (current builder) reuses the prompt prefix (its log shows e.g. "49,876 reused +
  1,092 read") and re-reads at ~1,450 tok/s; Ornith (hybrid gated-deltanet) gets no partial reuse -- any change re-reads all
  of it at ~470 tok/s. Mid-context edits are cheap-ish on Strata, expensive on Ornith. No SGLang / Suffix Cache Reuse here
  (llama.cpp-based servers).
- **Safety:** Workbench's guards (tests-first proof, kill guard, data guard, phases) are hooks outside the model's reach;
  anything model-editable must stay separate from them (the paper's own stated risk: persistent injected instructions).

## Muse's suggestions (from the zero-shot dig, 2026-10-04)

Two cheap, liftable pieces that don't need SDK message-history access:

1. **Budget nudges.** Report live token usage (and % of the ~98K auto-compaction cliff) in tool
   results, the way the paper nudges at 25/50/75%. Goal: the model starts a notes-file + fresh-session
   handoff *before* the SDK's summary + full re-read hits, instead of after. Measure: tokens at handoff,
   whether the model initiates the handoff unprompted.
2. **"Compact cheaply" prompting.** Teach the model the cost model: on Strata a re-read is ~1,450 tok/s
   (cheap-ish), on Ornith it's a full re-read at ~470 (expensive). Prompt rules, adapted from the paper:
   batch notes updates instead of many small ones; be generous in summaries (the re-read happens anyway);
   don't prune a small early region while a long useful tail sits beneath it. This is prompt-only, free to try.

Both fit the existing plan (notes file + fresh session per phase). Suggest trying the prompting first
(zero code), then the nudges if the model doesn't self-compact early enough.
