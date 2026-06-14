---
description: Turn a vague request into a verifiable Claude Code Workflow Contract (objective, finishing criteria, current state, scoped work items, escape hatch, verifier plan). Not a Codex /goal.
argument-hint: [the vague/underspecified request] [--panel to cross-check the plan]
---

# /fusion-plan

Convert an underspecified request into a **Claude Code Workflow Contract** — a self-contained markdown
file that states what should become true, how you'll know it's done, what's true now, the scoped work
items, the escape hatch, and the exact checks. It is the contract `/fusion-orchestrate` executes and
`scripts/lint_contract.py` validates. **This is not a Codex `/goal`** — Claude Code has no `/goal`, and
the linter rejects any `/goal` reference.

Load `references/workflow-contract.md` (the template + section semantics).

## Step 1 — Contextualize (don't over-explore)

Translate the raw request into the codebase's real nouns with **1–2 navigation calls** (Grep/Glob/Read),
e.g. "add retry logic to the API layer" → "add retry to `NetworkService`, mirror `APIClient` auth-retry".
Gather **what exists** (facts/relationships) and keep it separate from **what to do**. If still ambiguous
after 2 calls, ask the user one narrow question rather than guessing.

## Step 2 — Write the contract

Define **finishing criteria before the work**. Emit the file (default `docs/plans/<topic>-<DATE>.md`, or a
path the user gives) with these sections (see `references/workflow-contract.md`):

- **Objective** — what should become true (one or two sentences).
- **Finishing Criteria** — concrete, *verifiable* signals (a test, a grep, an observable output) — not
  "works" / "clean".
- **Current State** — the ledger: what is currently true, distinct from the objective.
- **Work Items** — each a `###` subsection with `Goal / Done-when / Key files / Dependencies / Size /
  Status`. Decompose to **natural granularity (2–3 items, cap 5)**; combine if you reach for more.
- **Escape Hatch** — the pause conditions (validation contradicts the goal, repo disagrees with the plan,
  looping without progress, risk to durable work, scope change).
- **Verifier Plan** — the narrowest concrete probe per item.
- (optional) **References** — `file:line` pointers, links.

Use the honest status vocabulary `[todo]/[doing]/[done]/[blocked]/[incomplete]/[abandoned]`.

## Step 3 — Lint

```bash
python3 <skill-root>/scripts/lint_contract.py docs/plans/<topic>-<DATE>.md
```

Fix every **error** (missing section, missing/empty work-item field, invalid status, `/goal` reference).
Address **warnings** (unverifiable-looking finishing criteria) where reasonable. Re-run until it passes.

## `--panel` (optional escalation)

If `$ARGUMENTS` contains the literal `--panel` flag — or the request is genuinely ambiguous and
high-stakes — first run the `/fusion` panel procedure (read `<skill-root>/commands/fusion.md`) on the
*planning question* ("what's the best approach / decomposition for X?"), then write the contract grounded
in the synthesized answer. Most plans don't need this — don't pay for a panel by default.

## `--deep` (optional: graduated involvement + a critique pass)

For a high-stakes design where you want a polished plan document:

1. **Ask involvement up front** — one question: *up-front* (clarify the request before exploring),
   *mid-flow* (check in before the critique), or *hands-off* (surface the plan when ready). Default if the
   user doesn't answer: hands-off. **Honor the choice** — if they picked a checkpoint, pause there and
   wait; never silently demote them.
2. **Explore the seams**, then draft the contract (Steps 1–2).
3. **Critique pass** — dispatch one critic subagent (or `--panel`) scoped to the top under-specified
   seams, contradictions, over-planning to cut, and the questions that would change the order. Fold it in
   so the plan gets **shorter and sharper** — a plan should shrink as it matures.

Deep mode still emits a lint-passing Workflow Contract (Step 3); it is **not** a Codex `/goal`.

## Present

The contract path + a one-paragraph summary (objective, item count, the riskiest item). Then suggest
`/fusion-orchestrate <contract-path>` to execute it.
