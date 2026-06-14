# Scoped subagent brief (example)

> Example brief `/fusion-orchestrate` dispatches for Item 2 of the health-endpoint contract. Point-to-a-
> section + explicit boundary. See `references/subagent-prompt-template.md`.

```
Read the plan at docs/plans/add-health-2026-06-14.md first. Your job is **Item 2: register the route**.
Items 1 (handler) and 3 (test) are handled separately — do not touch them.

Goal: Register GET /health in the router, wired to the Item 1 handler.
Done-when: app/router.py maps "/health" to health(); curl -s localhost:8080/health returns 200.
Key files: app/router.py
Discoveries (you wouldn't easily find these yourself):
  - Routes are a list of (path, handler) tuples in app/router.py:12-30; append there.
  - The handler from Item 1 is app.handlers.health.health (already on disk).

Boundary: Do ONLY the route registration. Stop when /health resolves. Do not refactor the router.
Do the work yourself — do NOT spawn your own subagents.
When done, report: the files you changed and one line of evidence (the curl result).
```

> If Item 1 and Item 2 were dispatched in parallel (they are not here — Item 2 depends on Item 1), each
> brief would also carry the verbatim sibling-warning from the template.
