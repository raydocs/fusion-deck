#!/usr/bin/env bash
# review_packet.sh — pre-generate a code-review packet ONCE to a file, so the diff bytes never
# pass through the orchestrator's own context and every panelist gets one identical view.
#
# Borrowed from superpowers' review-package: scripting the packet (vs. the orchestrator hand-running
# git log/--stat/diff in its own turn) keeps the diff out of context (~10% fewer tokens on a review)
# and pins one canonical view. The CLI panelists (codex/Gemini) run sandboxed and cannot Read a path,
# so the command cats this packet INTO prompt.md; the Opus panelist can be handed the path instead.
# -U10 gives each hunk enough surrounding context to judge without a second Read.
#
# Usage: review_packet.sh <scope> <out_dir>
#   <scope>    uncommitted | staged | back:N | <range>   (e.g. main...HEAD, HEAD~3..HEAD)
#   <out_dir>  where to write packet.md (the fusion run's out dir)
# Prints one honest status line (path + bytes + scope). Never emits the diff to stdout.
set -uo pipefail

scope="${1:?usage: review_packet.sh <scope> <out_dir>}"
out_dir="${2:?usage: review_packet.sh <scope> <out_dir>}"
git rev-parse --show-toplevel >/dev/null 2>&1 || { echo "review_packet: not a git repo" >&2; exit 2; }

case "$scope" in
  uncommitted) header="uncommitted working tree (vs HEAD)"
    log_cmd=(git status --short); stat_cmd=(git diff --stat); diff_cmd=(git diff -U10) ;;
  staged)      header="staged changes (index vs HEAD)"
    log_cmd=(git status --short); stat_cmd=(git diff --staged --stat); diff_cmd=(git diff --staged -U10) ;;
  back:*)      n="${scope#back:}"
    case "$n" in ''|*[!0-9]*) echo "review_packet: bad back:N '$scope'" >&2; exit 2 ;; esac
    range="HEAD~$n..HEAD"; header="last $n commit(s): $range"
    log_cmd=(git log --oneline "$range"); stat_cmd=(git diff --stat "$range"); diff_cmd=(git diff -U10 "$range") ;;
  *)
    if [[ "$scope" == *..* ]]; then
      range="$scope"; header="range: $range"
    elif git rev-parse --verify --quiet "${scope}^{commit}" >/dev/null; then
      range="${scope}...HEAD"
      header="range: $range (normalized from '$scope', merge-base diff)"
      echo "review_packet: scope '$scope' normalized to '$range'" >&2
    else
      echo "review_packet: unknown scope '$scope'" >&2
      exit 2
    fi
    log_cmd=(git log --oneline "$range"); stat_cmd=(git diff --stat "$range"); diff_cmd=(git diff -U10 "$range") ;;
esac

# Capture the diff first: an empty diff must be an honest error, not a headers-only packet.
diff_out="$("${diff_cmd[@]}" 2>/dev/null)"
if [ -z "$diff_out" ]; then
  echo "review_packet: empty diff for scope '$scope' — nothing to review" >&2
  exit 3
fi

mkdir -p "$out_dir"
out="$out_dir/packet.md"
{
  echo "# Review packet — $header"
  echo
  echo "## Commits / status"
  "${log_cmd[@]}" 2>/dev/null
  echo
  echo "## Files changed"
  "${stat_cmd[@]}" 2>/dev/null
  echo
  echo "## Diff (-U10)"
  printf '%s\n' "$diff_out"
} > "$out"

bytes=$(wc -c < "$out" | tr -d ' ')
echo "wrote $out: ${bytes} bytes (scope: $scope)"
