#!/usr/bin/env bash
# run_verifier.sh - run a deterministic verifier and write a small report.

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/gemini_backend.sh"   # for fusion_run_with_timeout
cmd=""; out_dir=""; first=false; dry=false
# Usage errors exit 64 (EX_USAGE), NOT the verifier's own exit code — a verifier command that exits 2
# must be distinguishable from "you called this script wrong".
while [ "$#" -gt 0 ]; do
  case "$1" in
    --command) cmd="${2:-}"; shift 2 ;;
    --out-dir) out_dir="${2:-}"; shift 2 ;;
    --first) first=true; shift ;;
    --dry-run) dry=true; shift ;;
    -h|--help)
      sed -n '2,2p' "$0"
      echo "usage: run_verifier.sh --command '<cmd>' [--out-dir DIR] | --first [--dry-run]"
      exit 0 ;;
    *) echo "run_verifier: unknown arg $1" >&2; exit 64 ;;
  esac
done

if [ -z "$cmd" ] && $first; then
  detected="$(bash "$here/detect_verifiers.sh")"
  cmd="$(printf '%s\n' "$detected" | sed -n 's/^VERIFIER_1_COMMAND=//p')"
fi
[ -n "$cmd" ] || { echo "run_verifier: need --command or --first" >&2; exit 64; }

out_dir="${out_dir:-$(mktemp -d "${TMPDIR:-/tmp}/fusion-verifier.XXXXXX")}"
mkdir -p "$out_dir"
report="$out_dir/verifier_report.txt"

{
  echo "VERIFIER_COMMAND=$cmd"
  echo "VERIFIER_STARTED=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$report"

if $dry; then
  echo "VERIFIER_STATE=DRY_RUN" | tee -a "$report"
  echo "VERIFIER_COMMAND=$cmd"
  echo "VERIFIER_REPORT=$report"
  exit 0
fi

# `bash -c`, NOT `bash -lc`: a login shell sources the user's profile (slow, env drift, and a profile
# that prints to stdout corrupts the report). Bounded: a hanging test suite must not hang forever.
verifier_timeout="${FUSION_VERIFIER_TIMEOUT:-900}"
set +e
fusion_run_with_timeout "$verifier_timeout" bash -c "$cmd" > "$out_dir/stdout.txt" 2> "$out_dir/stderr.txt"
rc=$?
set -e

{
  echo "VERIFIER_EXIT_CODE=$rc"
  echo "VERIFIER_FINISHED=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "--- stdout tail ---"
  tail -40 "$out_dir/stdout.txt" 2>/dev/null || true
  echo "--- stderr tail ---"
  tail -40 "$out_dir/stderr.txt" 2>/dev/null || true
} >> "$report"

if [ "$rc" -eq 0 ]; then state="PASS"
elif [ "$rc" -eq 124 ] || [ "$rc" -eq 143 ]; then state="TIMEOUT (${verifier_timeout}s, FUSION_VERIFIER_TIMEOUT)"
else state="FAIL"; fi
echo "VERIFIER_STATE=$state"
echo "VERIFIER_EXIT_CODE=$rc"
echo "VERIFIER_REPORT=$report"
exit "$rc"
