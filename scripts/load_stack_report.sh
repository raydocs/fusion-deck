#!/usr/bin/env bash
# load_stack_report.sh — per-command load-stack token estimates (efficiency visibility).
#
# For each commands/*.md: "mandatory" = every references/*.md named in the file's FIRST 20 LINES
# (the Load/header block — loaded on every invocation; slightly conservative when a header line
# names a conditional ref); "conditional" = mentions after line 20 (loaded only when a step/flag
# reaches them). Token estimate = ceil(bytes/4 × 1.05) — the repo's own heuristic — over command
# file + mandatory refs + ~120-token wrapper constant.
#
# Usage:
#   load_stack_report.sh                  # print the table
#   load_stack_report.sh --assert-max N   # exit 1 if any mandatory stack exceeds N tokens
#
# This is a budget floor-light, not an exact tokenizer: it keeps stack growth VISIBLE so bloat is a
# deliberate choice, never an accident (mirrors smoke's drift guards).

set -uo pipefail

here="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
root="$(cd "$here/.." && pwd)"

max=0
if [ "${1:-}" = "--assert-max" ]; then max="${2:?usage: --assert-max N}"; fi

tok() { # tokens for a file (0 if missing)
  local f="$1" b
  [ -f "$f" ] || { echo 0; return; }
  b="$(wc -c < "$f" | tr -d ' ')"
  echo $(( (b * 105 + 399) / 400 ))   # ceil(b/4 * 1.05)
}

WRAPPER_TOK=120
rc=0
printf '%-24s %8s %10s %8s  %s\n' "command" "cmd_tok" "refs_tok" "TOTAL" "mandatory refs"
for c in "$root"/commands/*.md; do
  name="$(basename "$c" .md)"
  cmd_tok="$(tok "$c")"
  refs="$(head -20 "$c" | grep -oE 'references/[a-z0-9._-]+\.md' | sort -u)"
  refs_tok=0; ref_names=""
  for r in $refs; do
    t="$(tok "$root/$r")"
    refs_tok=$((refs_tok + t))
    ref_names="${ref_names:+$ref_names }$(basename "$r" .md)"
  done
  total=$((WRAPPER_TOK + cmd_tok + refs_tok))
  printf '%-24s %8s %10s %8s  %s\n' "$name" "$cmd_tok" "$refs_tok" "$total" "${ref_names:--}"
  if [ "$max" -gt 0 ] && [ "$total" -gt "$max" ]; then
    echo "OVER BUDGET: $name mandatory stack $total > $max tokens" >&2
    rc=1
  fi
done
exit $rc
