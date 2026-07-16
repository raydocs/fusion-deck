#!/usr/bin/env bash
# run_panel.sh - v2 external panel runner for intentional panel modes.
#
# This script runs only external CLI panelists. Opus panelists and the judge are
# still spawned by the orchestrator, preserving the existing fusion-deck boundary.

set -uo pipefail

# Recursion guard — refuse BEFORE any side effect (the stale-clear below must never run for a child).
if [ "${FUSION_PANEL_CHILD:-0}" = "1" ]; then
  echo "[run_panel] recursive fusion invocation blocked: this process is already a panelist (FUSION_PANEL_CHILD=1)." >&2
  exit 14
fi

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/gemini_backend.sh"

mode="premium_triple"
if [ "${1:-}" = "--mode" ]; then mode="${2:-}"; shift 2; fi
prompt_file="${1:?usage: run_panel.sh --mode <mode> <prompt_file> <out_dir> [reasoning_effort]}"
out_dir="${2:?usage: run_panel.sh --mode <mode> <prompt_file> <out_dir> [reasoning_effort]}"
effort="${3:-medium}"

[ -s "$prompt_file" ] || { echo "[run_panel] prompt file '$prompt_file' missing/empty." >&2; exit 2; }
mkdir -p "$out_dir"
rm -f "$out_dir/manifest.txt" "$out_dir/manifest.txt.tmp" "$out_dir/codex_out.md" "$out_dir/gemini_out.md" \
      "$out_dir/codex.log" "$out_dir/gemini.log" "$out_dir/ledger.env" \
      "$out_dir/.codex_end" "$out_dir/.gemini_end"

assert_out="$(bash "$here/assert_panel.sh" --mode "$mode" 2>/dev/null)"; assert_rc=$?
if [ $assert_rc -ne 0 ]; then
  bash "$here/assert_panel.sh" --mode "$mode" >/dev/null
  exit $assert_rc
fi

need_codex=false; need_gemini=false; opus_panelists=1; opus_role="panelist+judge"
case "$mode" in
  single_opus) opus_panelists=1 ;;
  opus_self_consistency) opus_panelists=2 ;;
  opus_gpt_pair) need_codex=true ;;
  opus_gemini_pair) need_gemini=true ;;
  gpt_gemini_pair_plus_opus_judge) need_codex=true; need_gemini=true; opus_panelists=0; opus_role="judge-only" ;;
  premium_triple) need_codex=true; need_gemini=true ;;
  # WIDE modes: cross-family diversity AND same-model self-consistency in one round. Two cold Opus
  # runs + GPT + Gemini = 4 panelists; the judge additionally reads Opus-vs-Opus disagreement as a
  # confidence signal. This is the max-quality default for ultra's round 1.
  ultra_two_round|premium_wide) need_codex=true; need_gemini=true; opus_panelists=2 ;;
  *) echo "[run_panel] unknown mode: $mode" >&2; exit 2 ;;
esac

codex_out="$out_dir/codex_out.md"
gemini_out="$out_dir/gemini_out.md"
codex_pid=""; gemini_pid=""
panel_start="$(date +%s)"

# Each panelist subshell stamps its own end time, so per-panelist wall-clock is accurate even though
# both run in parallel and we `wait` for them in a fixed order.
if $need_codex && fusion_cli_available codex; then
  ( bash "$here/run_codex.sh" "$prompt_file" "$codex_out" "$effort"; s=$?; date +%s > "$out_dir/.codex_end"; exit $s ) > "$out_dir/codex.log" 2>&1 &
  codex_pid=$!
fi
if $need_gemini && fusion_detect_gemini_backend; then
  ( bash "$here/run_gemini.sh" "$prompt_file" "$gemini_out"; s=$?; date +%s > "$out_dir/.gemini_end"; exit $s ) > "$out_dir/gemini.log" 2>&1 &
  gemini_pid=$!
fi

codex_rc="skipped"; gemini_rc="skipped"
[ -n "$codex_pid" ] && { wait "$codex_pid"; codex_rc=$?; }
[ -n "$gemini_pid" ] && { wait "$gemini_pid"; gemini_rc=$?; }

codex_secs="-"; gemini_secs="-"
[ -s "$out_dir/.codex_end" ] && codex_secs=$(( $(cat "$out_dir/.codex_end") - panel_start ))
[ -s "$out_dir/.gemini_end" ] && gemini_secs=$(( $(cat "$out_dir/.gemini_end") - panel_start ))
prompt_bytes="$(wc -c < "$prompt_file" | tr -d ' ')"
codex_bytes=0;  [ -f "$codex_out" ]  && codex_bytes="$(wc -c < "$codex_out" | tr -d ' ')"
gemini_bytes=0; [ -f "$gemini_out" ] && gemini_bytes="$(wc -c < "$gemini_out" | tr -d ' ')"

codex_ok=false; [ "$codex_rc" = 0 ] && codex_ok=true
gemini_ok=false; [ "$gemini_rc" = 0 ] && gemini_ok=true

cli_participants=""
$codex_ok && cli_participants="gpt5.6sol"
$gemini_ok && cli_participants="${cli_participants:+$cli_participants+}gemini3.1pro"
absent=""
$need_codex && ! $codex_ok && absent="$absent gpt5.6sol(rc=$codex_rc)"
$need_gemini && ! $gemini_ok && absent="$absent gemini3.1pro(rc=$gemini_rc)"

realized_mode="$mode"
realized_state="CUSTOM_PANEL"
case "$mode" in
  single_opus) realized_state="OPUS_ONLY" ;;
  opus_self_consistency) realized_state="OPUS_SELF_CONSISTENCY" ;;
  opus_gpt_pair) $codex_ok && realized_state="OPUS_GPT_PAIR" || { realized_state="DEGRADED_FROM_REQUESTED_PAIR"; realized_mode="single_opus"; } ;;
  opus_gemini_pair) $gemini_ok && realized_state="OPUS_GEMINI_PAIR" || { realized_state="DEGRADED_FROM_REQUESTED_PAIR"; realized_mode="single_opus"; } ;;
  gpt_gemini_pair_plus_opus_judge)
    if $codex_ok && $gemini_ok; then realized_state="GPT_GEMINI_PAIR_PLUS_OPUS_JUDGE"
    else
      # With <2 CLI answers there is no external pair for a judge-only Opus to judge — the honest
      # realized shape is a normal single-Opus run (Opus as panelist+judge), not a judge of one.
      realized_state="DEGRADED_FROM_REQUESTED_PAIR"; realized_mode="single_opus"
      opus_panelists=1; opus_role="panelist+judge"
    fi ;;
  premium_triple|ultra_two_round|premium_wide)
    if $codex_ok && $gemini_ok; then realized_state="PREMIUM"; elif $codex_ok; then realized_state="DEGRADED_OPUS_GPT5"; elif $gemini_ok; then realized_state="DEGRADED_OPUS_GEMINI"; else realized_state="OPUS_ONLY"; fi
    # OPUS_ONLY is defined (SKILL.md / panel-modes) as TWO cold Opus runs — keep the manifest
    # consistent with that definition so the orchestrator spawns the right number of panelists.
    [ "$realized_state" = "OPUS_ONLY" ] && opus_panelists=2 ;;
esac

# Write the manifest to a temp file and rename it into place ONLY when complete (ledger lines
# included), so "manifest.txt exists" really is an atomic completion sentinel for readers.
manifest="$out_dir/manifest.txt"
manifest_tmp="$manifest.tmp"
{
  echo "REQUESTED_PANEL_MODE=$mode"
  echo "REALIZED_PANEL_MODE=$realized_mode"
  echo "REALIZED_PANEL_STATE=$realized_state"
  echo "CLI_PARTICIPANTS=${cli_participants:-none}"
  echo "OPUS_PANELISTS=$opus_panelists"
  echo "OPUS_ROLE=$opus_role"
  echo "ABSENT=${absent:-none}"
  echo "TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "PROMPT_FILE=$prompt_file"
  echo "PROMPT_BYTES=$prompt_bytes"
  echo "PANEL_TIMEOUT_SECONDS=${FUSION_PANEL_TIMEOUT:-600}"
  echo "CODEX_MODEL=${FUSION_CODEX_MODEL:-codex-default}"
  echo "GEMINI_BACKEND=${FUSION_GEMINI_BACKEND_RESOLVED:-none}"
  if [ "${FUSION_GEMINI_BACKEND_RESOLVED:-}" = "antigravity" ]; then
    echo "GEMINI_MODEL=${FUSION_ANTIGRAVITY_MODEL:-Gemini 3.1 Pro (High)}"
  else
    echo "GEMINI_MODEL=${FUSION_GEMINI_MODEL:-gemini-3.1-pro-preview}"
  fi
  echo "CODEX_OUT=$codex_out CODEX_RC=$codex_rc"
  echo "GEMINI_OUT=$gemini_out GEMINI_RC=$gemini_rc"
  echo "CODEX_SECONDS=$codex_secs CODEX_OUT_BYTES=$codex_bytes"
  echo "GEMINI_SECONDS=$gemini_secs GEMINI_OUT_BYTES=$gemini_bytes"
  echo "# NOTE: Opus panelists + judge are added by the orchestrator, not this script."
} > "$manifest_tmp"

task_summary="$(tr '\n' ' ' < "$prompt_file" | cut -c1-180)"
if ledger_env="$(python3 "$here/fusion_ledger.py" new --command run_panel --workflow "$mode" \
    --task "$task_summary" --task-type panel --risk unknown --verifiability unknown \
    --manifest "$manifest_tmp" --prompt "$prompt_file" 2>/dev/null)"; then
  printf '%s\n' "$ledger_env" > "$out_dir/ledger.env"
  printf '%s\n' "$ledger_env" >> "$manifest_tmp"
fi
mv "$manifest_tmp" "$manifest"
rm -f "$out_dir/.codex_end" "$out_dir/.gemini_end"

echo "[run_panel] REQUESTED=$mode REALIZED=$realized_state codex_rc=$codex_rc gemini_rc=$gemini_rc"
echo "[run_panel] CLI participants: ${cli_participants:-none}${absent:+ ; absent:$absent}"
echo "[run_panel] manifest -> $manifest"
echo "[run_panel] NEXT: spawn required Opus panelist(s), then judge per references/judge-rubric.md."

if $need_codex && [ "$codex_rc" != "skipped" ] && [ "$codex_rc" != 0 ] && \
   $need_gemini && [ "$gemini_rc" != "skipped" ] && [ "$gemini_rc" != 0 ]; then
  echo "[run_panel] all attempted external panelists failed." >&2
  exit 1
fi

# Runtime honest-degrade gate: install-time absence is caught by assert_panel.sh, but a panelist can
# still fail DURING the run (rate limit, auth error, timeout, garbage output). Proceeding silently
# would fake the requested panel — so without an explicit FUSION_ALLOW_DEGRADED=1, stop here (exit 13)
# and let the orchestrator surface the realized state to the user instead of quietly shipping less.
runtime_degraded=false
{ $need_codex && ! $codex_ok; } && runtime_degraded=true
{ $need_gemini && ! $gemini_ok; } && runtime_degraded=true
if $runtime_degraded && [ "${FUSION_ALLOW_DEGRADED:-0}" != "1" ]; then
  echo "[run_panel] a requested panelist FAILED at runtime (realized: $realized_state)." >&2
  echo "[run_panel] not proceeding silently — set FUSION_ALLOW_DEGRADED=1 to accept the realized panel," >&2
  echo "[run_panel] or retry once the failed CLI is healthy. Manifest (with realized state) was written." >&2
  exit 13
fi
exit 0
