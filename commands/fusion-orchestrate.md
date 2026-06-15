---
description: Decompose a task against a Workflow Contract, dispatch scoped Task subagents (sequential by default), verify each against its Done-when before the next, and roll up. The orchestrator plans and verifies but never implements.
argument-hint: [contract path or task] [--panel to cross-check a thorny decomposition]
---

# /fusion-orchestrate

Execute a task by **coordinating scoped subagents**, not by doing the work yourself. You plan, decompose,
dispatch, and verify; the subagents read, reason, and edit. This is where context discipline pays off.

Load `references/orchestration-rubric.md`, `references/subagent-prompt-template.md`, and
`references/verifier-prompt-template.md`.

> **CRITICAL — the orchestrator never implements.** You may use **Read / Grep / Glob** to map the repo and
> to **verify** a subagent's output, and **Bash** only for **verification** (tests, grep) and for editing
> the **plan file**. You may **NOT** use Edit/Write/Bash to change product code. "I'll just fix this one
> line" is a failure — dispatch it. All code changes happen **inside Task subagents**.

## Phase 0 — Verify workspace (required)

Confirm you're operating on the right code: correct repo/branch, the contract's **Current State** matches
what's on disk. If it doesn't, re-anchor (re-read the files) before proceeding — don't trust a stale plan.

## Phase 1 — Contextualize

If given a contract path, read it. If given a raw task, produce a contract first by following the
`/fusion-plan` procedure (read `<skill-root>/commands/fusion-plan.md`) — or ask the user to run
`/fusion-plan` — and don't orchestrate without one. Translate the request into real code nouns with **1–2 navigation calls**;
keep **what exists** separate from **what to do**.

## Phase 2 — Decompose (Gate A)

Write/confirm the plan as a real file (the Workflow Contract; default `docs/plans/<topic>-<DATE>.md`).
Decompose to **natural granularity — 2–3 work items, cap 5**; if reaching for more, combine or raise the
abstraction level. Each item carries `Goal / Done-when / Key files / Dependencies / Size / Status`, and a
**Verifier Plan** entry (the concrete probe). **Gate A:** before dispatching anything, verify the plan and
context are sound (`python3 <skill-root>/scripts/lint_contract.py <plan>` if it's a contract). The plan is
**read-only to subagents**; you own it as a **living checklist**.

`--panel`: if `$ARGUMENTS` contains the literal `--panel` flag — or for a genuinely thorny,
hard-to-reverse decomposition — first run the `/fusion` panel procedure
(`<skill-root>/commands/fusion.md`) on "how should this be broken down?", then write the plan from the
synthesis. Not the default.

## Phase 3 — Dispatch (scoped briefs)

Choose the dispatch mode:
- **Sequential (default):** one item at a time, each a **fresh** Task subagent.
- **Parallel:** only for items touching **independent** files. Every concurrent brief MUST include the
  verbatim **sibling-warning** (see `subagent-prompt-template.md`).
- **Steer-one-agent:** keep one session across items only when items are tightly coupled or there are
  many tiny ones.

**`--worktrees` (optional isolation for parallel dispatch).** If `$ARGUMENTS` contains `--worktrees`, run
each parallel item in its own git worktree so concurrent edits can't collide:
`bash <skill-root>/scripts/fusion_worktree.sh create <item-id>` (it copies `.worktreeinclude`-matched local
files like `.env.local`), dispatch the subagent there, **verify the worktree's diff before merging it
back**, then `… cleanup <item-id>`. Prefer your harness's native worktree isolation if it has one. Default
is **off** — in-place sequential. See `references/worktrees.md`.

Write each brief from `references/subagent-prompt-template.md`: it **orients, not directs** — `Goal`, key
file paths, and **discoveries the agent couldn't find itself**; it scopes explicitly ("Read the plan at
`<path>`; your job is item N; items X,Y are handled separately; do only this; stop when done"); and it
**excludes** CLAUDE.md conventions, step-by-step instructions, readable code, and any user↔orchestrator
chatter (two-conversations firewall). **One level of fan-out:** the brief tells the subagent **not to
spawn its own subagents** — it does the work itself.

**Before** dispatching item N, mark it `[doing]` in the plan. (Status transitions are explicit gates.)

## Phase 4 — Verify, then dispatch fresh (Gate B)

After a subagent returns, **verify against the item's Done-when with the concrete probe** from the
Verifier Plan — a grep / a file read / a single focused test — **not a skim, and never "did you do it?"**.
Catching drift before the next item builds on a flawed foundation is your value as the orchestrator.

- **Pass:** mark the item `[done]` in the plan, then dispatch the next item **fresh** (new Task, not a
  continued chat), referencing the updated plan.
- **Gap:** steer a correction — re-dispatch the same item once with a tightened brief naming exactly
  what's missing. **If it fails a second time, trigger the Escape Hatch: STOP, mark the item
  `[blocked]`/`[incomplete]` (with reason / proof / attempted / impact / next-decision), and surface to
  the user.** Never re-dispatch indefinitely; never proceed with unresolved gaps.

**Do not end your turn with unverified subagents** — wait for and verify every dispatched Task.

## Rollup

When all items resolve, report: per-item outcome (`[done]`/`[blocked]`/`[incomplete]` with detail),
coordination issues that surfaced, what you verified (the probes you ran), and suggested follow-ups for
deferred work.

**Ship-gate (if the work produced staged changes):** run the preflight before handing off so leaked
secrets or whitespace damage are caught at the seam, not after:

```bash
bash <skill-root>/scripts/preflight.sh commit   # whitespace + staged-index secret scan; honest-degrade w/o gitleaks
```

Report the realized `PREFLIGHT_SECRETSCAN` (GITLEAKS vs the degraded REGEX floor); a `PREFLIGHT_STATE=FAIL`
is a gap to surface, not to paper over. Then suggest `/fusion-handoff` to capture the handoff capsule.
