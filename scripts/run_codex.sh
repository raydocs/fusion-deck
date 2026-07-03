#!/usr/bin/env bash
# run_codex.sh — run one GPT-5.5 panelist (via the codex CLI) on a prompt, with web search + bash.
#
# Usage:
#   run_codex.sh <prompt_file> <output_file> [reasoning_effort]
#
# - <prompt_file>    : file containing the FULL panelist prompt (verbatim user task + brief instruction)
# - <output_file>    : where the panelist's final answer is written (clean — just the answer)
# - reasoning_effort : low | medium | high   (default: medium)
#
# Model selection (audited design decision):
#   We TRUST the codex CLI's configured default model, which is GPT-5.5 on a premium codex setup.
#   We do NOT hardcode a model slug, because codex slugs rotate and a stale pinned slug breaks more
#   often than it helps. To pin or override, export FUSION_CODEX_MODEL=<slug>. The RESOLVED model is
#   always echoed (MODEL=...) so a weak/wrong default is VISIBLE, never silently used.
#
# Flags:
#   -o/--output-last-message  writes ONLY the agent's final message (no streaming noise to parse).
#   -s workspace-write        gives the panelist a "bash tool" in an isolated scratch dir.
#   -c tools.web_search=true  enables the web search tool.
# The panelist runs in a throwaway scratch dir so its file writes never touch your repo, and so it
# cannot see any other panelist's output (blind-panel invariant).
#
# Env knobs:
#   FUSION_PANEL_TIMEOUT   hard time limit in seconds (default 600); a hung CLI is killed and ABSENT.
#   FUSION_NO_WEB=1        read-only sandbox + no web tool — REQUIRED posture when the prompt embeds
#                          untrusted content (e.g. a diff under review), so injected instructions
#                          can't exfiltrate it. /fusion-review sets this by default.
#   FUSION_MAX_PROMPT_BYTES  refuse oversized prompts (default 400000; 0 disables).
#   FUSION_MIN_OUTPUT_BYTES  treat tiny outputs as failures (default 200; 0 disables).

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/gemini_backend.sh"   # for fusion_run_with_timeout

prompt_file="${1:?usage: run_codex.sh <prompt_file> <output_file> [reasoning_effort]}"
output_file="${2:?usage: run_codex.sh <prompt_file> <output_file> [reasoning_effort]}"
effort="${3:-medium}"

if ! command -v codex >/dev/null 2>&1; then
  echo "[run_codex.sh] codex CLI not installed — cannot run the GPT-5.5 panelist." >&2
  exit 127
fi
if [ ! -s "$prompt_file" ]; then
  echo "[run_codex.sh] prompt file '$prompt_file' is missing or empty." >&2
  exit 2
fi

# Prompt-size guard: an oversized packet is a curation bug (use /fusion-context), not something to
# silently ship to a paid model. FUSION_MAX_PROMPT_BYTES=0 disables.
max_prompt_bytes="${FUSION_MAX_PROMPT_BYTES:-400000}"
prompt_bytes="$(wc -c < "$prompt_file" | tr -d ' ')"
if [ "$max_prompt_bytes" -gt 0 ] 2>/dev/null && [ "$prompt_bytes" -gt "$max_prompt_bytes" ]; then
  echo "[run_codex.sh] prompt is ${prompt_bytes} bytes > FUSION_MAX_PROMPT_BYTES=${max_prompt_bytes}." >&2
  echo "[run_codex.sh] curate a smaller packet (/fusion-context) or raise/disable the cap explicitly." >&2
  exit 2
fi

# Injection surface: panelist prompts can embed UNTRUSTED content (a diff under review). With
# FUSION_NO_WEB=1 the panelist gets a read-only sandbox and NO web tool, so injected instructions
# cannot exfiltrate the content. /fusion-review sets this by default.
no_web="${FUSION_NO_WEB:-0}"
timeout_secs="${FUSION_PANEL_TIMEOUT:-600}"

model="${FUSION_CODEX_MODEL:-}"
if [ "$no_web" = "1" ]; then
  echo "[run_codex.sh] MODEL=${model:-codex-default} EFFORT=$effort WEB_SEARCH=off SANDBOX=read-only (FUSION_NO_WEB=1) TIMEOUT=${timeout_secs}s" >&2
else
  echo "[run_codex.sh] MODEL=${model:-codex-default} EFFORT=$effort WEB_SEARCH=on(tools.web_search=true) TIMEOUT=${timeout_secs}s" >&2
fi

scratch="$(mktemp -d "${TMPDIR:-/tmp}/pfo-codex.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT

codex_args=(
  exec
  --skip-git-repo-check
  --cd "$scratch"
)
if [ "$no_web" = "1" ]; then
  codex_args+=(-s read-only)
else
  codex_args+=(-s workspace-write -c tools.web_search=true)
fi
codex_args+=(-c "model_reasoning_effort=$effort")
# Only pass an explicit model when the operator pinned one; otherwise trust the codex default.
[ -n "$model" ] && codex_args+=(-c "model=$model")
codex_args+=(-o "$output_file" -)

# Mark the panelist process tree: if the panelist (which has bash) reaches back into these scripts,
# the recursion guard refuses (exit 14) instead of convening a panel inside a panel.
export FUSION_PANEL_CHILD=1
fusion_run_with_timeout "$timeout_secs" codex "${codex_args[@]}" < "$prompt_file" > "$scratch/stream.log" 2>&1
status=$?

if [ $status -eq 124 ] || [ $status -eq 143 ]; then
  echo "[run_codex.sh] codex TIMED OUT after ${timeout_secs}s (FUSION_PANEL_TIMEOUT) — panelist is ABSENT." >&2
  exit 1
fi
# Plausibility floor: an "answer" of a few bytes is an error banner, not a panel answer. Counting it
# as a healthy panelist would silently fake the panel. FUSION_MIN_OUTPUT_BYTES=0 disables.
min_out_bytes="${FUSION_MIN_OUTPUT_BYTES:-200}"
out_bytes=0; [ -f "$output_file" ] && out_bytes="$(wc -c < "$output_file" | tr -d ' ')"
if [ $status -ne 0 ] || [ ! -s "$output_file" ]; then
  echo "[run_codex.sh] codex exited $status (or wrote no output); tail of log:" >&2
  tail -20 "$scratch/stream.log" >&2
  exit 1
fi
if [ "$min_out_bytes" -gt 0 ] 2>/dev/null && [ "$out_bytes" -lt "$min_out_bytes" ]; then
  echo "[run_codex.sh] output is only ${out_bytes} bytes (< FUSION_MIN_OUTPUT_BYTES=${min_out_bytes}) — treating as failed; tail of log:" >&2
  tail -20 "$scratch/stream.log" >&2
  exit 1
fi
echo "[run_codex.sh] ok -> $output_file (MODEL=${model:-codex-default})"
