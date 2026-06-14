#!/usr/bin/env bash
# smoke_test.sh — offline self-check for fusion-deck.
#
# SAFETY: this NEVER calls a real (paid) model. It does not invoke run_codex.sh / run_gemini.sh /
# run_triple_fusion.sh against live CLIs. The only way to make this skill spend money is to set
# FUSION_LIVE=1, which this script merely reports; even then this smoke test does not itself call
# paid APIs (live panel runs are driven by the commands, not by the smoke test).
#
# It validates: shell syntax (bash -n), python compile, required-file presence, SKILL.md frontmatter
# (name == directory), command frontmatter, detect_panel output, the assert gate's hard-fail and
# explicit-degrade behavior, and that lint_contract.py passes a good contract and rejects a bad one.
#
# Exit 0 = all checks pass; 1 = at least one failure.

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/.." && pwd)"
root_name="$(basename "$root")"
# Absolute path to bash, so we can run a script with an emptied PATH (hiding codex/gemini) while bash
# itself is still found — a prefix `PATH=/nonexistent bash …` would fail to locate bash (exit 127).
sh_bin="$(command -v bash)"

pass=0; fail=0
ok()   { printf '  PASS  %s\n' "$1"; pass=$((pass + 1)); }
bad()  { printf '  FAIL  %s\n' "$1"; fail=$((fail + 1)); }

mode="DRY (no paid model calls)"
[ "${FUSION_LIVE:-0}" = "1" ] && mode="LIVE (FUSION_LIVE=1) — commands may call paid models; smoke test still does not"
echo "== fusion-deck smoke test =="
echo "root: $root"
echo "mode: $mode"
echo

echo "-- shell syntax (bash -n) --"
for s in "$root"/scripts/*.sh; do
  if bash -n "$s" 2>/tmp/pfo_bashn.err; then ok "bash -n $(basename "$s")"
  else bad "bash -n $(basename "$s"): $(cat /tmp/pfo_bashn.err)"; fi
done

echo "-- python compile --"
if python3 -m py_compile "$root/scripts/lint_contract.py" 2>/tmp/pfo_py.err; then ok "py_compile lint_contract.py"
else bad "py_compile lint_contract.py: $(cat /tmp/pfo_py.err)"; fi
if python3 "$root/scripts/lint_contract.py" --list-rules >/dev/null 2>&1; then ok "lint_contract.py --list-rules"
else bad "lint_contract.py --list-rules"; fi

echo "-- required files --"
required=(
  README.md LICENSE install.sh SKILL.md
  commands/fusion.md commands/fusion-review.md commands/fusion-plan.md
  commands/fusion-context.md commands/fusion-orchestrate.md commands/fusion-handoff.md
  scripts/assert_triple_panel.sh scripts/detect_panel.sh scripts/run_codex.sh scripts/run_gemini.sh
  scripts/run_triple_fusion.sh scripts/smoke_test.sh scripts/lint_contract.py
  references/panel-prompt.md references/judge-rubric.md references/workflow-contract.md
  references/context-pack-format.md references/orchestration-rubric.md
  references/subagent-prompt-template.md references/verifier-prompt-template.md
  references/handoff-capsule.md references/contract-lint-rules.md references/degraded-mode.md
  references/safety.md
  examples/workflow-contract.example.md examples/context-pack.example.md
  examples/fusion-review.example.md examples/subagent-task.example.md examples/handoff.example.md
)
for f in "${required[@]}"; do
  [ -s "$root/$f" ] && ok "exists $f" || bad "MISSING or empty: $f"
done

echo "-- SKILL.md frontmatter --"
if head -1 "$root/SKILL.md" | grep -q '^---$'; then ok "SKILL.md starts with frontmatter"
else bad "SKILL.md missing leading '---'"; fi
skill_name="$(awk '/^---$/{n++; next} n==1 && /^name:/{sub(/^name:[[:space:]]*/,""); gsub(/[[:space:]]/,""); print; exit}' "$root/SKILL.md")"
# install.sh installs into a dir named from SKILL.md, so check the canonical name (clone-folder-independent).
if [ "$skill_name" = "fusion-deck" ]; then ok "SKILL.md name == canonical ('$skill_name')"
else bad "SKILL.md name ('$skill_name') != 'fusion-deck'"; fi
[ "$skill_name" = "$root_name" ] || echo "  note: checkout folder ('$root_name') differs — install.sh installs it under '$skill_name'."
if awk '/^---$/{n++; next} n==1 && /^description:/{found=1} END{exit !found}' "$root/SKILL.md"; then ok "SKILL.md has description"
else bad "SKILL.md missing description"; fi

echo "-- command frontmatter --"
for c in "$root"/commands/*.md; do
  if head -1 "$c" | grep -q '^---$' && awk '/^---$/{n++; next} n==1 && /^description:/{f=1} END{exit !f}' "$c"; then
    ok "frontmatter $(basename "$c")"
  else bad "frontmatter missing/incomplete: $(basename "$c")"; fi
done

echo "-- detect_panel output --"
dp="$(bash "$root/scripts/detect_panel.sh" 2>/dev/null)"
echo "$dp" | grep -q '^PANEL_STATE=' && ok "detect_panel prints PANEL_STATE" || bad "detect_panel missing PANEL_STATE"
echo "$dp" | grep -q '^SLUG='        && ok "detect_panel prints SLUG"        || bad "detect_panel missing SLUG"

echo "-- assert_triple_panel gate (simulated, no CLIs on PATH) --"
# Hard-fail when premium unavailable and no override: must exit non-zero.
if PATH=/nonexistent "$sh_bin" "$root/scripts/assert_triple_panel.sh" >/dev/null 2>&1; then
  bad "assert should hard-fail with no CLIs and no override"
else ok "assert hard-fails (exit non-zero) when premium unavailable"; fi
# Explicit degrade override: must exit 0 and announce DEGRADED.
deg="$(FUSION_ALLOW_DEGRADED=1 PATH=/nonexistent "$sh_bin" "$root/scripts/assert_triple_panel.sh" 2>/dev/null)"; deg_rc=$?
if [ "$deg_rc" -eq 0 ] && echo "$deg" | grep -q '^DEGRADED=1'; then ok "assert allows explicit degrade (FUSION_ALLOW_DEGRADED=1)"
else bad "assert degrade-override broken (rc=$deg_rc)"; fi

echo "-- lint_contract behavior --"
if python3 "$root/scripts/lint_contract.py" "$root/examples/workflow-contract.example.md" >/dev/null 2>&1; then
  ok "lint PASSES the good example contract"
else bad "lint should pass examples/workflow-contract.example.md"; fi
bad_fixture="$(mktemp /tmp/pfo_bad_contract.XXXXXX.md)"
printf '# Not a contract\n\nJust prose, no required sections, and it mentions /goal mode.\n' > "$bad_fixture"
if python3 "$root/scripts/lint_contract.py" "$bad_fixture" >/dev/null 2>&1; then
  bad "lint should REJECT a contract missing required sections / using /goal"
else ok "lint REJECTS a malformed contract (missing sections + /goal)"; fi
rm -f "$bad_fixture"

echo
echo "== result: $pass passed, $fail failed =="
[ "$fail" -eq 0 ] || exit 1
echo "SMOKE OK"
