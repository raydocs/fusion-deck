# The Claude Code Workflow Contract

A Workflow Contract is the artifact `/fusion-plan` emits and `/fusion-orchestrate` executes. It ports the
goal-meta discipline (a contract + an honesty path) into Claude Code, which has **no `/goal` tool** — so
the contract is a plain, self-contained markdown file, and `scripts/lint_contract.py` **rejects any
`/goal` reference**.

The distinction it encodes: the **Objective** is *what should become true*; the **Current State** is *what
is currently true*. Keeping both prevents drift and survives compaction/handoff.

## Required sections (the linter blocks if any is missing)

### Objective
What should become true, in the codebase's own nouns. One or two sentences.

### Finishing Criteria
The concrete, **verifiable** signals that the objective is met — a passing test, a grep that matches, an
observable output, an HTTP status. Avoid bare "works / clean / good / done" (the linter warns on these
unless paired with a concrete check). Define these **before** writing any work item.

### Current State
The ledger: what is true on disk **now**, distinct from the Objective. Include the last validation result.
Re-anchor this against the repo before orchestrating — if it disagrees with reality, fix it first.

### Work Items
Each work item is a `###` subsection carrying exactly these fields (all non-empty):

- **Goal** — one or two sentences.
- **Done-when** — the concrete completion condition (what is true when finished), ideally a probe.
- **Key files** — where the work happens (mark new files).
- **Dependencies** — which items must complete first (or `none`).
- **Size** — `small` or `large`.
- **Status** — one of `[todo] [doing] [done] [blocked] [incomplete] [abandoned]`.

Decompose to **natural granularity — 2–3 items, cap 5.** If you reach for more, combine or raise the
abstraction level. `Dependencies` + `Size` are what drive the sequential / parallel / steer choice in
`/fusion-orchestrate`.

For an item whose output later items build on, add an optional **Interfaces** line — the exact
names/signatures it *produces* (function names, params, return types) and *consumes* from a prior item. A
worker sees only its own item; this line is how item 3 learns the name item 1 actually used, so it doesn't
call `clearLayers()` where item 1 wrote `clearFullLayers()`. **Not linted** — add it only where a real
cross-item contract exists.

### Escape Hatch
The pause conditions — the honesty path for impossible/contradictory/scope-changing situations:
- validation contradicts the goal;
- a Done-when probe fails twice for the same item (don't re-dispatch indefinitely);
- the Current State disagrees with the repo on disk;
- the next step risks deleting/rewriting durable work you didn't create;
- finishing requires a scope change beyond the Objective.

### Verifier Plan
The narrowest concrete probe per work item — the exact grep / file read / single test to run after that
item, **before** dispatching the next. (See `verifier-prompt-template.md`.)

## Recommended sections (optional, but strongly advised for anything risky)

Borrowed from qiaomu-goal-meta's split of *what must not change* vs *where the agent may write*. The
linter does not require them (existing contracts don't break), but include them whenever the work touches
shared APIs, data, or a blast-radius bigger than a couple of files — they are what keep a blind subagent
from quietly expanding scope.

### Constraints
The **invariants that must not change**: public API signatures, on-disk/data shapes, the dependency set,
style/lint rules, branch, secrets. One bullet each, or `none`. (Distinct from Finishing Criteria, which is
what must *become* true.)

### Boundaries
The **write boundary**: which directories/globs the work may modify, and which paths are **forbidden**
(e.g. `vendor/`, generated files, another team's module). Pair with `.fusionignore` for the repo-wide
version. Never "edit anything" — that phrase is a hard lint error (C009).

`/fusion-orchestrate` copies the Constraints + Boundaries into each subagent brief, so a worker inherits
the negative space, not just the goal.

## Optional sections
**References** (`file:line` pointers, links), **Open Questions** (only if they block or shape work),
**Parent** (a prior contract this one builds on).

## Honest status states
- `[todo]` known, not started · `[doing]` active · `[done]` completed **and validated**
- `[blocked]` waiting on external input/dependency · `[abandoned]` intentionally stopped
- `[incomplete]` attempted, not fully solvable now — and **must** carry a real value for each of:
  ```
  - [incomplete] <item>
    - reason: <text>
    - proof: <text>
    - attempted: <text>
    - impact: <text>
    - next human/agent decision: <text>
  ```
  Put the value on the same line as the key (an indented continuation line is also accepted). Empty,
  placeholder (`TBD`/`N/A`/`-`), or punctuation-only values fail the lint (rule **C007**).

See `examples/workflow-contract.example.md` for a complete, lint-passing contract. Validate with
`python3 <skill-root>/scripts/lint_contract.py <file>`.
