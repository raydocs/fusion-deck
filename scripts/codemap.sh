#!/usr/bin/env bash
# codemap.sh — emit a SIGNATURES-ONLY codemap of source files (imports + class/func/type signatures,
# no bodies) at the best fidelity the machine can honestly support.
#
# This is the "Codemap" density tier of a Context Pack (context-pack-format.md): peripheral orientation
# files get cheap structure, not full bodies. Three tiers, best-available-first, with HONEST fallback —
# the same honest-degrade discipline as detect_panel.sh / degraded-mode.md, applied to context instead of
# the panel. It NEVER claims a tier it did not run.
#
#   TREESITTER  python can import `tree_sitter_languages` (the bundled grammars) — real parse trees.
#   CTAGS       else if ctags/universal-ctags runs — signatures via the ctags index.
#   REGEX       else ALWAYS — a zero-dependency grep heuristic. The floor. Always works.
#
# The DEFAULT is REGEX (zero deps); ctags/tree-sitter are OPTIONAL auto-detected upgrades. This is
# deliberately NOT a port of RepoPrompt's tree-sitter engine — it stays a thin helper (the skill's stated
# caution in context-pack-format.md against a "mini-RepoPrompt").
#
# Override: FUSION_CODEMAP_TIER=regex|ctags|treesitter forces a tier — but if the forced tier is
# unavailable it DEGRADES to the best available and prints the tier ACTUALLY used. The override can only
# cap fidelity honestly; it can never conjure a missing tool.
#
# Output: per file a 'File:' header, 'Imports:' lines, then signature lines. Final greppable line:
#   CODEMAP_STATE=<TREESITTER|CTAGS|REGEX>
#
# Usage: bash codemap.sh <path> [<path> ...]   (files and/or directories; dirs are walked for source)

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/gemini_backend.sh"

if [ "$#" -eq 0 ] || [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  sed -n '2,30p' "$0"
  echo
  echo "usage: bash codemap.sh <path> [<path> ...]"
  exit 2
fi

# A tool counts as available only if it's on PATH AND actually runs — presence != working.
# Bounded via shared fusion_bounded (timeout/gtimeout or bash watchdog).
ts_py_ok=false; ctags_ok=false
if command -v python3 >/dev/null 2>&1; then
  fusion_bounded python3 -c 'import tree_sitter_languages' >/dev/null 2>&1 && ts_py_ok=true
fi
# `ctags --version` prints "Universal Ctags" or "Exuberant Ctags"; both can emit signatures we use.
if command -v ctags >/dev/null 2>&1; then
  fusion_bounded ctags --version >/dev/null 2>&1 && ctags_ok=true
fi

# Only python `tree_sitter_languages` actually parses (emit_treesitter routes through it). A bare
# `tree-sitter` CLI is NOT counted — it cannot parse arbitrary files here, so claiming TREESITTER on the
# strength of the CLI alone would be an honest-degrade lie. Availability == the thing that really emits.
treesitter_avail=$ts_py_ok

# Resolve the tier to USE. The override caps fidelity but never invents a tool: a forced tier that is
# unavailable falls through to the best available, and we report what actually ran.
forced="${FUSION_CODEMAP_TIER:-}"
case "$(printf '%s' "$forced" | tr '[:upper:]' '[:lower:]')" in
  treesitter|tree-sitter|ts)
    if   $treesitter_avail; then tier=TREESITTER
    elif $ctags_ok;         then tier=CTAGS;  echo "codemap: FUSION_CODEMAP_TIER=treesitter unavailable — degrading to CTAGS" >&2
    else                         tier=REGEX;  echo "codemap: FUSION_CODEMAP_TIER=treesitter unavailable — degrading to REGEX" >&2
    fi ;;
  ctags)
    if   $ctags_ok;         then tier=CTAGS
    else                         tier=REGEX;  echo "codemap: FUSION_CODEMAP_TIER=ctags unavailable — degrading to REGEX" >&2
    fi ;;
  regex)
    tier=REGEX ;;                              # an explicit floor request — always honored exactly
  "")
    if   $treesitter_avail; then tier=TREESITTER
    elif $ctags_ok;         then tier=CTAGS
    else                         tier=REGEX
    fi ;;
  *)
    echo "codemap: unknown FUSION_CODEMAP_TIER='$forced' (want regex|ctags|treesitter) — auto-detecting" >&2
    if   $treesitter_avail; then tier=TREESITTER
    elif $ctags_ok;         then tier=CTAGS
    else                         tier=REGEX
    fi ;;
esac

# Collect the source files to map: explicit files as-is; directories walked for common source extensions.
# NUL-delimited throughout so paths with spaces survive.
collect_files() {
  for arg in "$@"; do
    if [ -f "$arg" ]; then
      printf '%s\0' "$arg"
    elif [ -d "$arg" ]; then
      find "$arg" -type f \( \
        -name '*.py'  -o -name '*.sh'  -o -name '*.bash' -o -name '*.js'  -o -name '*.jsx' -o \
        -name '*.ts'  -o -name '*.tsx' -o -name '*.go'   -o -name '*.rs'  -o -name '*.rb'  -o \
        -name '*.java' -o -name '*.c'  -o -name '*.h'    -o -name '*.cc'  -o -name '*.cpp' -o \
        -name '*.hpp' -o -name '*.md' \) \
        ! -path '*/.git/*' ! -path '*/node_modules/*' ! -path '*/.fusion-worktrees/*' -print0
    else
      echo "codemap: skip '$arg' (not a file or directory)" >&2
    fi
  done
}

# ── REGEX tier ─────────────────────────────────────────────────────────────────────────────────────────
# Zero-dependency floor. Improves on the context-pack-format.md one-liner three ways: it SEPARATES import
# lines from signature lines (so the output already matches the 'Imports:' + signatures block format),
# strips trailing block-open punctuation ('{') so a signature reads as a signature not a body opener, and
# it also catches POSIX-shell `name()` function definitions (this very skill is mostly bash — the keyword
# heuristic alone would map none of it).
emit_regex() {
  local f="$1"
  printf 'File: %s\n' "$f"
  printf 'Imports:\n'
  grep -nE '^[[:space:]]*(import |from |#include |require\(|use |using |source |\. )' "$f" 2>/dev/null \
    | sed 's/^/  /' || true
  grep -nE '^[[:space:]]*((export[[:space:]]+)?(async[[:space:]]+)?(class |def |func |fn |function |type |interface |struct |trait |impl |enum |module |sub |proc )|[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(\)[[:space:]]*\{?[[:space:]]*$)' "$f" 2>/dev/null \
    | sed -E 's/[[:space:]]*\{[[:space:]]*$//' || true
  printf '\n'
}

# ── CTAGS tier ─────────────────────────────────────────────────────────────────────────────────────────
# Use ctags' index for kinds + signatures. Universal Ctags exposes --fields=+S (signature) and a JSON-ish
# tab format; we parse the tab format (works on both Universal and Exuberant). Imports still come from the
# regex pass — ctags does not reliably index import statements, and an honest map says where it got each
# part rather than pretending ctags produced something it didn't.
emit_ctags() {
  local f="$1"
  printf 'File: %s\n' "$f"
  printf 'Imports:\n'
  grep -nE '^[[:space:]]*(import |from |#include |require\(|use |using )' "$f" 2>/dev/null \
    | sed 's/^/  /' || true
  # ctags -x gives a human cross-ref: "<name> <kind> <line> <file> <source-line>". Keep def-like kinds.
  fusion_bounded ctags -x --c-kinds=+p "$f" 2>/dev/null \
    | awk '$2 ~ /^(function|class|method|member|struct|interface|type|typedef|enum|trait|module|namespace|prototype|subroutine|func)$/ {
             kind=$2; line=$3; $1=""; $2=""; $3=""; $4="";
             sub(/^[ \t]+/,""); printf "  %s [%s:%s]\n", $0, kind, line }' \
    || true
  printf '\n'
}

# ── TREESITTER tier ────────────────────────────────────────────────────────────────────────────────────
# Real parse trees via the python `tree_sitter_languages` grammars (preferred; the `tree-sitter` CLI
# without configured grammars cannot parse arbitrary files, so we route through python when it has the
# grammars). Walks the top level of the tree and prints the source text of each definition node's
# header line — bodies excluded. If python parsing fails for a given file, we degrade THAT file to regex
# and say so on stderr; the global CODEMAP_STATE still reflects the requested tier only if it really ran.
emit_treesitter() {
  local f="$1"
  if $ts_py_ok && fusion_bounded python3 "$_TS_HELPER" "$f"; then
    ts_emitted=$((ts_emitted + 1)); return 0
  fi
  echo "codemap: tree-sitter parse failed for '$f' — falling back to regex for this file" >&2
  emit_regex "$f"
}

# The python helper is materialized once to a temp file (portable; avoids a brittle heredoc-per-file).
_TS_HELPER=""
if [ "$tier" = TREESITTER ] && $ts_py_ok; then
  _TS_HELPER="$(mktemp -t fusion_codemap_ts.XXXXXX 2>/dev/null || echo "/tmp/fusion_codemap_ts.$$")"
  cat > "$_TS_HELPER" <<'PYEOF'
import sys
from tree_sitter_languages import get_parser

EXT = {
    ".py": "python", ".js": "javascript", ".jsx": "javascript", ".ts": "typescript",
    ".tsx": "tsx", ".go": "go", ".rs": "rust", ".rb": "ruby", ".java": "java",
    ".c": "c", ".h": "c", ".cc": "cpp", ".cpp": "cpp", ".hpp": "cpp",
}
# Node types whose HEADER line is a signature worth emitting (definitions, not bodies).
DEF_TYPES = {
    "function_definition", "function_declaration", "method_definition", "class_definition",
    "class_declaration", "type_alias_declaration", "interface_declaration", "struct_item",
    "function_item", "impl_item", "trait_item", "type_definition", "method", "module",
    "type_spec", "type_declaration", "enum_declaration", "enum_item", "function_signature",
}
IMPORT_TYPES = {
    "import_statement", "import_from_statement", "import_declaration", "use_declaration",
    "preproc_include", "package_clause",
}

def header_line(src, node):
    # first physical line of the node's source — the signature, never the body.
    text = src[node.start_byte:node.end_byte].split(b"\n", 1)[0]
    return text.decode("utf-8", "replace").rstrip()

def main(path):
    import os
    ext = os.path.splitext(path)[1].lower()
    lang = EXT.get(ext)
    if lang is None:
        return 1
    with open(path, "rb") as fh:
        src = fh.read()
    parser = get_parser(lang)
    tree = parser.parse(src)
    print(f"File: {path}")
    imports, sigs = [], []
    def walk(node, depth=0):
        for ch in node.children:
            if ch.type in IMPORT_TYPES:
                imports.append(header_line(src, ch))
            if ch.type in DEF_TYPES:
                ln = ch.start_point[0] + 1
                sigs.append((ln, header_line(src, ch)))
            # recurse one extra level so methods inside a class are captured, but do not descend
            # into function bodies (we want signatures, not nested locals).
            if ch.type in ("class_definition", "class_declaration", "impl_item",
                           "module", "namespace_definition") or depth == 0:
                walk(ch, depth + 1)
    walk(tree.root_node, 0)
    print("Imports:")
    for imp in imports:
        print(f"  {imp}")
    for ln, sig in sorted(sigs):
        print(f"  {sig}  [line {ln}]")
    print()
    return 0

if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1]))
    except Exception as exc:  # noqa: BLE001 — any parse error => let bash fall back to regex
        print(f"codemap: tree-sitter helper error: {exc}", file=sys.stderr)
        sys.exit(1)
PYEOF
  trap '[ -n "${_TS_HELPER:-}" ] && rm -f "$_TS_HELPER"' EXIT
fi

# ── Drive the chosen tier over every collected file ──────────────────────────────────────────────────────
n_files=0
ts_emitted=0   # count of files that ACTUALLY parsed at the TREESITTER tier (for the honest-degrade check)
while IFS= read -r -d '' file; do
  n_files=$((n_files + 1))
  case "$tier" in
    TREESITTER) emit_treesitter "$file" ;;
    CTAGS)      emit_ctags      "$file" ;;
    REGEX)      emit_regex      "$file" ;;
  esac
done < <(collect_files "$@")

if [ "$n_files" -eq 0 ]; then
  echo "codemap: no source files found in the given path(s)." >&2
fi

# Honest-degrade backstop: if TREESITTER was selected but NOT ONE file actually parsed at that fidelity
# (e.g. python lacks the grammar for every file's language), report the floor that truly ran — REGEX.
if [ "$tier" = TREESITTER ] && [ "$ts_emitted" -eq 0 ]; then
  echo "codemap: TREESITTER selected but no file parsed at that tier — reporting REGEX (what actually ran)." >&2
  tier=REGEX
fi

# The single greppable disclosure line — the tier that ACTUALLY ran, never the one merely requested.
echo "CODEMAP_STATE=$tier"
