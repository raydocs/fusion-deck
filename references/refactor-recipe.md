# Refactor recipe

The recipe `/fusion-refactor` loads. A refactor is a **composition of existing commands, not a new engine**:
analyze structure like `/fusion-review`, plan ordered behavior-preserving steps like `/fusion-plan`, execute
like `/fusion-orchestrate`. The load-bearing idea: **refactoring changes shape, never behavior.** Restructure
the code; the observable behavior stays bit-identical. Anything that changes what the program *does* is a
feature change or a bug — not a refactor, and not in scope here.

## The hard invariant

> **Behavior is preserved unless explicitly broken.** Establish a **green behavior baseline first**, and
> **re-prove it after every step.** A step that can't show the same baseline green afterward is not done —
> it's a regression to revert, not a result to keep.

This is the refactor analogue of the orchestrator's "never implements" rule: it's the one discipline that, if
dropped, turns the whole exercise into silent breakage. New logic, new behavior, "while I'm here" fixes — all
out of scope. If you find a real bug mid-refactor, **note it, don't fix it** (surface it for a separate
`/fusion-plan`); fixing it changes behavior and contaminates the baseline.

## Step 0 — Establish the green baseline (required, before anything)

You cannot preserve what you haven't pinned. Find and run the existing behavior check **and record that it's
green** before touching code:

- **Best:** an existing test suite / the relevant test files for the target — run them, capture the pass line.
- **Else:** characterization checks — capture current observable output (CLI stdout, an HTTP response, a
  golden file) as the oracle the refactor must reproduce. Write them down; they are the contract.
- **Floor (honest-degrade):** if there is genuinely no runnable check, **say so loudly** — "no behavior
  baseline; refactor is UNVERIFIED" — and either stop to add a characterization test first, or proceed only
  with the user's explicit acknowledgement that correctness is unproven. Never present an unverified refactor
  as safe. This mirrors the skill's cardinal rule: degrade loudly, never fake the capability.

Record the exact baseline command and its green result in the contract's **Current State** — every later step
re-runs *this* command.

## Step 1 — Analyze structure (like `/fusion-review`)

Audit the target the way `/fusion-review` audits a diff, but hunting **structural smells**, not bugs. Name each
as a concrete `file:line` finding with evidence — never "this feels messy":

- **Duplication** — the same logic in N places (`file:line × N`); the consolidation target.
- **Excess complexity** — a function/class doing too much: deep nesting, long parameter lists, a god object.
- **Scattered logic** — one concern smeared across files that wants to live in one place (or the inverse: one
  file holding several unrelated concerns).
- **Dead / obsolete shape** — only code your refactor genuinely makes obsolete is in scope to delete; leave
  pre-existing dead code alone unless removing it *is* the task.

For a large or contested target, escalate to the real panel: run the `/fusion-review` procedure (read
`<skill-root>/commands/fusion-review.md`) and take its Consensus findings as the smell list. Independent
reviewers agree on the smells worth paying down and prune the cosmetic ones. Disclose the realized
`PANEL_STATE`; a missing panelist is absent, never agreement.

Output: a ranked smell list (`file:line` + evidence + the structural fix), highest-payoff first. **Don't fix
anything yet** — analysis stays separate from execution, same as everywhere in this skill.

## Step 2 — Plan ordered, behavior-preserving steps (like `/fusion-plan`)

Turn the smell list into a **Workflow Contract** by following the `/fusion-plan` procedure (read
`<skill-root>/commands/fusion-plan.md`; emit to `docs/refactors/<topic>-<DATE>.md`). The refactor-specific
constraints on that contract:

- **Finishing Criteria = the baseline, unchanged.** The whole contract's definition of done is "the Step-0
  baseline is still green **and** the named smells are gone." No new behavioral criteria.
- **Every Work Item's `Done-when` PRESERVES BEHAVIOR.** Each Done-when is two clauses: *the structural change
  landed* (grep shows the duplication collapsed / the function split) **AND** *the baseline command is still
  green*. A Done-when that asserts new behavior is a planning error — reject it.
- **Order by dependency, smallest reversible step first.** Refactors compound: extract-then-inline-then-rename
  in the wrong order fights itself. Sequence so each step is independently revertible and leaves the tree
  green. `Dependencies` + `Size` drive the dispatch mode in Step 3.
- **Natural granularity — 2–3 items, cap 5** (same rule as every plan here). One smell may be one item, or a
  few mechanical micro-steps grouped; don't pad to a count.

Lint it: `python3 <skill-root>/scripts/lint_contract.py docs/refactors/<topic>-<DATE>.md`. Fix every error.
`--panel` on the *decomposition* ("what's the safest order to land these?") only for a thorny, hard-to-reverse
restructuring — not by default.

## Step 3 — Execute (like `/fusion-orchestrate`, prefer STEER-ONE-AGENT)

Run the contract via the `/fusion-orchestrate` procedure (read `<skill-root>/commands/fusion-orchestrate.md`),
with one deliberate departure from its sequential-by-default:

- **Prefer steer-one-agent.** Refactor steps compound — step 2 reshapes what step 1 just moved — so the working
  memory of "what was extracted where" is worth keeping in one session rather than re-deriving it cold each
  fresh dispatch. This is the orchestration-rubric's "tightly coupled items" case, which for refactors is the
  norm, not the exception.
- **Parallel only across zero-overlap files.** Two steps may run concurrently **only** if their `Key files`
  sets are disjoint — no shared file, no rename one step depends on. Every concurrent brief carries the
  verbatim sibling-warning (`subagent-prompt-template.md`). When in doubt, serialize: a merge conflict mid-
  refactor is far more expensive than the lost parallelism.
- **The orchestrator still never implements** — all edits happen inside Task subagents; you plan and verify.

### Verify-then-dispatch-fresh, behavior-gated (the heart of the recipe)

This is `/fusion-orchestrate` Gate B with the invariant welded on. After each step's subagent returns:

1. **Re-run the Step-0 baseline command** — the exact same one. **Still green? proceed. Red? the step broke
   behavior — REVERT it** (don't patch forward), mark the item `[blocked]`, surface it. A red baseline is the
   refactor failing, full stop.
2. **Verify the structural change landed** — the grep/read from the Verifier Plan (duplication actually
   collapsed, function actually split). Shape changed *and* baseline green = `[done]`. Shape unchanged but
   green = nothing happened, not done.
3. Update the plan, then dispatch the next step fresh-or-steered per the mode above.

Never let a step end with the baseline red or unrun. "Looks refactored" is not done; **"same baseline still
green, smell gone" is done** — the refactor analogue of the judge rubric's "verified to run is done, looks
plausible is not."

## Rollup

Per-item outcome (`[done]`/`[blocked]`/`[incomplete]` with detail), the **baseline command and its
green/red result after each step** (the proof behavior held — or where it didn't), which smells are now gone
vs deferred, and any bugs you spotted-but-correctly-didn't-fix (hand those to a fresh `/fusion-plan`). Then
suggest `/fusion-handoff`. If the baseline was ever the floor (no real check), say so plainly in the rollup —
the refactor is structurally done but behaviorally **UNVERIFIED**.
