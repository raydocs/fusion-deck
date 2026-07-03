#!/usr/bin/env bash
# assert_triple_panel.sh — HARD GATE for premium mode.
#
# In premium mode the panel MUST be the full triple: Opus 4.8 (always present) + GPT-5.5 (codex)
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
#   10  codex (GPT-5.5) missing,  premium required (no override)
#   11  gemini (Gemini 3.1 Pro) missing, premium required (no override)
#   12  both codex and Gemini backend missing, premium required (no override)
#   2   usage error
#
# On a 0-exit it always prints the resulting PANEL_STATE so callers can branch and disclose it.

set -uo pipefail

# Recursion guard: a panelist process must never convene its own panel (blindness invariant + loop risk).
if [ "${FUSION_PANEL_CHILD:-0}" = "1" ]; then
  echo "[assert_triple_panel] recursive fusion invocation blocked: this process is already a panelist (FUSION_PANEL_CHILD=1)." >&2
  echo "[assert_triple_panel] panelists answer directly; only the outer orchestrator convenes panels." >&2
  exit 14
fi

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/gemini_backend.sh"

case "${1:-}" in
  -h|--help)
    sed -n '2,30p' "$0"; exit 2 ;;
esac

# A CLI counts as available only if it's on PATH AND actually runs (`--version`); presence != working.
# (Correct model/auth still needs a real call — see degraded-mode.md; the manifest logs resolved models.)
# Bound the probe so a hung CLI can never wedge the gate. Portable: timeout/gtimeout if present, else a
# bash watchdog (macOS ships no `timeout`).
have() { fusion_cli_available "$1"; }

codex_ok=false; gemini_ok=false
have codex  && codex_ok=true
fusion_detect_gemini_backend && gemini_ok=true

missing=""
$codex_ok  || missing="${missing}codex "
$gemini_ok || missing="${missing}gemini-backend "
missing="${missing% }"

if $codex_ok && $gemini_ok; then
  echo "[assert_triple_panel] OK — premium triple available (Opus 4.8 + GPT-5.5 + Gemini 3.1 Pro)."
  echo "PANEL_STATE=PREMIUM"
  echo "GEMINI_BACKEND=$FUSION_GEMINI_BACKEND_RESOLVED"
  exit 0
fi

# At least one external CLI is missing.
if [ "${FUSION_ALLOW_DEGRADED:-0}" = "1" ]; then
  if   $codex_ok;  then state="DEGRADED_OPUS_GPT5"
  elif $gemini_ok; then state="DEGRADED_OPUS_GEMINI"
  else                  state="OPUS_ONLY"
  fi
  {
    echo "############################################################"
    echo "# DEGRADED PANEL (FUSION_ALLOW_DEGRADED=1) — NOT PREMIUM    #"
    echo "# missing: ${missing:-none}"
    echo "# proceeding with: $state"
    echo "# The final answer MUST disclose this is a degraded panel.  #"
    echo "############################################################"
  } >&2
  echo "DEGRADED=1"
  echo "MISSING=$missing"
  echo "PANEL_STATE=$state"
  echo "GEMINI_BACKEND=${FUSION_GEMINI_BACKEND_RESOLVED:-none}"
  exit 0
fi

{
  echo "[assert_triple_panel] PREMIUM panel required but missing: ${missing}"
  echo "  Premium fusion needs BOTH external CLIs:"
  $codex_ok  || echo "    - codex  (GPT-5.5):        install from https://developers.openai.com/codex , then verify 'codex --version'"
  $gemini_ok || echo "    - agy    (Gemini 3.1 Pro): install from https://antigravity.google/docs/cli-install , then verify 'agy --version'"
  $gemini_ok || echo "      Legacy gemini is opt-in only: FUSION_GEMINI_BACKEND=gemini or FUSION_ALLOW_LEGACY_GEMINI=1"
  echo "  To KNOWINGLY proceed with a smaller (degraded) panel, re-run with: FUSION_ALLOW_DEGRADED=1"
  echo "  Never present a degraded panel as 'premium' — disclose the real PANEL_STATE in the answer."
} >&2

if   ! $codex_ok && ! $gemini_ok; then exit 12
elif ! $codex_ok;                  then exit 10
else                                    exit 11
fi
