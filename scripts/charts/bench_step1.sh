#!/usr/bin/env bash
# bench_step1.sh — Step-1 mechanical phase: session-start baseline (31dbda2) vs HEAD, same 20-symbol diff.
set -uo pipefail
SK=/Users/ruirui/Downloads/GitHub/fusion-deck
repo="${1:?usage: ab2.sh <repo>}"
tb=$(mktemp -d)
( cd "$SK" && git archive 31dbda2 scripts | tar -xf - -C "$tb" )
cd "$repo" || exit 2

f=$(git ls-files '*.cs' '*.py' '*.ts' | head -1)
real=$(git ls-files '*.cs' '*.py' '*.ts' | head -80 \
  | tr '\n' '\0' | xargs -0 grep -hoE '\b(class|def)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' 2>/dev/null \
  | awk '{print $2}' | sort -u | head -20)
case "$f" in
  *.cs) { echo; for c in $real; do echo "public class $c {}"; done; } >> "$f" ;;
  *)    { echo; for c in $real; do echo "class $c: pass"; done; } >> "$f" ;;
esac
printf '%s\n' $real > /tmp/ab_syms.txt
n=$(grep -c . /tmp/ab_syms.txt)

now(){ python3 -c 'import time;print(time.time())'; }
el(){ python3 -c "import sys;print(f'{(float(sys.argv[2])-float(sys.argv[1]))*1000:.0f}')" "$1" "$2"; }

o1=$(mktemp -d)
s=$(now); bash "$tb/scripts/review_packet.sh" uncommitted "$o1" >/dev/null 2>&1; a1=$(el $s $(now))
s=$(now); for x in $real; do grep -rnw --include='*.*' "$x" . 2>/dev/null | grep -v '^\./\.git/' | head -20; done > "$o1/c.txt" 2>/dev/null; a2=$(el $s $(now))
s=$(now); bash "$tb/scripts/codemap.sh" . > "$o1/m.txt" 2>/dev/null; a3=$(el $s $(now))

c=$(mktemp -d); o2=$(mktemp -d)
FUSION_MAP_CACHE=$c bash "$SK/scripts/fusion_map.sh" "$o2" >/dev/null 2>&1     # warm
s=$(now); bash "$SK/scripts/review_packet.sh" uncommitted "$o2" >/dev/null 2>&1; b1=$(el $s $(now))
s=$(now); bash "$SK/scripts/caller_slices.sh" uncommitted "$o2" >/dev/null 2>&1; b2=$(el $s $(now))
s=$(now); FUSION_MAP_CACHE=$c bash "$SK/scripts/fusion_map.sh" "$o2" >/dev/null 2>&1; b3=$(el $s $(now))

printf '  symbols=%s\n' "$n"
printf '  BASE  packet=%-6s callers=%-7s map=%-6s total=%s\n' "$a1" "$a2" "$a3" "$((a1+a2+a3))"
printf '  HEAD  packet=%-6s callers=%-7s map=%-6s total=%s\n' "$b1" "$b2" "$b3" "$((b1+b2+b3))"
python3 -c "print(f'  -> {($a1+$a2+$a3)/($b1+$b2+$b3):.1f}x')"
git checkout "$f" 2>/dev/null; rm -rf "$tb" "$o1" "$o2" "$c"
