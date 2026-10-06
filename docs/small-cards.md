# A coding agent on a 12 GB card (October 2026)

[← back to the overview](../README.md)

Can someone without a 32 GB card run our local coding agent (Workbench, now named **Mamu**: a desktop app on
Anthropic's Claude Agent SDK with tests-first, phases and working notes) on an ordinary gaming card? We ran the same
real jobs as on the V100 on the **RTX 4070 (12 GB) alone**, with 9-27B models that fit it.

**Short version:** a 12 GB card *can* do real jobs -- MiMo V2.6 9B passed every hidden-check task -- but 1-7x slower than
Strata on the V100, and rougher. For a comfortable experience, Strata's own figures point to a **24 GB card + 32 GB RAM**
(RTX 3090/4090) or a 12-16 GB card with 64 GB RAM, running the Strata Coder.

## The jobs

Four real tasks on two existing projects, each graded by hidden acceptance tests the agent never sees (a bug fix in a
GTK dashboard, two features in a voice assistant's Python code, a dashboard feature), plus a six-phase web app built from
scratch. A **quick filter** first -- the dashboard bug fix, the whole agent flow in one small job -- and the full set only
for models that pass it. One run per model.

## Results (RTX 4070 12 GB, which also drives the display: ~11 GB free)

| Model (file) | Server | Context that fits | Prompt / write tok/s | Quick filter | Full set |
| --- | --- | --- | --- | --- | --- |
| **MiMo V2.6 Distill (Qwen 9B), Q6_K** (7.8 GB + vision) | standard llama.cpp | 128K, 11.6 GB | 3,200 / 55 | pass, 44 min | **3 of 3 pass** (12-48 min each); six-phase app: server crash (below) |
| **Ornith 1.5 9B, Q6_K** (7.6 GB + vision) | Prism llama.cpp fork | 128K, 11.4 GB | 3,000 / 58 | pass, 32 min | **2 of 3** (dashboard bar order wrong); six-phase app lost its phase numbering |
| Bonsai 2 27B ternary, PQ2_0 (7.2 GB), no vision | Prism fork | 96K, 11.7 GB | 1,100 / 45 | pass, 59 min | not run |
| Bonsai 2 27B **with** vision | Prism fork | 64K only | 1,100 / 45 | **engine gave up** (64K too small) | -- |
| Gemma 4 12B QAT Q4_0 | both | 128K, 9.9 GB | 2,500 / 50 | fail, 3 tries (loops) | -- |
| *Strata Coder IQ1_M on the V100, for reference* | *Strata* | *128K* | *1,400 / 70* | *pass, ~6 min* | *all pass, 6-26 min each; six-phase app ~22 min* |

## What we learned

- **Context matters more than the model.** Claude Code's own instructions and tools are ~30K tokens before any work; the
  engine compacts at about context - answer room - 13K. At 64K that leaves almost nothing: Bonsai's run ended with
  "Autocompact is thrashing" on every real task. The same model at 96K passed. **96K is the workable minimum.**
- **Use the model card's temperature.** Ornith 9B at 1.0 instead of its "precise coding" 0.6 found the fix but needed
  204 steps and hit the time limit (75 steps / 32 min at 0.6).
- **The server matters.** MiMo's XML tool calls were parsed into one garbled 77,000-character command by a llama.cpp fork
  and worked on standard llama.cpp (5e03bdd). There, a browser screenshot in the conversation then crashed the server on
  every request.
- **A good chat model isn't automatically a builder.** Gemma 4 12B (excellent at single tool calls in a voice assistant)
  looped in long jobs -- one sentence, then one command (`ls tests/`, ~200 times) -- on both servers and at 0.7 and 1.0.
- **Agents find ways around a blank screenshot.** When the invisible-screen tool returned a blank picture, Ornith started
  the test app on the real desktop and screenshotted it; another test copy reached the user's real running app over the
  desktop message bus. Fixed in the agent: no display or session bus for the builder's commands, and a guard.

## Recommendation

| Your hardware | Builder |
| --- | --- |
| 32 GB card | Strata Coder, all on the card (tested) |
| 24 GB card + 32 GB RAM | Strata Coder (Strata's figures: ~85-99 tok/s on an RTX 3090 -- not tested by us) |
| 12-16 GB card + 64 GB RAM | Strata Coder (Strata: ~55 tok/s on an RTX 5070 -- not tested by us) |
| 12 GB card, little RAM | MiMo 9B or Ornith 9B at 128K -- works, slowly; expect rough edges |

Raw logs: `/mnt/data/notesbench/small/` on the test machine (fit, speed, quick filter, full runs per model).
