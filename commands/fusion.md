---
description: Fan a hard question out to the premium model panel (blind, parallel) and have Opus 4.8 judge and write the final answer.
argument-hint: [the hard question or task]
---

# /fusion

Turn one prompt into a **panel**: the same question goes to several models at once, each answering
**independently and blind**, then **Opus 4.8 judges** every answer and writes the final one. Use for
high-stakes research, design calls, and debugging where being confidently wrong is expensive. For quick
or low-stakes questions, answer directly — don't pay for a panel.

Load `references/panel-prompt.md` and `references/judge-rubric.md` before judging.

## Step 0 — Pick & assert the panel

```bash
bash <skill-root>/scripts/detect_panel.sh          # prints PANEL_STATE= and SLUG=
bash <skill-root>/scripts/assert_triple_panel.sh   # hard-fails unless PREMIUM, unless FUSION_ALLOW_DEGRADED=1
```

If `assert_triple_panel.sh` exits non-zero, STOP and tell the user which CLI is missing and how to enable
it (or to re-run with `FUSION_ALLOW_DEGRADED=1` to *knowingly* use a smaller panel). Record the resulting
`PANEL_STATE`; you will disclose it in the answer.

## Step 1 — Fan out, blind and in parallel

Build each panelist's prompt as the **user's task verbatim** plus the short independent-expert
instruction from `panel-prompt.md`. Do **not** assign lenses/personas or pre-digest the task. Write the
prompt to a file, then launch all panelists concurrently in one turn:

Run the CLI panelists with your **Bash tool in background mode** (`run_in_background: true`) — the script
waits on both CLIs internally, so background mode is what lets the call return immediately instead of
blocking your turn:

```bash
bash <skill-root>/scripts/run_triple_fusion.sh /tmp/pfo_fusion_prompt.txt /tmp/pfo_fusion_out medium
```

In the **same turn** (while that runs), spawn the **Opus 4.8 panelist** yourself via the `Agent`/`Task`
tool (`subagent_type: general-purpose`) with the *same* prompt — so all three run at once. The script
cannot spawn Opus, and **only you can judge** (the pipeline can't be reversed). For `OPUS_ONLY`, spawn
**two** cold Opus subagents. When the background task finishes, read `/tmp/pfo_fusion_out/manifest.txt`
and judge/disclose its **`REALIZED_PANEL_STATE`** (a failed/absent CLI panelist is treated as absent,
never silent agreement). Never paste one panelist's output into another's prompt.

## Step 2 — Judge (Opus 4.8)

When every panelist has returned, follow `references/judge-rubric.md`. **Classify the deliverable first:**
- **Artifact** (code/config/schema) → **Track A**: run each candidate, merge what demonstrably works onto
  the stronger base, run the merged result, fix until it passes.
- **Research/analysis** → **Track B**: the five sections — Consensus, Contradictions, Partial coverage,
  Unique insights, Blind spots — then a grounded final answer.

A panelist that failed or was dropped is treated as **absent**, never as silent agreement. Weight a
panelist that ran code or read a primary source over one reasoning from memory.

## Step 3 — Present

Lead with the **final deliverable**, then the audit trail (Track A: what each candidate did when run +
merge rationale + what you verified; Track B: the five-section analysis). **Disclose the realized
`PANEL_STATE`** and which panelists participated. If the panel degraded, say so and how to enable PREMIUM.
