// SWE-bench runner: each task's bug report goes to a local model through the SAME engine as Workbench
// (Claude Agent SDK, claude_code preset, llama-swap on :8040). Web search/fetch are off -- no looking up the
// real fix. The model edits the project on this machine; python/tests run inside the task's container via
// `tx`. The final change is saved as a patch for the official grader (swebench.harness.run_evaluation).
//   node run_agent.mjs <label> <llama-swap model name> [minutes per task, default 30]
import { query } from "@anthropic-ai/claude-agent-sdk";
import { execFileSync } from "node:child_process";
import fs from "node:fs"; import path from "node:path"; import os from "node:os";

const [label, model, mins = "30"] = process.argv.slice(2);
const HERE = path.dirname(new URL(import.meta.url).pathname);
const tasks = JSON.parse(fs.readFileSync(path.join(HERE, "tasks.json"), "utf8"))
  .filter((t) => !process.env.SWE_ONLY || process.env.SWE_ONLY.split(",").includes(t.instance_id));   // SWE_ONLY=id,id for a trial
const predsFile = path.join(HERE, `preds-${label}.jsonl`);
const done = new Set(fs.existsSync(predsFile) ? fs.readFileSync(predsFile, "utf8").split("\n").filter(Boolean).map((l) => JSON.parse(l).instance_id) : []);
const dk = (args, opts = {}) => execFileSync("bash", ["-c", "docker " + args], { encoding: "utf8", maxBuffer: 256 << 20, ...opts }).trim();
const sh = (cmd, cwd) => execFileSync("bash", ["-c", cmd], { cwd, encoding: "utf8", maxBuffer: 256 << 20 }).trim();
const log = (s) => { const line = `${new Date().toISOString().slice(11, 19)} ${s}`; console.log(line); fs.appendFileSync(path.join(HERE, `run-${label}.log`), line + "\n"); };

const RULES = `
YOU ARE FIXING A REAL BUG REPORT in the repository in your working directory. Nobody will answer questions -- work on your own until it's fixed.
- Python, pytest and anything that needs the project's installed dependencies must be run with the \`tx\` command, e.g.
  \`tx python reproduce_bug.py\` or \`tx python -m pytest tests/some_test.py -x -q\`. It runs inside the project's own
  environment. Plain \`python\` on this machine does NOT have the project's dependencies.
- Steps: read the issue; find the relevant source code; write a small script that reproduces the bug and run it with tx;
  fix the SOURCE code (make the smallest change that fixes it properly); run your reproduction again and the existing
  tests closest to the code you changed; then stop and summarise what you changed.
- Do not modify or delete existing tests. Do not install packages. No internet access.`;

for (const t of tasks) {
  if (done.has(t.instance_id)) continue;
  const id = t.instance_id, ct = `swe-${label}-${id}`.replace(/[^a-zA-Z0-9_.-]/g, "_");
  const work = path.join(HERE, "work", label, id);
  const t0 = Date.now(); let turns = 0, err = "";
  try {
    log(`${id}: pulling ${t.image}`); dk(`pull -q ${t.image}`);
    fs.rmSync(work, { recursive: true, force: true }); fs.mkdirSync(path.dirname(work), { recursive: true });
    dk(`create --name ${ct}-src ${t.image}`); dk(`cp ${ct}-src:/testbed ${work}`); dk(`rm ${ct}-src`);
    dk(`run -d --network none --name ${ct} -v ${work}:/testbed ${t.image} sleep infinity`);
    sh("git config --global --add safe.directory '*' 2>/dev/null; true", work);
    const preUntracked = new Set(sh("git status --porcelain --untracked-files=all | sed -n 's/^?? //p'", work).split("\n").filter(Boolean));
    const abort = new AbortController(); const timer = setTimeout(() => abort.abort(), Number(mins) * 60000);
    const env = { ...process.env, PATH: `${path.join(HERE, "bin")}:${path.join(HERE, "node", "bin")}:${process.env.PATH}`, SWE_CT: ct,
      CLAUDE_CONFIG_DIR: path.join(HERE, "claude-config"), ANTHROPIC_BASE_URL: "http://127.0.0.1:8040", ANTHROPIC_AUTH_TOKEN: "local",
      ANTHROPIC_MODEL: model, ANTHROPIC_DEFAULT_HAIKU_MODEL: model, ANTHROPIC_DEFAULT_SONNET_MODEL: model, ANTHROPIC_DEFAULT_OPUS_MODEL: model,
      CLAUDE_CODE_MAX_CONTEXT_TOKENS: "131072", DISABLE_TELEMETRY: "1", DISABLE_ERROR_REPORTING: "1" };
    try {
      for await (const m of query({ prompt: `Fix this issue in the repository:\n\n${t.problem_statement}`, options: {
          cwd: work, env, model, abortController: abort, permissionMode: "bypassPermissions", settingSources: [], maxTurns: 100,
          disallowedTools: ["WebSearch", "WebFetch"], systemPrompt: { type: "preset", preset: "claude_code", append: RULES + (process.env.SWE_SYSTEM_EXTRA ? "\n" + process.env.SWE_SYSTEM_EXTRA : "") } } })) {   // SWE_SYSTEM_EXTRA: model-specific line, e.g. Muse Glimmer's "Reasoning strength: high"
        if (m.type === "assistant") turns++;
        if (m.type === "result" && m.subtype !== "success") err = m.subtype;
      }
    } catch (e) { err = abort.signal.aborted ? "timeout" : String(e.message || e).slice(0, 200); }
    clearTimeout(timer);
    // the model's change: tracked edits + files it created, minus files that were already untracked.
    // First hand the files back: git run INSIDE the container (as root) left root-owned objects in .git and
    // `git add` failed -- Ornith's django-13794 was lost that way (2026-09-30).
    try { dk(`exec ${ct} chown -R ${process.getuid()}:${process.getgid()} /testbed`); } catch {}
    sh("git add -A", work);
    // leave out: files that were already untracked, and NEW files at the top of the repo -- that's where scratch
    // files go (the trial left reproduce_issue.py and a dummy_file.txt with a stray byte); real fixes live in the source tree
    // ...and new files in a new top-level FOLDER (gemma built docs into repro/_build: a 32,791-line "fix", 2026-09-30),
    // and build output anywhere. A new file is kept only inside a folder the project already had.
    const topLevel = new Set(sh("git ls-tree --name-only HEAD", work).split("\n"));
    const JUNK = /(^|\/)(_build|build|dist|__pycache__|\.pytest_cache|[^/]+\.egg-info)\/|\.pyc$/;
    const fresh = sh("git diff --cached --name-only --diff-filter=A HEAD", work).split("\n").filter((f) => f &&
      (preUntracked.has(f) || !f.includes("/") || !topLevel.has(f.split("/")[0]) || JUNK.test(f)));
    for (const f of fresh) sh(`git reset -q -- ${JSON.stringify(f)}`, work);
    const patch = execFileSync("git", ["diff", "--cached", "HEAD"], { cwd: work, encoding: "utf8", maxBuffer: 256 << 20 });
    sh("git reset -q", work);
    fs.appendFileSync(predsFile, JSON.stringify({ instance_id: id, model_name_or_path: label, model_patch: patch,
      secs: Math.round((Date.now() - t0) / 1000), turns, error: err }) + "\n");
    log(`${id}: done in ${Math.round((Date.now() - t0) / 60000)} min, ${turns} turns, patch ${patch.split("\n").length} lines${err ? ", " + err : ""}`);
  } catch (e) { log(`${id}: SETUP FAILED ${String(e.message || e).slice(0, 300)}`); }
  finally {
    try { dk(`rm -f ${ct}`); } catch {}
    // the container wrote root-owned files into the work copy; clear it from inside a container
    try { dk(`run --rm -v ${path.dirname(work)}:/w alpine rm -rf /w/${id}`); } catch {}
  }
}
log("ALL TASKS DONE");
