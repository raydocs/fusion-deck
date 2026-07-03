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
If you hit a decision this brief doesn't resolve (an ambiguity, a trade-off, an unexpected conflict),
STOP and report it back — do not pick an interpretation and build on it.
When done, report: the files you changed and one line of evidence per Done-when.
```

## Include / don't-include

**Include:** the goal, the relevant file paths, and discoveries from planning the agent couldn't find on
its own. For a small task, add "skip deep review / oracle steps." If a judged plan or panel answer was
exported to a file (`references/export.md`), **point the brief at that path** ("Read the export at
`.fusion/exports/…` first") instead of pasting its content — a path is the cleanest discovery and doesn't
drift. If the contract has **Constraints / Boundaries** sections (`workflow-contract.md`), copy the
relevant ones into the brief verbatim — the worker must inherit the negative space (what not to change,
where not to write), not just the goal.

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

## The implementer works blind — resolve every decision

A dispatched subagent (and a blind panelist) **cannot ask you a clarifying question** — it runs from the
brief alone. So the brief, and the plan it points at, must leave nothing load-bearing unresolved. Borrowed
from RepoPrompt CE's architect constraint, state it plainly in the brief when the work has real design
latitude:

> The implementer will work from this brief without asking clarifying questions, so every design decision
> must be resolved, every touched component identified, and every behavioral change specified precisely.

If you *can't* resolve a decision, that's a signal the **plan** isn't ready — run the `/fusion-plan`
clarify gate first, don't push an ambiguous brief and hope. The mirror rule
(`orchestration-rubric.md`): judgment never delegates — a worker that meets an unresolved decision
mid-task surfaces it up and stops, because a plausible-but-wrong interpretation compounds in everything
built on top of it. And "resolve every decision" never means
*fabricate*: in an unfamiliar domain (medical, legal, financial, compliance, an unknown data format), the
resolution is to **inspect authoritative evidence or pause** — never invent a domain rule. Pair an
ambiguous high-risk item with a Discovery Gate (`commands/fusion-plan.md`), not a confident guess.

## Scoping patterns (pick by size)
- **Paraphrase** — small self-contained work: describe it inline; don't pass the whole plan.
- **Point-to-a-section** — broader work: "Read the plan at `<path>`; your job is item 2; items 1 and 3 are
  handled separately."
- **State-the-boundary** — "Do only X. Stop when X is done." (Beats hoping the agent infers scope.)
