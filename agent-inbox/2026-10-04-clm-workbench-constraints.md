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
