---
description: Optimize a measurable metric with a disciplined measure→change→re-measure loop — baseline first, one attributed change per iteration, the panel decides continue/stop. No baseline, no claim.
argument-hint: [what to optimize: metric + scope + stop criterion] [--cap N iterations]
---

# /fusion-optimize

Make something **measurably** faster, smaller, or cheaper without guessing. The loop is the point: define
one metric and a stop criterion, establish a baseline, then change **one attributed thing at a time** and
re-measure — and let the **panel**, not your gut, call continue / stop / try-next at each decision point.
**No baseline → no optimization claim.** Like `/fusion-orchestrate`, you coordinate and verify; the actual
changes happen inside Task subagents.

Load `references/optimize-scoreboard.md` (the scoreboard + loop discipline).

## Step 1 — Define the metric & stop criterion

Name the single metric (p95 latency / wall-clock / bundle bytes / test runtime / allocations), the exact
**probe command** that measures it, the scope, and the stop criterion — a target value, diminishing
returns, or an iteration cap (default 5; override with `--cap N`). If the user gave no metric, ask one
narrow question; don't invent one.

## Step 2 — Baseline (before any change)

Instrument behind a debug/test gate — **never in the measured hot path**, never in prod. Run the probe
**3–5 times**, record the values and their variance in the scoreboard. This baseline is the only thing a
later "we improved it" can be true against.

## Step 3 — Loop: plan → change → re-measure → decide

Each iteration: (1) plan **one** candidate change grounded in the bottleneck evidence — single model, this
is routine; (2) dispatch a **fresh Task subagent** to land it and keep tests green; (3) re-run the probe
(same 3–5 samples); (4) append an attributed row to the scoreboard (change · metric · delta vs baseline ·
kept/reverted); (5) at the **decision point**, run the `/fusion` panel procedure (read
`<skill-root>/commands/fusion.md`) on "did this earn its keep, what next, are we done?" — the one place a
panel is worth it in a loop. Hard-fail unless PREMIUM or `FUSION_ALLOW_DEGRADED=1`; on exit 13 STOP and disclose the realized `PANEL_STATE` from the manifest — never silently continue (`references/degraded-mode.md`). **Don't feed raw logs to the panel** — pass the scoreboard and the diff.

Stop when the target is met, returns diminish, or the cap is hit. Revert any change that didn't beat noise.

## Present

The scoreboard path, baseline → best metric (with variance), the changes that stuck, and the realized
`PANEL_STATE` at the decision points. Note anything left on the table.
