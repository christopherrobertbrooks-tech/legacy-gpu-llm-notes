
## Update 2026-10-04 (Claude): first A/B of "working notes + fresh session per phase"

Built in Workbench Lab: at a mid-plan phase end the builder must update WORKBENCH-NOTES.md (Done / Decisions / Open
problems / Next; enforced by a Stop hook outside the model's reach); the next phase starts a new engine session from
Chris's request + the plan + the notes. Same 4-phase web app, Strata Coder, one run each:

- **Notes + fresh:** 25.2 min, prompt flat at 56-66K, no compaction, 30 tests pass, works fully when used in a browser.
- **Resume (today):** 22.6 min, prompt grew to 89K and **auto-compacted** in phase 3, 36 tests pass, but **the page is
  broken** (refresh expects an `ok` field the list endpoint never sends; nothing updates without a reload).
- Resume is faster on a short project (cached prompt vs ~40 s re-read per fresh phase). n=1, and both runs lacked a
  working browser check (a Lab port bug, now fixed), so the broken page can't be pinned on compaction yet.
- Next: rerun both with the port fix, ideally a longer (5-6 phase) project where resume would compact more than once.

## Update 2026-10-04 (Claude): round 2, 6-phase project

- **Notes + fresh:** all 6 phases in 22 min, prompt 43-74K, no compaction, 82 tests, every feature works by hand.
- **Resume:** compacted 3 times and **died in phase 5**: Claude Code asks for 32K of answer room, Strata refuses
  prompt + answer room > 131K, so past ~99.5K every request -- compaction included -- was refused. With 20K answer room
  (CLAUDE_CODE_MAX_OUTPUT_TOKENS=20000; thinking is capped at 8K) the same dead session compacted and finished. Its app
  works too (57 tests). Roughly half the time of resume for the notes version on this project.
- Takeaway: on multi-phase work the notes + fresh session design is faster AND removes a failure mode; the answer-room
  fix is needed regardless (any long chat can hit it).
