---
description: Maximum-quality v2 workflow: blind first round, contradiction matrix, targeted probes, verifier, then final Opus synthesis.
argument-hint: [hard task requiring maximum quality]
---

# /fusion-ultra

Use this when the user wants maximum quality or the task is high-risk, hard to reverse, or likely to
benefit from a second round. `/fusion-ultra` is not "three long answers plus a longer merge." It spends
the second round only on the uncertainty that matters.

Load `references/ultra-two-round.md`, `references/contradiction-matrix.md`,
`references/panel-prompt.md`, `references/judge-rubric.md`, and `references/verifier-contract.md`.

## Step 1 - Round 0 Context

Build a compact evidence/context packet. For private code, include code in the prompt packet but instruct
panelists: "web search public facts only; do not search with proprietary code."

## Step 2 - Round 1 Blind Panel (wide: 4 panelists)

Run the external panel with the v2 runner. Ultra's round 1 is **wide**: the premium triple plus a
second cold Opus run — same-model self-consistency on top of cross-family diversity, and Opus-vs-Opus
disagreement becomes an extra confidence signal for the judge.

```bash
out=$(mktemp -d "${TMPDIR:-/tmp}/fusion-ultra.XXXXXX")   # fresh dir — never a fixed /tmp path
# write the panel prompt to "$out/prompt.md", then:
bash <skill-root>/scripts/run_panel.sh --mode ultra_two_round "$out/prompt.md" "$out" high
```

Hard-fail unless PREMIUM or `FUSION_ALLOW_DEGRADED=1`; on exit 13 STOP and disclose the realized `PANEL_STATE` from the manifest — never silently continue (`references/degraded-mode.md`).

In the same turn, spawn **two cold Opus panelists** with the same prompt (the manifest's
`OPUS_PANELISTS=2` confirms the count). Ask every panelist for:

- answer / recommendation;
- assumptions;
- evidence used;
- likely failure modes;
- what would change my mind.

**Checkpoint before ending this turn: BOTH the backgrounded Bash call AND the Opus spawn must have gone out in this same message; if only one did, launch the other immediately and disclose in the audit trail that the panel was not fully concurrent.**

## Step 3 - Contradiction Matrix

As judge, build the contradiction matrix from `references/contradiction-matrix.md`: consensus,
contradictions, blind spots, and targeted probes. Do not ask models to rewrite full answers in round 2.

## Step 4 - Targeted Probes

Assign only the unresolved, high-information probes:

- Codex: code trace, tests, patch feasibility, concrete implementation checks.
- Gemini/Antigravity: long-context cross-check, missing constraints, alternate framing.
- Opus: synthesis, risk framing, final decision.

Run deterministic verifiers when available. Deterministic verifiers per ecosystem are catalogued in
`references/verifier-recipes.md`.

## Step 5 - Final

Lead with the final deliverable. Then disclose: realized panel state/mode, contradiction matrix summary,
targeted probes, verifier results, residual uncertainty, and run id.

If `$ARGUMENTS` contains `--export`, also persist the final deliverable to a repo-local file and return
the path so the next step can consume it by path (see `references/export.md`):

```bash
p=$(bash <skill-root>/scripts/fusion_export.sh path ultra "<the question>")  # -> .fusion/exports/…
```

Run the `safety.md` secret scan before writing. Present both the answer and the path.
