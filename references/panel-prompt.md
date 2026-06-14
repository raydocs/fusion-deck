# The panel

Fusion's power is **independent answers, synthesized** — not a clever prompt or assigned personas. The
same question goes to several models at once; each works it cold with no knowledge of the others; the
judge fuses their answers. Independent agreement is high-confidence; independent disagreement is exactly
the signal worth surfacing.

## No lenses, no personas

Do **not** assign panelists roles or stances (skeptic, optimizer, first-principles, …). That biases *how*
each reasons and corrupts the independence that makes the panel work. Pass every panelist the user's task
**verbatim** and let each answer it straight. The diversity is already free: the same prompt run
independently yields different reasoning paths, tool calls, and sources — even two cold runs of the *same*
model diverge enough that synthesizing them beats running it once. You **harvest** diversity from
independence; you don't manufacture it.

## The blindness invariant (enforce by construction)

Panelists must **never** see each other's work, and the orchestrator must not pre-digest the task before
handing it over. Enforce this mechanically, not just by intent:

- Every panelist gets the **same prompt file** and writes to a **separate output file**
  (`scripts/run_triple_fusion.sh` does this for the CLI panelists; spawn the Opus panelist with the same
  prompt and let it return its own answer).
- Never paste one panelist's output (or status) into another's prompt.
- The Opus panelist's brief contains **only the user's question** — not the conversation, not the other
  panelists' outputs, not your own notes.
- The **judge runs strictly after all panelists return.** The pipeline can't be reversed: panelist models
  can't call back out to spawn Opus, so **Opus 4.8 is always the judge/driver.**

## The exact prompt each panelist gets

The user's task **verbatim**, plus this short instruction (nothing more — no framing that nudges a
conclusion):

> You are one of several independent experts answering this task. Research with web search and bash as
> useful, then return a **complete, self-contained answer**. You will not see the other experts' answers
> and they will not see yours.

## Panel composition per PANEL_STATE / slug

- `PREMIUM` (`opus4.8-gpt5.5-gemini3.1pro`) — Opus 4.8 + GPT-5.5 (codex) + Gemini 3.1 Pro (gemini), blind
  and parallel, then Opus judges.
- `DEGRADED_OPUS_GPT5` (`opus4.8-gpt5.5`) — Opus 4.8 + GPT-5.5.
- `DEGRADED_OPUS_GEMINI` (`opus4.8-gemini3.1pro`) — Opus 4.8 + Gemini 3.1 Pro.
- `OPUS_ONLY` (`opus4.8-4.8`) — the same prompt run as **two** independent Opus 4.8 subagents, then judged.

In every case Opus 4.8 also judges, and the judge is kept separate from the panelists (panelists are
spawned; the orchestrator judges) so the synthesis reads the answers fresh rather than defending one it
wrote. A degraded panel is always disclosed in the final answer — never presented as PREMIUM.
