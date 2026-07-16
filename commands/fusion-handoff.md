---
description: Emit a Handoff Capsule — a self-contained file (Purpose, Summary, Files Created/Changed, Verification Results, Known Risks, Next Steps) that lets the next agent or human resume without the conversation.
argument-hint: [what to hand off — a finished task, a plan, or a review]
---

# /fusion-handoff

Write a **Handoff Capsule**: a single file that captures the durable state of a piece of work so the next
agent or human can pick it up **without the chat history**. The conversation is ephemeral; the capsule is
the memory.

Load `references/handoff-capsule.md` (the skeleton + acceptance bar).

## Step 1 — Classify intent, strip meta-framing

Classify what's being handed off: **Question**, **Plan**, or **Review** (a Review capsule's body should
contain the literal phrase "code review"). Strip any "make me a handoff for X" meta-framing down to the
**real subject X**.

## Step 2 — Compose the capsule

Write to a unique repo-local file `handoffs/<YYYY-MM-DD>-<HH-MM>-<type>-<slug>.md` with these sections
(see `references/handoff-capsule.md`):

- **Purpose** — the goal in the codebase's own terms (1–2 sentences).
- **Contract Snapshot** — for a Plan/orchestrate handoff: the contract path, objective vs current state,
  per-item statuses, blockers / `[incomplete]` payloads, and escape-hatch state (else "none — standalone").
  This is what lets the live state survive a compaction.
- **Summary** — what was done / decided, in your own voice.
- **Files Created / Changed** — paths, each with a one-line "what & why" and `file:line` where useful.
- **Verification Results** — what you ran and what you observed (commands + outcomes). Report failures and
  skips honestly; mark anything unverified. **If the handed-off work includes code that will be
  committed/pushed, run the ship-gate first** and record its result here:
  `bash <skill-root>/scripts/preflight.sh commit` (or `push <base>`) — whitespace + staged-index secret
  scan, honest-degrade to a regex floor without `gitleaks`. Note the realized `PREFLIGHT_SECRETSCAN`; a
  `FAIL` is a known risk the next person must clear, not something to bury. If the secret-scan helper can't run, disclose it and scan manually; never skip silently.
- **Known Risks** — what's fragile, assumed, or unproven; anything that could bite the next person.
- **Next Steps** — the concrete next actions, ordered; open questions **only if** they block or shape the
  next move.

**Merge, don't append:** extract the architectural bones in your own words — **no transcript dumps, no
raw subagent output**. A reader unfamiliar with the area must be able to execute from it.

## Step 3 — Present

Print the capsule path and the ready-made pointer sentence the next agent uses verbatim:

> Read the handoff capsule at `<path>` before starting; it has the purpose, what's done, what's verified,
> the risks, and the next steps.

Single-model — a handoff is summarization; one good pass suffices.
