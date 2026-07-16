#!/usr/bin/env bash
# run_triple_fusion.sh — compatibility shim over run_panel.sh --mode premium_triple.
#
# Historical entry point for the two external CLI panelists (GPT-5.6 Sol + Gemini 3.1 Pro)
# launched blind and in parallel. The single implementation is run_panel.sh (v2), which
# preserves the compat contract:
#   - recursion guard BEFORE any side effect (exit 14)
#   - stale-output clear of the same panel artifacts
#   - assert gate before launch (exit 10/11/12; honors FUSION_ALLOW_DEGRADED)
#   - background parallel launch of codex + gemini
#   - atomic manifest write (temp + rename) with ledger append
#   - runtime honest-degrade gate (exit 13 without override; exit 1 if both CLIs fail)
#
# Manifest schema is the v2 unified form (REQUESTED_PANEL_MODE / REALIZED_PANEL_MODE /
# REALIZED_PANEL_STATE / CLAUDE_PANELISTS=…). The legacy INTENDED_PANEL_STATE and
# CLAUDE_PANELIST=added-by-orchestrator fields are not written.
#
# Usage:
#   run_triple_fusion.sh <prompt_file> <out_dir> [reasoning_effort]
#
# IMPORTANT — what this script does NOT do:
#   It does NOT spawn the Claude (the session model) panelist, and it does NOT judge. Only the Claude Code
#   orchestrator can spawn a Claude panelist and only Claude judges/synthesizes.

set -uo pipefail
# Resolve this script's directory with bash builtins only (no dirname) so PATH=/nonexistent
# gate probes still find the sibling run_panel.sh.
_self="${BASH_SOURCE[0]}"
_dir="${_self%/*}"
[ "$_dir" = "$_self" ] && _dir="."
here="$(cd "$_dir" && pwd)"
# Use $BASH (absolute path of this interpreter) so PATH=/nonexistent probes still work.
exec "${BASH:-bash}" "$here/run_panel.sh" --mode premium_triple "$@"
