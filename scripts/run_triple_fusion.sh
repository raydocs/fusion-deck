#!/usr/bin/env bash
# run_triple_fusion.sh — launch the TWO external CLI panelists (GPT-5.5 + Gemini 3.1 Pro) blind and
# in parallel on one prompt, then write a manifest the orchestrator reads.
#
# Usage:
#   run_triple_fusion.sh <prompt_file> <out_dir> [reasoning_effort]
#
# IMPORTANT — what this script does NOT do:
#   It does NOT spawn the Opus 4.8 panelist, and it does NOT judge. Only the Claude Code orchestrator
#   can spawn an Opus panelist (via the Agent/Task tool) and only Opus 4.8 judges/synthesizes — the
#   pipeline cannot be reversed. This script handles ONLY the two CLI panelists and reports their
#   output paths + the realized PANEL_STATE. The orchestrator then: (1) spawns its own Opus panelist
#   with the SAME prompt, (2) waits for these CLI outputs, (3) judges per references/judge-rubric.md.
#
# Blind-panel invariant: both CLI panelists receive the SAME prompt file and write to SEPARATE output
# files. No panelist's output is ever fed to another. Each runs in its own scratch dir.

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
prompt_file="${1:?usage: run_triple_fusion.sh <prompt_file> <out_dir> [reasoning_effort]}"
out_dir="${2:?usage: run_triple_fusion.sh <prompt_file> <out_dir> [reasoning_effort]}"
effort="${3:-medium}"

[ -s "$prompt_file" ] || { echo "[run_triple_fusion] prompt file '$prompt_file' missing/empty." >&2; exit 2; }
mkdir -p "$out_dir"

# Clear stale artifacts from any PRIOR run that reused this out_dir. Without this, a leftover manifest /
# output from an earlier run can be read mid-flight and mistaken for THIS run's result — a stale read looks
# exactly like a degraded panel when it isn't. We remove only the files this script writes (never the whole
# dir), which makes the manifest a reliable completion sentinel: manifest.txt present <=> this run finished.
rm -f "$out_dir/manifest.txt" "$out_dir/codex_out.md" "$out_dir/gemini_out.md" \
      "$out_dir/codex.log" "$out_dir/gemini.log"

# Gate: confirm the panel (honors FUSION_ALLOW_DEGRADED). Capture PANEL_STATE without aborting so we
# can record it in the manifest; if assert fails hard (no override), propagate its exit code.
assert_out="$(bash "$here/assert_triple_panel.sh" 2>/dev/null)"; assert_rc=$?
panel_state="$(printf '%s\n' "$assert_out" | sed -n 's/^PANEL_STATE=//p' | tail -1)"
if [ $assert_rc -ne 0 ]; then
  echo "[run_triple_fusion] premium panel not available and FUSION_ALLOW_DEGRADED is not set." >&2
  bash "$here/assert_triple_panel.sh" >/dev/null   # re-run so its remediation message reaches stderr
  exit $assert_rc
fi
panel_state="${panel_state:-UNKNOWN}"

codex_out="$out_dir/codex_out.md"
gemini_out="$out_dir/gemini_out.md"
codex_pid=""; gemini_pid=""

# Same bounded availability check as the gate (assert_triple_panel.sh), so launch decisions agree with it
# and a hung CLI can't wedge this script either. Portable timeout (timeout/gtimeout, else bash watchdog).
_bounded() {
  if command -v timeout  >/dev/null 2>&1; then timeout  5 "$@"; return $?; fi
  if command -v gtimeout >/dev/null 2>&1; then gtimeout 5 "$@"; return $?; fi
  "$@" & _bp=$!; ( sleep 5; kill -9 "$_bp" 2>/dev/null ) & _bw=$!
  wait "$_bp" 2>/dev/null; _brc=$?; kill "$_bw" 2>/dev/null; wait "$_bw" 2>/dev/null; return "$_brc"
}
have() { command -v "$1" >/dev/null 2>&1 && _bounded "$1" --version >/dev/null 2>&1; }

if have codex; then
  ( bash "$here/run_codex.sh" "$prompt_file" "$codex_out" "$effort" ) > "$out_dir/codex.log" 2>&1 &
  codex_pid=$!
fi
if have gemini; then
  ( bash "$here/run_gemini.sh" "$prompt_file" "$gemini_out" ) > "$out_dir/gemini.log" 2>&1 &
  gemini_pid=$!
fi

codex_rc="skipped"; gemini_rc="skipped"
[ -n "$codex_pid" ]  && { wait "$codex_pid";  codex_rc=$?; }
[ -n "$gemini_pid" ] && { wait "$gemini_pid"; gemini_rc=$?; }

# REALIZED accounting: who ACTUALLY produced output. A CLI panelist that errored or was skipped is
# ABSENT to the judge (never silent agreement). Opus 4.8 is always added later by the orchestrator.
codex_ok2=false;  [ "$codex_rc"  = 0 ] && codex_ok2=true
gemini_ok2=false; [ "$gemini_rc" = 0 ] && gemini_ok2=true
if   $codex_ok2 && $gemini_ok2; then realized="PREMIUM"
elif $codex_ok2;                then realized="DEGRADED_OPUS_GPT5"
elif $gemini_ok2;               then realized="DEGRADED_OPUS_GEMINI"
else                                 realized="OPUS_ONLY"; fi
# Honest accounting: this script runs ONLY the CLI panelists. The Opus 4.8 panelist is added later by the
# orchestrator (in-process subagent), so it is recorded as orchestrator-added — NOT claimed as run here.
cli_participants=""; $codex_ok2 && cli_participants="gpt5.5"; $gemini_ok2 && cli_participants="${cli_participants:+$cli_participants+}gemini3.1pro"
absent=""; $codex_ok2 || absent="$absent gpt5.5(rc=$codex_rc)"; $gemini_ok2 || absent="$absent gemini3.1pro(rc=$gemini_rc)"

manifest="$out_dir/manifest.txt"
{
  echo "INTENDED_PANEL_STATE=$panel_state"
  echo "REALIZED_PANEL_STATE=$realized"
  echo "CLI_PARTICIPANTS=${cli_participants:-none}"
  echo "OPUS_PANELIST=added-by-orchestrator"
  echo "ABSENT=${absent:-none}"
  echo "TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "PROMPT_FILE=$prompt_file"
  echo "CODEX_MODEL=${FUSION_CODEX_MODEL:-codex-default}"
  echo "GEMINI_MODEL=${FUSION_GEMINI_MODEL:-gemini-3.1-pro-preview}"
  echo "CODEX_OUT=$codex_out CODEX_RC=$codex_rc"
  echo "GEMINI_OUT=$gemini_out GEMINI_RC=$gemini_rc"
  echo "# NOTE: Opus 4.8 panelist + judge are added by the orchestrator, not this script."
} > "$manifest"

echo "[run_triple_fusion] INTENDED=$panel_state REALIZED=$realized  codex_rc=$codex_rc gemini_rc=$gemini_rc"
echo "[run_triple_fusion] CLI participants: ${cli_participants:-none}${absent:+ ; absent:$absent} (Opus added by orchestrator)"
echo "[run_triple_fusion] manifest -> $manifest"
echo "[run_triple_fusion] NEXT (orchestrator): spawn an Opus 4.8 panelist with the SAME prompt, then judge"
echo "                    all returned answers per <skill-root>/references/judge-rubric.md. Disclose the"
echo "                    REALIZED panel ($realized) — a failed/absent CLI panelist is NOT silent agreement."

# A panelist that errored is treated as ABSENT by the judge, never as silent agreement. We only fail
# hard if BOTH external panelists were attempted and both failed (no external panel signal at all).
if [ "$codex_rc" != "skipped" ] && [ "$codex_rc" != 0 ] && \
   [ "$gemini_rc" != "skipped" ] && [ "$gemini_rc" != 0 ]; then
  echo "[run_triple_fusion] both external panelists failed — only the Opus panelist will be available." >&2
  exit 1
fi
exit 0
