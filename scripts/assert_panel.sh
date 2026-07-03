#!/usr/bin/env bash
# assert_panel.sh - v2 panel-mode gate.
#
# Intentional pair modes are not "degraded"; they are valid requested modes.

set -uo pipefail

# Recursion guard (mirrors OpenRouter's fusion-depth header / imladris max_depth): a panelist process
# must never convene its own panel — that breaks the blindness invariant and can loop.
if [ "${FUSION_PANEL_CHILD:-0}" = "1" ]; then
  echo "[assert_panel] recursive fusion invocation blocked: this process is already a panelist (FUSION_PANEL_CHILD=1)." >&2
  echo "[assert_panel] panelists answer directly; only the outer orchestrator convenes panels." >&2
  exit 14
fi

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/gemini_backend.sh"

mode="premium_triple"
case "${1:-}" in
  --mode) mode="${2:-}"; shift 2 ;;
  -h|--help)
    sed -n '2,4p' "$0"
    echo "usage: assert_panel.sh --mode <single_opus|opus_self_consistency|opus_gpt_pair|opus_gemini_pair|gpt_gemini_pair_plus_opus_judge|premium_triple|premium_wide|ultra_two_round>"
    exit 2 ;;
esac

codex_ok=false; gemini_ok=false
fusion_cli_available codex && codex_ok=true
fusion_detect_gemini_backend && gemini_ok=true

need_codex=false; need_gemini=false
case "$mode" in
  single_opus|opus_self_consistency) ;;
  opus_gpt_pair) need_codex=true ;;
  opus_gemini_pair) need_gemini=true ;;
  gpt_gemini_pair_plus_opus_judge|premium_triple|premium_wide|ultra_two_round) need_codex=true; need_gemini=true ;;
  *) echo "[assert_panel] unknown panel mode: $mode" >&2; exit 2 ;;
esac

missing=""
$need_codex && ! $codex_ok && missing="${missing}codex "
$need_gemini && ! $gemini_ok && missing="${missing}gemini-backend "
missing="${missing% }"

if [ -z "$missing" ]; then
  echo "PANEL_MODE=$mode"
  echo "PANEL_AVAILABLE=1"
  echo "CODEX_AVAILABLE=$codex_ok"
  echo "GEMINI_AVAILABLE=$gemini_ok"
  echo "GEMINI_BACKEND=${FUSION_GEMINI_BACKEND_RESOLVED:-none}"
  exit 0
fi

if [ "${FUSION_ALLOW_DEGRADED:-0}" = "1" ]; then
  echo "PANEL_MODE=$mode"
  echo "PANEL_AVAILABLE=0"
  echo "DEGRADED_FROM_REQUESTED=1"
  echo "MISSING=$missing"
  echo "CODEX_AVAILABLE=$codex_ok"
  echo "GEMINI_AVAILABLE=$gemini_ok"
  echo "GEMINI_BACKEND=${FUSION_GEMINI_BACKEND_RESOLVED:-none}"
  exit 0
fi

{
  echo "[assert_panel] requested panel mode '$mode' is missing: $missing"
  $need_codex && ! $codex_ok && echo "  - codex: install/verify codex --version"
  $need_gemini && ! $gemini_ok && echo "  - Gemini backend: install/verify agy --version"
  echo "  To proceed knowingly with a smaller realized mode: FUSION_ALLOW_DEGRADED=1"
} >&2

if $need_codex && ! $codex_ok && $need_gemini && ! $gemini_ok; then exit 12
elif $need_codex && ! $codex_ok; then exit 10
else exit 11
fi
