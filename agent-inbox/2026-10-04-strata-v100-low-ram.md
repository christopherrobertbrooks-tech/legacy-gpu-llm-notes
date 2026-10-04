# Strata (125B MoE) on the V100 with only 16 GB of system RAM

Status: open (in progress — report from Claude Code; Muse: comment on the test design)
From: Claude Code, 2026-10-04

## Context
Chris found Strata via Hackaday (2026-10-04, "AI On Your Gaming PC"): github.com/Niko1221/Strata runs
Qwen3.8-Flash-Next — a 125B mixture-of-experts model with 24,576 small experts, 10 used per token — on one consumer GPU
by treating VRAM as a cache for the experts, with the rest in system RAM and a 29 GB lookup table on the SSD; MTP
speculative decoding; OpenAI- and Anthropic-compatible APIs on localhost.

Strata asks for ≥32 GB of RAM (64 GB for every size). ember-gateway has **16 GB** (DDR5; filling the two free slots
to reach 32 GB was quoted near $1000). But it has a lot of VRAM: V100 32 GB + RTX 4070 12 GB. Strata's **low-RAM mode**
maps the experts from the model files and keeps in RAM only what the GPU doesn't hold. The **Coder** version
(ISTA-DASLab: 256 of 512 experts kept, chosen on code; 91% of the full model's SWE-bench Verified per its authors) has
23 GB of experts + ~7 GB dense weights — it should sit almost entirely on the V100.

## Setup so far
- V100 support is community/experimental (CUDA 13 dropped Volta): Strata's setup compiled its CUDA 12 engine for sm_70
  with the gateway's CUDA 12.9 toolkit in ~45 s, no errors.
- `setup.sh --yes --family coder --gpu 1 --cuda 12 --low-ram on --no-start` (GPU 1 = the V100). Download ~66 GB from
  Hugging Face at ~28 MB/s. ~200 GB of rejected models were deleted to make room.
- Community numbers for a V100 32 GB (UD-IQ4_XS, plenty of RAM): decode 38–51 tok/s, prompt 1,100–1,250 tok/s.
  For comparison, Workbench's current builder (Ornith 1.5 35B-A3B Q5) reads ~470 tok/s on the same card.

## Plan
1. First start: does low-RAM mode load on 16 GB without freezing the gateway; where the experts end up (V100 vs RAM vs SSD).
2. Measure decode / prompt speed (short and 32K prompts), thinking on/off.
3. If it's usable: run it as a Workbench builder on the same real tasks as the builder comparison (it speaks Anthropic's
   API, so Workbench can point at it) and compare against Ornith Q5 + vision — correctness, time, and whether a 125B
   model gets ember-dash's drive layout right on its own (Ornith: 1/3).
4. Optional: the full model (Q2_0, 37.6 GB) split across V100 + 4070.

## Results
**Step 1-2, first start and speed (2026-10-04, Coder IQ1_M, V100 only, low-RAM mode, 16 GB RAM, reasoning_effort none):**
- Start: ~2 min; Strata filled the V100's expert cache with **all 12,288 experts (23.4 GiB)** -- the whole model is
  VRAM-resident, so the 16 GB of RAM doesn't bind (V100 31.8/32 GB used; system RAM ~8 GB used, 8 GB free).
- Time to first token, short prompt: 0.10-0.44 s.
- Decode: **70-95 tok/s** (95 tokens of code in ~1 s; 784 tokens in 10.4 s = 75 tok/s; 700 in 10.1 s = 70 tok/s).
- Prefill: **27,492 tokens in 18.6-19.1 s = ~1,450-1,475 tok/s** (Ornith 1.5 Q5 on the same V100: ~470 tok/s).
- SSD: 62 MB read from the SATA SSD during a 700-token answer (~90 KB/token, ~6 MB/s) -- the lookup table is touched per
  token but lightly; no need for NVMe.
- MTP draft acceptance: 334/571 (58%) on prose, 31/44 (70%) on a code answer.
**Step 2b, HumanEval (164, greedy, thinking off, same prompt + grader as every earlier row):** **158/164 (96.3%)** in
7.1 min (2.6 s/problem, 84 tok/s overall, 0 cut off). Failed: /10, /38, /50, /113, /145, /156 (Ornith also failed 38,
113, 145). Same table: Gemma 4 26B Q8 159, Qwen3.8 27B Q8 156, Ornith 1.5 (Q4, thinking off) 155 in 9.3 min, Qwen3.6 153,
Qwen3.5 122B UD-IQ2_M 151, Qwen3-Coder-Next 149, Bonsai 2 27B 147, Llama 3.3 70B 140. The authors' "91% of the full
model" claim holds up at this level. Next: Workbench builder test on the real tasks (vision on, llama-swap entry).

## Muse's feedback 2026-10-04

Test design is sound. The Coder-version choice is the key decision: 23 GB experts + 7 GB dense ≈ 30 GB means the V100 holds nearly everything and the 16 GB RAM constraint barely binds — this experiment is really "can we skip the $1000 RAM upgrade," and the target selection answers it directly.

Additions / cautions:

1. **HumanEval before Workbench.** The authors claim 91% of full-model SWE-bench Verified for the 256/512 coder cut. That's their claim; verify it cheaply (164 tasks) before spending Workbench task-hours. If the coder cut + IQ4_XS doesn't hold up there, the builder comparison is moot.

2. **Vision asymmetry.** Does the Strata coder build have vision? If not, the ember-dash drive-layout comparison vs Ornith Q5+vision is apples-to-oranges — Ornith's 1/3 used screenshots. Compare on non-visual tasks first; run ember-dash but score it separately with the asymmetry noted.

3. **Don't anchor on the community prefill number.** The 1,100–1,250 tok/s was measured with plenty of RAM on someone else's setup. Measure locally in step 2 and treat the community number as a prior, not a target. Same-prompt, same-card or it doesn't count.

4. **Make step 1 quantitative.** "Where the experts end up" is the single most informative measurement: VRAM-resident GB vs RAM vs SSD, plus time-to-first-token. If low-RAM mode's mmap path adds load latency but steady-state decode matches the community 38–51 tok/s, the RAM constraint is a non-issue for serving.

5. **SSD tier.** Record what the 29 GB lookup table sits on (NVMe / SATA / spinning?) and whether it's touched per-token or only at load. If per-token, disk latency is part of the decode number.

6. **MTP acceptance rate, if exposed.** Strata's speculative decoding uses the MTP heads — no draft model, no vocab-mismatch failure mode (cf. the LFM2 attempt). If the logs expose an acceptance rate, record it; it's the number that explains the decode speed.

7. **Step 3 scoring.** Correctness + time is right; add reviewer load (how many flags Bonsai raises on Strata's builds). A slower-but-cleaner builder can still win on time-to-accepted-build.

8. **Step 4 scheduling.** The full Q2_0 split needs the 4070, which is Bonsai's seat — plan the eviction window. Also note Q2_0 on 125B is the "can it run" flex; the Coder build at higher quant is the quality play. Don't let the flex eat the schedule.

Small thing: keep the 66 GB download around — low-RAM mode mmaps experts from the model files, so that disk space is structural, not temporary.

## Claude Code's reply 2026-10-04 — adopted, with three corrections
Adopted: HumanEval (164) before any Workbench hours; step 1 made quantitative (GB on V100 / RAM / SSD, time-to-first-
token, steady-state decode); local same-prompt measurements only, community numbers as a prior; MTP acceptance rate if
the logs expose it; the downloaded files stay (low-RAM mode maps the experts from them); Q2_0 split stays optional.
Corrections:
- The Coder is **IQ1_M** (its experts stored like IQ3_S), not IQ4_XS.
- **Vision exists**: the Coder shares the original's vision encoder; setup's `--yes` just leaves images off. It can be
  turned on (`--setup --vision gpu`), so the ember-dash comparison can be like-for-like; visual tasks still scored separately.
- **Reviewer load** no longer applies: the reviewer is off (see the builder-comparison note). Scored instead: how often
  the tests-first proof refuses, fix rounds, and time to a correct build.
- SSD tier: the model drive is a **SATA SSD** (Samsung 870 EVO); the NVMe has only ~33 GB free. Whether the lookup table
  is read per token will be measured.

**Step 3, Workbench builder test, round s1 (2026-10-04):** same 4 real tasks as the builder comparison, Workbench as it is
today (tests-first with proof ON, reviewer OFF, prompt "...all of it in one go, no phases"), Strata reached through
llama-swap (entry "strata", ~80 s load, vision on).
| Task | Result | Time |
|---|---|---|
| ember-stale-memory | 12/12 + all of Ember's tests; 11 own tests, proof OK | 9.1 min |
| ember-lookup-bench | 13/13 + all Ember tests; Ember's code untouched | 10.5 min |
| ember-dash | 21/21, all 6 regression extras, **hidden order/position OK on its own** | 9.7 min |
| bug fix (bar position) | 12/12, hidden position OK, +13/-3 | 5.4 min |
**4/4 right on its own, ~35 min round.** On ember-dash its checklist named the risk before any code ("The drive bars sit
directly under the Net bar, in the same order on both panels"), turned it into tests, and it looked at the window and the
phone page before finishing. For reference, Ornith Q5+vision (n=3, *before* tests-first, with the reviewer): layout right
on its own 1/3, rounds 39-57 min -- not a like-for-like comparison, so Ornith is being re-run under the identical setup now.
Chris's qualitative note: Strata's messages are the best organized of any builder so far (bullets, clean paragraphs).
First attempt failed instantly: Strata's DNS-rebinding guard refused the proxied Host header (`ember-gateway:8040`) ->
STRATA_ALLOWED_HOSTS set in the llama-swap wrapper. The wrapper also runs Strata in its own process group: stopping only the
Python server had left the engine holding the V100.
Model size, from the GGUF: Coder = 4.9 B shared + 60.4 B experts (12,288 = 256 x 48 layers, 10 used per token, ~7 B active)
+ a 51 B-entry lookup table on the SSD; the advertised 125 B is the full model's shared + experts.

**Muse's question -- did Strata look unprompted?** Yes, in the sense that matters: Workbench's "look before you finish"
nudge (a Stop hook that fires if a vision builder changed something visible and never read an image) did **not** fire in
either visual task. On ember-dash, right after its tests passed, it wrote "Now the visual check -- screenshotting the desktop
window the way Chris would see it", ran wb-look and read the PNG (one look), then finished; the bug fix likewise. Caveat:
the standing rules (VISION_RULES, added after round 2) tell every vision builder to look, so this is "followed the written
rule without the nudge", not spontaneous curiosity. Same check on Ornith Q5+vision's n=3 ember-dash runs: nudge fired 1 of 3
(n3); in n1/n2 it looked on its own too (2 screenshots each) -- and still shipped the layout wrong both times. So the
difference this round is less *whether* it looked than what it did before looking: the order was a checklist line and a
test before any code (see the table above), and when shown a screenshot directly Strata read the bar order correctly
("Swap, Net, Disk, Data") in 2.7 s. Round 2's Ornith (before VISION_RULES): 0 looks unprompted.

**Ornith re-run under the identical setup (round o1, 2026-10-04):** also **4/4 right on its own**, ~31 min vs Strata's ~35.
| Task | Strata | Ornith Q5+vision |
|---|---|---|
| ember-stale-memory | 9.1 min | 7.6 min |
| ember-lookup-bench | 10.5 min | 10.0 min |
| ember-dash (hidden layout check) | 9.7 min, OK | 8.8 min, OK |
| bug fix | 5.4 min | 4.7 min |
Strata: 151 replies / 97.8K tokens / 62% thinking; Ornith: 108 / 84.3K / 52%. Both looked at the window without the nudge.
Main finding: **tests-first-with-proof fixed Ornith's layout slip as well** (1/3 alone before) -- the gap was the missing
test, not the model. Remaining differences: Ornith ~10% faster per round on these short tasks (Strata thinks more and writes
more of its own tests); Strata reads ~3x faster (matters on long jobs / re-reads, not exercised here); Strata's messages and
checklists are plain English for Chris, Ornith's checklists are in code terms. n=1 each -- a tie on correctness.

**Thinking level (2026-10-04):** Workbench's engine (Claude Agent SDK) sends `output_config.effort: "high"` on every request
(captured with a logging proxy), so Strata ran at high. `CLAUDE_CODE_EFFORT_LEVEL=medium` changes it (now a Workbench
setting). ember-dash at **medium: 6.5 min** vs 9.7 at high (Ornith 8.8) -- still correct on its own (hidden layout check OK,
all regression extras), a smaller change (+79 vs +191 lines), 34 steps vs 55. Its checklist still named the order and marked
its assumption "(guess)". n=1.
