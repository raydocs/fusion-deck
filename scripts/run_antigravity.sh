#!/usr/bin/env bash
# run_antigravity.sh - run the Gemini panelist via Antigravity CLI (`agy`).
#
# Usage:
#   run_antigravity.sh <prompt_file> <output_file>
#
# Antigravity print mode takes the prompt as an argv value (`agy --print "..."`), not stdin. That is
# different from legacy Gemini CLI, so this runner keeps the behavior isolated behind run_gemini.sh.

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/gemini_backend.sh"   # for fusion_run_with_timeout

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
# agy print mode passes the prompt via ARGV. Two consequences run_gemini.sh's stdin path avoids:
# (1) macOS ARG_MAX is ~1MB including the environment — a large review packet fails outright;
# (2) the full prompt is visible to every local process via `ps` while agy runs.
# So: warn early, and HARD-FAIL above a cap instead of letting execve fail (or worse, half-work).
if [ "${FUSION_ANTIGRAVITY_WARN_ARG_BYTES:-120000}" -gt 0 ] 2>/dev/null && \
   [ "$prompt_bytes" -gt "${FUSION_ANTIGRAVITY_WARN_ARG_BYTES:-120000}" ]; then
  echo "[run_antigravity.sh] warning: prompt is ${prompt_bytes} bytes; agy print mode passes prompts via argv (visible in ps)." >&2
fi
max_arg_bytes="${FUSION_ANTIGRAVITY_MAX_ARG_BYTES:-200000}"
if [ "$max_arg_bytes" -gt 0 ] 2>/dev/null && [ "$prompt_bytes" -gt "$max_arg_bytes" ]; then
  echo "[run_antigravity.sh] prompt is ${prompt_bytes} bytes > FUSION_ANTIGRAVITY_MAX_ARG_BYTES=${max_arg_bytes}." >&2
  echo "[run_antigravity.sh] agy takes the prompt via argv, so oversized packets can hit ARG_MAX. Curate a" >&2
  echo "[run_antigravity.sh] smaller packet (/fusion-context), or use the legacy stdin backend explicitly." >&2
  exit 2
fi

agy_args=(
  --dangerously-skip-permissions
  --print-timeout "$print_timeout"
  --model "$antigravity_model"
  --print "$prompt"
)

# Outer hard bound in addition to agy's own --print-timeout, so a hang in the CLI itself (before its
# internal timeout arms) still can't wedge the panel.
timeout_secs="${FUSION_PANEL_TIMEOUT:-600}"
# Mark the panelist process tree so the recursion guard refuses any nested fusion invocation.
export FUSION_PANEL_CHILD=1
( cd "$scratch" && fusion_run_with_timeout "$timeout_secs" agy "${agy_args[@]}" < /dev/null ) > "$out_abs" 2> "$scratch/agy.err"
status=$?

if [ $status -eq 124 ] || [ $status -eq 143 ]; then
  echo "[run_antigravity.sh] agy TIMED OUT after ${timeout_secs}s (FUSION_PANEL_TIMEOUT) — panelist is ABSENT." >&2
  exit 1
fi
if [ $status -ne 0 ] || [ ! -s "$output_file" ]; then
  echo "[run_antigravity.sh] agy exited $status or produced no output; tail of log:" >&2
  tail -20 "$scratch/agy.err" >&2
  echo "[run_antigravity.sh] note: some agy versions have reported empty stdout in non-TTY print mode." >&2
  exit 1
fi
# Plausibility floor — a few-byte "answer" is an error banner, not a panel answer.
min_out_bytes="${FUSION_MIN_OUTPUT_BYTES:-200}"
out_bytes="$(wc -c < "$out_abs" | tr -d ' ')"
if [ "$min_out_bytes" -gt 0 ] 2>/dev/null && [ "$out_bytes" -lt "$min_out_bytes" ]; then
  echo "[run_antigravity.sh] output is only ${out_bytes} bytes (< FUSION_MIN_OUTPUT_BYTES=${min_out_bytes}) — treating as failed." >&2
  exit 1
fi

echo "[run_antigravity.sh] ok -> $output_file (MODEL=$antigravity_model BACKEND=antigravity)"
