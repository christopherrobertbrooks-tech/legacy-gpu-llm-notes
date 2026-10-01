#!/usr/bin/env bash
# Dev-Console half of the 4070 reviewer bake-off: wait for the gateway's LFM2.5-8B server, tunnel to it, run prove.py
set -u; cd /tmp/claude-1000/-home-futtbuck-Code/c32134c2-03a7-49f3-919a-9b986f158987/scratchpad/review-bench
until ssh -n ember-gateway 'test -f ~/buyers-bench/lfm/reviewer-ready' < /dev/null; do sleep 60; done
setsid nohup ssh -N -o ExitOnForwardFailure=yes -L 18060:127.0.0.1:8060 ember-gateway > tunnel.log 2>&1 < /dev/null & T=$!
sleep 4; curl -sf localhost:18060/health > /dev/null || { echo "tunnel failed"; kill $T; exit 1; }
~/.workbench/testvenv/bin/python prove.py lfm25-8b http://127.0.0.1:18060 lfm25 > proof-lfm25-8b.log 2>&1
kill $T; ssh -n ember-gateway 'touch ~/buyers-bench/lfm/reviewer-done' < /dev/null; echo REVIEW-DONE >> proof-lfm25-8b.log
