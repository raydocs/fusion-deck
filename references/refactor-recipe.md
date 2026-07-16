# Refactor recipe

The recipe `/fusion-refactor` loads. A refactor is a **composition of existing commands, not a new engine**:
analyze structure like `/fusion-review`, plan ordered behavior-preserving steps like `/fusion-plan`, execute
like `/fusion-orchestrate`. The load-bearing idea: **refactoring changes shape, never behavior.** Restructure
the code; the observable behavior stays bit-identical. Anything that changes what the program *does* is a
feature change or a bug — not a refactor, and not in scope here.

**Read first (do not restate):** `commands/fusion-review.md`, `commands/fusion-plan.md`,
`commands/fusion-orchestrate.md`, plus `orchestration-rubric.md` / `workflow-contract.md` for shared
rules (granularity, Gate B, orchestrator-never-implements, status vocabulary). This file holds only the
**refactor-specific deltas**.

## The hard invariant

> **Behavior is preserved unless explicitly broken.** Establish a **green behavior baseline first**, and
> **re-prove it after every step.** A step that can't show the same baseline green afterward is not done —
> it's a regression to revert, not a result to keep.

New logic, new behavior, "while I'm here" fixes — all out of scope. If you find a real bug mid-refactor,
**note it, don't fix it** (surface it for a separate `/fusion-plan`); fixing it changes behavior and
contaminates the baseline.

## Step 0 — Establish the green baseline (required, before anything)

You cannot preserve what you haven't pinned. Find and run the existing behavior check **and record that it's
green** before touching code:

- **Best:** an existing test suite / the relevant test files for the target — run them, capture the pass line.
- **Else:** characterization checks — capture current observable output (CLI stdout, an HTTP response, a
  golden file) as the oracle the refactor must reproduce. Write them down; they are the contract.
- **Floor (honest-degrade):** if there is genuinely no runnable check, **say so loudly** — "no behavior
  baseline; refactor is UNVERIFIED" — and either stop to add a characterization test first, or proceed only
  with the user's explicit acknowledgement that correctness is unproven. Never present an unverified refactor
  as safe.

Record the exact baseline command and its green result in the contract's **Current State** — every later step
re-runs *this* command.

## Step 1 — Analyze structure (like `/fusion-review`)

Follow `/fusion-review`, but hunt **structural smells** (not bugs), each as concrete `file:line` evidence:

- **Duplication** — same logic in N places; the consolidation target.
- **Excess complexity** — deep nesting, long parameter lists, god object.
- **Scattered logic** — one concern smeared across files (or one file holding unrelated concerns).
- **Dead / obsolete shape** — only code your refactor genuinely makes obsolete; leave pre-existing dead
  code alone unless removing it *is* the task.

Large/contested target → run the real `/fusion-review` procedure; take Consensus findings as the smell list.
Disclose realized `PANEL_STATE`. Output: ranked smell list. **Don't fix anything yet.**

## Step 2 — Plan ordered, behavior-preserving steps (like `/fusion-plan`)

Follow `/fusion-plan` (emit to `docs/refactors/<topic>-<DATE>.md`) with these **deltas**:

- **Finishing Criteria = the baseline, unchanged.** Done = "Step-0 baseline still green **and** named
  smells gone." No new behavioral criteria.
- **Every Work Item's `Done-when` PRESERVES BEHAVIOR** — structural change landed **AND** baseline still
  green. A Done-when that asserts new behavior is a planning error.
- **Order by dependency, smallest reversible step first.** Each step independently revertible and leaves
  the tree green.
- Granularity / lint / optional `--panel` on decomposition: same as `/fusion-plan` (do not restate).

## Step 3 — Execute (like `/fusion-orchestrate`, prefer STEER-ONE-AGENT)

Follow `/fusion-orchestrate` with one deliberate departure:

- **Prefer steer-one-agent** — refactor steps compound (step 2 reshapes what step 1 just moved), so keeping
  working memory in one session beats re-deriving it cold each fresh dispatch.
- **Parallel only across zero-overlap files** (disjoint `Key files`; sibling-warning required). When in
  doubt, serialize.
- Orchestrator-never-implements still applies (edits inside Task subagents only).

### Verify-then-dispatch-fresh, behavior-gated

Gate B with the invariant welded on. After each step's subagent returns:

1. **Re-run the Step-0 baseline command.** Still green → proceed. Red → **REVERT** (don't patch forward),
   mark `[blocked]`, surface. A red baseline is the refactor failing, full stop.
2. **Verify the structural change landed** (Verifier Plan probe). Shape changed *and* baseline green =
   `[done]`. Shape unchanged but green = not done.
3. Update the plan, then dispatch the next step fresh-or-steered per the mode above.

Never let a step end with the baseline red or unrun. **"Same baseline still green, smell gone" is done.**

## Rollup

Per-item outcome, the **baseline command and its green/red result after each step**, which smells are gone
vs deferred, and bugs spotted-but-correctly-didn't-fix (hand those to a fresh `/fusion-plan`). Suggest
`/fusion-handoff`. If the baseline was the floor (no real check), say so — structurally done but
behaviorally **UNVERIFIED**.
