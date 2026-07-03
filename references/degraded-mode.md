# Degraded mode — policy

The PREMIUM panel is the full triple (Opus 4.8 + GPT-5.5 + Gemini 3.1 Pro). Gemini 3.1 Pro is provided
by Antigravity CLI (`agy`) by default; legacy `gemini` is only used when explicitly enabled. When an
external CLI/backend is missing the panel is **degraded** — and that must always be **explicit and
disclosed**, never silently faked. This is the skill's cardinal rule.

## Behavior (enforced by the scripts)

- `scripts/detect_panel.sh` reports the honest `PANEL_STATE`, `SLUG`, and `GEMINI_BACKEND` for the
  current machine. It never reports `PREMIUM` unless both `codex` and a valid Gemini backend are present.
- `scripts/assert_triple_panel.sh` is the gate for premium commands (`/fusion`, `/fusion-review`):
  - `codex` and a Gemini backend present → exit `0`, `PANEL_STATE=PREMIUM`.
  - a CLI/backend missing, **no override** → exit non-zero (`10` no codex, `11` no Gemini backend,
    `12` neither) with a remediation message. The command STOPS.
  - a CLI missing **and `FUSION_ALLOW_DEGRADED=1`** → exit `0`, prints a loud `DEGRADED=1 MISSING=… ` banner
    and the actual `PANEL_STATE`. The run proceeds, knowingly degraded.

## Runtime degrade (exit 13)

The assert gate only proves the CLIs *existed at launch*. A panelist can still fail **during** the run —
rate limit, auth error, `FUSION_PANEL_TIMEOUT` (default 600s) kill, or an implausibly tiny output
(below `FUSION_MIN_OUTPUT_BYTES`, default 200 — an error banner is not an answer). When that happens and
`FUSION_ALLOW_DEGRADED` is not set, `run_panel.sh` / `run_triple_fusion.sh` write the manifest with the
honest `REALIZED_PANEL_STATE` and exit **13**. The orchestrator must then STOP, disclose the realized
state, and let the user choose: retry, or re-run accepting the degraded panel with
`FUSION_ALLOW_DEGRADED=1`. Exit 13 is never a silent continue.

## Recursion guard (exit 14)

A panelist must never convene its own panel — nested panels break the blindness invariant and can loop.
The runners stamp the panelist process tree with `FUSION_PANEL_CHILD=1`; every gate/runner script
refuses with exit **14** when it sees that marker. The Opus panelist (a spawned subagent, no env
inheritance) is bound by the instruction in `panel-prompt.md`: it answers directly and never invokes
fusion commands.

## The disclosure rule
Every panel answer's audit trail begins with the realized panel (provenance header in
`judge-rubric.md`): which `PANEL_STATE`/slug ran and which panelists participated. A degraded answer must
read as degraded. If degraded, also say how to enable PREMIUM (install the missing CLI/backend).

## Treating a dropped panelist
A panelist that's missing, errored, or was dropped is **absent** to the judge — never counted as silent
agreement. With one external CLI down, the panel is still a real (smaller) panel; with both down, it
degrades to `OPUS_ONLY` (two cold Opus runs), which is the floor — always available.

`FUSION_ALLOW_DEGRADED` is the operator's explicit escape hatch. It must always produce a visible banner;
it must never become a silent default.
