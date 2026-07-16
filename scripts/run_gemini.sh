#!/usr/bin/env bash
# run_gemini.sh — run one Gemini 3.1 Pro panelist via the configured backend.
#
# Usage:
#   run_gemini.sh <prompt_file> <output_file>
#
# Model selection (audited design decision):
#   We PIN the slug to gemini-3.1-pro-preview by default, because it is a PREVIEW model gated behind
#   version/flags — the CLI's auto-routing does NOT guarantee you get 3.1 Pro. Pinning is the only way
#   to be sure. Override with FUSION_GEMINI_MODEL=<slug> when the preview slug rotates. The resolved
#   model is always echoed (MODEL=...).
#
# Backend selection:
#   FUSION_GEMINI_BACKEND=auto (default) uses Antigravity CLI (`agy`) when available.
#   Legacy `gemini` requires FUSION_GEMINI_BACKEND=gemini or FUSION_ALLOW_LEGACY_GEMINI=1.
#
# Degrades gracefully: if no Gemini backend is available it exits 127 with a clear message so the
# orchestrator can drop Gemini and downgrade the panel (DEGRADED_CLAUDE_GPT) rather than failing the
# whole run.

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/gemini_backend.sh"

prompt_file="${1:?usage: run_gemini.sh <prompt_file> <output_file>}"
output_file="${2:?usage: run_gemini.sh <prompt_file> <output_file>}"

if [ ! -s "$prompt_file" ]; then
  echo "[run_gemini.sh] prompt file '$prompt_file' is missing or empty." >&2
  exit 2
fi

if ! fusion_detect_gemini_backend; then
  echo "[run_gemini.sh] no Gemini backend available - skip this panelist (panel downgrades)." >&2
  echo "[run_gemini.sh] $FUSION_GEMINI_BACKEND_REASON" >&2
  exit 127
fi

if [ "$FUSION_GEMINI_BACKEND_RESOLVED" = "antigravity" ]; then
  exec bash "$here/run_antigravity.sh" "$prompt_file" "$output_file"
fi

# Prompt-size guard (same knob as run_codex.sh): oversized packets are curation bugs.
fusion_check_prompt_bytes "run_gemini.sh" "$prompt_file" || exit 2

timeout_secs="${FUSION_PANEL_TIMEOUT:-600}"
gemini_model="${FUSION_GEMINI_MODEL:-gemini-3.1-pro-preview}"
echo "[run_gemini.sh] MODEL=$gemini_model BACKEND=legacy-gemini TIMEOUT=${timeout_secs}s" >&2

# Resolve prompt/output to ABSOLUTE paths, then run gemini inside a throwaway scratch dir. --yolo
# auto-approves tool use, so isolating cwd keeps its file writes out of the caller's repo and blind to
# other panelists' artifacts. Reads of the prompt still work via the absolute path.
prompt_abs="$(cd "$(dirname "$prompt_file")" && pwd)/$(basename "$prompt_file")"
out_abs="$(cd "$(dirname "$output_file")" && pwd)/$(basename "$output_file")"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/pfo-gemini.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT

# Non-interactive (headless) run. --yolo auto-approves tool use; --skip-trust is REQUIRED because the
# fresh scratch dir is untrusted. The prompt is fed on STDIN (not argv) so a large review packet can't hit
# ARG_MAX and the prompt text isn't exposed in process args (gemini reads the prompt from stdin).
# Mark the panelist process tree so the recursion guard refuses any nested fusion invocation.
export FUSION_PANEL_CHILD=1
( cd "$scratch" && fusion_run_with_timeout "$timeout_secs" gemini --model "$gemini_model" --yolo --skip-trust < "$prompt_abs" ) \
  > "$out_abs" 2> >(tail -20 >&2)
status=$?

if [ $status -eq 124 ] || [ $status -eq 143 ]; then
  echo "[run_gemini.sh] gemini TIMED OUT after ${timeout_secs}s (FUSION_PANEL_TIMEOUT) — panelist is ABSENT." >&2
  exit 1
fi
if [ $status -ne 0 ] || [ ! -s "$output_file" ]; then
  echo "[run_gemini.sh] gemini exited $status or produced no output." >&2
  exit 1
fi
# Plausibility floor — a few-byte "answer" is an error banner, not a panel answer.
fusion_check_min_output "run_gemini.sh" "$out_abs" || exit 1
echo "[run_gemini.sh] ok -> $output_file (MODEL=$gemini_model BACKEND=legacy-gemini)"
