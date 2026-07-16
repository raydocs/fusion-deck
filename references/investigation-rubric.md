# Investigation rubric

How `/fusion-investigate` finds a **root cause** — not a plausible story. The load-bearing idea is a
strict ordering: **evidence before hypotheses, hypotheses before the panel, the panel only by exception.**
You never assert a cause without a location, and the work ends at a durable, growing report file — it does
**not** implement the fix.

The investigator's stance mirrors the orchestrator's (`orchestration-rubric.md`): you plan, dispatch
read-only subagents, and adjudicate; the subagents read and reason but do **not** edit. Nothing in an
investigation changes product code.

## The report is the durable artifact

Open the report file in Step 1 and **grow it across the phases** — it is the state, not a write-up bolted
on at the end. Default path: `docs/investigations/<topic>-<DATE>.md` (`<topic>` a short slug of the
symptom; `<DATE>` ISO `YYYY-MM-DD`). A fresh subagent or a post-compaction you should be able to read it
and know exactly what's been ruled in, ruled out, and why. Append; don't rewrite history — an eliminated
hypothesis stays in the record with the evidence that killed it.

## Phase 1 — Triage & competing hypotheses

Restate the symptom as something checkable, then enumerate the suspects:

- **Observed vs expected** — the concrete behavior and what it should be instead. An error string, a wrong
  value, a missing row, a hang. No adjectives; the literal symptom.
- **Repro** — the smallest sequence that reliably triggers it, or honestly "intermittent / not yet
  reproduced." A cause you can't trigger is a cause you can't prove; say so.
- **Competing hypotheses (ranked)** — a *short set*, not one. The single most important discipline of the
  phase: write down **2–4 plausible causes**, ranked by prior likelihood, each phrased as a falsifiable
  claim ("X happens because Y returns null when Z"). One hypothesis is not a triage — it's a guess wearing
  a confidence it hasn't earned. Keep "what's observed" strictly separate from "what might cause it" so the
  symptom never silently becomes its own explanation.

Write all of this into the report under **Symptom** and **Hypotheses (ranked)** before gathering a single
fact.

## Phase 2 — Evidence gathering (read-only subagents → the ledger)

Dispatch `Explore` / `general-purpose` Task subagents to collect **facts with locations**. Use subagents
to keep your own context lean and to parallelize independent traces; for a large or unfamiliar surface,
build a pack first with `/fusion-context`. Each brief is read-only and scoped to one trace — the call
path, a suspect module, the git history of one file. Subagents do **not** spawn their own subagents and do
**not** edit (one level of fan-out, same as orchestration).

When you run **two or more investigators in parallel** on disjoint hypotheses, avoid write contention on
the report: give each one its **own sub-section to append to** — `## Findings: <hypothesis-or-trace>` —
rather than all writing the shared ledger at once. You merge their sub-sections into the single evidence
ledger when they return. One scaffolded report, per-agent sub-sections, no clobbering.

Everything they return lands in the **evidence ledger** — the spine of the report. Every entry is a
**fact anchored to a location**, never an opinion:

| kind | what it looks like |
| --- | --- |
| code | `file:line` of the offending statement / branch / signature |
| history | `git blame <file>:<line>` → commit; `git log -S<symbol>`; the introducing diff |
| runtime | the failing test name + assertion, a log line with its source, a stack frame |
| data | the actual value observed (`null`, off-by-one index, wrong enum) vs expected |

**The gate: no location, not evidence.** "It's probably the cache" is not a ledger entry; "`cache.go:88`
returns the stale entry because the TTL check uses `<=` not `<`" is. If a claim can't be pinned to a
`file:line` / commit / test, it stays a hypothesis, not a fact. When a failing test is the evidence, it
must be **discriminating** — failing because of *this* cause, not merely red (see
`references/probe-quality.md`).

After each batch, score every hypothesis against the ledger and record the verdict in the report:

- **supported** — a ledger fact is consistent with it and predicted by it.
- **weakened** — a fact is in tension with it but doesn't kill it.
- **eliminated** — a fact is incompatible with it. Write *why*, with the deciding location. An eliminated
  hypothesis is a result; keep it.

Iterate: surviving hypotheses generate the next traces to dispatch. Stop gathering when one cause is
decisively supported and the rest are eliminated — or when ≥2 genuinely survive and only judgment can
separate them (→ Phase 3).

## Phase 3 — Panel adjudication, BY EXCEPTION

Most investigations end here without a panel, and that is the **expected, cheaper path** — say so plainly.

- **Evidence is decisive** (one hypothesis supported, the rest eliminated by located facts) → **SKIP the
  panel.** Record in the report: "Panel skipped — evidence decisive; <cause> supported by <file:line>,
  alternatives eliminated." Spending a panel on a settled question is waste, not rigor — so this is the
  default; `--panel` overrides it when you want the cross-check on a high-stakes call anyway.
- **≥2 hypotheses genuinely survive the evidence** → fan the **competing theories + the evidence ledger**
  to the `/fusion` panel (read `commands/fusion.md`). This is a **Track B** adjudication (see
  `judge-rubric.md`): the panelists each weigh which cause the *ledger* supports; Claude (the session model) judges
  consensus / contradictions / which cause the evidence backs / blind spots — it does not re-investigate
  from memory. The question to the panel is "which of these located hypotheses does this evidence support,
  and what's missing?" — not "what's the bug?"
- `--panel` is the operator's explicit cross-check — it forces a panel even when you'd otherwise skip,
  whether to adjudicate close survivors or to stress-test a root cause that looks decisive. It cross-checks
  the conclusion drawn from the ledger; it never substitutes for the evidence-first phases.

**Disclose the realized `PANEL_STATE`** in the report exactly as the disclosure rule requires
(`degraded-mode.md`, `judge-rubric.md` provenance header): which panel actually ran and which panelists
participated. A panelist that's missing, errored, or was dropped is **ABSENT** — never counted as silent
agreement, and never lets a degraded panel read as PREMIUM. If the panel itself can't separate the
survivors, that's a result too: name the experiment (a new log, a failing test, a value to capture) that
*would* separate them, and lower the confidence accordingly.

## Phase 4 — Root-cause report (do NOT implement)

Finish the report so it stands on its own:

- **Root cause** — the single cause, stated as a falsifiable claim, with its **deciding `file:line`** (and
  introducing commit, if known). The whole report exists to earn this line; it must point at a location.
- **Hypotheses eliminated** — each rejected candidate with the located fact that killed it. This is what
  separates a root-cause report from a guess: the reader sees what was ruled out and how.
- **Confidence — honest** — **proven** (a located fact and/or a failing test nails it) vs **suspected**
  (consistent with the evidence but not yet demonstrated). Name the **residual uncertainty** out loud: what
  you couldn't reach, what would raise confidence, what assumption you're carrying. A suspected cause
  labeled "proven" is the investigation's version of faking green — don't.
- **Recommended fix(es)** — where and what, ranked; note risk and blast radius. **Do not implement here.**
  The handoff is `/fusion-plan` → `/fusion-orchestrate` to fix, or `/fusion-review` on the proposed fix.

## Principles

(Phase rules above are authoritative; these are the load-bearing one-liners only.)

- **Evidence over assertion; no location → not a root cause.** The ledger is the argument.
- **Panel by exception, disclosed honestly** — skip when decisive; ≥2 survivors or `--panel`; missing
  panelist = absent, never agreement.
- **Investigate, don't fix** — grounded cause + recommendation; confidence is proven vs suspected.
