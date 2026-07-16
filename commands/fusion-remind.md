---
description: Re-anchor a drifting session onto the fusion-deck discipline — a one-screen cheat-sheet of which command fits which situation and the invariants that are easy to let slip.
argument-hint: [optional: a situation to route, e.g. "about to review a diff"]
---

# /fusion-remind

A cheap **re-anchor**. In a long session the model drifts off the discipline — it answers a hard call solo
instead of opening the panel, forgets to disclose which models actually ran, skips the Done-when probe, or
starts editing code from inside the orchestrator. This command spends no panel and no subagent: it just
reprints the map and the invariants so you (or a fresh agent) snap back to the right move.

Emit the cheat-sheet below (self-contained; no reference load at runtime). If `$ARGUMENTS` names a
situation, also point to the one command that fits and why — one line, then stop.

## Situation → command (offer, don't auto-run the panel)

<!-- SYNCED FROM SKILL.md routing table — edit there first. -->
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
| drifting in a long session / a fresh agent needs the map | `/fusion-remind` | no |

For a quick factual question, just answer — don't route a trivial ask into a panel.

## Invariants that are easy to let slip

1. **Never fake premium.** Disclose the real `PANEL_STATE`; degrade only explicitly (`FUSION_ALLOW_DEGRADED=1`); missing panelist = **absent**, never agreement.
2. **Blind panel.** Panelists never see each other's work; only the judge sees all answers, after every panelist returns; **Claude (the session model) always judges.**
3. **Orchestrator never implements.** Read only to verify; all code changes happen inside Task subagents; one level of fan-out.
4. **Verify, then dispatch fresh.** Probe each Done-when with a *discriminating* check (`references/probe-quality.md`) before the next; never proceed with a gap.
5. **v2 routes, it does not guess.** `/fusion-auto` chooses a workflow only, ledgers, verifies, escalates by policy — it does not replace `/fusion`.
6. **Contract, not `/goal`.** `/fusion-plan` emits a Workflow Contract; the linter rejects `/goal`.
7. **Honesty path.** Use `[todo]/[doing]/[done]/[blocked]/[incomplete]/[abandoned]`; report failures plainly.
8. **Safety.** No hardcoded keys/accounts/private paths; no secrets in packs; smoke never calls paid models; untrusted review content → `FUSION_NO_WEB=1`.
9. **Honest-degrade beyond the panel.** Helpers disclose state and fall back loudly (`codemap` / selection lint / opt-in flags) — use the best available, say what ran.

This is a reminder, not a workflow — it ends here. Pick the command above and go.

<!-- Rationale for this command's design: `references/reminder.md` (not needed at runtime). -->
