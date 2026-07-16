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

Write to a unique repo-local file `handoffs/<YYYY-MM-DD>-<HH-MM>-<type>-<slug>.md` with the sections
defined in `handoff-capsule.md` (name them in one line): **Purpose · Contract Snapshot · Summary · Files
Created/Changed · Verification Results · Known Risks · Next Steps**. Section bodies and acceptance bar
live only in that reference.

**Ship-gate when handing off code that will be committed/pushed** — run first and record the result under
Verification Results:

```bash
bash <skill-root>/scripts/preflight.sh commit   # or: push <base>
```

Whitespace + staged-index secret scan, honest-degrade to a regex floor without `gitleaks`. Note the
realized `PREFLIGHT_SECRETSCAN`; a `FAIL` is a known risk the next person must clear, not something to bury.
If the secret-scan helper can't run, disclose it and scan manually; never skip silently.

**Merge, don't append:** extract the architectural bones in your own words — **no transcript dumps, no
raw subagent output**. A reader unfamiliar with the area must be able to execute from it.

## Step 3 — Present

Print the capsule path and the ready-made pointer sentence the next agent uses verbatim:

> Read the handoff capsule at `<path>` before starting; it has the purpose, what's done, what's verified,
> the risks, and the next steps.

Single-model — a handoff is summarization; one good pass suffices.
