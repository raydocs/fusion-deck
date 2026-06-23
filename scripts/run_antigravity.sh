#!/usr/bin/env bash
# run_antigravity.sh - run the Gemini panelist via Antigravity CLI (`agy`).
#
# Usage:
#   run_antigravity.sh <prompt_file> <output_file>
#
# Antigravity print mode takes the prompt as an argv value (`agy --print "..."`), not stdin. That is
# different from legacy Gemini CLI, so this runner keeps the behavior isolated behind run_gemini.sh.

set -uo pipefail

prompt_file="${1:?usage: run_antigravity.sh <prompt_file> <output_file>}"
output_file="${2:?usage: run_antigravity.sh <prompt_file> <output_file>}"

if ! command -v agy >/dev/null 2>&1; then
  echo "[run_antigravity.sh] agy CLI not installed - skip this panelist (panel downgrades)." >&2
  exit 127
fi
if [ ! -s "$prompt_file" ]; then
  echo "[run_antigravity.sh] prompt file '$prompt_file' is missing or empty." >&2
  exit 2
fi

antigravity_model="${FUSION_ANTIGRAVITY_MODEL:-Gemini 3.1 Pro (High)}"
print_timeout="${FUSION_ANTIGRAVITY_PRINT_TIMEOUT:-5m0s}"
echo "[run_antigravity.sh] MODEL=$antigravity_model PRINT_TIMEOUT=$print_timeout BACKEND=antigravity" >&2

prompt_abs="$(cd "$(dirname "$prompt_file")" && pwd)/$(basename "$prompt_file")"
out_abs="$(cd "$(dirname "$output_file")" && pwd)/$(basename "$output_file")"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/pfo-antigravity.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT

prompt="$(cat "$prompt_abs")"
prompt_bytes="$(wc -c < "$prompt_abs" | tr -d ' ')"
if [ "${FUSION_ANTIGRAVITY_WARN_ARG_BYTES:-120000}" -gt 0 ] 2>/dev/null && \
   [ "$prompt_bytes" -gt "${FUSION_ANTIGRAVITY_WARN_ARG_BYTES:-120000}" ]; then
  echo "[run_antigravity.sh] warning: prompt is ${prompt_bytes} bytes; agy print mode passes prompts via argv." >&2
fi

agy_args=(
  --dangerously-skip-permissions
  --print-timeout "$print_timeout"
  --model "$antigravity_model"
  --print "$prompt"
)

( cd "$scratch" && agy "${agy_args[@]}" < /dev/null ) > "$out_abs" 2> "$scratch/agy.err"
status=$?

if [ $status -ne 0 ] || [ ! -s "$output_file" ]; then
  echo "[run_antigravity.sh] agy exited $status or produced no output; tail of log:" >&2
  tail -20 "$scratch/agy.err" >&2
  echo "[run_antigravity.sh] note: some agy versions have reported empty stdout in non-TTY print mode." >&2
  exit 1
fi

echo "[run_antigravity.sh] ok -> $output_file (MODEL=$antigravity_model BACKEND=antigravity)"
