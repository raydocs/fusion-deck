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
bash <skill-root>/scripts/detect_panel.sh          # prints PANEL_STATE=, SLUG=, and GEMINI_BACKEND=
bash <skill-root>/scripts/assert_triple_panel.sh   # hard-fails unless PREMIUM, unless FUSION_ALLOW_DEGRADED=1
```

Hard-fail unless PREMIUM or `FUSION_ALLOW_DEGRADED=1`; on exit 13 STOP and disclose the realized `PANEL_STATE` from the manifest — never silently continue (`references/degraded-mode.md`).

## Step 1 — Fan out, blind and in parallel

Build each panelist's prompt as the **user's task verbatim** plus the short independent-expert
instruction from `panel-prompt.md`. Do **not** assign lenses/personas or pre-digest the task. Write the
prompt to a file, then launch all panelists concurrently in one turn:

Run the CLI panelists with your **Bash tool in background mode** (`run_in_background: true`) — the script
waits on both CLIs internally, so background mode is what lets the call return immediately instead of
blocking your turn. **Use a fresh `mktemp -d` out dir, never a fixed path** — fixed paths make two
concurrent sessions clobber each other's in-flight outputs (and are world-readable on shared hosts):

```bash
out=$(mktemp -d "${TMPDIR:-/tmp}/fusion.XXXXXX")
# write the panel prompt to "$out/prompt.md", then:
bash <skill-root>/scripts/run_triple_fusion.sh "$out/prompt.md" "$out" medium
```

In the **same turn** (while that runs), spawn the **Opus 4.8 panelist** yourself via the `Agent`/`Task`
tool (`subagent_type: general-purpose`) with the *same* prompt — so all three run at once. The script
cannot spawn Opus, and **only you can judge** (the pipeline can't be reversed). For `OPUS_ONLY`, spawn
**two** cold Opus subagents.

**Checkpoint before ending this turn: BOTH the backgrounded Bash call AND the Opus spawn must have gone out in this same message; if only one did, launch the other immediately and disclose in the audit trail that the panel was not fully concurrent.**

If `$ARGUMENTS` contains `--wide`, run the **wide panel** instead: launch the CLIs via
`run_panel.sh --mode premium_wide` and spawn **two** cold Opus panelists (4 answers total). Same cost
class as ultra's round 1; use when the user wants maximum quality on a single-round question. Check
`OPUS_PANELISTS` in the manifest — it tells you how many Opus panelists to spawn in every mode. When the background task finishes, read `"$out"/manifest.txt`
and judge/disclose its **`REALIZED_PANEL_STATE`** (a failed/absent CLI panelist is treated as absent,
never silent agreement). The script also writes `ledger.env` with `RUN_ID` /
`RUN_DIR` for the local v2 run ledger. Never paste one panelist's output into another's prompt.

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

If `$ARGUMENTS` contains `--export`, also persist the final deliverable to a repo-local file and return
the path so the next step can consume it by path (see `references/export.md`):

```bash
p=$(bash <skill-root>/scripts/fusion_export.sh path fusion "<the question>")  # -> .fusion/exports/…
```

Run the `safety.md` secret scan before writing. Present both the answer and the path.
