#!/usr/bin/env bash
# gemini_backend.sh — shared runtime library for fusion panel scripts.
#
# Provides: Gemini backend detection, bounded CLI probes, and shared guards
# (recursion, prompt-size, min-output) used by runners and panel gates.
#
# Default Gemini backend policy:
#   FUSION_GEMINI_BACKEND=auto prefers Antigravity CLI (`agy`).
#   Legacy `gemini` is used only when explicitly requested, because consumer
#   Gemini CLI auth stopped serving requests after 2026-06-18.

set -uo pipefail

# The source-file extension list, shared by every context builder (codemap.sh walks it, fusion_map.sh
# filters `git ls-files` by it). ONE list on purpose: two copies drift, and a stale copy that silently
# omits a language produces an empty-but-successful map — the exact failure this skill forbids. Add a
# language HERE, then add its grammar to codemap.sh's tree-sitter EXT/DEF_TYPES tables.
#
# Modifier-led languages (cs/swift/kt/php/scala) are load-bearing: they declare methods with no keyword,
# so they are the ones a keyword-only heuristic silently drops. See references/codemap.md.
FUSION_SOURCE_EXT="py sh bash js jsx ts tsx go rs rb java c h cc cpp hpp md cs swift kt kts m mm php scala lua"

# True if PATH has one of the shared source extensions. Used by git-driven callers that never walk a
# directory (so they get the same language coverage without duplicating the list).
# Matched with ONE padded case test rather than `for e in $FUSION_SOURCE_EXT` — that loop relies on the
# shell word-splitting an unquoted expansion, which bash does and zsh does not. Under zsh the list stayed
# a single token and the function matched NOTHING, i.e. a silent empty map. These scripts all run under a
# bash shebang so it never bit at runtime, but a check that can silently answer "no source files" for an
# entire repo should not depend on which shell sourced it.
fusion_is_source_path() {
  local p="${1:-}"
  case "$p" in *.*) ;; *) return 1 ;; esac
  case " $FUSION_SOURCE_EXT " in *" ${p##*.} "*) return 0 ;; esac
  return 1
}

# Build a DISPOSABLE, per-seat SNAPSHOT so a CLI panelist can read the code under review instead of
# answering from memory — without ever touching the operator's repo, and without a path back to it.
#
#   fusion_panel_workspace <repo> <dest>   -> echoes <dest> on success, non-zero + nothing on failure
#
# NOT a git worktree. A worktree's `.git` is a FILE containing `gitdir: <real repo>/.git/worktrees/<id>`,
# so one `git rev-parse --git-common-dir` walks a seat straight back to the operator's live checkout.
# Measured from inside a "isolated" worktree: it read `.fusion/exports/` (prior judged answers, which
# destroys the blindness invariant panel-prompt.md requires be enforced mechanically) and `.git/config`
# (remote URLs, which can carry tokens). `git archive` writes content with no backlink of any kind.
#
# Three properties the snapshot must hold, each of which failed at least once:
#   1. WRITES land nowhere real. The Antigravity seat runs with --dangerously-skip-permissions and has
#      no read-only mode, so it must never be pointed at the live tree.
#   2. NO BACKLINK, so blindness is structural rather than "happened not to look".
#   3. Each seat gets its OWN dest, so no seat can see another's scratch.
fusion_panel_workspace() {
  local repo="${1:?fusion_panel_workspace <repo> <dest>}" dest="${2:?}"
  local top patch keep
  top="$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null)" || return 1
  [ -n "$top" ] || return 1
  mkdir -p "$dest" 2>/dev/null || return 1
  git -C "$top" archive HEAD 2>/dev/null | ( cd "$dest" && tar -xf - ) 2>/dev/null || return 1

  patch="$dest.patch"
  if git -C "$top" diff HEAD --binary > "$patch" 2>/dev/null && [ -s "$patch" ]; then
    if ! ( cd "$dest" && git apply "$patch" ) 2>/dev/null \
       && ! ( cd "$dest" && patch -p1 --silent < "$patch" ) 2>/dev/null; then
      # Never claim a fidelity we did not achieve: say so, and let the caller disclose it.
      echo "[fusion_panel_workspace] could not apply the working-tree diff — the snapshot is at HEAD," >&2
      echo "[fusion_panel_workspace] so it does NOT contain uncommitted changes. Disclose this." >&2
    fi
  fi
  rm -f "$patch"

  # Untracked-but-not-ignored files are part of an `uncommitted` review and no diff carries them.
  #   - .fusion/ is skipped unconditionally: manifests and exported judgments from PRIOR runs, which a
  #     seat must not anchor on. Do not rely on the target repo's .gitignore; most repos have no rule.
  #   - SYMLINKS ARE REFUSED. `[ -f ]` and plain `cp` both FOLLOW links, so an untracked
  #     `key.py -> ~/.ssh/id_rsa` had its CONTENT copied into a directory whose entire purpose is to be
  #     handed to an external model. Verified exfiltration, not a hypothetical.
  # Filter in the shell (test -L / -f are builtins, no forks), then copy the survivors with ONE tar.
  # A per-file `mkdir -p` + `cp` loop costs two forks each — measured 1072 ms for 156 untracked files,
  # which was most of the snapshot's cost. Symlinks are dropped from the LIST rather than archived: tar
  # would preserve the link, and a link to ~/.ssh still resolves on this host from inside the snapshot.
  keep="$dest.keep"
  : > "$keep"
  ( cd "$top" && git ls-files -o --exclude-standard -z ) 2>/dev/null \
    | while IFS= read -r -d '' p; do
        case "$p" in .fusion/*|*/.fusion/*) continue ;; esac
        if [ -L "$top/$p" ]; then
          echo "[fusion_panel_workspace] refusing untracked symlink '$p' (it can point outside the repo)." >&2
          continue
        fi
        [ -f "$top/$p" ] || continue
        printf '%s\0' "$p"
      done >> "$keep"
  if [ -s "$keep" ]; then
    if ! ( cd "$top" && tar -cf - --null -T "$keep" ) 2>/dev/null | ( cd "$dest" && tar -xf - ) 2>/dev/null; then
      rm -f "$keep"
      echo "[fusion_panel_workspace] copying untracked files failed — refusing to hand over a partial snapshot." >&2
      return 1
    fi
  fi
  rm -f "$keep"

  # STRIP EVERY SYMLINK from the finished snapshot.
  #
  # Filtering the untracked list was not enough: `git archive` faithfully reproduces TRACKED symlinks, so
  # a repo that tracks `link -> ~/.ssh/id_rsa` handed the seat a working read-through to arbitrary host
  # files from inside the "isolated" snapshot. Verified. Doing it here, after extraction, also closes the
  # TOCTOU in the untracked path (filtered by path, then re-opened by tar).
  #
  # Removing rather than repairing: a link that escapes is a leak, and one that stays inside is redundant
  # because its target is already in the snapshot. A code reviewer needs neither.
  _fpw_links="$(find "$dest" -type l 2>/dev/null | wc -l | tr -d ' ')"
  if [ "${_fpw_links:-0}" -gt 0 ]; then
    find "$dest" -type l -exec rm -f {} + 2>/dev/null
    echo "[fusion_panel_workspace] removed $_fpw_links symlink(s) from the snapshot (they can resolve outside it)." >&2
  fi

  # Give the seat a working `git` again — a FRESH standalone history, no remote, no path to the original.
  # WITH a commit: `git add -A` is the hashing step (measured 93 ms); the commit only writes trees and one
  # object (26 ms) and reusing the index's blob IDs costs nothing. Skipping it left an unborn HEAD, so
  # `git diff HEAD`, `git log` and `git show` all exited 128 for the seat — a real capability loss for
  # 26 ms. A failure here is NOT survivable silently: the caller would report a seat that read the code.
  if ! ( cd "$dest" && git init -q . && git add -A \
         && git -c user.email=panel@fusion -c user.name=panel commit -qm "panel snapshot" ) >/dev/null 2>&1; then
    echo "[fusion_panel_workspace] could not initialize the snapshot repo — refusing to report a workspace." >&2
    return 1
  fi

  printf '%s\n' "$dest"
}

# Remove a workspace made by fusion_panel_workspace. A snapshot registers NOTHING in the operator's repo,
# so removal is a plain rm — unlike a worktree there is no admin data to strand when a run is interrupted
# before its trap fires.
fusion_panel_workspace_cleanup() {
  local repo="${1:-}" dest="${2:-}"
  [ -n "$dest" ] || return 0
  rm -rf "$dest" "$dest.patch" "$dest.keep" 2>/dev/null
  return 0
}

# Run a command under a hard time limit (seconds). Portable: timeout/gtimeout when present, else a
# bash watchdog. The watchdog TERMs first (KILL only after a grace period), and on the normal path we
# kill the watchdog's own children too so no orphan `sleep` outlives the probe.
fusion_run_with_timeout() {
  _frt_secs="$1"; shift
  if command -v timeout >/dev/null 2>&1; then timeout "$_frt_secs" "$@"; return $?; fi
  if command -v gtimeout >/dev/null 2>&1; then gtimeout "$_frt_secs" "$@"; return $?; fi
  "$@" & _frt_pid=$!
  ( sleep "$_frt_secs"; kill "$_frt_pid" 2>/dev/null; sleep 5; kill -9 "$_frt_pid" 2>/dev/null ) & _frt_w=$!
  wait "$_frt_pid" 2>/dev/null
  _frt_rc=$?
  pkill -P "$_frt_w" 2>/dev/null
  kill "$_frt_w" 2>/dev/null
  wait "$_frt_w" 2>/dev/null
  return "$_frt_rc"
}

fusion_bounded() {
  fusion_run_with_timeout 5 "$@"
}

fusion_cli_available() {
  command -v "$1" >/dev/null 2>&1 && fusion_bounded "$1" --version >/dev/null 2>&1
}

# Recursion guard: a panelist process must never convene its own panel (blindness invariant + loop risk).
# Call BEFORE any side effect (stale-clear, mkdir, etc.). Exits 14 when FUSION_PANEL_CHILD=1.
fusion_guard_recursion() {
  _fgr_tag="$1"
  if [ "${FUSION_PANEL_CHILD:-0}" = "1" ]; then
    echo "[$_fgr_tag] recursive fusion invocation blocked: this process is already a panelist (FUSION_PANEL_CHILD=1)." >&2
    echo "[$_fgr_tag] panelists answer directly; only the outer orchestrator convenes panels." >&2
    exit 14
  fi
}

# Prompt-size guard: oversized packets are curation bugs. FUSION_MAX_PROMPT_BYTES=0 disables.
# Returns 2 when over cap (caller: fusion_check_prompt_bytes TAG FILE || exit 2).
fusion_check_prompt_bytes() {
  _fcp_tag="$1"
  _fcp_file="$2"
  _fcp_max="${FUSION_MAX_PROMPT_BYTES:-400000}"
  _fcp_bytes="$(wc -c < "$_fcp_file" | tr -d ' ')"
  if [ "$_fcp_max" -gt 0 ] 2>/dev/null && [ "$_fcp_bytes" -gt "$_fcp_max" ]; then
    echo "[$_fcp_tag] prompt is ${_fcp_bytes} bytes > FUSION_MAX_PROMPT_BYTES=${_fcp_max}." >&2
    echo "[$_fcp_tag] curate a smaller packet (/fusion-context) or raise/disable the cap explicitly." >&2
    return 2
  fi
  return 0
}

# Plausibility floor: a few-byte "answer" is an error banner, not a panel answer.
# FUSION_MIN_OUTPUT_BYTES=0 disables. Returns 1 when under floor.
# Callers that also want a log tail (run_codex) print/tail after a nonzero return.
fusion_check_min_output() {
  _fcm_tag="$1"
  _fcm_file="$2"
  _fcm_min="${FUSION_MIN_OUTPUT_BYTES:-200}"
  _fcm_bytes=0
  [ -f "$_fcm_file" ] && _fcm_bytes="$(wc -c < "$_fcm_file" | tr -d ' ')"
  if [ "$_fcm_min" -gt 0 ] 2>/dev/null && [ "$_fcm_bytes" -lt "$_fcm_min" ]; then
    echo "[$_fcm_tag] output is only ${_fcm_bytes} bytes (< FUSION_MIN_OUTPUT_BYTES=${_fcm_min}) — treating as failed." >&2
    return 1
  fi
  return 0
}

fusion_detect_gemini_backend() {
  FUSION_GEMINI_BACKEND_RESOLVED=""
  FUSION_GEMINI_BACKEND_BINARY=""
  FUSION_GEMINI_BACKEND_REASON=""

  case "${FUSION_GEMINI_BACKEND:-auto}" in
    auto|"")
      if fusion_cli_available agy; then
        FUSION_GEMINI_BACKEND_RESOLVED="antigravity"
        FUSION_GEMINI_BACKEND_BINARY="agy"
        FUSION_GEMINI_BACKEND_REASON="auto selected Antigravity CLI"
      elif [ "${FUSION_ALLOW_LEGACY_GEMINI:-0}" = "1" ] && fusion_cli_available gemini; then
        FUSION_GEMINI_BACKEND_RESOLVED="legacy-gemini"
        FUSION_GEMINI_BACKEND_BINARY="gemini"
        FUSION_GEMINI_BACKEND_REASON="auto selected legacy Gemini CLI because FUSION_ALLOW_LEGACY_GEMINI=1"
      else
        FUSION_GEMINI_BACKEND_REASON="Antigravity CLI (agy) not available; legacy gemini ignored unless explicitly enabled"
      fi
      ;;
    agy|antigravity)
      if fusion_cli_available agy; then
        FUSION_GEMINI_BACKEND_RESOLVED="antigravity"
        FUSION_GEMINI_BACKEND_BINARY="agy"
        FUSION_GEMINI_BACKEND_REASON="FUSION_GEMINI_BACKEND=${FUSION_GEMINI_BACKEND}"
      else
        FUSION_GEMINI_BACKEND_REASON="FUSION_GEMINI_BACKEND=${FUSION_GEMINI_BACKEND} but agy is not available"
      fi
      ;;
    gemini|legacy|legacy-gemini)
      if fusion_cli_available gemini; then
        FUSION_GEMINI_BACKEND_RESOLVED="legacy-gemini"
        FUSION_GEMINI_BACKEND_BINARY="gemini"
        FUSION_GEMINI_BACKEND_REASON="FUSION_GEMINI_BACKEND=${FUSION_GEMINI_BACKEND}"
      else
        FUSION_GEMINI_BACKEND_REASON="FUSION_GEMINI_BACKEND=${FUSION_GEMINI_BACKEND} but gemini is not available"
      fi
      ;;
    *)
      FUSION_GEMINI_BACKEND_REASON="unknown FUSION_GEMINI_BACKEND=${FUSION_GEMINI_BACKEND}"
      ;;
  esac

  [ -n "$FUSION_GEMINI_BACKEND_RESOLVED" ]
}
