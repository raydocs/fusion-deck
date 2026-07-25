#!/usr/bin/env bash
# caller_slices.sh — pull the UNMODIFIED call-sites of the symbols a diff touches, as slices.
#
# A reviewer handed only the changed hunks gives generic feedback: it cannot see how the changed code is
# used. This bundles each call-site with its surrounding block so the panel can judge the change against
# real usage.
#
# Usage: caller_slices.sh <scope> <out_dir> [context_lines] [hunks_per_symbol]
#   <scope>  uncommitted | staged | back:N | <range>   (same vocabulary as review_packet.sh)
# Writes <out_dir>/callers.md and prints a greppable CALLER_SLICES= line plus one status line. The slice
# bytes never pass through the caller's context — same discipline as review_packet.sh.
#
# Three things here are load-bearing, all learned the hard way:
#
#   1. `git grep`, never `grep -r`. git searches tracked files only, so it skips .git and every gitignored
#      build tree instead of reading them and filtering after. Measured 16-25x on ordinary repos and 518x
#      on one with a large node_modules (491 s -> 0.9 s).
#   2. ONE grep for all symbols, not one per symbol. Twenty separate `git grep` processes cost 322 ms
#      where a single multi-pattern pass costs 32 ms. The per-symbol cap the loop used to provide is
#      re-applied afterwards in awk, so one hot symbol still cannot eat the whole packet.
#   3. The symbol list reaches awk through a FILE, never `-v`. BSD awk rejects a -v value containing
#      newlines ("newline in string") and then emits NOTHING while the script still exits 0 — a silent
#      empty slice set under a status line announcing N symbols.

set -uo pipefail

scope="${1:?usage: caller_slices.sh <scope> <out_dir> [context_lines] [hunks_per_symbol]}"
out_dir="${2:?usage: caller_slices.sh <scope> <out_dir> [context_lines] [hunks_per_symbol]}"
ctx="${3:-4}"
cap="${4:-5}"

git rev-parse --show-toplevel >/dev/null 2>&1 || { echo "caller_slices: not a git repo" >&2; exit 2; }
case "$ctx$cap" in *[!0-9]*) echo "caller_slices: context/cap must be whole numbers" >&2; exit 2 ;; esac

case "$scope" in
  uncommitted) diff_cmd=(git diff) ;;
  staged)      diff_cmd=(git diff --staged) ;;
  back:*)      n="${scope#back:}"
    case "$n" in ''|*[!0-9]*) echo "caller_slices: bad back:N '$scope'" >&2; exit 2 ;; esac
    diff_cmd=(git diff "HEAD~$n..HEAD") ;;
  *)
    if [ "${scope#*..}" != "$scope" ]; then diff_cmd=(git diff "$scope")
    elif git rev-parse --verify --quiet "${scope}^{commit}" >/dev/null; then diff_cmd=(git diff "${scope}...HEAD")
    else echo "caller_slices: unknown scope '$scope'" >&2; exit 2; fi ;;
esac

mkdir -p "$out_dir" || exit 2
out="$out_dir/callers.md"
symfile="$out_dir/.caller_syms"

# Symbols DECLARED by the diff — the identifier after the keyword, never the keyword itself. This only
# sees keyword-declared symbols; in modifier-led languages (C#, Java, Swift, Kotlin) it catches types but
# not methods, which is why the repo map's codemap tier carries those instead.
"${diff_cmd[@]}" 2>/dev/null | grep -E '^\+' \
  | grep -oE '\b(def|func|function|class|fn|sub|type|interface|struct)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' \
  | awk '{print $2}' | sort -u | grep . > "$symfile"

# NOT `grep -c . || echo 0`: on an empty file grep PRINTS 0 and EXITS 1, so the fallback appends a
# second line and the numeric test below fails on "0\n0".
n_sym=$(grep -c . "$symfile" 2>/dev/null | head -1)
n_sym=${n_sym:-0}
if [ "$n_sym" -eq 0 ]; then
  rm -f "$symfile"
  { echo "# Call-sites of changed symbols"; echo
    echo "No keyword-declared symbols in this diff (docs/config/deletion-only, or a modifier-led"
    echo "language whose methods carry no keyword). Caller context omitted — see the repo map instead."
  } > "$out"
  echo "CALLER_SLICES=NO_SYMBOLS"
  echo "caller_slices: no symbols in '$scope' — wrote an explicit note, not an empty file"
  exit 0
fi

pat=()
while IFS= read -r s; do [ -n "$s" ] && pat+=(-e "$s"); done < "$symfile"

{
  echo "# Call-sites of changed symbols"
  echo
  echo '```'
  # git grep separates hunks with a literal `--`. Attribute each hunk to the symbol on its match line
  # (joined by ':' rather than '-') and keep the first $cap hunks per symbol.
  git grep -n -w -C"$ctx" "${pat[@]}" 2>/dev/null \
    | awk -v cap="$cap" -v symfile="$symfile" '
        BEGIN { WORD = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_" }
        FILENAME == symfile { if ($0 != "") a[++n] = $0; next }
        # Keep git grep`s `--` between emitted hunks. Dropping it ran the slices together, so a reader
        # could not tell where one call-site ended and the next began — and neither could a test count
        # hunks to check the per-symbol cap.
        function flush(  i) {
          if (owner != "" && seen[owner] < cap) {
            seen[owner]++
            if (emitted++) print "--"
            for (i = 1; i <= nb; i++) print buf[i]
          }
          nb = 0; owner = ""
        }
        /^--$/ { flush(); next }
        {
          buf[++nb] = $0
          if (owner == "" && $0 ~ /^[^:]+:[0-9]+:/) {
            # Attribute on the CONTENT, with word boundaries — not `index()` over the whole line. The
            # line starts with `path:line:`, so a substring test let a file named Character.cs own every
            # hunk in it and quietly voided the per-symbol cap for whatever else matched there.
            # index() + manual boundary test, not a regex: building one regex per symbol per line was
            # 20 compiles x every match line and made this pass SLOWER than the 20-process loop it
            # replaced (417 ms vs 321 ms). index() is a plain scan.
            content = $0; sub(/^[^:]+:[0-9]+:/, "", content)
            for (i = 1; i <= n; i++) {
              p = index(content, a[i])
              if (p == 0) continue
              before = (p == 1) ? "" : substr(content, p - 1, 1)
              after  = substr(content, p + length(a[i]), 1)
              if (index(WORD, before) == 0 && index(WORD, after) == 0) { owner = a[i]; break }
            }
          }
        }
        END { flush() }' "$symfile" -
  echo '```'
} > "$out"

rm -f "$symfile"

# An empty slice set while symbols EXIST is a failure, not a result: it means the pipeline broke, and the
# status line would otherwise still announce N symbols over an empty fence.
body=$(sed -n '/^```$/,$p' "$out" | sed '1d;$d' | grep -c . 2>/dev/null | head -1)
body=${body:-0}
bytes=$(wc -c < "$out" | tr -d ' ')
if [ "${body:-0}" -eq 0 ]; then
  echo "caller_slices: $n_sym symbol(s) declared by the diff but NOT ONE call-site slice was produced." >&2
  echo "caller_slices: that is a broken pipeline, not an empty repo — refusing to ship a context-free" >&2
  echo "caller_slices: packet. (A brand-new symbol with no callers yet is the one honest case; if that" >&2
  echo "caller_slices: is what this is, say so explicitly in the brief.)" >&2
  echo "CALLER_SLICES=EMPTY"
  exit 4
fi
echo "CALLER_SLICES=OK"
echo "caller_slices: wrote $out: $bytes bytes ($n_sym symbols, $body lines, <=$cap hunks each, ${ctx} context)"
