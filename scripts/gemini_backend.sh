#!/usr/bin/env bash
# Shared Gemini-panel backend detection.
#
# Default policy:
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
