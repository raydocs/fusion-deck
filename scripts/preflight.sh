#!/usr/bin/env bash
# preflight.sh — a ship-gate to run before a commit or push (and before a Handoff Capsule / after an
# orchestrate rollup). Borrowed from RepoPrompt CE's rpce-contribution-check: catch whitespace damage and
# leaked secrets in what is ACTUALLY staged (the index), and gate a push on a clean worktree.
#
# Honest-degrade (same posture as the panel / codemap): if `gitleaks` is installed it does the secret
# scan; otherwise a built-in regex floor runs and the run is loudly marked DEGRADED — never silently
# skipped. It NEVER prints the matched secret value, only the file:line.
#
# Usage:
#   preflight.sh                 commit mode (default): scan the STAGED index
#   preflight.sh commit          same as default
#   preflight.sh push [base]     push mode: scan base..HEAD (base default: @{upstream} else origin/main)
#                                and require a clean worktree
#   preflight.sh -h | --help     this help
#
# Exit: 0 = PASS, 1 = FAIL (whitespace / secret / dirty-worktree), 2 = usage / not a git repo.
# Final greppable lines: PREFLIGHT_SECRETSCAN=<GITLEAKS|REGEX>  and  PREFLIGHT_STATE=<PASS|FAIL>.

set -uo pipefail

fail=0
note() { printf '  %s\n' "$*"; }
bad()  { printf '  FAIL  %s\n' "$*"; fail=1; }
ok()   { printf '  ok    %s\n' "$*"; }

# Secret filename deny-globs + content regex — mirror references/safety.md (kept in sync deliberately).
DENY_GLOBS=(".env*" "*.pem" "*.key" "id_rsa*" "credentials*" "secrets*" "*.p12" "*.keystore")
# POSIX ERE (no PCRE) so BSD/macOS `grep -iE` handles it — `grep -P` is unavailable on macOS.
SECRET_RE='(api[_-]?key|secret|token|password|passwd|bearer|private[_-]?key|aws_secret|client[_-]?secret)[[:space:]]*[:=]'

mode="${1:-commit}"
case "$mode" in -h|--help) sed -n '2,20p' "$0"; exit 0 ;; esac

if ! command -v git >/dev/null 2>&1 || ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "preflight: not inside a git repository" >&2
  echo "PREFLIGHT_STATE=FAIL"
  exit 2
fi

echo "== fusion-deck preflight ($mode) =="

# Resolve the set of changed files + the diff to scan, per mode.
base=""
if [ "$mode" = "push" ]; then
  base="${2:-}"
  if [ -z "$base" ]; then
    if git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' >/dev/null 2>&1; then
      base="@{upstream}"
    elif git rev-parse --verify origin/main >/dev/null 2>&1; then
      base="origin/main"
    else
      bad "push: no upstream and no origin/main to diff against — pass an explicit <base>"
    fi
  fi
  [ -n "$base" ] && note "outgoing range: ${base}..HEAD"
  files_cmd=(git diff --name-only "${base}" HEAD)
  check_cmd=(git diff --check "${base}" HEAD)
  content_cmd=(git diff -U0 "${base}" HEAD)
elif [ "$mode" = "commit" ]; then
  files_cmd=(git diff --cached --name-only)
  check_cmd=(git diff --cached --check)
  content_cmd=(git diff --cached -U0)
else
  echo "preflight: unknown mode '$mode' (want: commit | push)" >&2
  echo "PREFLIGHT_STATE=FAIL"; exit 2
fi

# Push mode with no resolvable base: we already reported the reason — bail cleanly rather than run
# `git diff "" HEAD` and spew git errors into the whitespace/secret checks.
if [ "$mode" = "push" ] && [ -z "$base" ]; then
  echo "PREFLIGHT_SECRETSCAN=SKIPPED"; echo "PREFLIGHT_STATE=FAIL"; exit 1
fi

# Portable array fill (no `mapfile` — macOS ships bash 3.2, which lacks it; mirror the codebase's read loops).
changed=()
while IFS= read -r _line; do
  [ -n "$_line" ] && changed+=("$_line")
done < <("${files_cmd[@]}" 2>/dev/null || true)
if [ "${#changed[@]}" -eq 0 ]; then
  note "no ${mode} changes to check"
fi

# 1) Whitespace / conflict-marker damage. (mktemp, not a fixed /tmp name: two concurrent preflights —
# or two users on one host — must not clobber each other's scratch file.)
ws_tmp="$(mktemp "${TMPDIR:-/tmp}/pfo_preflight_ws.XXXXXX")"
if "${check_cmd[@]}" >"$ws_tmp" 2>&1; then ok "whitespace clean ($mode)"
else bad "whitespace/conflict-marker issues:"; sed 's/^/        /' "$ws_tmp"; fi
rm -f "$ws_tmp"

# 2) Secret FILENAME deny-globs on the changed file list. Guard the expansion — an empty array under
# `set -u` is an "unbound variable" error in bash 3.2.
if [ "${#changed[@]}" -gt 0 ]; then
  for f in "${changed[@]}"; do
    base_f="$(basename "$f")"
    for g in "${DENY_GLOBS[@]}"; do
      # shellcheck disable=SC2053
      if [[ "$base_f" == $g ]]; then bad "staged a secret-looking file: $f (matches '$g')"; fi
    done
  done
fi

# The regex floor — used when gitleaks is absent OR when a gitleaks invocation isn't understood (so a
# CLI/version mismatch degrades honestly instead of false-failing). Scans only ADDED lines and redacts
# the value (truncate at ':'/'='). POSIX ERE + `grep -iE` (no PCRE — unavailable on macOS).
regex_scan() {
  scan_state="REGEX"
  hits="$("${content_cmd[@]}" 2>/dev/null | grep -E '^\+' | grep -vE '^\+\+\+' \
          | grep -iE "$SECRET_RE" 2>/dev/null | sed -E 's/([:=]).*/\1 [redacted]/' || true)"
  if [ -n "$hits" ]; then
    bad "regex secret scan flagged added lines (matched a key/secret/token assignment):"
    printf '%s\n' "$hits" | sed 's/^/        /'
  else
    ok "regex secret scan: no obvious secret assignments in added lines"
  fi
}

# 3) Secret CONTENT scan — gitleaks if usable, else the regex floor. Disclose which ran.
scan_state="REGEX"
if command -v gitleaks >/dev/null 2>&1; then
  # Pick the subcommand by capability: gitleaks >=8.19 has `git` (and deprecates detect/protect); older
  # gitleaks only has detect/protect. Probe with --help so we never guess from a version string.
  if gitleaks git --help >/dev/null 2>&1; then
    if [ "$mode" = "commit" ]; then gl_cmd=(gitleaks git --staged --redact --no-banner .)
    else gl_cmd=(gitleaks git --redact --no-banner --log-opts="${base}..HEAD" .); fi
  else
    if [ "$mode" = "commit" ]; then gl_cmd=(gitleaks protect --staged --redact --no-banner)
    else gl_cmd=(gitleaks detect --redact --no-banner --log-opts="${base}..HEAD"); fi
  fi
  # Classify by OUTPUT, not exit code (gitleaks uses 1 for both "leaks found" and some usage errors):
  # "no leaks" -> clean; "leaks found" -> real finding; anything else -> unrecognized, degrade to regex.
  gl_out="$("${gl_cmd[@]}" 2>&1)"
  gl_low="$(printf '%s' "$gl_out" | tr '[:upper:]' '[:lower:]')"
  case "$gl_low" in
    *"no leaks found"*|*"no leaks were found"*)
      scan_state="GITLEAKS"; ok "gitleaks: no secrets ($mode)" ;;
    *"leak"*"found"*|*"leaks found"*)
      scan_state="GITLEAKS"; bad "gitleaks flagged secrets (values redacted):"
      printf '%s\n' "$gl_out" | sed 's/^/        /' ;;
    *)
      note "gitleaks present but its output wasn't understood (version/flags) — DEGRADED to regex floor"
      regex_scan ;;
  esac
else
  note "gitleaks not installed — DEGRADED to regex secret scan (install gitleaks for a real scan)"
  regex_scan
fi

# 4) push only — require a clean worktree before publishing.
if [ "$mode" = "push" ]; then
  if [ -z "$(git status --porcelain 2>/dev/null)" ]; then ok "worktree clean"
  else bad "worktree is dirty — commit or stash before pushing:"; git status --short | sed 's/^/        /'; fi
fi

echo "PREFLIGHT_SECRETSCAN=$scan_state"
if [ "$fail" -eq 0 ]; then echo "PREFLIGHT_STATE=PASS"; exit 0
else echo "PREFLIGHT_STATE=FAIL"; exit 1; fi
