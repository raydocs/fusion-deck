# Handoff Capsule

A Handoff Capsule is a single self-contained file that lets the next agent or human resume work **without
the conversation**. The chat is ephemeral; the capsule is the durable memory.

## File path
`handoffs/<YYYY-MM-DD>-<HH-MM>-<type>-<slug>.md`, where `type` ∈ {`question`, `plan`, `review`}. Classify
intent first, and strip any "make me a handoff for X" meta-framing down to the real subject X.

## Skeleton (fixed sections)

```
# Handoff: <slug>   (<type>)

## Purpose
<the goal in the codebase's own terms — 1–2 sentences>

## Contract Snapshot
For a Plan/orchestrate handoff, point at the live contract so state survives compaction (else "none — standalone handoff"):
- Contract: `docs/plans/<topic>-<DATE>.md`
- Objective vs Current State: <one line each — what should become true vs what is true now>
- Work-item statuses: <Item 1 [done] · Item 2 [doing] · Item 3 [blocked] …>
- Blockers / [incomplete] payload: <reason / proof / attempted / impact / next-decision — or "none">
- Escape hatch: <triggered? which condition — or "not triggered">

## Summary
<what was done / decided, in your own voice — the architectural bones>

## Files Created / Changed
- `path/one` — <what & why> (<file:line> where useful)
- `path/two` — <what & why>

## Verification Results
<commands you ran and what you observed; report failures and skips honestly; mark anything unverified>

## Known Risks
<what's fragile, assumed, or unproven; anything that could bite the next person>

## Next Steps
1. <concrete next action>
2. <…>
<open questions ONLY if they block or shape the next move>
```

A **Review** capsule's body should contain the literal phrase **"code review"** (a useful convention that
signals diff-analysis intent to downstream tooling).

## Acceptance bar
- **Self-contained:** a reader unfamiliar with the area can pick it up and execute.
- **Merge, don't append:** extract the bones in your own words. **No transcript dumps, no raw subagent
  output.** Delegate evidence-gathering to subagents; you write.
- **Honest:** Verification Results states what actually ran and what failed or was skipped — never claims
  "done" for unverified work.
- **Concise:** the capsule gets *shorter* as the work matures, not longer.

## Pointer sentence
End by printing the ready-made sentence the next agent uses verbatim:

> Read the handoff capsule at `<path>` before starting; it has the purpose, what's done, what's verified,
> the risks, and the next steps.

See `examples/handoff.example.md`.
