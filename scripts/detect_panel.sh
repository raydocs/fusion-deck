#!/usr/bin/env bash
# detect_panel.sh — report which panelist CLIs are installed and the richest HONEST panel.
#
# fusion-deck fans a prompt out to a panel of models in parallel, then Opus 4.8
# judges. Opus 4.8 is ALWAYS a panelist (via the Agent/Task tool, in-process subagents) and is
# ALWAYS the judge — it needs no CLI. This script only probes the EXTERNAL panelist CLIs
# (GPT-5.5 via `codex`, Gemini 3.1 Pro via `gemini`) and reports the richest panel the machine
# can currently support.
#
# It NEVER pretends a missing CLI is present: a degraded machine is reported as DEGRADED_* or
# OPUS_ONLY, never as PREMIUM. Silently faking the premium triple is the cardinal sin of this skill.
#
# Output: human-readable lines + two greppable lines the orchestrator keys on:
#   PANEL_STATE=<PREMIUM|DEGRADED_OPUS_GPT5|DEGRADED_OPUS_GEMINI|OPUS_ONLY>
#   SLUG=<opus4.8-gpt5.5-gemini3.1pro|opus4.8-gpt5.5|opus4.8-gemini3.1pro|opus4.8-4.8>

set -uo pipefail

# A CLI counts as available only if it's on PATH AND actually runs (`--version`) — being on PATH is not
# the same as a working install. (Correct model/auth still needs a real call; see degraded-mode.md.)
# Bound the probe so a hung CLI can never wedge the gate. Portable: timeout/gtimeout if present, else a
# bash watchdog (macOS ships no `timeout`).
_bounded() {
  if command -v timeout  >/dev/null 2>&1; then timeout  5 "$@"; return $?; fi
  if command -v gtimeout >/dev/null 2>&1; then gtimeout 5 "$@"; return $?; fi
  "$@" & _bp=$!; ( sleep 5; kill -9 "$_bp" 2>/dev/null ) & _bw=$!
  wait "$_bp" 2>/dev/null; _brc=$?; kill "$_bw" 2>/dev/null; wait "$_bw" 2>/dev/null; return "$_brc"
}
have() { command -v "$1" >/dev/null 2>&1 && _bounded "$1" --version >/dev/null 2>&1; }

codex_ok=false; gemini_ok=false
have codex  && codex_ok=true
have gemini && gemini_ok=true

echo "panelist availability (Opus 4.8 is always a panelist + the judge, via Agent/Task subagents):"
echo "  opus4.8       : yes (Agent subagents — always available)"
printf "  gpt5.5        : %s (codex CLI)\n"  "$([ "$codex_ok"  = true ] && echo yes || echo NO)"
printf "  gemini3.1pro  : %s (gemini CLI)\n" "$([ "$gemini_ok" = true ] && echo yes || echo NO)"
echo

if   $codex_ok && $gemini_ok; then state="PREMIUM";              slug="opus4.8-gpt5.5-gemini3.1pro"
elif $codex_ok;                then state="DEGRADED_OPUS_GPT5";   slug="opus4.8-gpt5.5"
elif $gemini_ok;               then state="DEGRADED_OPUS_GEMINI"; slug="opus4.8-gemini3.1pro"
else                                state="OPUS_ONLY";            slug="opus4.8-4.8"
fi

case "$state" in
  PREMIUM) echo "panel: PREMIUM triple available (Opus 4.8 + GPT-5.5 + Gemini 3.1 Pro)." ;;
  *)       echo "panel: $state — NOT the premium triple. Install the missing CLI(s) to enable PREMIUM:"
           $codex_ok  || echo "    - codex  (GPT-5.5):       https://developers.openai.com/codex"
           $gemini_ok || echo "    - gemini (Gemini 3.1 Pro): https://github.com/google-gemini/gemini-cli" ;;
esac
echo

echo "recommended panel: $slug"
echo "PANEL_STATE=$state"
echo "SLUG=$slug"
