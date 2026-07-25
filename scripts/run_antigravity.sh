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

# TWO timeouts, and they must be layered in the right order. `--print-timeout` is agy's own graceful
# limit; fusion_run_with_timeout below is the backstop for a CLI that hangs before its own timer arms.
# The graceful one therefore has to be SHORTER than the backstop, and both have to move together.
#
# They did not. The inner default was a hardcoded 5m0s (300s) while the backstop was FUSION_PANEL_TIMEOUT
# (600s), so the inner limit always fired first: the documented knob had NO effect on this seat, and
# codex effectively got twice the budget. Measured on real review packets, this seat takes 204s / 240s /
# 304s — the same order of magnitude as the 300s cap, which is the worst possible place for a hard limit.
# One prompt timed out at 304s and succeeded at 240s on retry: the cap was mispositioned, not the prompt.
timeout_secs="${FUSION_PANEL_TIMEOUT:-600}"
# Validate before arithmetic: in an arithmetic context bash treats a non-numeric string as a VARIABLE
# NAME, so `FUSION_PANEL_TIMEOUT=abc` died with "abc: unbound variable" under `set -u` — a crash whose
# message names neither the variable the operator set nor the reason.
case "$timeout_secs" in
  ''|*[!0-9]*)
    echo "[run_antigravity.sh] FUSION_PANEL_TIMEOUT must be a whole number of seconds (got '$timeout_secs')." >&2
    exit 2 ;;
esac
_agy_grace=$(( timeout_secs > 60 ? timeout_secs - 30 : timeout_secs ))
print_timeout="${FUSION_ANTIGRAVITY_PRINT_TIMEOUT:-${_agy_grace}s}"
echo "[run_antigravity.sh] MODEL=$antigravity_model PRINT_TIMEOUT=$print_timeout BACKEND=antigravity" >&2

prompt_abs="$(cd "$(dirname "$prompt_file")" && pwd)/$(basename "$prompt_file")"
out_abs="$(cd "$(dirname "$output_file")" && pwd)/$(basename "$output_file")"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/pfo-antigravity.XXXXXX")"
workspace=""
trap 'fusion_panel_workspace_cleanup "${FUSION_PANEL_REPO:-}" "$workspace"; rm -rf "$scratch"' EXIT

# Repo access for THIS seat is opt-in and OFF by default, unlike run_codex.sh.
#
# The reason is asymmetric capability, not caution for its own sake: codex exposes `-s read-only` and a
# web-tool switch, so /fusion-review can put it in a sandbox with no egress. `agy` exposes NEITHER — this
# runner launches it with --dangerously-skip-permissions and there is no flag here that disables its
# network or confines its filesystem access. `FUSION_NO_WEB=1` is honored by run_codex.sh alone; it has
# never had any effect on this seat. A disposable snapshot bounds what WRITES touch; it does not bound
# what the model can read elsewhere on the host or send anywhere. Since the review packet is UNTRUSTED
# by construction (a diff can carry injected instructions), handing this seat the code under review adds
# an exfiltration surface with no mitigation available at this layer.
#
# So: packet-only by default. An operator who accepts that risk sets FUSION_PANEL_REPO_UNSANDBOXED=1,
# and the run says so out loud.
cwd="$scratch"
if [ -n "${FUSION_PANEL_REPO:-}" ] && [ "${FUSION_PANEL_REPO_UNSANDBOXED:-0}" != "1" ]; then
  echo "[run_antigravity.sh] WORKSPACE=none — repo access declined for this seat. agy runs with" >&2
  echo "[run_antigravity.sh] --dangerously-skip-permissions and exposes no read-only/no-network mode, so" >&2
  echo "[run_antigravity.sh] code access here cannot be paired with egress control. This seat answers from" >&2
  echo "[run_antigravity.sh] the packet ALONE — weight it accordingly, and say so in the audit trail." >&2
  echo "[run_antigravity.sh] Override (accepting the risk): FUSION_PANEL_REPO_UNSANDBOXED=1" >&2
elif [ -n "${FUSION_PANEL_REPO:-}" ]; then
  if workspace="$(fusion_panel_workspace "$FUSION_PANEL_REPO" "$scratch/repo")"; then
    cwd="$workspace"
    echo "[run_antigravity.sh] WORKSPACE=snapshot-UNSANDBOXED (at $cwd) — operator opted in via" >&2
    echo "[run_antigravity.sh] FUSION_PANEL_REPO_UNSANDBOXED=1; this seat has code access WITHOUT egress control." >&2
  else
    workspace=""
    echo "[run_antigravity.sh] WORKSPACE=none — could not build a snapshot from '$FUSION_PANEL_REPO'; this" >&2
    echo "[run_antigravity.sh] seat answers from the packet ALONE. Disclose that in the audit trail." >&2
  fi
fi

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

# Backstop for a hang in the CLI itself, before its own --print-timeout arms. Derived above so the two
# layers cannot drift apart again.
# Mark the panelist process tree so the recursion guard refuses any nested fusion invocation.
export FUSION_PANEL_CHILD=1
( cd "$cwd" && fusion_run_with_timeout "$timeout_secs" agy "${agy_args[@]}" < /dev/null ) > "$out_abs" 2> "$scratch/agy.err"
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
fusion_check_min_output "run_antigravity.sh" "$out_abs" || exit 1

echo "[run_antigravity.sh] ok -> $output_file (MODEL=$antigravity_model BACKEND=antigravity)"
