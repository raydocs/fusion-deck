#!/usr/bin/env bash
# bench_step1.sh — reproduce the README's Step-1 timings: session baseline vs HEAD, same symbol set.
#
# Usage: bench_step1.sh <repo> [baseline-ref]
#
# WHAT THIS DOES NOT MEASURE. The sandbox is `git archive HEAD` plus untracked files, so it contains no
# gitignored build output and only a one-commit `.git`. The largest single term in the README's headline —
# `grep -r` reading a multi-GB `node_modules` and the object store before filtering, 491 s -> 0.9 s — is
# therefore ABSENT here, and the ratio this prints is a LOWER BOUND on a repo that has such a tree. That
# figure was measured separately against a real working tree; this script reproduces the script-level
# improvement without touching the operator's checkout.
#
# It NEVER modifies the repo you point it at. An earlier version appended fixture declarations to a
# tracked file in that repo and then ran `git checkout` on it — which discards any uncommitted edits the
# operator had in that file. Everything now happens inside a disposable snapshot built by the same helper
# the panel seats use, so the worst case is a stale temp directory.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SK="$(cd "$here/../.." && pwd)"                     # repo root, derived — not hardcoded to one machine
. "$SK/scripts/gemini_backend.sh"                   # fusion_panel_workspace

repo="${1:?usage: bench_step1.sh <repo> [baseline-ref]}"
base="${2:-31dbda2}"

repo="$(cd "$repo" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "bench_step1: '$1' is not a git repository" >&2; exit 2; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/fusion-bench.XXXXXX")" || exit 2
trap 'rm -rf "$tmp"' EXIT INT TERM

echo "bench_step1: snapshotting $repo (the original is never modified)…"
snap="$(fusion_panel_workspace "$repo" "$tmp/snap")" || {
  echo "bench_step1: could not snapshot the repo" >&2; exit 2; }

# Baseline scripts, extracted from THIS repo's history.
tb="$tmp/base"; mkdir -p "$tb"
( cd "$SK" && git archive "$base" scripts ) 2>/dev/null | tar -xf - -C "$tb" || {
  echo "bench_step1: could not extract scripts at '$base'" >&2; exit 2; }

cd "$snap" || exit 2

# A fixture diff with a realistic symbol count, applied INSIDE the snapshot.
f="$(git ls-files '*.cs' '*.py' '*.ts' '*.go' 2>/dev/null | head -1)"
[ -n "$f" ] || { echo "bench_step1: no source file to build a fixture diff from" >&2; exit 3; }
syms="$tmp/syms"
git ls-files '*.cs' '*.py' '*.ts' '*.go' 2>/dev/null | head -80 | tr '\n' '\0' \
  | xargs -0 grep -hoE '\b(class|def|func)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' 2>/dev/null \
  | awk '{print $2}' | sort -u | head -20 > "$syms"
n=$(grep -c . "$syms" | head -1)
[ "${n:-0}" -gt 0 ] || { echo "bench_step1: found no symbols to benchmark with" >&2; exit 3; }
{
  echo
  while IFS= read -r c; do
    case "$f" in
      *.cs) printf 'public class %s {}\n' "$c" ;;
      *.go) printf 'type %s struct{}\n'   "$c" ;;
      *)    printf 'class %s: pass\n'     "$c" ;;
    esac
  done < "$syms"
} >> "$f"

now(){ python3 -c 'import time;print(time.time())'; }
el(){ python3 -c "import sys;print(f'{(float(sys.argv[2])-float(sys.argv[1]))*1000:.0f}')" "$1" "$2"; }

o1="$tmp/o1"; mkdir -p "$o1"
s=$(now); bash "$tb/scripts/review_packet.sh" uncommitted "$o1" >/dev/null 2>&1; a1=$(el "$s" "$(now)")
s=$(now)
while IFS= read -r x; do
  grep -rnw --include='*.*' "$x" . 2>/dev/null | grep -v '^\./\.git/' | head -20
done < "$syms" > "$o1/c.txt" 2>/dev/null
a2=$(el "$s" "$(now)")
s=$(now); bash "$tb/scripts/codemap.sh" . > "$o1/m.txt" 2>/dev/null; a3=$(el "$s" "$(now)")

c="$tmp/cache"; o2="$tmp/o2"; mkdir -p "$c" "$o2"
FUSION_MAP_CACHE="$c" bash "$SK/scripts/fusion_map.sh" "$o2" >/dev/null 2>&1        # warm
s=$(now); bash "$SK/scripts/review_packet.sh" uncommitted "$o2" >/dev/null 2>&1; b1=$(el "$s" "$(now)")
s=$(now); bash "$SK/scripts/caller_slices.sh" uncommitted "$o2" >/dev/null 2>&1;  b2=$(el "$s" "$(now)")
s=$(now); FUSION_MAP_CACHE="$c" bash "$SK/scripts/fusion_map.sh" "$o2" >/dev/null 2>&1; b3=$(el "$s" "$(now)")

printf '  repo=%s  symbols=%s  baseline=%s\n' "$(basename "$repo")" "$n" "$base"
printf '  BASE  packet=%-6s callers=%-7s map=%-6s total=%s\n' "$a1" "$a2" "$a3" "$((a1 + a2 + a3))"
printf '  HEAD  packet=%-6s callers=%-7s map=%-6s total=%s\n' "$b1" "$b2" "$b3" "$((b1 + b2 + b3))"
python3 -c "print(f'  -> {($a1+$a2+$a3)/max($b1+$b2+$b3,1):.1f}x')"
