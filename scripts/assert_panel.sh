#!/usr/bin/env bash
# assert_panel.sh - v2 panel-mode gate.
#
# Intentional pair modes are not "degraded"; they are valid requested modes.
# On every exit-0 this script also prints PANEL_STATE= (composition disclosure)
# so callers can branch and disclose the honest panel shape. Under explicit
# FUSION_ALLOW_DEGRADED=1 it prints both DEGRADED_FROM_REQUESTED=1 and DEGRADED=1.

set -uo pipefail

# Recursion guard (mirrors OpenRouter's fusion-depth header / imladris max_depth): a panelist process
# must never convene its own panel — that breaks the blindness invariant and can loop.
# Resolve script dir with bash builtins only (no external dirname) so PATH=/nonexistent probes work.
_self="${BASH_SOURCE[0]}"
_dir="${_self%/*}"
[ "$_dir" = "$_self" ] && _dir="."
here="$(cd "$_dir" && pwd)"
. "$here/gemini_backend.sh"
fusion_guard_recursion "assert_panel"

mode="premium_triple"
case "${1:-}" in
  --mode) mode="${2:-}"; shift 2 ;;
  -h|--help)
    sed -n '2,6p' "$0"
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

# mode → PANEL_STATE when all required CLIs are present (composition disclosure).
# Single/pair intentional modes map to the closest honest triple-state name.
panel_state_for_mode() {
  case "$mode" in
    single_opus|opus_self_consistency) echo "OPUS_ONLY" ;;
    opus_gpt_pair)                     echo "DEGRADED_OPUS_GPT5" ;;
    opus_gemini_pair)                  echo "DEGRADED_OPUS_GEMINI" ;;
    gpt_gemini_pair_plus_opus_judge|premium_triple|premium_wide|ultra_two_round) echo "PREMIUM" ;;
    *) echo "CUSTOM_PANEL" ;;
  esac
}

# Availability → PANEL_STATE when the requested mode is missing CLIs (honest degrade).
panel_state_for_availability() {
  if   $codex_ok && $gemini_ok; then echo "PREMIUM"
  elif $codex_ok;               then echo "DEGRADED_OPUS_GPT5"
  elif $gemini_ok;              then echo "DEGRADED_OPUS_GEMINI"
  else                             echo "OPUS_ONLY"
  fi
}

missing=""
$need_codex && ! $codex_ok && missing="${missing}codex "
$need_gemini && ! $gemini_ok && missing="${missing}gemini-backend "
missing="${missing% }"

if [ -z "$missing" ]; then
  echo "PANEL_MODE=$mode"
  echo "PANEL_AVAILABLE=1"
  echo "PANEL_STATE=$(panel_state_for_mode)"
  echo "CODEX_AVAILABLE=$codex_ok"
  echo "GEMINI_AVAILABLE=$gemini_ok"
  echo "GEMINI_BACKEND=${FUSION_GEMINI_BACKEND_RESOLVED:-none}"
  exit 0
fi

if [ "${FUSION_ALLOW_DEGRADED:-0}" = "1" ]; then
  state="$(panel_state_for_availability)"
  {
    echo "############################################################"
    echo "# DEGRADED PANEL (FUSION_ALLOW_DEGRADED=1) — NOT PREMIUM    #"
    echo "# missing: ${missing:-none}"
    echo "# proceeding with: $state"
    echo "# The final answer MUST disclose this is a degraded panel.  #"
    echo "############################################################"
  } >&2
  echo "PANEL_MODE=$mode"
  echo "PANEL_AVAILABLE=0"
  echo "DEGRADED_FROM_REQUESTED=1"
  echo "DEGRADED=1"
  echo "MISSING=$missing"
  echo "PANEL_STATE=$state"
  echo "CODEX_AVAILABLE=$codex_ok"
  echo "GEMINI_AVAILABLE=$gemini_ok"
  echo "GEMINI_BACKEND=${FUSION_GEMINI_BACKEND_RESOLVED:-none}"
  exit 0
fi

{
  echo "[assert_panel] requested panel mode '$mode' is missing: $missing"
  echo "  Premium fusion needs BOTH external CLIs (when the mode requires them):"
  $need_codex && ! $codex_ok && echo "    - codex  (GPT-5.6 Sol):        install from https://developers.openai.com/codex , then verify 'codex --version'"
  $need_gemini && ! $gemini_ok && echo "    - agy    (Gemini 3.1 Pro): install from https://antigravity.google/docs/cli-install , then verify 'agy --version'"
  $need_gemini && ! $gemini_ok && echo "      Legacy gemini is opt-in only: FUSION_GEMINI_BACKEND=gemini or FUSION_ALLOW_LEGACY_GEMINI=1"
  echo "  To KNOWINGLY proceed with a smaller (degraded) panel, re-run with: FUSION_ALLOW_DEGRADED=1"
  echo "  Never present a degraded panel as 'premium' — disclose the real PANEL_STATE in the answer."
} >&2

if $need_codex && ! $codex_ok && $need_gemini && ! $gemini_ok; then exit 12
elif $need_codex && ! $codex_ok; then exit 10
else exit 11
fi
