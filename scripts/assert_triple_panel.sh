#!/usr/bin/env bash
# assert_triple_panel.sh — HARD GATE for premium mode (compat wrapper).
#
# In premium mode the panel MUST be the full triple: Opus 4.8 (always present) + GPT-5.6 Sol (codex)
# + Gemini 3.1 Pro (Antigravity CLI by default, legacy gemini only when explicit). This script enforces
# that the codex CLI and a Gemini backend are present and exits
# non-zero with an actionable remediation message if either is missing — so a caller can NEVER
# silently downgrade to a smaller panel while telling the user it ran "premium fusion."
#
# Escape hatch (qiaomu discipline): an operator who KNOWINGLY wants to proceed with a smaller panel
# sets FUSION_ALLOW_DEGRADED=1. Then the script does NOT fail — it prints a loud DEGRADED banner and
# exits 0 so wrappers proceed — but the degrade is now explicit and recorded, never silent.
#
# Exit codes:
#   0   premium triple confirmed (codex AND gemini present)  — OR  degrade explicitly allowed
#   10  codex (GPT-5.6 Sol) missing,  premium required (no override)
#   11  gemini (Gemini 3.1 Pro) missing, premium required (no override)
#   12  both codex and Gemini backend missing, premium required (no override)
#   2   usage error
#   14  recursive fusion invocation blocked (FUSION_PANEL_CHILD=1)
#
# On a 0-exit it always prints the resulting PANEL_STATE so callers can branch and disclose it.
#
# Implementation: thin compat wrapper over assert_panel.sh --mode premium_triple (Batch 9).

set -uo pipefail
# Resolve this script's directory with bash builtins only (no dirname) so PATH=/nonexistent
# smoke/gate probes still find the sibling assert_panel.sh.
_self="${BASH_SOURCE[0]}"
_dir="${_self%/*}"
[ "$_dir" = "$_self" ] && _dir="."
here="$(cd "$_dir" && pwd)"
case "${1:-}" in
  -h|--help)
    sed -n '2,24p' "$0"; exit 2 ;;
esac
# Use $BASH (absolute path of this interpreter) so PATH=/nonexistent probes still work.
exec "${BASH:-bash}" "$here/assert_panel.sh" --mode premium_triple "$@"
