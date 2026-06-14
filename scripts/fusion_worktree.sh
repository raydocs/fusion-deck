#!/usr/bin/env bash
# fusion_worktree.sh — portable git-worktree isolation for /fusion-orchestrate parallel dispatch.
#
# When the orchestrator runs sibling items in parallel and they could collide on disk, each gets its OWN
# worktree (a separate checkout sharing the repo's object store) on its OWN branch. The judge then reviews
# each worktree's diff before anything merges back. This is the PORTABLE fallback; a Claude Code harness
# that exposes native subagent worktree isolation (EnterWorktree) should be preferred — see worktrees.md.
#
# A worktree is a clean checkout — it does NOT carry git-IGNORED local files (.env.local, build caches,
# venvs). Some of those a sibling genuinely needs to run. `.worktreeinclude` (repo root, gitignore syntax)
# is the OPT-IN allowlist: only files git ALREADY ignores AND that the include positively matches are
# copied. We NEVER copy tracked files, dirty files, symlinks, or anything that escapes the repo.
#
# Subcommands:
#   create <id> [base-ref]   add a worktree at .fusion-worktrees/<id> on branch fusion/<id>, then copy
#                            the .worktreeinclude-matched ignored files into it
#   cleanup <id>             git worktree remove it safely
#   list                     list fusion-managed worktrees
#
# Greppable output lines (the orchestrator keys on these):
#   WORKTREE_STATE=<OK|EXISTS|NO_GIT|ERROR>
#   WORKTREE_PATH=<abs path>      (create, on OK)
#   WORKTREE_BRANCH=<branch>      (create, on OK)
#   COPIED=<n>                    (create, on OK — count of .worktreeinclude files copied)
#
# It NEVER claims a capability it did not run: not in a repo => WORKTREE_STATE=NO_GIT and a non-zero exit,
# never a faked OK. Honest-degrade is the cardinal rule (see references/degraded-mode.md).

set -uo pipefail

WT_DIR=".fusion-worktrees"        # repo-relative home for fusion worktrees
BRANCH_PREFIX="fusion/"           # branch namespace, so `list` and cleanup can find our own
INCLUDE_FILE=".worktreeinclude"   # repo-root allowlist, gitignore syntax

die_usage() {
  cat >&2 <<'EOF'
usage: fusion_worktree.sh <subcommand> [args]
  create <id> [base-ref]   add .fusion-worktrees/<id> on branch fusion/<id>; copy .worktreeinclude files
  cleanup <id>             remove the worktree for <id>
  list                     list fusion-managed worktrees
EOF
  echo "WORKTREE_STATE=ERROR"
}

# Must be inside a work tree. Print NO_GIT and fail otherwise — never pretend.
require_git() {
  if ! command -v git >/dev/null 2>&1 \
     || [ "$(git rev-parse --is-inside-work-tree 2>/dev/null)" != "true" ]; then
    echo "not inside a git work tree — worktree isolation unavailable." >&2
    echo "WORKTREE_STATE=NO_GIT"
    return 1
  fi
  return 0
}

# Repo top level (absolute). Caller has already passed require_git.
repo_root() { git rev-parse --show-toplevel; }

# Validate an <id>: a single safe path segment (no slashes, no '..', no leading dash/dot). The id becomes
# both a directory name and a branch suffix, so keep it boring.
valid_id() {
  case "$1" in
    ""|.*|-*|*/*|*..*) return 1 ;;
    *[!A-Za-z0-9._-]*) return 1 ;;
    *) return 0 ;;
  esac
}

cmd_create() {
  require_git || return 1
  local id="${1:-}" base="${2:-}"
  if ! valid_id "$id"; then
    echo "error: invalid <id> (use [A-Za-z0-9._-], no slashes, no leading dot/dash)." >&2
    echo "WORKTREE_STATE=ERROR"; return 2
  fi

  local root; root="$(repo_root)"
  local rel="$WT_DIR/$id"
  local abs="$root/$rel"
  local branch="$BRANCH_PREFIX$id"

  # Already there? Report EXISTS and stop — don't clobber another item's worktree.
  if [ -e "$abs" ] || git show-ref --verify --quiet "refs/heads/$branch" \
     || git worktree list --porcelain 2>/dev/null | grep -qxF "worktree $abs"; then
    echo "worktree '$id' already exists at $rel (branch $branch) — refusing to overwrite." >&2
    echo "WORKTREE_STATE=EXISTS"; return 1
  fi

  # New branch off base-ref (default: current HEAD). `git worktree add -b` is atomic: branch + checkout.
  local add_out
  if [ -n "$base" ]; then
    add_out="$(git worktree add -b "$branch" "$abs" "$base" 2>&1)"
  else
    add_out="$(git worktree add -b "$branch" "$abs" 2>&1)"
  fi
  if [ $? -ne 0 ]; then
    echo "error: git worktree add failed:" >&2
    echo "$add_out" >&2
    echo "WORKTREE_STATE=ERROR"; return 1
  fi

  local copied
  copied="$(copy_includes "$root" "$abs")"

  echo "created worktree '$id'."
  echo "WORKTREE_STATE=OK"
  echo "WORKTREE_PATH=$abs"
  echo "WORKTREE_BRANCH=$branch"
  echo "COPIED=$copied"
  return 0
}

# Copy git-IGNORED, .worktreeinclude-matched, real regular files from <root> into <dest>.
# Echoes the count copied. Skips silently (COPIED=0) when there is no include file. The gate is doubled:
#   1. the include must POSITIVELY match it — `ls-files --others --ignored --exclude-from=<inc>` lists the
#      UNTRACKED files the include rules alone select (this is git's own primitive; it expands matched dirs
#      to their files, honors '!' negation, and already excludes tracked files).
#   2. git must ALREADY ignore the path (`check-ignore -q`) — opt-in is not enough; an untracked file that
#      the include matches but the repo does NOT ignore (a to-be-tracked new file) is refused.
# Plus per-file safety in copy_one: real regular file only (no symlinks), inside the worktree (no escape).
#
# Note: `git check-ignore` has no --exclude-from; ls-files --exclude-from is the correct primitive for the
# positive-match gate. Per gitignore semantics, a '!' negation CANNOT re-include a file under a directory
# that was matched as a whole (e.g. `.venv/` then `!.venv/**/__pycache__/` does not re-exclude the cache) —
# that is a git limitation, not ours; list the dir's children individually if you need to carve some out.
copy_includes() {
  local root="$1" dest="$2"
  local inc="$root/$INCLUDE_FILE"
  [ -f "$inc" ] || { echo 0; return 0; }

  local n=0 path
  # Files the .worktreeinclude rules positively select (gate 1), NUL-delimited so spaces/newlines survive.
  # --others excludes tracked files; --ignored + --exclude-from scopes to the include's own patterns.
  while IFS= read -r -d '' path; do
    # Gate 2 — the repo must ALREADY ignore it (reject untracked-but-not-ignored, to-be-tracked files).
    git -C "$root" check-ignore -q -- "$path" 2>/dev/null || continue
    copy_one "$root" "$dest" "$path" && n=$((n + 1))
  done < <(git -C "$root" ls-files --others --ignored --exclude-from="$inc" -z 2>/dev/null)

  echo "$n"
}

# A file whose basename looks like a secret (mirrors safety.md / selection_lint DENY_GLOBS). Used only to
# print a transparency note on copy — it does NOT block (carrying local secrets is .worktreeinclude's job).
_looks_secret() {
  case "$(basename "$1")" in
    .env|.env.*|*.pem|*.key|id_rsa|id_rsa.*|credentials*|secrets*|*.p12|*.keystore) return 0 ;;
    *) return 1 ;;
  esac
}

# Copy a single repo-relative <path> from <root> to <dest>, with safety gates. Returns 0 iff copied.
copy_one() {
  local root="$1" dest="$2" path="$3"
  local src="$root/$path" out="$dest/$path"

  # Regular files only — no symlinks, no non-regular files.
  [ -f "$src" ] || return 1
  [ -L "$src" ] && return 1

  # Escape guard: the resolved destination must stay under <dest>. Portable (no `realpath -m`): resolve
  # the parent dir with pwd -P, then re-append the basename.
  local parent base resolved
  parent="$(dirname "$out")"
  base="$(basename "$out")"
  mkdir -p "$parent" 2>/dev/null || return 1
  resolved="$(cd "$parent" 2>/dev/null && pwd -P)/$base" || return 1
  case "$resolved" in
    "$dest"/*) : ;;            # ok — stays inside the worktree
    *) return 1 ;;            # would escape — refuse
  esac

  cp -p "$src" "$out" 2>/dev/null || return 1
  # Transparency: .worktreeinclude is opt-in, but a broad glob (`*.local`) can sweep in a secret the author
  # didn't single out. We still copy it (that IS the feature — the sibling may need it), but never silently.
  _looks_secret "$path" && \
    echo "fusion_worktree: copied a secret-shaped file into the worktree — $path (stays local; never commit it)" >&2
  return 0
}

cmd_cleanup() {
  require_git || return 1
  local id="${1:-}"
  if ! valid_id "$id"; then
    echo "error: invalid <id>." >&2
    echo "WORKTREE_STATE=ERROR"; return 2
  fi
  local root; root="$(repo_root)"
  local abs="$root/$WT_DIR/$id"
  local branch="$BRANCH_PREFIX$id"

  if ! git worktree list --porcelain 2>/dev/null | grep -qxF "worktree $abs"; then
    echo "no fusion worktree registered at $WT_DIR/$id." >&2
    echo "WORKTREE_STATE=ERROR"; return 1
  fi

  local rm_out
  rm_out="$(git worktree remove "$abs" 2>&1)"
  if [ $? -ne 0 ]; then
    echo "error: git worktree remove failed (uncommitted changes? use the diff first):" >&2
    echo "$rm_out" >&2
    echo "WORKTREE_STATE=ERROR"; return 1
  fi
  # Safe branch delete: `-d` REFUSES to drop an unmerged branch, so committed-but-unmerged work is kept
  # (the diff may not have been reviewed/merged yet). If it's kept, say how to force-delete after merge.
  if ! git branch -d "$branch" >/dev/null 2>&1; then
    echo "note: branch $branch kept (has unmerged commits) — after merging, delete with: git branch -D $branch" >&2
  fi

  echo "removed worktree '$id'."
  echo "WORKTREE_STATE=OK"
  return 0
}

cmd_list() {
  require_git || return 1
  local root; root="$(repo_root)"
  local prefix="$root/$WT_DIR/"
  local found=0 path=""

  echo "fusion-managed worktrees under $WT_DIR/:"
  # Parse porcelain: a 'worktree <abs>' line begins each record; the following 'branch <ref>' names it.
  while IFS= read -r line; do
    case "$line" in
      "worktree "*) path="${line#worktree }" ;;
      "branch "*)
        case "$path" in
          "$prefix"*)
            printf "  %-40s %s\n" "${path#"$root"/}" "${line#branch refs/heads/}"
            found=$((found + 1)) ;;
        esac ;;
    esac
  done < <(git worktree list --porcelain 2>/dev/null)

  [ "$found" -eq 0 ] && echo "  (none)"
  echo "WORKTREE_STATE=OK"
  return 0
}

main() {
  local sub="${1:-}"
  case "$sub" in
    create)  shift; cmd_create "$@" ;;
    cleanup) shift; cmd_cleanup "$@" ;;
    list)    shift; cmd_list "$@" ;;
    -h|--help|"") die_usage; return 2 ;;
    *) echo "error: unknown subcommand '$sub'." >&2; die_usage; return 2 ;;
  esac
}

main "$@"
