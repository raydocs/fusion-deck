---
description: Re-anchor a drifting session onto the fusion-deck discipline — a one-screen cheat-sheet of which command fits which situation and the invariants that are easy to let slip.
argument-hint: [optional: a situation to route, e.g. "about to review a diff"]
---

# /fusion-remind

A cheap **re-anchor**. In a long session the model drifts off the discipline — it answers a hard call solo
instead of opening the panel, forgets to disclose which models actually ran, skips the Done-when probe, or
starts editing code from inside the orchestrator. This command spends no panel and no subagent: it just
reprints the map and the invariants so you (or a fresh agent) snap back to the right move.

Load `references/reminder.md` and emit the cheat-sheet below. If `$ARGUMENTS` names a situation, also point
to the one command that fits and why — one line, then stop.

## Situation → command (offer, don't auto-run the panel)

| The situation | Command | Panel? |
| --- | --- | --- |
| a hard call / trade-off to settle or cross-check | `/fusion` | yes |
| "choose the right workflow for this" / cheap-unless-risky | `/fusion-auto` | router decides |
| maximum quality / high-risk, hard-to-reverse call | `/fusion-ultra` | yes + probes |
| review code, a diff, or a plan before it ships | `/fusion-review` | yes |
| a bug, or "why is it built like this?" | `/fusion-investigate` | by exception |
| a vague ask to turn into a checkable plan | `/fusion-plan` (`--deep` for a design doc) | no |
| hand the right files to another agent/model | `/fusion-context` (`--discover` to auto-curate) | no |
| a big multi-step change done carefully | `/fusion-orchestrate` (`--worktrees` to parallelize) | no |
| make something measurably faster / smaller | `/fusion-optimize` | by exception |
| clean up structure without changing behavior | `/fusion-refactor` | no |
| pass work to the next agent / future-you | `/fusion-handoff` | no |

For a quick factual question, just answer — don't route a trivial ask into a panel.

## Invariants that are easy to let slip

1. **Never fake premium.** Disclose the realized `PANEL_STATE`; degrade only with `FUSION_ALLOW_DEGRADED=1`,
   and say so. A missing panelist is **absent**, never silent agreement.
2. **Blind panel, Opus judges last.** Panelists never see each other's work; only the judge reads all
   answers, only after every panelist returns. Don't pre-digest the task before handing it over.
3. **Orchestrator never implements.** Read only to verify; all code changes happen inside Task subagents;
   one level of fan-out.
4. **Verify, then dispatch fresh.** Probe each item's Done-when with a *discriminating* check
   (`references/probe-quality.md`) before the next — never "did you do it?". Never proceed with a gap.
5. **Contract, not `/goal`.** `/fusion-plan` emits a Workflow Contract; the linter rejects `/goal`.
6. **Honesty path.** Use `[todo]/[doing]/[done]/[blocked]/[incomplete]/[abandoned]`; report failures plainly.

This is a reminder, not a workflow — it ends here. Pick the command above and go.
