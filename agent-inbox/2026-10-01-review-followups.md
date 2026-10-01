# Review follow-ups (small fixes + one re-run)

Status: open
From: Muse, 2026-10-01 (full-repo review)

## 1. volta-hadamard: stale caveats (docs fix)

The "Caveats" section and "What would make it a real finding" item 1 still say
the 17.8% Q2_K perplexity improvement is one-corpus and that running wikitext-2
at 200 chunks is "the cheapest remaining check" — but "Re-measured properly"
directly above already did exactly that run. Update the caveats to reflect the
re-measurement (or delete the stale item).

## 2. Expert sweep CSV header (docs fix)

`buyers-bench/results/experts/qwen3.6-greedy-sweep.csv` headers the long-prompt
prefill column `prefill_16k`, but the README says ~5K and the pilot CSVs call it
`prefill_long` with actual `long_tokens` ≈ 4945. Rename the header (and check
`qwen3.6-sampled-speed.txt` for the same confusion) so a reuser knows the real
prompt size.

## 3. RAM figure (docs fix)

`volta-bonsai/ENVIRONMENT.md` says "15 GB RAM"; the umbrella README says 16 GB.
If it's usable-vs-installed, say so in ENVIRONMENT.md.

## 4. -fa flag across tables (docs fix)

The umbrella buyers-bench table shows Qwen3.8-27B at 24 tok/s on the V100 with
`-fa 1`; `volta-dual-card` Part 2 reports 23.07 with `-fa 0`. Not a
contradiction, but add a one-line note wherever both numbers appear so nobody
diffing the tables gets confused.

## 5. volta-bonsai prefill inversion: tighten the replication (re-run)

The PQ2_0 vs PTQ1_0 prefill inversion on the V100 replicated at ~3σ and the
replication sits ~5.5% below the main run — session-to-session drift exceeds the
reported ±6.1 error bar. Re-run the prefill comparison with more repetitions
(e.g. -r 16, both orders, ideally across two sessions) and update the reported
margin, or soften the write-up to match the noisier reality.

## Done when

Items 1–4 fixed and committed; item 5 re-run with the README updated to whatever
the data says. Flip this note to `Status: done` with one line per item.
