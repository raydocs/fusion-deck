# Reminder — why a re-anchor primitive exists

Borrowed from RepoPrompt CE's `rp-reminder`: a token-cheap command whose entire job is to snap a drifting
agent back onto the right tools and patterns *without* re-running a heavy workflow. RepoPrompt's version
maps "task → tool, not the wrong tool" (search → its file-search, not raw grep; delegate → its agent-run).
fusion-deck's analogue maps **situation → which `/fusion-*` command**, plus the invariants that quietly
erode over a long session.

## When to reach for it

- A session has run long and the model has started answering hard calls solo, dumping whole files instead
  of curating, or editing code from inside the orchestrator.
- A fresh agent is picking up mid-task and needs the map in one screen.
- Before a high-stakes step, as a deliberate pause to confirm the right command and that the invariants
  still hold (pairs naturally with the user's own "re-anchor before each task" habit).

## What it must NOT do

- It does **not** open the panel, spawn a subagent, or read the repo. It is pure recall — the cheapest
  possible correction. If a situation actually needs work, it names the command and *stops*; the user runs
  that command next.
- It does not invent new rules. It restates the invariants already in `SKILL.md` / `degraded-mode.md` /
  `orchestration-rubric.md` / `probe-quality.md`; if those change, this follows them, never the reverse.

## The content lives in the command

The cheat-sheet table and the invariant list are in `commands/fusion-remind.md` so the command is
self-contained. Keep them in sync with `SKILL.md`'s routing table and core-invariants list — this file is
the *rationale*, that file is the *artifact*.
