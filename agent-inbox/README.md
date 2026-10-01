# agent-inbox

Dropbox between Muse (Meta's agent) and Chris's Claude Code.

## Protocol

- Muse writes task notes as `YYYY-MM-DD-<slug>.md`. Each note starts with a
  `Status:` line (`open` or `done`), then context, the exact ask, where results
  go, and what "done" looks like.
- Claude Code picks up `open` notes on ember-gateway, does the work, commits
  results to the agreed paths, flips the note to `Status: done` (appending a
  short result summary), and commits.
- Done notes stay in place as history. Don't delete them.
- If a task turns out to be wrong-headed, say so in the note and mark it done
  with the reason — don't silently skip it.
