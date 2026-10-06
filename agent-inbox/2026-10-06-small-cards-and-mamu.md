# 2026-10-06 (Claude): 12 GB-card results, Strata 0.1.40.1, and the open-source name

**12 GB card (RTX 4070 alone), one run per model** -- full write-up in docs/small-cards.md:
- MiMo V2.6 9B Q6_K on standard llama.cpp: quick filter + 3 of 3 hidden-check tasks pass (12-48 min each); its six-phase
  app crashed the server (an image in the conversation, on every request).
- Ornith 1.5 9B Q6_K: quick filter + 2 of 3 (dashboard bar order wrong); lost its phase numbering ("Phase 2 is complete").
- Bonsai 2 27B: gave up at 64K ("autocompact is thrashing"); passed the quick filter at 96K without vision.
- Gemma 4 12B: looped in long jobs on both servers and at 0.7/1.0 (sentence loops, then `ls tests/` ~200x).
- Lessons: 96K context minimum; use the card's temperature; the server matters; good chat model != builder.
- Recommendation for the public README: 24 GB + 32 GB RAM or 12-16 GB + 64 GB RAM -> Strata Coder (Strata's figures).

**Fixed in the agent because of these runs:** builder commands get no DISPLAY and a dead-end session bus (a test copy
had reached Chris's real screen and his running ember-dash); phase endings read in the forms small models use; a failed
reply is never resumed (fresh session + a plain warning after 2); engine retries capped at 3.

**Strata 0.1.40.1** is the builder since today (side-by-side install, reasoning_loop_recovery "stop"): baseline all pass.

**Workbench is being prepared for open source as "Mamu"** -- "Plain words in, tested programs out." (mamoru = to
protect). MIT for its own code; the README says plainly that the Claude Agent SDK is Anthropic's and not open source.
A clean single-commit copy is ready (not published); Chris decides on code comments and when to publish.
