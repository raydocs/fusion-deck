---
description: Audit code or a plan with the premium panel — independent blind reviewers, then an Opus-judged structured findings report (severity, file:line, evidence).
argument-hint: [what to review — a diff, files, a design, or a plan]
---

# /fusion-review

A panel audit. Several models independently review the same target (a diff, files, a design doc, a plan),
then **Opus 4.8 synthesizes** their findings — surfacing where reviewers **agree** (highest-confidence
issues), where they **disagree** (adjudicate by evidence), and what only one caught. This is the strongest
fusion fit after `/fusion` itself, because independent reviewers catch each other's misses and false
alarms.

Load `references/panel-prompt.md` and `references/judge-rubric.md`.

## Step 0 — Scope & assert the panel

Pin the exact review target with an explicit scope token — `uncommitted` (working tree), `staged`,
`back:N` (last N commits), `main` / `<branch>` (e.g. `git diff main...HEAD`), or a pasted design. Then:

```bash
bash <skill-root>/scripts/detect_panel.sh
bash <skill-root>/scripts/assert_triple_panel.sh
```

Same honest-degrade rule as `/fusion`: hard-fail unless PREMIUM or `FUSION_ALLOW_DEGRADED=1`; record the
`PANEL_STATE` to disclose.

## Step 1 — Fan out, blind and in parallel

**Build an explicit review packet first.** The codex/gemini panelists run sandboxed and cannot read your
repo, so bundle the ACTUAL materials into the brief: the diff (`git diff <range>`) and/or the full
contents of the target files (or a Context Pack from `/fusion-context`), with line numbers so panelists
can cite `file:line`. Never pass bare paths — a panelist that can't see the code can't review it.

Give every panelist the **same review brief verbatim** (the packet + the independent-expert instruction
from `panel-prompt.md`), asking each for findings as a list of `{severity, location (file:line),
evidence, why it matters, suggested fix}`. Ask for correctness/security/edge-case bugs **and** reuse /
simplification / efficiency cleanups. Don't assign each reviewer a different lens — independence already
yields diverse coverage. Launch via `<skill-root>/scripts/run_triple_fusion.sh` + an Opus `Agent`/`Task`
panelist, in one turn (see `/fusion` Step 1 — run the Bash call in background mode and spawn Opus
concurrently).

## Step 2 — Judge: synthesize the findings (Opus 4.8)

This is a research/analysis deliverable → **Track B**. Merge the independent reviews into:

- **Consensus** — issues ≥2 reviewers independently flagged. **Highest confidence; lead with these.**
- **Contradictions** — one says "bug", another "fine". Adjudicate by evidence (who read the actual code /
  traced the path); if unresolved, say what would settle it.
- **Partial coverage** — issues only one reviewer reached (often the deepest).
- **Unique insights** — non-obvious catches worth preserving.
- **Blind spots** — what the whole panel missed; add any the panel didn't name.

**Adversarially verify before reporting:** for each high-severity finding, confirm it against the real
code (read the cited file:line). Drop findings that don't survive — a plausible-but-wrong finding wastes
the reader's time. De-dupe by `file:line`.

## Step 3 — Present

A single prioritized findings report with a hard budget (RepoPrompt-style — caps force triage over a
dump): lead with **≤5 Must-fix** (each: severity, `file:line`, evidence, concrete fix), then **≤5
Suggestions**, then **≤3 Questions**, ordered consensus-first. Then the five-section audit trail.
**Disclose the realized `PANEL_STATE`** (read it from the manifest). Do not auto-apply fixes unless the
user asks — this command reviews.
