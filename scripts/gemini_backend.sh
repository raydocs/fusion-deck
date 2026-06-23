#!/usr/bin/env bash
# Shared Gemini-panel backend detection.
#
# Default policy:
#   FUSION_GEMINI_BACKEND=auto prefers Antigravity CLI (`agy`).
#   Legacy `gemini` is used only when explicitly requested, because consumer
#   Gemini CLI auth stopped serving requests after 2026-06-18.

set -uo pipefail

fusion_bounded() {
  if command -v timeout >/dev/null 2>&1; then timeout 5 "$@"; return $?; fi
  if command -v gtimeout >/dev/null 2>&1; then gtimeout 5 "$@"; return $?; fi
  "$@" & _fbp=$!
  ( sleep 5; kill -9 "$_fbp" 2>/dev/null ) & _fbw=$!
  wait "$_fbp" 2>/dev/null
  _fbrc=$?
  kill "$_fbw" 2>/dev/null
  wait "$_fbw" 2>/dev/null
  return "$_fbrc"
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
