#!/usr/bin/env bash
# detect_panel.sh — report which panelist CLIs are installed and the richest HONEST panel.
#
# fusion-deck fans a prompt out to a panel of models in parallel, then Opus 4.8
# judges. Opus 4.8 is ALWAYS a panelist (via the Agent/Task tool, in-process subagents) and is
# ALWAYS the judge — it needs no CLI. This script only probes the EXTERNAL panelist CLIs
# (GPT-5.6 Sol via `codex`, Gemini 3.1 Pro via Antigravity CLI or explicit legacy `gemini`) and reports the
# richest panel the machine
# can currently support.
#
# It NEVER pretends a missing CLI is present: a degraded machine is reported as DEGRADED_* or
# OPUS_ONLY, never as PREMIUM. Silently faking the premium triple is the cardinal sin of this skill.
#
# Output: human-readable lines + two greppable lines the orchestrator keys on:
#   PANEL_STATE=<PREMIUM|DEGRADED_OPUS_GPT5|DEGRADED_OPUS_GEMINI|OPUS_ONLY>
#   SLUG=<opus4.8-gpt5.6sol-gemini3.1pro|opus4.8-gpt5.6sol|opus4.8-gemini3.1pro|opus4.8-4.8>
#
# The human "panelist availability" banner prints only when the state is NOT PREMIUM (remediation
# matters) or when --verbose is passed. Greppable PANEL_STATE=/SLUG=/GEMINI_BACKEND= always print.

set -uo pipefail

verbose=false
for arg in "$@"; do
  case "$arg" in
    --verbose|-v) verbose=true ;;
    -h|--help)
      echo "Usage: detect_panel.sh [--verbose]"
      exit 0
      ;;
  esac
done

# Prefer bash param expansion over external `dirname` so a stripped PATH still works for
# degraded-path probes (PATH without panelist CLIs, system bins optional).
_self="${BASH_SOURCE[0]}"
here="$(cd "${_self%/*}" && pwd)"
. "$here/gemini_backend.sh"

# A CLI counts as available only if it's on PATH AND actually runs (`--version`) — being on PATH is not
# the same as a working install. (Correct model/auth still needs a real call; see degraded-mode.md.)
# Bound the probe so a hung CLI can never wedge the gate. Portable: timeout/gtimeout if present, else a
# bash watchdog (macOS ships no `timeout`).
have() { fusion_cli_available "$1"; }

codex_ok=false; gemini_ok=false
have codex  && codex_ok=true
fusion_detect_gemini_backend && gemini_ok=true

if   $codex_ok && $gemini_ok; then state="PREMIUM";              slug="opus4.8-gpt5.6sol-gemini3.1pro"
elif $codex_ok;                then state="DEGRADED_OPUS_GPT5";   slug="opus4.8-gpt5.6sol"
elif $gemini_ok;               then state="DEGRADED_OPUS_GEMINI"; slug="opus4.8-gemini3.1pro"
else                                state="OPUS_ONLY";            slug="opus4.8-4.8"
fi

show_banner=false
if $verbose || [ "$state" != "PREMIUM" ]; then
  show_banner=true
fi

if $show_banner; then
  echo "panelist availability (Opus 4.8 is always a panelist + the judge, via Agent/Task subagents):"
  echo "  opus4.8       : yes (Agent subagents — always available)"
  printf "  gpt5.6sol        : %s (codex CLI)\n"  "$([ "$codex_ok"  = true ] && echo yes || echo NO)"
  if $gemini_ok; then
    printf "  gemini3.1pro  : yes (%s via %s)\n" "${FUSION_GEMINI_BACKEND_RESOLVED:-?}" "${FUSION_GEMINI_BACKEND_BINARY:-?}"
  else
    printf "  gemini3.1pro  : NO (%s)\n" "${FUSION_GEMINI_BACKEND_REASON:-not available}"
  fi
  echo

  case "$state" in
    PREMIUM) echo "panel: PREMIUM triple available (Opus 4.8 + GPT-5.6 Sol + Gemini 3.1 Pro)." ;;
    *)       echo "panel: $state — NOT the premium triple. Install the missing CLI(s) to enable PREMIUM:"
             $codex_ok  || echo "    - codex  (GPT-5.6 Sol):       https://developers.openai.com/codex"
             $gemini_ok || echo "    - agy    (Gemini 3.1 Pro): https://antigravity.google/docs/cli-install" ;;
  esac
  echo

  echo "recommended panel: $slug"
fi

echo "PANEL_STATE=$state"
echo "SLUG=$slug"
echo "GEMINI_BACKEND=${FUSION_GEMINI_BACKEND_RESOLVED:-none}"
