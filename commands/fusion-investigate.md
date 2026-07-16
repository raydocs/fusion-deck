---
description: Investigate a bug or a "why is it like this" question evidence-first — read-only subagents gather file:line evidence, the panel adjudicates competing hypotheses, ending at a root-cause report. Not a guess.
argument-hint: [the bug, failure, or "why does X" question] [--panel to force hypothesis adjudication]
---

# /fusion-investigate

Find the **root cause**, not a plausible story. Many real problems are neither a question nor a review —
they're "why is this actually like this / where does this bug come from." This command gathers **evidence
before hypotheses**, then — only when hypotheses genuinely conflict — fans the competing theories to the
panel and lets Claude (the session model) judge which the evidence supports. It ends at a durable root-cause report and
never asserts a cause it didn't ground in `file:line` evidence.

Load `references/investigation-rubric.md` (the phases + report format); if you reach the panel step, also
`references/judge-rubric.md` (Track B).

## Step 1 — Triage & hypotheses

Restate the symptom concretely (repro, observed-vs-expected); list **2–4 ranked competing hypotheses**;
start the report file. Full phase rules: `investigation-rubric.md` § Phase 1.

## Step 2 — Gather evidence (subagents, read-only)

Dispatch read-only `Explore`/`general-purpose` subagents into an **evidence ledger** of located facts
(`file:line` / commit / test); score each hypothesis support/weaken/eliminate. Full ledger and parallel-
subagent rules: `investigation-rubric.md` § Phase 2. For a big surface, build a pack first with
`/fusion-context` (read `<skill-root>/commands/fusion-context.md`).

## Step 3 — Adjudicate (panel, by exception)

If evidence is decisive, **skip the panel** and go to the report. **Only when ≥2 hypotheses survive**, run
the `/fusion` panel procedure (read `<skill-root>/commands/fusion.md`) on the competing theories + ledger
(Track B). `--panel` forces the cross-check even when you'd skip. Full skip/run/disclose rules:
`investigation-rubric.md` § Phase 3. Hard-fail unless PREMIUM or `FUSION_ALLOW_DEGRADED=1`; on exit 13 STOP
and disclose the realized `PANEL_STATE` from the manifest — never silently continue
(`references/degraded-mode.md`).

## Step 4 — Report

Finish the report: **root cause** with deciding `file:line`, eliminated hypotheses, **honest confidence**
(proven vs suspected), recommended fix(es). **Do not implement.** Full report shape:
`investigation-rubric.md` § Phase 4.

## Present

The report path + a 3-line summary: the root cause, the evidence that nails it, and the next step (usually
`/fusion-plan` → `/fusion-orchestrate` to fix, or `/fusion-review` on the fix).
