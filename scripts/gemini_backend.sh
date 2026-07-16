#!/usr/bin/env bash
# gemini_backend.sh — shared runtime library for fusion panel scripts.
#
# Provides: Gemini backend detection, bounded CLI probes, and shared guards
# (recursion, prompt-size, min-output) used by runners and panel gates.
#
# Default Gemini backend policy:
#   FUSION_GEMINI_BACKEND=auto prefers Antigravity CLI (`agy`).
#   Legacy `gemini` is used only when explicitly requested, because consumer
#   Gemini CLI auth stopped serving requests after 2026-06-18.

set -uo pipefail

# Run a command under a hard time limit (seconds). Portable: timeout/gtimeout when present, else a
# bash watchdog. The watchdog TERMs first (KILL only after a grace period), and on the normal path we
# kill the watchdog's own children too so no orphan `sleep` outlives the probe.
fusion_run_with_timeout() {
  _frt_secs="$1"; shift
  if command -v timeout >/dev/null 2>&1; then timeout "$_frt_secs" "$@"; return $?; fi
  if command -v gtimeout >/dev/null 2>&1; then gtimeout "$_frt_secs" "$@"; return $?; fi
  "$@" & _frt_pid=$!
  ( sleep "$_frt_secs"; kill "$_frt_pid" 2>/dev/null; sleep 5; kill -9 "$_frt_pid" 2>/dev/null ) & _frt_w=$!
  wait "$_frt_pid" 2>/dev/null
  _frt_rc=$?
  pkill -P "$_frt_w" 2>/dev/null
  kill "$_frt_w" 2>/dev/null
  wait "$_frt_w" 2>/dev/null
  return "$_frt_rc"
}

fusion_bounded() {
  fusion_run_with_timeout 5 "$@"
}

fusion_cli_available() {
  command -v "$1" >/dev/null 2>&1 && fusion_bounded "$1" --version >/dev/null 2>&1
}

# Recursion guard: a panelist process must never convene its own panel (blindness invariant + loop risk).
# Call BEFORE any side effect (stale-clear, mkdir, etc.). Exits 14 when FUSION_PANEL_CHILD=1.
fusion_guard_recursion() {
  _fgr_tag="$1"
  if [ "${FUSION_PANEL_CHILD:-0}" = "1" ]; then
    echo "[$_fgr_tag] recursive fusion invocation blocked: this process is already a panelist (FUSION_PANEL_CHILD=1)." >&2
    echo "[$_fgr_tag] panelists answer directly; only the outer orchestrator convenes panels." >&2
    exit 14
  fi
}

# Prompt-size guard: oversized packets are curation bugs. FUSION_MAX_PROMPT_BYTES=0 disables.
# Returns 2 when over cap (caller: fusion_check_prompt_bytes TAG FILE || exit 2).
fusion_check_prompt_bytes() {
  _fcp_tag="$1"
  _fcp_file="$2"
  _fcp_max="${FUSION_MAX_PROMPT_BYTES:-400000}"
  _fcp_bytes="$(wc -c < "$_fcp_file" | tr -d ' ')"
  if [ "$_fcp_max" -gt 0 ] 2>/dev/null && [ "$_fcp_bytes" -gt "$_fcp_max" ]; then
    echo "[$_fcp_tag] prompt is ${_fcp_bytes} bytes > FUSION_MAX_PROMPT_BYTES=${_fcp_max}." >&2
    echo "[$_fcp_tag] curate a smaller packet (/fusion-context) or raise/disable the cap explicitly." >&2
    return 2
  fi
  return 0
}

# Plausibility floor: a few-byte "answer" is an error banner, not a panel answer.
# FUSION_MIN_OUTPUT_BYTES=0 disables. Returns 1 when under floor.
# Callers that also want a log tail (run_codex) print/tail after a nonzero return.
fusion_check_min_output() {
  _fcm_tag="$1"
  _fcm_file="$2"
  _fcm_min="${FUSION_MIN_OUTPUT_BYTES:-200}"
  _fcm_bytes=0
  [ -f "$_fcm_file" ] && _fcm_bytes="$(wc -c < "$_fcm_file" | tr -d ' ')"
  if [ "$_fcm_min" -gt 0 ] 2>/dev/null && [ "$_fcm_bytes" -lt "$_fcm_min" ]; then
    echo "[$_fcm_tag] output is only ${_fcm_bytes} bytes (< FUSION_MIN_OUTPUT_BYTES=${_fcm_min}) — treating as failed." >&2
    return 1
  fi
  return 0
}

fusion_detect_gemini_backend() {
  FUSION_GEMINI_BACKEND_RESOLVED=""
  FUSION_GEMINI_BACKEND_BINARY=""
  FUSION_GEMINI_BACKEND_REASON=""

  case "${FUSION_GEMINI_BACKEND:-auto}" in
    auto|"")
      if fusion_cli_available agy; then
        FUSION_GEMINI_BACKEND_RESOLVED="antigravity"
        FUSION_GEMINI_BACKEND_BINARY="agy"
        FUSION_GEMINI_BACKEND_REASON="auto selected Antigravity CLI"
      elif [ "${FUSION_ALLOW_LEGACY_GEMINI:-0}" = "1" ] && fusion_cli_available gemini; then
        FUSION_GEMINI_BACKEND_RESOLVED="legacy-gemini"
        FUSION_GEMINI_BACKEND_BINARY="gemini"
        FUSION_GEMINI_BACKEND_REASON="auto selected legacy Gemini CLI because FUSION_ALLOW_LEGACY_GEMINI=1"
      else
        FUSION_GEMINI_BACKEND_REASON="Antigravity CLI (agy) not available; legacy gemini ignored unless explicitly enabled"
      fi
      ;;
    agy|antigravity)
      if fusion_cli_available agy; then
        FUSION_GEMINI_BACKEND_RESOLVED="antigravity"
        FUSION_GEMINI_BACKEND_BINARY="agy"
        FUSION_GEMINI_BACKEND_REASON="FUSION_GEMINI_BACKEND=${FUSION_GEMINI_BACKEND}"
      else
        FUSION_GEMINI_BACKEND_REASON="FUSION_GEMINI_BACKEND=${FUSION_GEMINI_BACKEND} but agy is not available"
      fi
      ;;
    gemini|legacy|legacy-gemini)
      if fusion_cli_available gemini; then
        FUSION_GEMINI_BACKEND_RESOLVED="legacy-gemini"
        FUSION_GEMINI_BACKEND_BINARY="gemini"
        FUSION_GEMINI_BACKEND_REASON="FUSION_GEMINI_BACKEND=${FUSION_GEMINI_BACKEND}"
      else
        FUSION_GEMINI_BACKEND_REASON="FUSION_GEMINI_BACKEND=${FUSION_GEMINI_BACKEND} but gemini is not available"
      fi
      ;;
    *)
      FUSION_GEMINI_BACKEND_REASON="unknown FUSION_GEMINI_BACKEND=${FUSION_GEMINI_BACKEND}"
      ;;
  esac

  [ -n "$FUSION_GEMINI_BACKEND_RESOLVED" ]
}
