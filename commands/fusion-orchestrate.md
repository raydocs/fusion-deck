---
description: Decompose a task against a Workflow Contract, dispatch scoped Task subagents (sequential by default), verify each against its Done-when before the next, and roll up. The orchestrator plans and verifies but never implements.
argument-hint: [contract path or task] [--panel to cross-check a thorny decomposition]
---

# /fusion-orchestrate

Coordinate scoped subagents — plan, decompose, dispatch, verify. Expanded semantics:
`references/orchestration-rubric.md` (also load `references/subagent-prompt-template.md` and
`references/verifier-prompt-template.md`).

> **CRITICAL — the orchestrator never implements.** All product-code edits inside Task subagents only.
> Full tool/role rules: `orchestration-rubric.md` § "The orchestrator never implements".

## Phase 0 — Verify workspace (required)

Right repo/branch; contract **Current State** matches disk. Re-anchor if not.

## Phase 1 — Contextualize

Contract path → read it. Raw task → `/fusion-plan` first (read `<skill-root>/commands/fusion-plan.md`)
or ask the user; don't orchestrate without a contract. **1–2 navigation calls**; separate what-exists from
what-to-do.

## Phase 2 — Decompose (Gate A)

Write/confirm plan file (default `docs/plans/<topic>-<DATE>.md`).
**Natural granularity: 2–3 work items, cap 5.** Each item: `Goal / Done-when / Key files / Dependencies /
Size / Status` + Verifier Plan probe. Plan is read-only to subagents; you own it as a living checklist.

**Gate A** before any dispatch — lint, then one batched semantic scan (contradicting items/Constraints,
placeholder or non-discriminating Done-when, missing cross-item interfaces); surface once, then:

```bash
python3 <skill-root>/scripts/lint_contract.py <plan>
```

`--panel`: if `$ARGUMENTS` contains `--panel` (or thorny hard-to-reverse decomposition) → run `/fusion`
(read `<skill-root>/commands/fusion.md`) on breakdown first. Not the default.

## Phase 3 — Dispatch (scoped briefs)

Modes: **Sequential (default)** · **Parallel** (independent files; sibling-warning required) ·
**Steer-one-agent** (tight coupling / many tiny items). Full rules: rubric § Dispatch mode.

**`--worktrees`** when `$ARGUMENTS` contains it:

```bash
bash <skill-root>/scripts/fusion_worktree.sh create <item-id>
# dispatch in worktree; verify its diff before merge; then:
bash <skill-root>/scripts/fusion_worktree.sh cleanup <item-id>
```

Default off. See `references/worktrees.md`.

Briefs from `subagent-prompt-template.md` (orient not direct; scope to item N; two-conversations firewall).
**One level of fan-out** (no nested subagents). **Specify the subagent model on every dispatch** (omitted
inherits yours — often the most expensive). Size to the item: transcription → cheap; multi-file/judgment →
mid; hardest reasoning stays on your panel. **Turn count beats token price.** Mark `[doing]` **before**
dispatching item N.

## Phase 4 — Verify, then dispatch fresh (Gate B)

**Gate B: discriminating probe against Done-when, then dispatch the next item fresh.** Never skim; never
proceed with gaps. Full sequence: rubric § Verify-then-dispatch-fresh (Gate B).

- **Pass:** mark `[done]` → next item **fresh** (new Task).
- **Gap:** re-dispatch once. **Second failure → Escape Hatch: STOP**, mark `[blocked]`/`[incomplete]`
  (reason / proof / attempted / impact / next-decision), surface to user (rubric § Escape hatch).

**Do not end your turn with unverified subagents.**

## Rollup

Per-item outcomes, probes run, follow-ups (rubric § Rollup). **Ship-gate if staged changes:**

```bash
bash <skill-root>/scripts/preflight.sh commit
```

Report `PREFLIGHT_SECRETSCAN`; `PREFLIGHT_STATE=FAIL` is a gap. Suggest `/fusion-handoff`.
