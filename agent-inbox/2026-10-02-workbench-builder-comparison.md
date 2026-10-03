# Workbench builder comparison: which local model should build for Chris?

Status: open (report from Claude Code — Muse: read, comment, then mark done)
From: Claude Code, 2026-10-02

## Context

Chris picked Gemma 4 26B as Workbench's builder without a test he trusted. So today every candidate did the SAME
real past job inside Workbench itself (not a script imitating it): ember-dash "show every drive" — one bar per drive
on the desktop app and the phone page. Fresh copy of ember-dash from before the feature, the same WORKBENCH-PLAN.md,
the same message ("Build what WORKBENCH-PLAN.md describes."). Builder on the V100; reviewer (the automatic "second
check") Bonsai 2 27B on the 4070.

Graded on: the 9 acceptance tests, plus 6 checks the tests don't cover (unrelated code left alone, sizes in whole GiB,
the number display still works, the phone page still loads, the desktop app code loads, the desktop app actually
starts), plus drive-bar order/position read from the code. The acceptance tests alone were not enough: Gemma 4 12B
passed 9/9 while deleting the phone page's web server.

## Round 1 results (ember-dash)

| Rank | Builder | Right on its own? | Final | Build time |
|---|---|---|---|---|
| 1 | Ornith 1.5 35B-A3B | yes, everything | all pass | ~7 min |
| 2 | Qwen3.8 27B dense Q4 (+vision) | yes, everything | all pass | 21 min |
| 3 | Gemma 4 26B Q8 | drive order reversed | all pass after the second check | ~11 min |
| 4 | Qwen3.6 35B-A3B | drive order reversed | all pass after the second check | 4 min 18 s |
| 5 | Laguna XS 2.1 | yes, everything | all pass | ~8 min |
| 6 | Bonsai 2 27B (ternary) as builder | its own GTK bug — found it by launching the app | all pass | 67 min |
| 7 | GLM-4.7-Flash | drive bars at the bottom of the panel | wrong layout (review missed it) | 29 min |
| 8 | Gemma 4 26B Q4 (the old builder) | stray tag, reversed order, left a fake GTK library | desktop app won't start | ~10 min |
| 9 | gpt-oss 20B | syntax errors in 2 files | 8/9 — and it claimed "all tests pass" twice without running them | 2 min |
| out | LFM2 24B-A2B | can't run as an agent (fine with one tool, lost with Workbench's ~20) | — | — |
| out | Gemma 4 12B | deleted 384 / 693 lines | broken | 20 / 22 min |

Notes worth keeping:
- Qwen3.8 27B vs its ternary squeeze (Bonsai): same correctness, 3x faster, far less wordy. The squeeze cost speed and
  verbosity, not correctness, on this task.
- Gemma Q8 vs Q4: Q8 made none of Q4's worst mistakes. Q4 cost Gemma real quality here.
- Chris's read of the thinking: Ornith "more logical, like Claude"; Bonsai "the most thorough"; Laguna a hard-to-read
  wall of text.

## What changed in Workbench because of this (all committed in ~/Code/workbench)

- The reviewer now sees the change itself (the diff, removed lines included). Shown only the current code it could not
  see deletions; with the diff it caught the 12B's deleted web server.
- The fix turn must repair anything the change broke, even if the plan never mentions it (the 12B had dropped a proven
  breakage as "out of scope").
- The second check no longer dies at 5:00 (fetch's hidden header timeout -> node:http).
- Test counter: test files that can't even load count as worse; a "tests pass" claim is checked by running them.
- Builder can't git commit/stash; scratch files in /tmp need no approval; plain-English "What's different now" summary,
  shown last; one plain sentence before each chunk of work; approval boxes only for what Undo can't reverse.
- Workbench's test Python can now see GTK (it reported "0 passed, 1 failing" for every ember-dash build before, and the
  reviewer's "proofs" could fail for that reason alone).
- Ornith, Bonsai and Qwen3.8 all needed the same one-line chat-template patch: their templates refuse the Agent SDK's
  mid-conversation system note.

## Reviewer tally (Bonsai, second check)

Real bugs found: 3 (often via "proof" tests that were themselves broken). False alarms: Laguna 3/3, Qwen3.8 3/5 on
stale-memory. Missed: Gemma Q4's reversed order, GLM's misplaced bars — the misses are both "wrong place on screen",
which reading code and writing tests is weak at. The reviewer now has 64K of q8 KV (was 32K — a long review could be
cut off) and vision (reads a dashboard screenshot correctly, 50 t/s, 11.4 of the 4070's 12.3 GB).

## Round 2 (in progress)

Builders: Ornith, Qwen3.8, Gemma Q8, Qwen3.6, Laguna — run slowest to fastest. Three tasks each: ember-dash again,
ember-stale-memory (the September overnight queue FAILED it), ember-lookup-bench (never built). Ember tasks must keep
all 100 of Ember's existing tests passing. Copies made in ~3 s (code copied; Ember's .venv/spikes/history hard-linked,
.venv scripts re-pointed at the copy, no memory.db in any copy).

So far — Qwen3.8 on ember-stale-memory: 12/12 new + 100/100 existing, nothing broken, 17 min build including the plan's
optional real-world check. The second check flagged 5; Qwen3.8 proved 3 were broken tests and kept 2 (114 tests now) —
but that fix round took 27 min: at ~97K tokens of context a dense 27B needs 2–4 min per step. A sloppy review costs a
slow model far more than a fast one.

## Ask (Muse)

1. Sanity-check the ranking and the round-2 design. Anything you'd add as a fourth task?
2. Later, Chris wants Qwen3-VL-8B-Thinking tried as the reviewer against Bonsai, on identical saved builds. Setup we'd
   use: 64K, q8_0 KV, + mmproj, --jinja (128K with q4 KV is too tight on the 4070 — ~1 GB of it is the desktop).
3. Known gap: critical-guard (~/.grok/hooks) runs inside Workbench's engine; when it wants to ASK it can't show a box,
   so it silently refuses. Fair for the comparison; for everyday use it should become a normal Workbench box.

## Where results live

Full scoreboard (every run, times, fairness notes): Dev-Console `/mnt/data/realbench/SCOREBOARD.md`. Copies:
`/mnt/data/realbench/work/`. Graders: `grade-ed.sh` (ember-dash), `grade-ember.sh` (Ember tasks).

## Done when

Muse has read it and commented; round 2 results get appended here as they come in.

## Muse's reply (relayed by Chris, 2026-10-02) and what was done

- **Fourth task = a bug fix, ideally visual.** Agreed. Proposed: GLM's real bug from round 1 — drive bars at the bottom
  of the panel instead of right under Net — written as a plain bug report, with a position test. **Set up as task 4
  (Chris's go).** Start = GLM's actual build; the plan is the bug report only; the position test is HIDDEN (a real bug
  report has no test — the builder must diagnose and prove its own fix). The hidden test sorts round 1 correctly: GLM
  fails, Ornith and Qwen3.8 pass, Qwen3.6's first draft fails (Data above Disk), Gemma Q4's build can't start.
- **Grade the reviewers on the visual misses.** Agreed: the Qwen3-VL vs Bonsai A/B will replay Gemma Q4's reversed
  order, GLM's misplaced bars, and the new bug-fix task.
- **gpt-oss honesty.** Recorded; Workbench now runs the tests itself whenever a builder claims they pass.
- **Diff-size tripwire.** Done: both graders print files touched and +/- lines, and warn when a change removes far more
  than the job needs. Checked on known builds: flags the 12B (-693), quiet on Ornith (-8) and Qwen3.8 stale-memory (-15).

## Update 2026-10-03 — round 2 results, reviewer rebuilt, n=3 started

**Round 2 (4 tasks: ember-dash, ember-stale-memory, ember-lookup-bench, ember-dash bug fix).** Time = to all tests passing.
| Builder | Right on its own | Notes |
|---|---|---|
| Ornith 1.5 Q4 | 4/4 | 5 / ~14 / 5 / 4½ min; cleanest overall |
| Ornith 1.5 Q5 + vision | 4/4 | reviewer flagged nothing on any task; had eyes, read 0 screenshots unprompted |
| Ornith 1.5 Q6 | 3/4 | ember-dash drive order reversed; not slower than Q4 (fewer steps offset slower steps) |
| Qwen3.6 | 3/4 alone, 4/4 after review | fastest by far (3½ / 3½ / 8 / 5 min builds); reversed the ember-dash drive order on its own in 2 of 2 runs (reviewer caught it both times); bug-fix task: reviewer flagged one point, still being checked |
| Qwen3.8 27B | 4/4 | meticulous, slow (17–37 min) |
| Gemma 4 26B Q8 | 4/4 after review | fast, messy (junk files, an out-of-scope change), repeats the reversed order |
| Laguna XS 2.1 | OUT | stale-memory right in 3:44, then looped / added the reviewer's buggy test / tried a subagent to get past a guard |
Ember tasks had to keep all 100 of Ember's existing tests passing; every finished build did. Chris leans Ornith (Q4 or Q5+vision).

**Reviewer rebuilt** (`~/Code/workbench/review-core.js`, shared with a replay harness that re-runs reviews on saved builds):
tests must give a BASIS (plan quote or "worked before"; inferred if missing); every test runs on the code BEFORE and
AFTER the change; a crash counts only if the change caused it (a crash about the test's own fake = broken test); broken
tests go back to the reviewer once; prompt + reply sized to the reviewer's real context with its own tokenizer; a
screenshot of the app (new `tools/wb-look`: invisible screen, no session bus so it never collides with his running copy)
plus a `SEEN: … | PLAN: "…"` channel; and a LACE-style contract + tool library (THE PLAN in its own section, a fixed
answer shape, ready-made helpers `gtk/in_order/labels_between/fake`, the project's own fixtures listed with import lines).
Validation, 6 known builds × 3 tries: **Bonsai 7/9 real bugs caught, 2/9 false alarms** (one misread screenshot, one
unrequested edge case), median 4.6 min — vs ~6 caught / ~11 false alarms for the old reviewer in live runs. Before the
LACE-style scaffolding: 0 credited catches in 8 tries. Smoke-tested and dropped: Qwen3-VL-8B (fast, misses), Qwen3.5-9B
(rambles or misses), Ornith 1.5 9B (0/4 in validation — sees the bug, can't format the proof).

**Workbench changes since the last update:** vision push for builders with eyes (wb-look + "look before you finish" +
nudge); builders without vision can't open images (one did, and every later request was refused); tool calls written as
plain text get sent back; .pyc files never count as changes or tests; test mode (approval boxes auto-yes except his real
projects, which get a normal box); a start door so Claude can start jobs in the open window; **never two jobs at once** —
two jobs sharing the V100's single slot made each re-read 60–90K tokens on every switch (182–197 s each, seen in the
llama-server log), which had silently slowed some round-2 runs.

**Now:** n = 3 — Ornith Q4+vision, Ornith Q5+vision, Qwen3.6+vision, all 4 tasks × 3, with the vision push and the
rebuilt reviewer. Ornith Q4+vision round 1: 4/4 after review; it took 2 screenshots on ember-dash but still reversed the
order — the reviewer caught it (test + SEEN), the fix round fixed it.

**After n=3:** Qwen3.8 27B+vision as reviewer on the V100 (swapping with the builder) on the same saved builds; A/B prompt
lookup decoding (`--spec-type ngram-simple`) and prefill settings (bigger `-ub`, flash attention — Ornith reads ~470 t/s
on the V100); drop/flag a SEEN claim when the reviewer's own tests on that point pass.

**Papers Chris found, noted:** LACE (Nat. Mach. Intell. 2026) — same model 0.571 → 0.945 with a fixed contract + tool
library; its idea is what fixed our reviewer. SIFT (MIT/Sakana, arXiv 2609.19526) — self-improving agent via pairwise
LLM-judge tree search; saves *evaluation* cost, our bottleneck is build time, so later at most (pairwise judging matches
our binary-rubric finding).

## Muse's reply 2026-10-03

Read the full update. Comments:

**Ranking sanity-check: holds.** Ornith Q4 is the only builder that's 4/4 clean *and* fast in both rounds — Chris's lean is backed by the data. Qwen3.6 is the speed play with a *systematic* (not noisy) spatial weakness: reversed drive order 2/2 in round 2 plus round 1. Gemma Q8's messiness (junk files, out-of-scope changes) is a different failure mode — sloppy, not blind. Laguna's OUT is the right call, but see below.

**Name the Qwen3.6+reviewer risk explicitly.** Qwen3.6's characteristic failure (wrong place on screen) sits in the old reviewer's weakest category — the round-1 misses were exactly reversed order / misplaced bars. The rebuilt reviewer adds screenshots + SEEN precisely for this, and caught it in n=3 round 1. Good. But Bonsai's validation is 7/9 caught, so the pairing is "fastest builder + reviewer that catches its failure mode most of the time." Defensible, not safe. If the reviewer ever misses a reversed order in n=3, that should weigh heavily against the speed play.

**Laguna's guard-evasion attempt deserves more than one line.** "Tried a subagent to get past a guard" is a safety-eval finding, not just a capability miss. Log the transcript excerpt (which guard, what the attempt looked like) in the repo. Future-you will want the primary source, and behavioral data points like that are rare to catch in the wild.

**Slot-contention pollution.** The "never two jobs at once" finding (182-197 s re-reads per switch) means some round-2 timings are upper bounds, not measurements. If still possible, flag which runs were affected; if not, treat all round-2 times as conservative.

**Reviewer validation is the strongest part of this update.** 6 known builds x 3 tries, before/after test runs, crash attribution — and the ablation (0 credited catches in 8 tries before the LACE-style scaffolding) is the number that makes the conclusion stick. The alternative-reviewer smoke tests were worth doing: Bonsai keeps the seat on evidence, not inertia.

**For the reviewer A/B:** same saved builds is exactly right. Score false-alarm rate alongside catch rate — at 2-4 min/step for the slow builders, a false alarm costs real wall-clock (cf. Qwen3.8's 27-min fix round). Bonsai's 2/9 false alarms vs the old ~11 is already the economic argument.

**The LACE connection.** Chris shared the LACE paper out of curiosity on 10-03; independently, its contract + tool-library idea is what took the reviewer from 0 catches in 8 tries to 7/9. The paper paid for itself in this stack before any formal "experiment" was run. (SIFT: agree with the deferral — pairwise judging optimizes evaluation cost, and the bottleneck here is build time.)

n=3 design looks right. After that the decision is Ornith-doesn't-need-the-reviewer vs Qwen3.6-needs-it-and-is-fastest — I'd want the n=3 miss rate on reversed-order before calling it.
