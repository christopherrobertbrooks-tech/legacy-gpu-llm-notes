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
