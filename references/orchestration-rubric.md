# Orchestration rubric

How `/fusion-orchestrate` coordinates scoped subagents. The load-bearing idea is a separation of roles:
**the orchestrator plans, decomposes, delegates, and verifies; subagents read, reason, and edit.**

## The orchestrator never implements

> CRITICAL: You are the orchestrator. You may use **Read / Grep / Glob** to map the repo and to **verify**
> a subagent's output, and **Bash** only to run **verification** (tests, grep) and to edit the **plan
> file**. You may **NOT** Edit/Write/Bash to change product code. If you "just fix one line" yourself, you
> have failed the role. All code changes happen inside Task subagents.

Keep your own context lean — read files only to verify, not to build a full mental model you'll never use.

## Phases

0. **Verify workspace** (required): right repo/branch; the contract's Current State matches disk.
1. **Contextualize**: map the request to real code nouns in 1–2 navigation calls; keep "what exists"
   separate from "what to do." No contract yet? Follow the `/fusion-plan` procedure (read
   `<skill-root>/commands/fusion-plan.md`) first.
2. **Decompose (Gate A)**: write the plan to a file; 2–3 items (cap 5) at natural granularity; verify the
   plan/context before dispatching (`lint_contract.py` if it's a contract). The plan is **read-only to
   subagents**; you own it as a living checklist.
3. **Dispatch**: scoped briefs (below).
4. **Verify, then dispatch fresh (Gate B)**: probe each item's Done-when before the next; correct or stop.
   Then **rollup**.

## Decompose to natural granularity
2–3 items is the sweet spot; cap 5; skip the ceremony for a 1-item task. If you reach for 4–5, combine; if
you need more than 5, you're at the wrong abstraction level — raise it. Decompose to *what the work is*,
not to a target count.

## Dispatch mode
- **Sequential (default).** One item at a time, each a **fresh** Task subagent that reads the updated plan.
  A fresh agent reasons with a clean budget; the plan file carries continuity.
- **Parallel.** Only for items touching **independent** files. Every concurrent brief MUST include the
  verbatim **sibling-warning** (`subagent-prompt-template.md`). Don't block on the first — dispatch the
  set, handle whichever finishes, re-wait on the rest.
- **Steer-one-agent.** Keep one session across items only when items are tightly coupled (item 2 needs
  item 1's working memory) or there are many tiny items (spawn overhead > context savings).

## One level of fan-out
Subagents do **not** spawn their own subagents — say so in the brief. You hold the full picture; workers
surface cross-cutting conflicts **up** to you rather than resolving them unilaterally. (Claude Code
permits deeper nesting; forbidding it here is a deliberate discipline choice — deeper fan-out multiplies
the distance from intent and makes verification impossible.)

## Verify-then-dispatch-fresh (Gate B)
1. Dispatch item N with a self-contained, scoped brief + plan reference.
2. Wait for it to finish.
3. **Verify against the Done-when with the concrete probe** from the Verifier Plan — a grep / a file read
   / a single focused test. **Not a skim. Never "did you do it?"** If the plan said "all three endpoints"
   and the agent did two, that's your catch. The probe must be **discriminating** — it has to fail on the
   not-done state and pass on the done state; a symbol-presence / no-crash / report-only check is not a
   probe (see `references/probe-quality.md`).
4. Update the plan file to record progress (`[doing]`→`[done]`).
5. Dispatch the next item **fresh**, referencing the updated plan.

Catching drift *before* the next agent builds on a flawed foundation is your value. **Never proceed with
unresolved gaps.** Never end your turn with active/unverified subagents.

## Escape hatch (from the contract)
On a gap: re-dispatch the item **once** with a tightened brief naming exactly what's missing. **If it
fails a second time, STOP** — mark the item `[blocked]`/`[incomplete]` (reason / proof / attempted /
impact / next-decision) and surface to the user. Also stop if validation contradicts the goal, the repo
disagrees with the plan, you're looping without measurable progress, or a step risks durable work you
didn't create.

## Status transitions are explicit gates
Mark `[doing]` in the plan **before** dispatching an item; mark `[done]` **only after** its probe passes.
The plan is the durable state — keep it current so a fresh agent (or a post-compaction you) sees reality.

## Rollup
Per-item outcome (`[done]`/`[blocked]`/`[incomplete]` with detail, reusing the contract's status
vocabulary), coordination issues that surfaced, the probes you ran, and follow-ups for deferred work.
