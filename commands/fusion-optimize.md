---
description: Optimize a measurable metric with a disciplined measure→change→re-measure loop — baseline first, one attributed change per iteration, the panel decides continue/stop. No baseline, no claim.
argument-hint: [what to optimize: metric + scope + stop criterion] [--cap N iterations]
---

# /fusion-optimize

Measurable speed/size/cost — no guessing. **No baseline → no optimization claim.** You coordinate; changes
land inside Task subagents. Loop discipline: `references/optimize-scoreboard.md`.

## Step 1 — Define the metric & stop criterion

One metric, exact probe command, scope, stop criterion (target / diminishing returns / cap; default 5;
`--cap N`). If no metric given, ask one narrow question. Details: scoreboard § Step 1.

## Step 2 — Baseline (before any change)

Instrument behind a debug/test gate — **never in the hot path / prod**. Run probe **3–5×**; record as
iteration `0` (scoreboard § Steps 2–3).

## Step 3 — Loop: plan → change → re-measure → decide

Each iteration: (1) plan **one** change grounded in bottleneck evidence (single-model); (2) fresh Task
subagent lands it, tests green;
(3) re-run probe 3–5×; (4) append scoreboard row; (5) at the **decision point**, run `/fusion` (read
`<skill-root>/commands/fusion.md`) on continue/stop/next. Hard-fail unless PREMIUM or
`FUSION_ALLOW_DEGRADED=1`; exit 13 → STOP and disclose `PANEL_STATE` (`references/degraded-mode.md`).
**Pass scoreboard + diff only — no raw logs** (scoreboard § Step 6).

**Keep only what beats noise; revert the rest** (scoreboard § Step 5). Stop at target, diminishing
returns, or hard cap (scoreboard § Hard iteration cap).

## Present

Scoreboard path, baseline → best (with variance), kept changes, realized `PANEL_STATE`. Note leftovers.
