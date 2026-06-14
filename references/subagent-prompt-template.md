# Scoped subagent brief — template

Scope is the orchestrator's most important job. A subagent can see the whole plan but doesn't know which
part is *its* job unless you say so. A brief **orients, it does not direct** — pass forward **discoveries,
not instructions**.

## Fill-in template

```
Read the plan at <PLAN_PATH> first. Your job is **<ITEM N: short name>**.
Items <X, Y> are handled separately — do not touch them.

Goal: <1–2 sentences>
Done-when: <the concrete completion condition for this item>
Key files: <paths where the work happens; mark new files>
Discoveries (things you wouldn't easily find yourself):
  - <e.g. "the retry pattern to mirror is in APIClient.swift:40-90">
  - <e.g. "config is loaded in settings.py, not env vars">

Boundary: Do ONLY <X>. Stop when <X> is done. Do not refactor adjacent code.
Do the work yourself — do NOT spawn your own subagents.
When done, report: the files you changed and one line of evidence per Done-when.
```

## Include / don't-include

**Include:** the goal, the relevant file paths, and discoveries from planning the agent couldn't find on
its own. For a small task, add "skip deep review / oracle steps."

**Don't include:** project conventions already in `CLAUDE.md`/`AGENTS.md` (agents read those themselves),
step-by-step micro-instructions, code the agent can read itself, or any user↔orchestrator chatter.

## Two-conversations firewall
The orchestrator↔user channel (preferences, meta-feedback) is **separate** from the orchestrator↔worker
channel (pure technical task). Translate the *actionable* part of user steering into the brief; never
paste user commentary verbatim into a worker brief. If an in-flight brief already leaked such chatter,
cancel it and re-send clean.

## Sibling-warning (verbatim — REQUIRED for every parallel dispatch)

When fan-out > 1, every concurrent brief MUST include this exact block:

```
Another agent is concurrently working on <sibling task> in <modules>. Avoid modifying files in that
area. If you find yourself blocked by or conflicting with that work, stop and report back rather than
pushing through.
```

## Scoping patterns (pick by size)
- **Paraphrase** — small self-contained work: describe it inline; don't pass the whole plan.
- **Point-to-a-section** — broader work: "Read the plan at `<path>`; your job is item 2; items 1 and 3 are
  handled separately."
- **State-the-boundary** — "Do only X. Stop when X is done." (Beats hoping the agent infers scope.)
