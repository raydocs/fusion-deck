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

set -uo pipefail

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

model="${FUSION_CODEX_MODEL:-}"
echo "[run_codex.sh] MODEL=${model:-codex-default} EFFORT=$effort WEB_SEARCH=on(tools.web_search=true)" >&2

scratch="$(mktemp -d "${TMPDIR:-/tmp}/pfo-codex.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT

codex_args=(
  exec
  --skip-git-repo-check
  --cd "$scratch"
  -s workspace-write
  -c tools.web_search=true
  -c "model_reasoning_effort=$effort"
)
# Only pass an explicit model when the operator pinned one; otherwise trust the codex default.
[ -n "$model" ] && codex_args+=(-c "model=$model")
codex_args+=(-o "$output_file" -)

codex "${codex_args[@]}" < "$prompt_file" > "$scratch/stream.log" 2>&1
status=$?

if [ $status -ne 0 ] || [ ! -s "$output_file" ]; then
  echo "[run_codex.sh] codex exited $status (or wrote no output); tail of log:" >&2
  tail -20 "$scratch/stream.log" >&2
  exit 1
fi
echo "[run_codex.sh] ok -> $output_file (MODEL=${model:-codex-default})"
