#!/usr/bin/env bash
# caller_slices.sh — pull the UNMODIFIED call-sites of the symbols a diff touches, as slices.
#
# A reviewer handed only the changed hunks gives generic feedback: it cannot see how the changed code is
# used. This bundles each call-site with its surrounding block so the panel can judge the change against
# real usage.
#
# Usage: caller_slices.sh <scope> <out_dir> [context_lines] [hunks_per_symbol] [lines_per_symbol]
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
#   3. `core.quotePath=false` on every path-producing call. It defaults to TRUE, so a non-ASCII path comes
#      back escaped as "\344\270\255...py" — a reviewer cannot cite it and the extension test rejects it.
#   4. The symbol list reaches awk through a FILE, never `-v`. BSD awk rejects a -v value containing
#      newlines ("newline in string") and then emits NOTHING while the script still exits 0 — a silent
#      empty slice set under a status line announcing N symbols.

set -uo pipefail

scope="${1:?usage: caller_slices.sh <scope> <out_dir> [context_lines] [hunks_per_symbol] [lines_per_symbol]}"
out_dir="${2:?usage: caller_slices.sh <scope> <out_dir> [context_lines] [hunks_per_symbol] [lines_per_symbol]}"
ctx="${3:-4}"
cap="${4:-5}"
maxlines="${5:-60}"

toplevel="$(git rev-parse --show-toplevel 2>/dev/null)" \
  || { echo "caller_slices: not a git repo" >&2; exit 2; }
case "$ctx$cap$maxlines" in *[!0-9]*) echo "caller_slices: numeric args must be whole numbers" >&2; exit 2 ;; esac

# Resolve out_dir BEFORE moving, then run from the repo ROOT. `git diff` is repo-wide from anywhere but
# `git grep` is scoped to the CWD subtree, so running this from a subdirectory found no call-sites, hit
# the empty-result guard and hard-stopped the review with EMPTY on a perfectly healthy repo.
mkdir -p "$out_dir" || exit 2
out_dir="$(cd "$out_dir" && pwd)" || exit 2
cd "$toplevel" || exit 2

case "$scope" in
  uncommitted) diff_cmd=(git -c core.quotePath=false diff) ;;
  staged)      diff_cmd=(git -c core.quotePath=false diff --staged) ;;
  back:*)      n="${scope#back:}"
    case "$n" in ''|*[!0-9]*) echo "caller_slices: bad back:N '$scope'" >&2; exit 2 ;; esac
    diff_cmd=(git -c core.quotePath=false diff "HEAD~$n..HEAD") ;;
  *)
    if [ "${scope#*..}" != "$scope" ]; then diff_cmd=(git -c core.quotePath=false diff "$scope")
    elif git rev-parse --verify --quiet "${scope}^{commit}" >/dev/null; then diff_cmd=(git -c core.quotePath=false diff "${scope}...HEAD")
    else echo "caller_slices: unknown scope '$scope'" >&2; exit 2; fi ;;
esac

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
  git -c core.quotePath=false grep -n -w -C"$ctx" "${pat[@]}" 2>/dev/null \
    | awk -v cap="$cap" -v maxlines="$maxlines" -v symfile="$symfile" '
        BEGIN { WORD = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_" }
        FILENAME == symfile { if ($0 != "") a[++n] = $0; next }
        function reset(  i) {
          for (i in owners) delete owners[i]; for (i in firstline) delete firstline[i]
          nowners = 0; nb = 0; hunkno++
        }
        # A hunk belongs to EVERY symbol matched inside it, not just the first. Owning it by one symbol
        # meant a hunk was dropped whole once that owner hit its cap — taking with it the only call-site
        # of any colder symbol that happened to share the hunk. Measured: a symbol with two real
        # call-sites contributed zero lines because a hot symbol owned the hunks they shared.
        function flush(  i, o, room, r, take) {
          if (nowners == 0) { reset(); return }
          # The invariant: EVERY symbol with a call-site contributes at least one hunk containing one of
          # its own call-sites. Budgets bound how much MORE it gets, never whether it appears at all.
          # Both previous versions of this cap violated that and a symbol went missing entirely, so the
          # floor is now explicit rather than a consequence of the arithmetic.
          room = 0; floor_needed = 0
          for (i = 1; i <= nowners; i++) {
            o = owners[i]
            if (!(o in got)) floor_needed = 1
            if (seen[o] < cap) { r = maxlines - lines[o]; if (r > room) room = r }
          }
          if (room <= 0 && !floor_needed) { reset(); return }
          if (room <= 0) room = maxlines          # honouring the floor for a symbol not yet represented
          # git grep MERGES matches closer than 2*context into one hunk, so a hunk is not a bounded unit:
          # 200 adjacent call-sites arrived as a single 400-line hunk while the count still read "<=5".
          # Truncate to the remaining line budget rather than emit it whole or drop it entirely.
          take = (nb <= room) ? nb : room
          if (emitted++) print "--"
          for (i = 1; i <= take; i++) print buf[i]
          if (take < nb) printf "   [... %d more lines in this hunk, truncated at the per-symbol line budget]\n", nb - take
          # Charge only the owners whose OWN match line made it into the emitted portion. Charging every
          # co-owner meant a symbol paid its whole line budget for a hunk that was 99% another symbol,
          # in which its own line had been truncated away, after which its dedicated hunk was
          # dropped for lack of budget. Measured: a symbol with call-sites in three files contributed
          # zero lines. You are charged for what you actually got.
          for (i = 1; i <= nowners; i++) {
            o = owners[i]
            if (firstline[o] <= take) { seen[o]++; lines[o] += take; got[o] = 1 }
          }
          reset()
        }
        /^--$/ { flush(); next }
        {
          buf[++nb] = $0
          if ($0 ~ /^[^:]+:[0-9]+:/) {
            # Attribute on the CONTENT with word boundaries — not index() over the whole line, which let
            # a file named Character.cs own every hunk in it and voided the cap for anything else there.
            # index(WORD, "") returns 1 (awk finds the empty string at position 1), so both edges are
            # tested by POSITION; testing them with index() silently dropped every call-site where the
            # symbol starts or ends the line.
            content = $0; sub(/^[^:]+:[0-9]+:/, "", content)
            for (i = 1; i <= n; i++) {
              p = index(content, a[i])
              if (p == 0) continue
              e = p + length(a[i])
              if ((p == 1 || index(WORD, substr(content, p - 1, 1)) == 0) &&
                  (e > length(content) || index(WORD, substr(content, e, 1)) == 0)) {
                # Generation key is an explicit per-hunk counter, not `emitted`: `emitted` advances only
                # on hunks that are actually printed, so a dropped hunk left the generation stale and any
                # symbol marked during it would have been excluded from owning the NEXT hunk.
                if (!(a[i] in mark) || mark[a[i]] != hunkno) {
                  mark[a[i]] = hunkno
                  owners[++nowners] = a[i]
                  firstline[a[i]] = nb
                }
              }
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
echo "caller_slices: wrote $out: $bytes bytes ($n_sym symbols, $body lines; per symbol <=$cap hunks and"
echo "caller_slices: <=$maxlines lines, EXCEPT that a symbol not yet represented always gets one hunk; ${ctx} lines of context)"
