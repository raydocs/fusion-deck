---
description: Refactor safely — analyze structure for duplication/complexity, plan ordered behavior-preserving steps, then steer one agent through them. Changes structure, not behavior.
argument-hint: [files, directory, or system to refactor]
---

# /fusion-refactor

Improve **structure without changing behavior**. This is a composition, not a new engine: it reuses pieces
you already have — analyze like `/fusion-review`, plan like `/fusion-plan`, execute like
`/fusion-orchestrate` — under one hard invariant: **behavior is preserved unless it's explicitly broken.**

Load `references/refactor-recipe.md` (the recipe + the behavior-preservation invariant).

## Step 1 — Analyze structure

Map the target for **duplication, excess complexity, and scattered logic that wants consolidating** —
concrete `file:line` smells, not vibes. Establish the **behavior baseline**: the tests (or characterization
checks) that are green now and must stay green. For a contested call on *whether* a refactor is safe,
escalate that one question with `/fusion-review --panel`.

## Step 2 — Plan ordered, behavior-preserving steps

Write a Workflow Contract (`/fusion-plan` procedure — read `<skill-root>/commands/fusion-plan.md`) whose
every **Done-when preserves behavior** (same baseline green; no new logic). Order by dependency; smallest
safe steps first.

## Step 3 — Execute (steer one agent)

Refactors compound — later steps build on earlier ones — so prefer `/fusion-orchestrate`'s
**steer-one-agent** mode (read `<skill-root>/commands/fusion-orchestrate.md`); parallelize only across
**zero-overlap** files. After each step the probe is the same: **the behavior baseline still passes.**

## Present

What changed structurally, the baseline that stayed green throughout (your proof behavior held), and any
smell deliberately deferred. Suggest `/fusion-handoff` if handing on.
