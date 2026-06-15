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
for p in "$root"/scripts/*.py; do
  if python3 -m py_compile "$p" 2>/tmp/pfo_py.err; then ok "py_compile $(basename "$p")"
  else bad "py_compile $(basename "$p"): $(cat /tmp/pfo_py.err)"; fi
done
if python3 "$root/scripts/lint_contract.py" --list-rules >/dev/null 2>&1; then ok "lint_contract.py --list-rules"
else bad "lint_contract.py --list-rules"; fi
if python3 "$root/scripts/selection_lint.py" --list-rules >/dev/null 2>&1; then ok "selection_lint.py --list-rules"
else bad "selection_lint.py --list-rules"; fi

echo "-- required files --"
required=(
  README.md LICENSE install.sh SKILL.md
  commands/fusion.md commands/fusion-review.md commands/fusion-plan.md
  commands/fusion-context.md commands/fusion-orchestrate.md commands/fusion-handoff.md
  commands/fusion-investigate.md commands/fusion-optimize.md commands/fusion-refactor.md
  commands/fusion-remind.md
  scripts/assert_triple_panel.sh scripts/detect_panel.sh scripts/run_codex.sh scripts/run_gemini.sh
  scripts/run_triple_fusion.sh scripts/smoke_test.sh scripts/lint_contract.py
  scripts/codemap.sh scripts/selection_lint.py scripts/fusion_worktree.sh
  references/panel-prompt.md references/judge-rubric.md references/workflow-contract.md
  references/context-pack-format.md references/orchestration-rubric.md
  references/subagent-prompt-template.md references/verifier-prompt-template.md
  references/handoff-capsule.md references/contract-lint-rules.md references/degraded-mode.md
  references/safety.md
  references/investigation-rubric.md references/optimize-scoreboard.md references/codemap.md
  references/context-discovery.md references/refactor-recipe.md references/worktrees.md
  references/reminder.md references/probe-quality.md references/export.md
  scripts/preflight.sh scripts/fusion_export.sh
  examples/workflow-contract.example.md examples/context-pack.example.md
  examples/fusion-review.example.md examples/subagent-task.example.md examples/handoff.example.md
  examples/selection.example.json
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
# C009 — an otherwise-valid contract with a dangerous vague phrase must be rejected (and the clean
# example must still pass, i.e. no false-positive — covered by the example-passes check above).
c009_fixture="$(mktemp /tmp/pfo_c009.XXXXXX.md)"
cat "$root/examples/workflow-contract.example.md" > "$c009_fixture"
printf '\n- Note: just keep trying until it looks good.\n' >> "$c009_fixture"
if python3 "$root/scripts/lint_contract.py" "$c009_fixture" >/dev/null 2>&1; then
  bad "lint should REJECT dangerous vague language (C009: 'keep trying' / 'until it looks good')"
else ok "lint REJECTS dangerous vague language (C009)"; fi
rm -f "$c009_fixture"

echo "-- codemap honest-degrade --"
cm="$(FUSION_CODEMAP_TIER=regex bash "$root/scripts/codemap.sh" "$root/scripts/lint_contract.py" 2>/dev/null)"
echo "$cm" | grep -q '^CODEMAP_STATE='      && ok "codemap.sh prints CODEMAP_STATE"            || bad "codemap.sh missing CODEMAP_STATE"
echo "$cm" | grep -q '^CODEMAP_STATE=REGEX' && ok "codemap.sh honors FUSION_CODEMAP_TIER=regex" || bad "codemap.sh regex-tier override broken"
# A bare `tree-sitter` CLI must NOT upgrade the tier (only python grammars actually parse) — regression for
# the honest-degrade over-claim where a present-but-unused CLI faked CODEMAP_STATE=TREESITTER.
cm_ts_dir="$(mktemp -d /tmp/pfo_cmts.XXXXXX)"
printf '#!/usr/bin/env bash\necho "tree-sitter 0.0-fake"\n' > "$cm_ts_dir/tree-sitter"; chmod +x "$cm_ts_dir/tree-sitter"
cm_base="$(bash "$root/scripts/codemap.sh" "$root/scripts/lint_contract.py" 2>/dev/null | grep '^CODEMAP_STATE=')"
cm_fake="$(PATH="$cm_ts_dir:$PATH" bash "$root/scripts/codemap.sh" "$root/scripts/lint_contract.py" 2>/dev/null | grep '^CODEMAP_STATE=')"
if [ "$cm_base" = "$cm_fake" ]; then ok "codemap.sh: a bare tree-sitter CLI does not change the tier ($cm_fake)"
else bad "codemap.sh: a bare tree-sitter CLI changed the tier ($cm_base -> $cm_fake) — over-claim"; fi
rm -rf "$cm_ts_dir"

echo "-- selection_lint behavior --"
if python3 "$root/scripts/selection_lint.py" "$root/examples/selection.example.json" >/dev/null 2>&1; then
  ok "selection_lint PASSES the good example manifest"
else bad "selection_lint should pass examples/selection.example.json"; fi
bad_sel="$(mktemp /tmp/pfo_bad_sel.XXXXXX.json)"
printf '{"task":"x","budget_tokens":1000,"selected":[{"path":"a.py","mode":"full","reason":"r"}]}\n' > "$bad_sel"
if python3 "$root/scripts/selection_lint.py" "$bad_sel" >/dev/null 2>&1; then
  bad "selection_lint should REJECT a selected file with no evidence (S007)"
else ok "selection_lint REJECTS a no-evidence manifest (S007 gate)"; fi
rm -f "$bad_sel"

echo "-- worktree NO_GIT guard --"
wt_tmp="$(mktemp -d /tmp/pfo_wt.XXXXXX)"
if ( cd "$wt_tmp" && bash "$root/scripts/fusion_worktree.sh" list >/dev/null 2>&1 ); then
  bad "fusion_worktree.sh list should fail (non-zero) outside a git repo"
else
  wt="$(cd "$wt_tmp" && bash "$root/scripts/fusion_worktree.sh" list 2>/dev/null)"
  echo "$wt" | grep -q '^WORKTREE_STATE=NO_GIT' && ok "fusion_worktree.sh reports NO_GIT outside a repo" || bad "fusion_worktree.sh missing NO_GIT line"
fi
rm -rf "$wt_tmp"

echo "-- run_triple_fusion stale-output guard --"
# A prior run's leftovers in a reused out_dir must be cleared at start, so a mid-run read can't mistake
# stale output for this run's result. Hide the panel CLIs via PATH so the run aborts at the assert gate
# AFTER the stale-clear (never a paid call); skip if a CLI somehow resolves under /usr/bin:/bin.
if PATH=/usr/bin:/bin command -v codex >/dev/null 2>&1 || PATH=/usr/bin:/bin command -v gemini >/dev/null 2>&1; then
  echo "  note  SKIP stale-clear check (a panel CLI resolves under /usr/bin:/bin; can't hide it safely)"
else
  rtf_d="$(mktemp -d /tmp/pfo_rtf.XXXXXX)"; rtf_p="$(mktemp /tmp/pfo_rtf_p.XXXXXX)"; printf 'hi\n' > "$rtf_p"
  printf 'stale\n' > "$rtf_d/manifest.txt"; printf 'stale\n' > "$rtf_d/gemini_out.md"
  PATH=/usr/bin:/bin "$sh_bin" "$root/scripts/run_triple_fusion.sh" "$rtf_p" "$rtf_d" >/dev/null 2>&1
  if [ ! -e "$rtf_d/manifest.txt" ] && [ ! -e "$rtf_d/gemini_out.md" ]; then ok "run_triple_fusion clears stale outputs before running"
  else bad "run_triple_fusion left stale artifacts ($(ls "$rtf_d" 2>/dev/null | tr '\n' ' '))"; fi
  rm -rf "$rtf_d" "$rtf_p"
fi

echo "-- selection_lint .fusionignore gate (S012) --"
fi_tmp="$(mktemp -d /tmp/pfo_fi.XXXXXX)"
mkdir -p "$fi_tmp/.git" "$fi_tmp/.fusion" "$fi_tmp/build" "$fi_tmp/docs"
printf 'build\n!build/keep.js\n' > "$fi_tmp/.fusionignore"
printf 'x\n' > "$fi_tmp/build/x.js"; printf 'k\n' > "$fi_tmp/build/keep.js"
# An ignored file with valid evidence must be dropped (S012).
printf '{"task":"t","budget_tokens":1000,"selected":[{"path":"build/x.js","mode":"full","reason":"r","evidence":["grep:x"]}]}\n' > "$fi_tmp/.fusion/sel_bad.json"
if python3 "$root/scripts/selection_lint.py" "$fi_tmp/.fusion/sel_bad.json" >/dev/null 2>&1; then
  bad "selection_lint should REJECT a .fusionignore-excluded file (S012)"
else ok "selection_lint REJECTS a .fusionignore-excluded file (S012)"; fi
# A force-included (!) file under an ignored dir must pass.
printf '{"task":"t","budget_tokens":1000,"selected":[{"path":"build/keep.js","mode":"full","reason":"r","evidence":["grep:k"]}]}\n' > "$fi_tmp/.fusion/sel_ok.json"
if python3 "$root/scripts/selection_lint.py" "$fi_tmp/.fusion/sel_ok.json" >/dev/null 2>&1; then
  ok "selection_lint ALLOWS a force-included (!) file under an ignored dir"
else bad "selection_lint should allow a force-included (!) .fusionignore file"; fi
rm -rf "$fi_tmp"

echo "-- fusion_export path + cleanup --"
fx="$(bash "$root/scripts/fusion_export.sh" path fusion "Some Task Title!" 2>/dev/null)"
case "$fx" in
  .fusion/exports/fusion-*-some-task-title.md) ok "fusion_export path: repo-relative, slugged ($fx)" ;;
  *) bad "fusion_export path unexpected: '$fx'" ;;
esac
if bash "$root/scripts/fusion_export.sh" cleanup 14 >/dev/null 2>&1; then ok "fusion_export cleanup runs (exit 0)"
else bad "fusion_export cleanup failed"; fi

echo "-- preflight ship-gate --"
# Outside a git repo: must fail with PREFLIGHT_STATE=FAIL and a usage-class exit (2).
pf_tmp="$(mktemp -d /tmp/pfo_pf.XXXXXX)"
pf_out="$(cd "$pf_tmp" && bash "$root/scripts/preflight.sh" commit 2>/dev/null)"; pf_rc=$?
if [ "$pf_rc" -eq 2 ] && echo "$pf_out" | grep -q '^PREFLIGHT_STATE=FAIL'; then
  ok "preflight reports FAIL (exit 2) outside a git repo"
else bad "preflight should FAIL/exit-2 outside a git repo (rc=$pf_rc)"; fi
# Inside a clean repo with nothing staged: PASS and disclose the secret-scan tier.
if ( cd "$pf_tmp" && git init -q && git config user.email t@t && git config user.name t ) 2>/dev/null; then
  pf2="$(cd "$pf_tmp" && bash "$root/scripts/preflight.sh" commit 2>/dev/null)"
  echo "$pf2" | grep -q '^PREFLIGHT_SECRETSCAN=' && ok "preflight discloses PREFLIGHT_SECRETSCAN tier" || bad "preflight missing PREFLIGHT_SECRETSCAN"
  echo "$pf2" | grep -q '^PREFLIGHT_STATE=PASS'  && ok "preflight PASSES a clean empty index"          || bad "preflight should PASS a clean empty index"
else echo "  note  SKIP preflight in-repo check (git init unavailable)"; fi
rm -rf "$pf_tmp"

echo
echo "== result: $pass passed, $fail failed =="
[ "$fail" -eq 0 ] || exit 1
echo "SMOKE OK"
