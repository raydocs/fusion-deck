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

# `--print-tier`: resolve the tier and exit, doing no mapping. Callers that cache blocks must key on the
# tier that produced them (a REGEX block reused after tree-sitter is installed is a silent fidelity lie),
# and they must not re-derive availability themselves — a second copy of that logic would drift from this
# one. Costs only the bounded availability probes.
if [ "${1:-}" = "--print-tier" ]; then
  echo "CODEMAP_STATE=$tier"
  exit 0
fi

# Collect the source files to map: explicit files as-is; directories walked for common source extensions.
# NUL-delimited throughout so paths with spaces survive.
#
# Directory walks PRUNE well-known build/vendor output (Library, Temp, obj, bin, build, dist, target,
# vendor, __pycache__, .venv/venv) on top of .git/node_modules/.fusion*. Walking a gitignored multi-GB
# build tree is the same silent-slowness bug as `grep -r` over `.git` — and none of it is source worth
# mapping. An explicit FILE argument is always honored as-is, so a pruned path can still be forced in.
collect_files() {
  # Extension predicates come from the ONE shared list (FUSION_SOURCE_EXT in gemini_backend.sh) — a
  # second copy here would drift and silently drop a language.
  # read -ra, not `for e in $LIST`: the unquoted form depends on the shell doing word-splitting (bash
  # does, zsh does not) — the same fragility fusion_is_source_path was rewritten to avoid.
  local ext_args=() exts=() e first=1
  read -ra exts <<< "$FUSION_SOURCE_EXT"
  for e in "${exts[@]}"; do
    if [ "$first" -eq 1 ]; then ext_args+=( -name "*.$e" ); first=0
    else                        ext_args+=( -o -name "*.$e" ); fi
  done
  for arg in "$@"; do
    if [ -f "$arg" ]; then
      printf '%s\0' "$arg"
    elif [ -d "$arg" ]; then
      # -prune, NOT `! -path`. `! -path '*/Library/*'` still DESCENDS into the directory and tests every
      # file inside it before rejecting them — on a Unity `Library/` that is hundreds of thousands of
      # stats for zero results. -prune never enters. Same class of bug as `grep -r` reading `.git`.
      find "$arg" \( \
          -name '.git' -o -name 'node_modules' -o -name '.fusion-worktrees' -o -name '.fusion' -o \
          -name 'Library' -o -name 'Temp' -o -name 'obj' -o -name 'bin' -o -name 'build' -o \
          -name 'dist' -o -name 'target' -o -name 'vendor' -o -name '__pycache__' -o \
          -name '.venv' -o -name 'venv' \
        \) -prune -o -type f \( "${ext_args[@]}" \) -print0
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
#
# Modifier-led declarations: C#/Java/Swift/Kotlin declare with `public class X` and — for methods — with
# NO keyword at all (`public void Bind(Actor a)`, `private static float Clamp01(float v)`). A keyword-only
# pattern maps zero signatures on those repos while still exiting 0, which is a silent empty map. So the
# modifier prefix is optional-repeatable before the keyword group, and a second alternation catches
# `<modifier>+ <return-type> <name>(` methods. Requiring at least one modifier there keeps `if (`/`while (`
# and ordinary call sites out.
_CM_MOD='(public|private|protected|internal|open|final|override|virtual|abstract|static|sealed|partial|suspend|export|async|inline|extern)'
emit_regex() {
  local f="$1"
  printf 'File: %s\n' "$f"
  # Markdown has no declarations, so the keyword pattern maps it to an EMPTY block — 150 of them in a
  # 498-file repo, each still flagged ' +' in file_map as if signatures existed. A doc's structure IS its
  # heading outline, so emit that: the block becomes useful instead of a lie.
  case "$f" in
    *.md)
      # Capped: an append-only doc (session log, changelog) can carry thousands of headings, and an
      # uncapped outline would outweigh the source files the map exists to describe.
      grep -nE '^#{1,6}[[:space:]]+\S' "$f" 2>/dev/null | head -n "${FUSION_CODEMAP_MD_MAX_HEADINGS:-40}" || true
      printf '\n'
      return 0
      ;;
  esac
  printf 'Imports:\n'
  grep -nE '^[[:space:]]*(import |from |#include |require\(|use |using |source |package |\. )' "$f" 2>/dev/null \
    | sed 's/^/  /' || true
  grep -nE '^[[:space:]]*(('"$_CM_MOD"'[[:space:]]+)*(class |def |func |fn |function |type |interface |struct |trait |impl |enum |module |sub |proc |record |protocol |object )|('"$_CM_MOD"'[[:space:]]+)+[]A-Za-z0-9_<>,.?[]*[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(|[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(\)[[:space:]]*\{?[[:space:]]*$)' "$f" 2>/dev/null \
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
    # Modifier-led languages. get_parser() raises for a grammar this install lacks; the caller then
    # degrades THAT file to regex and says so on stderr, so an optimistic entry costs nothing.
    ".cs": "c_sharp", ".swift": "swift", ".kt": "kotlin", ".kts": "kotlin",
    ".php": "php", ".scala": "scala", ".lua": "lua", ".m": "objc", ".mm": "objc",
}
# Node types whose HEADER line is a signature worth emitting (definitions, not bodies).
DEF_TYPES = {
    "function_definition", "function_declaration", "method_definition", "class_definition",
    "class_declaration", "type_alias_declaration", "interface_declaration", "struct_item",
    "function_item", "impl_item", "trait_item", "type_definition", "method", "module",
    "type_spec", "type_declaration", "enum_declaration", "enum_item", "function_signature",
    # C# / Swift / Kotlin / PHP: methods and properties are their own node types, not "function_*".
    "method_declaration", "constructor_declaration", "property_declaration", "record_declaration",
    "struct_declaration", "delegate_declaration", "operator_declaration", "protocol_declaration",
    "object_declaration", "init_declaration", "subscript_declaration", "secondary_constructor",
}
IMPORT_TYPES = {
    "import_statement", "import_from_statement", "import_declaration", "use_declaration",
    "preproc_include", "package_clause",
    "using_directive", "import_header", "namespace_use_declaration", "import_spec",
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
            # C#/Java/Kotlin/Swift wrap members in an intermediate body node (declaration_list,
            # class_body), so descending only into the type node itself would find no methods.
            if ch.type in ("class_definition", "class_declaration", "impl_item",
                           "module", "namespace_definition", "namespace_declaration",
                           "struct_declaration", "interface_declaration", "record_declaration",
                           "object_declaration", "protocol_declaration",
                           "declaration_list", "class_body", "enum_body") or depth == 0:
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

# An empty map is NEVER a success. Exiting 0 here let a caller ship a codemap-shaped artifact with no
# map in it — e.g. /fusion-review's caller-context fallback on a C# repo, where the extension list matched
# nothing and the panel was handed context-free "context". Same honest-degrade rule as detect_panel.sh:
# report what actually ran, and make "nothing ran" loud. Exit 3 (2 is already usage).
if [ "$n_files" -eq 0 ]; then
  echo "codemap: no source files found in the given path(s) — refusing to emit an empty map." >&2
  echo "codemap: if the language is unmapped, add its extension to collect_files (and EXT/DEF_TYPES" >&2
  echo "codemap: for the tree-sitter tier); if the path was pruned as build output, pass the file(s)" >&2
  echo "codemap: explicitly — explicit FILE arguments bypass the prune list." >&2
  echo "CODEMAP_FILES=0"
  echo "CODEMAP_STATE=$tier"
  exit 3
fi

# Honest-degrade backstop: if TREESITTER was selected but NOT ONE file actually parsed at that fidelity
# (e.g. python lacks the grammar for every file's language), report the floor that truly ran — REGEX.
if [ "$tier" = TREESITTER ] && [ "$ts_emitted" -eq 0 ]; then
  echo "codemap: TREESITTER selected but no file parsed at that tier — reporting REGEX (what actually ran)." >&2
  tier=REGEX
fi

# The greppable disclosure lines — how many files were actually mapped, and the tier that ACTUALLY ran
# (never the one merely requested).
echo "CODEMAP_FILES=$n_files"
echo "CODEMAP_STATE=$tier"
