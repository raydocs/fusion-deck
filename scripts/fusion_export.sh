#!/usr/bin/env bash
# fusion_export.sh — compute a safe, repo-relative path for a fusion export, and clean up stale ones.
#
# The point (borrowed from RepoPrompt CE's prompt-exports + stray-export cleanup): a panel command's
# judged output should land in a real file under .fusion/exports/ so the NEXT step (a subagent, another
# model, or future-you) reads it BY PATH instead of having it re-summarized inline and drift. Pairs with
# the Handoff Capsule.
#
# Usage:
#   fusion_export.sh path <verb> <slug-source-text...>   print a repo-relative export path (mkdir -p'd)
#   fusion_export.sh cleanup [days]                       delete exports older than <days> (default 14)
#   fusion_export.sh -h | --help                          this help
#
# Notes:
#   * The path is .fusion/exports/<verb>-<YYYY-MM-DD>-<slug>.md, repo-relative (git toplevel if available,
#     else CWD). Never an absolute path in shared artifacts (safety.md).
#   * <verb> is normalized to a short token (fusion|plan|review|investigate|optimize|orchestrate|handoff
#     or any [a-z0-9-] string). <slug> is derived from the task text: lowercased, non-alnum -> '-', capped.
#   * This script only computes a path and prunes old files; it never writes export CONTENT (the command
#     does that) and never reads or emits secrets.

set -uo pipefail

die() { echo "fusion_export: $*" >&2; exit 2; }

repo_root() {
  if command -v git >/dev/null 2>&1 && git rev-parse --show-toplevel >/dev/null 2>&1; then
    git rev-parse --show-toplevel
  else
    pwd
  fi
}

slugify() {
  # lowercase, every run of non-[a-z0-9] -> single '-', strip leading/trailing '-', cap to 48 chars.
  printf '%s' "$*" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' \
    | cut -c1-48 \
    | sed -E 's/-+$//'
}

cmd="${1:-}"
case "$cmd" in
  -h|--help|"")
    sed -n '2,26p' "$0"; echo; echo "usage: fusion_export.sh path <verb> <slug-text> | cleanup [days]"; exit 0 ;;

  path)
    verb_raw="${2:-}"; shift 2 2>/dev/null || true
    [ -n "$verb_raw" ] || die "path: need a <verb>"
    [ "$#" -ge 1 ] || die "path: need slug source text"
    verb="$(slugify "$verb_raw")"; [ -n "$verb" ] || die "path: empty verb after normalize"
    slug="$(slugify "$*")"; [ -n "$slug" ] || slug="untitled"
    root="$(repo_root)"
    day="$(date +%F)"                              # YYYY-MM-DD
    rel=".fusion/exports/${verb}-${day}-${slug}.md"
    mkdir -p "$root/.fusion/exports" || die "cannot create $root/.fusion/exports"
    # If the same verb+day+slug already exists, suffix -2, -3, … so we never clobber a prior export.
    if [ -e "$root/$rel" ]; then
      i=2
      while [ -e "$root/.fusion/exports/${verb}-${day}-${slug}-${i}.md" ]; do i=$((i + 1)); done
      rel=".fusion/exports/${verb}-${day}-${slug}-${i}.md"
    fi
    printf '%s\n' "$rel"
    ;;

  cleanup)
    days="${2:-14}"
    case "$days" in (*[!0-9]*|"") die "cleanup: <days> must be a non-negative integer" ;; esac
    root="$(repo_root)"; dir="$root/.fusion/exports"
    [ -d "$dir" ] || { echo "fusion_export: nothing to clean ($dir absent)"; exit 0; }
    removed=0
    # -mtime +N is "older than N days". NUL-safe loop so spaced names survive.
    while IFS= read -r -d '' f; do
      rm -f "$f" && removed=$((removed + 1)) && echo "  pruned $(basename "$f")"
    done < <(find "$dir" -type f -name '*.md' -mtime +"$days" -print0 2>/dev/null)
    echo "fusion_export: pruned $removed stale export(s) older than ${days}d from $dir"
    ;;

  *)
    die "unknown subcommand '$cmd' (want: path | cleanup | --help)" ;;
esac
