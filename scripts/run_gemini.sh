#!/usr/bin/env bash
# run_gemini.sh — run one Gemini 3.1 Pro panelist (via the gemini CLI) on a prompt, with web + bash.
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
# Degrades gracefully: if `gemini` is missing it exits 127 with a clear message so the orchestrator
# can drop Gemini and downgrade the panel (DEGRADED_OPUS_GPT5) rather than failing the whole run.

set -uo pipefail

prompt_file="${1:?usage: run_gemini.sh <prompt_file> <output_file>}"
output_file="${2:?usage: run_gemini.sh <prompt_file> <output_file>}"

if ! command -v gemini >/dev/null 2>&1; then
  echo "[run_gemini.sh] gemini CLI not installed — skip this panelist (panel downgrades)." >&2
  exit 127
fi
if [ ! -s "$prompt_file" ]; then
  echo "[run_gemini.sh] prompt file '$prompt_file' is missing or empty." >&2
  exit 2
fi

gemini_model="${FUSION_GEMINI_MODEL:-gemini-3.1-pro-preview}"
echo "[run_gemini.sh] MODEL=$gemini_model" >&2

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
( cd "$scratch" && gemini --model "$gemini_model" --yolo --skip-trust < "$prompt_abs" ) \
  > "$out_abs" 2> >(tail -20 >&2)
status=$?

if [ $status -ne 0 ] || [ ! -s "$output_file" ]; then
  echo "[run_gemini.sh] gemini exited $status or produced no output." >&2
  exit 1
fi
echo "[run_gemini.sh] ok -> $output_file (MODEL=$gemini_model)"
