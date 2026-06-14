---
description: Investigate a bug or a "why is it like this" question evidence-first — read-only subagents gather file:line evidence, the panel adjudicates competing hypotheses, ending at a root-cause report. Not a guess.
argument-hint: [the bug, failure, or "why does X" question] [--panel to force hypothesis adjudication]
---

# /fusion-investigate

Find the **root cause**, not a plausible story. Many real problems are neither a question nor a review —
they're "why is this actually like this / where does this bug come from." This command gathers **evidence
before hypotheses**, then — only when hypotheses genuinely conflict — fans the competing theories to the
panel and lets Opus 4.8 judge which the evidence supports. It ends at a durable root-cause report and
never asserts a cause it didn't ground in `file:line` evidence.

Load `references/investigation-rubric.md` (the phases + report format); if you reach the panel step, also
`references/judge-rubric.md` (Track B).

## Step 1 — Triage & hypotheses

Restate the symptom concretely — repro, error string, observed-vs-expected. List the **candidate
hypotheses** up front as a short ranked set: competing explanations, not one. Keep "what's observed"
separate from "what might cause it." Start the report file (default `docs/investigations/<topic>-<DATE>.md`).

## Step 2 — Gather evidence (subagents, read-only)

Dispatch `Explore`/`general-purpose` subagents to collect a concrete **evidence ledger**: the call path,
the offending `file:line`, git blame/diff, logs, the failing test. Each entry is a fact with a location,
not an opinion. For a big or unfamiliar surface, build a pack first with `/fusion-context` (read
`<skill-root>/commands/fusion-context.md`). Append findings to the report and mark each hypothesis the
evidence **supports / weakens / eliminates**.

## Step 3 — Adjudicate (panel, by exception)

If the evidence cleanly points to one cause, **skip the panel** — say so and go to the report. **Only when
two or more hypotheses genuinely survive the evidence**, run the `/fusion` panel procedure (read
`<skill-root>/commands/fusion.md`) on the competing theories plus the evidence ledger; Opus judges Track B
(consensus / contradictions / which cause the evidence supports / blind spots). `--panel` is the operator's
explicit cross-check: it forces a panel even when you'd otherwise skip — to adjudicate close survivors, or to
stress-test a root cause you think is decisive. It cross-checks the conclusion; it never replaces the
evidence-first discipline. Disclose the realized `PANEL_STATE`; a missing panelist is absent, never agreement.

## Step 4 — Report

Finish the report: **root cause** with its deciding `file:line` evidence, hypotheses eliminated and why,
**honest confidence** (proven vs suspected — name the residual uncertainty), and the recommended fix(es).
Do **not** implement here.

## Present

The report path + a 3-line summary: the root cause, the evidence that nails it, and the next step (usually
`/fusion-plan` → `/fusion-orchestrate` to fix, or `/fusion-review` on the fix).
