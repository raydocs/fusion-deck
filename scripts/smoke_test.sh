#!/usr/bin/env bash
# smoke_test.sh — offline self-check for fusion-deck.
#
# SAFETY: this NEVER calls a real (paid) model. It does not invoke run_codex.sh / run_gemini.sh /
# run_triple_fusion.sh against live CLIs. The only way to make this skill spend money is to set
# FUSION_LIVE=1, which this script merely reports; even then this smoke test does not itself call
# paid APIs (live panel runs are driven by the commands, not by the smoke test).
#
# It validates: shell syntax (bash -n), python compile, required-file presence, SKILL.md frontmatter
# (name == directory), command frontmatter, panel gates, v2 router/ledger/verifier helpers, and core
# linters.
#
# Exit 0 = all checks pass; 1 = at least one failure.

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/.." && pwd)"
root_name="$(basename "$root")"
# Absolute path to bash, so we can run a script with an emptied PATH (hiding codex/gemini/agy) while bash
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

err_tmp="$(mktemp "${TMPDIR:-/tmp}/pfo_smoke_err.XXXXXX")"
trap 'rm -f "$err_tmp"' EXIT

echo "-- shell syntax (bash -n) --"
for s in "$root"/scripts/*.sh; do
  if bash -n "$s" 2>"$err_tmp"; then ok "bash -n $(basename "$s")"
  else bad "bash -n $(basename "$s"): $(cat "$err_tmp")"; fi
done

echo "-- python compile --"
for p in "$root"/scripts/*.py; do
  if python3 -m py_compile "$p" 2>"$err_tmp"; then ok "py_compile $(basename "$p")"
  else bad "py_compile $(basename "$p"): $(cat "$err_tmp")"; fi
done
if python3 "$root/scripts/lint_contract.py" --list-rules >/dev/null 2>&1; then ok "lint_contract.py --list-rules"
else bad "lint_contract.py --list-rules"; fi
if python3 "$root/scripts/selection_lint.py" --list-rules >/dev/null 2>&1; then ok "selection_lint.py --list-rules"
else bad "selection_lint.py --list-rules"; fi

echo "-- required files --"
required=(
  README.md LICENSE install.sh SKILL.md .fusionignore
  commands/fusion.md commands/fusion-review.md commands/fusion-plan.md
  commands/fusion-context.md commands/fusion-orchestrate.md commands/fusion-handoff.md
  commands/fusion-investigate.md commands/fusion-optimize.md commands/fusion-refactor.md
  commands/fusion-remind.md commands/fusion-auto.md commands/fusion-ultra.md
  scripts/assert_triple_panel.sh scripts/detect_panel.sh scripts/gemini_backend.sh
  scripts/run_codex.sh scripts/run_gemini.sh scripts/run_antigravity.sh
  scripts/review_packet.sh scripts/load_stack_report.sh
  scripts/run_triple_fusion.sh scripts/smoke_test.sh scripts/lint_contract.py scripts/fusion_ledger.py
  scripts/route_task.py scripts/assert_panel.sh scripts/run_panel.sh scripts/detect_verifiers.sh
  scripts/run_verifier.sh scripts/codemap.sh scripts/selection_lint.py scripts/fusion_worktree.sh
  references/panel-prompt.md references/judge-rubric.md references/workflow-contract.md
  references/context-pack-format.md references/orchestration-rubric.md
  references/subagent-prompt-template.md references/verifier-prompt-template.md
  references/handoff-capsule.md references/contract-lint-rules.md references/degraded-mode.md
  references/safety.md
  references/investigation-rubric.md references/optimize-scoreboard.md references/codemap.md
  references/context-discovery.md references/refactor-recipe.md references/worktrees.md
  references/reminder.md references/probe-quality.md references/export.md references/router-policy.md
  references/panel-modes.md references/run-ledger.md
  references/verifier-contract.md references/verifier-recipes.md references/contradiction-matrix.md
  docs/roadmap/v2-router.md tests/router_cases.yml
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
echo "$dp" | grep -q '^GEMINI_BACKEND=' && ok "detect_panel prints GEMINI_BACKEND" || bad "detect_panel missing GEMINI_BACKEND"

echo "-- PREMIUM slug consistency (version-agnostic) --"
# Extract the PREMIUM slug from detect_panel.sh source (the slug="…" next to state="PREMIUM") and
# assert that exact string appears verbatim in SKILL.md and references/panel-prompt.md. No version
# is hardcoded here so the check survives future panelist renames.
premium_slug="$(
  grep 'state="PREMIUM"' "$root/scripts/detect_panel.sh" \
    | sed -n 's/.*slug="\([^"]*\)".*/\1/p' | head -1
)"
if [ -n "$premium_slug" ] \
  && grep -qF "$premium_slug" "$root/SKILL.md" \
  && grep -qF "$premium_slug" "$root/references/panel-prompt.md"; then
  ok "PREMIUM slug '$premium_slug' consistent in detect_panel / SKILL.md / panel-prompt.md"
else
  bad "PREMIUM slug missing or inconsistent across docs (got: '${premium_slug:-<empty>}')"
fi

echo "-- assert_triple_panel gate (simulated, no CLIs on PATH) --"
# Hard-fail when premium unavailable and no override: must exit non-zero.
if PATH=/nonexistent "$sh_bin" "$root/scripts/assert_triple_panel.sh" >/dev/null 2>&1; then
  bad "assert should hard-fail with no CLIs and no override"
else ok "assert hard-fails (exit non-zero) when premium unavailable"; fi
# Explicit degrade override: must exit 0 and announce DEGRADED.
deg="$(FUSION_ALLOW_DEGRADED=1 PATH=/nonexistent "$sh_bin" "$root/scripts/assert_triple_panel.sh" 2>/dev/null)"; deg_rc=$?
if [ "$deg_rc" -eq 0 ] && echo "$deg" | grep -q '^DEGRADED=1'; then ok "assert allows explicit degrade (FUSION_ALLOW_DEGRADED=1)"
else bad "assert degrade-override broken (rc=$deg_rc)"; fi

echo "-- Gemini backend selection (simulated CLIs) --"
gb_tmp="$(mktemp -d "${TMPDIR:-/tmp}/pfo_gb.XXXXXX")"
cat > "$gb_tmp/codex" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ]; then echo "codex fake"; exit 0; fi
exit 1
EOF
cat > "$gb_tmp/gemini" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ]; then echo "gemini fake"; exit 0; fi
exit 1
EOF
chmod +x "$gb_tmp/codex" "$gb_tmp/gemini"
gb_default="$(PATH="$gb_tmp:/usr/bin:/bin" "$sh_bin" "$root/scripts/detect_panel.sh" 2>/dev/null)"
if echo "$gb_default" | grep -q '^PANEL_STATE=DEGRADED_OPUS_GPT5' && \
   echo "$gb_default" | grep -q '^GEMINI_BACKEND=none'; then
  ok "backend auto ignores legacy gemini unless explicitly enabled"
else bad "backend auto should ignore legacy gemini by default"; fi
gb_legacy="$(FUSION_ALLOW_LEGACY_GEMINI=1 PATH="$gb_tmp:/usr/bin:/bin" "$sh_bin" "$root/scripts/detect_panel.sh" 2>/dev/null)"
if echo "$gb_legacy" | grep -q '^PANEL_STATE=PREMIUM' && \
   echo "$gb_legacy" | grep -q '^GEMINI_BACKEND=legacy-gemini'; then
  ok "backend auto can opt into legacy gemini"
else bad "backend legacy opt-in should make Gemini panelist available"; fi
cat > "$gb_tmp/agy" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ]; then echo "agy fake"; exit 0; fi
while [ "$#" -gt 0 ]; do
  case "$1" in
    --print|-p|--prompt) shift; printf 'AGY:%s\n' "$1"; exit 0 ;;
  esac
  shift
done
exit 1
EOF
chmod +x "$gb_tmp/agy"
gb_agy="$(PATH="$gb_tmp:/usr/bin:/bin" "$sh_bin" "$root/scripts/detect_panel.sh" 2>/dev/null)"
if echo "$gb_agy" | grep -q '^PANEL_STATE=PREMIUM' && \
   echo "$gb_agy" | grep -q '^GEMINI_BACKEND=antigravity'; then
  ok "backend auto prefers Antigravity agy"
else bad "backend auto should prefer agy"; fi
gb_prompt="$(mktemp "${TMPDIR:-/tmp}/pfo_agy_prompt.XXXXXX")"; gb_out="$(mktemp "${TMPDIR:-/tmp}/pfo_agy_out.XXXXXX")"
printf 'hello backend\n' > "$gb_prompt"; : > "$gb_out"
# FUSION_MIN_OUTPUT_BYTES=0: the fake agy's answer is a few bytes, which the plausibility floor would
# (correctly) reject in a real run — this check only exercises backend delegation.
if FUSION_MIN_OUTPUT_BYTES=0 PATH="$gb_tmp:/usr/bin:/bin" "$sh_bin" "$root/scripts/run_gemini.sh" "$gb_prompt" "$gb_out" >/dev/null 2>&1 && \
   grep -q '^AGY:hello backend' "$gb_out"; then
  ok "run_gemini.sh delegates to agy backend"
else bad "run_gemini.sh should delegate to agy backend"; fi
rm -rf "$gb_tmp" "$gb_prompt" "$gb_out"

echo "-- v2 router / panel / ledger / verifier helpers --"
if python3 "$root/scripts/route_task.py" --check "$root/tests/router_cases.yml" >/dev/null 2>&1; then
  ok "route_task.py passes router_cases.yml"
else bad "route_task.py should pass tests/router_cases.yml"; fi
rt="$(python3 "$root/scripts/route_task.py" --task "review my staged diff" 2>/dev/null)"
echo "$rt" | grep -q '"recommended_workflow": "pair_review_then_verify"' && ok "route_task.py routes review -> pair_review_then_verify" || bad "route_task.py review route mismatch"
if PATH=/nonexistent "$sh_bin" "$root/scripts/assert_panel.sh" --mode single_opus >/dev/null 2>&1; then
  ok "assert_panel.sh allows single_opus with no external CLIs"
else bad "assert_panel.sh single_opus should not need external CLIs"; fi
# Recursion guard: a panelist process (FUSION_PANEL_CHILD=1) must be refused with exit 14 everywhere.
FUSION_PANEL_CHILD=1 "$sh_bin" "$root/scripts/assert_panel.sh" --mode single_opus >/dev/null 2>&1
[ $? -eq 14 ] && ok "assert_panel.sh blocks recursive invocation (exit 14)" || bad "assert_panel.sh should exit 14 under FUSION_PANEL_CHILD=1"
FUSION_PANEL_CHILD=1 "$sh_bin" "$root/scripts/assert_triple_panel.sh" >/dev/null 2>&1
[ $? -eq 14 ] && ok "assert_triple_panel.sh blocks recursive invocation (exit 14)" || bad "assert_triple_panel.sh should exit 14 under FUSION_PANEL_CHILD=1"
rec_d="$(mktemp -d "${TMPDIR:-/tmp}/pfo_rec.XXXXXX")"; printf 'x\n' > "$rec_d/p.md"; printf 'keep\n' > "$rec_d/manifest.txt"
FUSION_PANEL_CHILD=1 "$sh_bin" "$root/scripts/run_panel.sh" --mode single_opus "$rec_d/p.md" "$rec_d" >/dev/null 2>&1
rec_rc=$?
if [ "$rec_rc" -eq 14 ] && [ -s "$rec_d/manifest.txt" ]; then
  ok "run_panel.sh blocks recursion BEFORE the stale-clear (exit 14, out_dir untouched)"
else bad "run_panel.sh recursion guard broken (rc=$rec_rc, manifest kept: $([ -s "$rec_d/manifest.txt" ] && echo yes || echo no))"; fi
rm -rf "$rec_d"
if PATH=/nonexistent "$sh_bin" "$root/scripts/assert_panel.sh" --mode opus_gpt_pair >/dev/null 2>&1; then
  bad "assert_panel.sh opus_gpt_pair should fail without codex"
else ok "assert_panel.sh fails missing intentional pair dependency"; fi
ap_tmp="$(mktemp -d "${TMPDIR:-/tmp}/pfo_ap.XXXXXX")"
cat > "$ap_tmp/codex" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ]; then echo "codex fake"; exit 0; fi
exit 1
EOF
cat > "$ap_tmp/agy" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ]; then echo "agy fake"; exit 0; fi
exit 1
EOF
chmod +x "$ap_tmp/codex" "$ap_tmp/agy"
if PATH="$ap_tmp:/usr/bin:/bin" "$sh_bin" "$root/scripts/assert_panel.sh" --mode premium_triple >/dev/null 2>&1; then
  ok "assert_panel.sh accepts premium_triple with fake codex+agy"
else bad "assert_panel.sh should accept premium_triple with fake codex+agy"; fi
rm -rf "$ap_tmp"
ledger_tmp="$(mktemp -d "${TMPDIR:-/tmp}/pfo_ledger.XXXXXX")"
if python3 "$root/scripts/fusion_ledger.py" --out-root "$ledger_tmp" new --command smoke --workflow single_model --task "hello" >/dev/null 2>&1 && \
   python3 "$root/scripts/fusion_ledger.py" --out-root "$ledger_tmp" show latest >/dev/null 2>&1 && \
   python3 "$root/scripts/fusion_ledger.py" --out-root "$ledger_tmp" summarize --last 1 | grep -q '^RUNS=1'; then
  ok "fusion_ledger.py creates/shows/summarizes runs"
else bad "fusion_ledger.py basic lifecycle failed"; fi
rm -rf "$ledger_tmp"
vf_tmp="$(mktemp -d "${TMPDIR:-/tmp}/pfo_vf.XXXXXX")"
printf 'test:\n\t@echo ok\n' > "$vf_tmp/Makefile"
vf_detect="$(cd "$vf_tmp" && "$sh_bin" "$root/scripts/detect_verifiers.sh" 2>/dev/null)"
echo "$vf_detect" | grep -q '^VERIFIER_STATE=FOUND' && ok "detect_verifiers.sh finds Makefile test" || bad "detect_verifiers.sh should find Makefile test"
if ( cd "$vf_tmp" && "$sh_bin" "$root/scripts/run_verifier.sh" --command "make test" --out-dir "$vf_tmp/out" >/dev/null 2>&1 ); then
  ok "run_verifier.sh runs explicit command"
else bad "run_verifier.sh should run explicit command"; fi
rm -rf "$vf_tmp"

echo "-- lint_contract behavior --"
if python3 "$root/scripts/lint_contract.py" "$root/examples/workflow-contract.example.md" >/dev/null 2>&1; then
  ok "lint PASSES the good example contract"
else bad "lint should pass examples/workflow-contract.example.md"; fi
bad_fixture="$(mktemp "${TMPDIR:-/tmp}/pfo_bad_contract.XXXXXX.md")"
printf '# Not a contract\n\nJust prose, no required sections, and it mentions /goal mode.\n' > "$bad_fixture"
if python3 "$root/scripts/lint_contract.py" "$bad_fixture" >/dev/null 2>&1; then
  bad "lint should REJECT a contract missing required sections / using /goal"
else ok "lint REJECTS a malformed contract (missing sections + /goal)"; fi
rm -f "$bad_fixture"
# C009 — an otherwise-valid contract with a dangerous vague phrase must be rejected (and the clean
# example must still pass, i.e. no false-positive — covered by the example-passes check above).
c009_fixture="$(mktemp "${TMPDIR:-/tmp}/pfo_c009.XXXXXX.md")"
cat "$root/examples/workflow-contract.example.md" > "$c009_fixture"
printf '\n- Note: just keep trying until it looks good.\n' >> "$c009_fixture"
if python3 "$root/scripts/lint_contract.py" "$c009_fixture" >/dev/null 2>&1; then
  bad "lint should REJECT dangerous vague language (C009: 'keep trying' / 'until it looks good')"
else ok "lint REJECTS dangerous vague language (C009)"; fi
rm -f "$c009_fixture"
# C009 negation guard — a PROHIBITION ("do not edit anything outside app/") must NOT trip C009.
c009_neg="$(mktemp "${TMPDIR:-/tmp}/pfo_c009neg.XXXXXX.md")"
cat "$root/examples/workflow-contract.example.md" > "$c009_neg"
printf '\n- Boundary: do not edit anything outside `app/`; never change whatever is in vendor/.\n' >> "$c009_neg"
if python3 "$root/scripts/lint_contract.py" "$c009_neg" >/dev/null 2>&1; then
  ok "C009 negation guard: a prohibition ('do not edit anything') is allowed"
else bad "C009 false-positive: a negated prohibition tripped C009"; fi
rm -f "$c009_neg"

echo "-- codemap honest-degrade --"
cm="$(FUSION_CODEMAP_TIER=regex bash "$root/scripts/codemap.sh" "$root/scripts/lint_contract.py" 2>/dev/null)"
echo "$cm" | grep -q '^CODEMAP_STATE='      && ok "codemap.sh prints CODEMAP_STATE"            || bad "codemap.sh missing CODEMAP_STATE"
echo "$cm" | grep -q '^CODEMAP_STATE=REGEX' && ok "codemap.sh honors FUSION_CODEMAP_TIER=regex" || bad "codemap.sh regex-tier override broken"
# A bare `tree-sitter` CLI must NOT upgrade the tier (only python grammars actually parse) — regression for
# the honest-degrade over-claim where a present-but-unused CLI faked CODEMAP_STATE=TREESITTER.
cm_ts_dir="$(mktemp -d "${TMPDIR:-/tmp}/pfo_cmts.XXXXXX")"
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
bad_sel="$(mktemp "${TMPDIR:-/tmp}/pfo_bad_sel.XXXXXX.json")"
printf '{"task":"x","budget_tokens":1000,"selected":[{"path":"a.py","mode":"full","reason":"r"}]}\n' > "$bad_sel"
if python3 "$root/scripts/selection_lint.py" "$bad_sel" >/dev/null 2>&1; then
  bad "selection_lint should REJECT a selected file with no evidence (S007)"
else ok "selection_lint REJECTS a no-evidence manifest (S007 gate)"; fi
rm -f "$bad_sel"

echo "-- worktree NO_GIT guard --"
wt_tmp="$(mktemp -d "${TMPDIR:-/tmp}/pfo_wt.XXXXXX")"
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
if PATH=/usr/bin:/bin command -v codex >/dev/null 2>&1 || \
   PATH=/usr/bin:/bin command -v gemini >/dev/null 2>&1 || \
   PATH=/usr/bin:/bin command -v agy >/dev/null 2>&1; then
  echo "  note  SKIP stale-clear check (a panel CLI resolves under /usr/bin:/bin; can't hide it safely)"
else
  rtf_d="$(mktemp -d "${TMPDIR:-/tmp}/pfo_rtf.XXXXXX")"; rtf_p="$(mktemp "${TMPDIR:-/tmp}/pfo_rtf_p.XXXXXX")"; printf 'hi\n' > "$rtf_p"
  printf 'stale\n' > "$rtf_d/manifest.txt"; printf 'stale\n' > "$rtf_d/gemini_out.md"
  PATH=/usr/bin:/bin "$sh_bin" "$root/scripts/run_triple_fusion.sh" "$rtf_p" "$rtf_d" >/dev/null 2>&1
  if [ ! -e "$rtf_d/manifest.txt" ] && [ ! -e "$rtf_d/gemini_out.md" ]; then ok "run_triple_fusion clears stale outputs before running"
  else bad "run_triple_fusion left stale artifacts ($(ls "$rtf_d" 2>/dev/null | tr '\n' ' '))"; fi
  rm -rf "$rtf_d" "$rtf_p"
fi

echo "-- run_panel.sh end-to-end (fake CLIs, no paid calls) --"
# Same PATH-hiding guard as the stale-clear check: only run when no real panel CLI resolves under
# /usr/bin:/bin, so the fakes fully shadow and nothing paid can be invoked.
if PATH=/usr/bin:/bin command -v codex >/dev/null 2>&1 || \
   PATH=/usr/bin:/bin command -v gemini >/dev/null 2>&1 || \
   PATH=/usr/bin:/bin command -v agy >/dev/null 2>&1; then
  echo "  note  SKIP run_panel end-to-end (a panel CLI resolves under /usr/bin:/bin; can't hide it safely)"
else
  rp_tmp="$(mktemp -d "${TMPDIR:-/tmp}/pfo_rp.XXXXXX")"
  # Healthy fake codex: honors --version, finds -o <file>, writes a plausible-size answer.
  cat > "$rp_tmp/codex" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ]; then echo "codex fake"; exit 0; fi
out=""; prev=""
for a in "$@"; do [ "$prev" = "-o" ] && out="$a"; prev="$a"; done
cat >/dev/null
[ -z "$out" ] && exit 1
{ printf 'CODEX-ANSWER '; head -c 300 /dev/zero | tr '\0' 'x'; echo; } > "$out"
exit 0
EOF
  # Healthy fake agy: answers --print on stdout with a plausible-size answer.
  cat > "$rp_tmp/agy" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ]; then echo "agy fake"; exit 0; fi
while [ "$#" -gt 0 ]; do
  case "$1" in
    --print) printf 'AGY-ANSWER '; head -c 300 /dev/zero | tr '\0' 'y'; echo; exit 0 ;;
  esac
  shift
done
exit 1
EOF
  chmod +x "$rp_tmp/codex" "$rp_tmp/agy"
  rp_out="$rp_tmp/out"; rp_prompt="$rp_tmp/prompt.md"; printf 'panel smoke question\n' > "$rp_prompt"
  PATH="$rp_tmp:/usr/bin:/bin" "$sh_bin" "$root/scripts/run_panel.sh" --mode premium_triple "$rp_prompt" "$rp_out" >/dev/null 2>&1
  rp_rc=$?
  if [ "$rp_rc" -eq 0 ] && grep -q '^REALIZED_PANEL_STATE=PREMIUM' "$rp_out/manifest.txt" 2>/dev/null; then
    ok "run_panel premium_triple with healthy fakes -> exit 0, REALIZED=PREMIUM"
  else bad "run_panel healthy-fakes run broken (rc=$rp_rc)"; fi
  if grep -q '^CODEX_SECONDS=' "$rp_out/manifest.txt" 2>/dev/null && \
     grep -q '^PROMPT_BYTES=' "$rp_out/manifest.txt" 2>/dev/null; then
    ok "run_panel manifest records timing + byte accounting"
  else bad "run_panel manifest missing timing/byte fields"; fi
  # Wide panel: premium_wide must realize PREMIUM with TWO Opus panelists (self-consistency seat).
  PATH="$rp_tmp:/usr/bin:/bin" "$sh_bin" "$root/scripts/run_panel.sh" --mode premium_wide "$rp_prompt" "$rp_out" >/dev/null 2>&1
  rp_rc=$?
  if [ "$rp_rc" -eq 0 ] && grep -q '^REALIZED_PANEL_STATE=PREMIUM' "$rp_out/manifest.txt" 2>/dev/null && \
     grep -q '^OPUS_PANELISTS=2' "$rp_out/manifest.txt" 2>/dev/null; then
    ok "run_panel premium_wide -> PREMIUM with OPUS_PANELISTS=2 (wide round)"
  else bad "run_panel premium_wide broken (rc=$rp_rc)"; fi
  # Runtime degrade: codex fails mid-run -> honest manifest + exit 13 without FUSION_ALLOW_DEGRADED.
  cat > "$rp_tmp/codex" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ]; then echo "codex fake"; exit 0; fi
cat >/dev/null; echo "boom: rate limited" >&2; exit 1
EOF
  chmod +x "$rp_tmp/codex"
  PATH="$rp_tmp:/usr/bin:/bin" "$sh_bin" "$root/scripts/run_panel.sh" --mode premium_triple "$rp_prompt" "$rp_out" >/dev/null 2>&1
  rp_rc=$?
  if [ "$rp_rc" -eq 13 ] && grep -q '^REALIZED_PANEL_STATE=DEGRADED_OPUS_GEMINI' "$rp_out/manifest.txt" 2>/dev/null; then
    ok "run_panel runtime failure -> exit 13 + honest DEGRADED manifest (no silent degrade)"
  else bad "run_panel runtime-degrade gate broken (rc=$rp_rc, want 13)"; fi
  PATH="$rp_tmp:/usr/bin:/bin" FUSION_ALLOW_DEGRADED=1 "$sh_bin" "$root/scripts/run_panel.sh" --mode premium_triple "$rp_prompt" "$rp_out" >/dev/null 2>&1
  rp_rc=$?
  if [ "$rp_rc" -eq 0 ]; then ok "run_panel accepts runtime degrade with explicit FUSION_ALLOW_DEGRADED=1"
  else bad "run_panel explicit-degrade path broken (rc=$rp_rc)"; fi
  # Plausibility floor: a tiny error-banner "answer" must count as a FAILED panelist, not a healthy one.
  cat > "$rp_tmp/codex" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ]; then echo "codex fake"; exit 0; fi
out=""; prev=""
for a in "$@"; do [ "$prev" = "-o" ] && out="$a"; prev="$a"; done
cat >/dev/null; [ -n "$out" ] && printf 'err\n' > "$out"; exit 0
EOF
  chmod +x "$rp_tmp/codex"
  PATH="$rp_tmp:/usr/bin:/bin" "$sh_bin" "$root/scripts/run_panel.sh" --mode premium_triple "$rp_prompt" "$rp_out" >/dev/null 2>&1
  rp_rc=$?
  if [ "$rp_rc" -eq 13 ] && grep -q '^REALIZED_PANEL_STATE=DEGRADED_OPUS_GEMINI' "$rp_out/manifest.txt" 2>/dev/null; then
    ok "run_panel treats a tiny error-banner output as a FAILED panelist (plausibility floor)"
  else bad "run_panel plausibility floor broken (rc=$rp_rc, want 13)"; fi
  rm -rf "$rp_tmp"
fi

echo "-- triple runner shims (compat over v2 run_panel / assert_panel) --"
# run_triple_fusion.sh and assert_triple_panel.sh are thin shims over the v2 path. These checks
# lock the compat contract (exit codes, v2 manifest fields, degrade override) without paid calls.
if PATH=/usr/bin:/bin command -v codex >/dev/null 2>&1 || \
   PATH=/usr/bin:/bin command -v gemini >/dev/null 2>&1 || \
   PATH=/usr/bin:/bin command -v agy >/dev/null 2>&1; then
  echo "  note  SKIP triple-shim e2e (a panel CLI resolves under /usr/bin:/bin; can't hide it safely)"
else
  sh_tmp="$(mktemp -d "${TMPDIR:-/tmp}/pfo_shim.XXXXXX")"
  cat > "$sh_tmp/codex" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ]; then echo "codex fake"; exit 0; fi
out=""; prev=""
for a in "$@"; do [ "$prev" = "-o" ] && out="$a"; prev="$a"; done
cat >/dev/null
[ -z "$out" ] && exit 1
{ printf 'CODEX-ANSWER '; head -c 300 /dev/zero | tr '\0' 'x'; echo; } > "$out"
exit 0
EOF
  cat > "$sh_tmp/agy" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ]; then echo "agy fake"; exit 0; fi
while [ "$#" -gt 0 ]; do
  case "$1" in
    --print) printf 'AGY-ANSWER '; head -c 300 /dev/zero | tr '\0' 'y'; echo; exit 0 ;;
  esac
  shift
done
exit 1
EOF
  chmod +x "$sh_tmp/codex" "$sh_tmp/agy"
  sh_out="$sh_tmp/out"; sh_prompt="$sh_tmp/prompt.md"; printf 'shim smoke question\n' > "$sh_prompt"
  # Shim parity: healthy fakes → exit 0, v2 realized-state PREMIUM + OPUS_PANELISTS=1.
  PATH="$sh_tmp:/usr/bin:/bin" "$sh_bin" "$root/scripts/run_triple_fusion.sh" "$sh_prompt" "$sh_out" >/dev/null 2>&1
  sh_rc=$?
  if [ "$sh_rc" -eq 0 ] && grep -q '^REALIZED_PANEL_STATE=PREMIUM' "$sh_out/manifest.txt" 2>/dev/null && \
     grep -q '^OPUS_PANELISTS=1' "$sh_out/manifest.txt" 2>/dev/null; then
    ok "run_triple_fusion shim -> exit 0, REALIZED_PANEL_STATE=PREMIUM, OPUS_PANELISTS=1"
  else bad "run_triple_fusion shim parity broken (rc=$sh_rc)"; fi
  # Shim degrade parity: failing codex → exit 13 without override; exit 0 with override.
  cat > "$sh_tmp/codex" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ]; then echo "codex fake"; exit 0; fi
cat >/dev/null; echo "boom: rate limited" >&2; exit 1
EOF
  chmod +x "$sh_tmp/codex"
  PATH="$sh_tmp:/usr/bin:/bin" "$sh_bin" "$root/scripts/run_triple_fusion.sh" "$sh_prompt" "$sh_out" >/dev/null 2>&1
  sh_rc=$?
  if [ "$sh_rc" -eq 13 ]; then ok "run_triple_fusion shim runtime failure -> exit 13"
  else bad "run_triple_fusion shim degrade gate broken (rc=$sh_rc, want 13)"; fi
  PATH="$sh_tmp:/usr/bin:/bin" FUSION_ALLOW_DEGRADED=1 "$sh_bin" "$root/scripts/run_triple_fusion.sh" "$sh_prompt" "$sh_out" >/dev/null 2>&1
  sh_rc=$?
  if [ "$sh_rc" -eq 0 ]; then ok "run_triple_fusion shim accepts runtime degrade with FUSION_ALLOW_DEGRADED=1"
  else bad "run_triple_fusion shim explicit-degrade path broken (rc=$sh_rc)"; fi
  # assert_triple_panel wrapper: nonzero with no CLIs; under override with one CLI prints PANEL_STATE= + DEGRADED=1.
  if PATH=/nonexistent "$sh_bin" "$root/scripts/assert_triple_panel.sh" >/dev/null 2>&1; then
    bad "assert_triple_panel wrapper should fail with no CLIs"
  else ok "assert_triple_panel wrapper still exits nonzero with no CLIs"; fi
  # One CLI present (codex only) + override → DEGRADED_OPUS_GPT5 style state + DEGRADED=1.
  rm -f "$sh_tmp/agy"
  atp="$(FUSION_ALLOW_DEGRADED=1 PATH="$sh_tmp:/usr/bin:/bin" "$sh_bin" "$root/scripts/assert_triple_panel.sh" 2>/dev/null)"; atp_rc=$?
  if [ "$atp_rc" -eq 0 ] && echo "$atp" | grep -q '^PANEL_STATE=' && echo "$atp" | grep -q '^DEGRADED=1'; then
    ok "assert_triple_panel wrapper under FUSION_ALLOW_DEGRADED=1 prints PANEL_STATE= and DEGRADED=1"
  else bad "assert_triple_panel wrapper degrade disclosure broken (rc=$atp_rc)"; fi
  rm -rf "$sh_tmp"
fi

echo "-- selection_lint .fusionignore gate (S012) --"
fi_tmp="$(mktemp -d "${TMPDIR:-/tmp}/pfo_fi.XXXXXX")"
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
pf_tmp="$(mktemp -d "${TMPDIR:-/tmp}/pfo_pf.XXXXXX")"
pf_out="$(cd "$pf_tmp" && bash "$root/scripts/preflight.sh" commit 2>/dev/null)"; pf_rc=$?
if [ "$pf_rc" -eq 2 ] && echo "$pf_out" | grep -q '^PREFLIGHT_STATE=FAIL'; then
  ok "preflight reports FAIL (exit 2) outside a git repo"
else bad "preflight should FAIL/exit-2 outside a git repo (rc=$pf_rc)"; fi
# Inside a clean repo with nothing staged: PASS and disclose the secret-scan tier.
if ( cd "$pf_tmp" && git init -q && git config user.email t@t && git config user.name t ) 2>/dev/null; then
  pf2="$(cd "$pf_tmp" && bash "$root/scripts/preflight.sh" commit 2>/dev/null)"
  echo "$pf2" | grep -q '^PREFLIGHT_SECRETSCAN=' && ok "preflight discloses PREFLIGHT_SECRETSCAN tier" || bad "preflight missing PREFLIGHT_SECRETSCAN"
  echo "$pf2" | grep -q '^PREFLIGHT_STATE=PASS'  && ok "preflight PASSES a clean empty index"          || bad "preflight should PASS a clean empty index"
  # Discriminating check: a STAGED secret (file + content) must FAIL, and the value must NOT leak.
  # Build the secret keyword by concatenation so THIS scanner's own source file doesn't trip the regex
  # floor (the runtime still writes a real secret assignment into the temp repo that preflight scans).
  _k="api""_key"
  ( cd "$pf_tmp" && printf '%s = "sk-LEAKED-VALUE-9999"\n' "$_k" > config.py && printf 'X=1\n' > .env && git add config.py .env ) 2>/dev/null
  pf3="$(cd "$pf_tmp" && bash "$root/scripts/preflight.sh" commit 2>/dev/null)"; pf3_rc=$?
  if [ "$pf3_rc" -eq 1 ] && echo "$pf3" | grep -q '^PREFLIGHT_STATE=FAIL'; then ok "preflight FAILS on a staged secret + .env file"
  else bad "preflight should FAIL on a staged secret (rc=$pf3_rc)"; fi
  if echo "$pf3" | grep -q 'LEAKED-VALUE'; then bad "preflight LEAKED the secret value into output"
  else ok "preflight redacts the secret value (no leak)"; fi
else echo "  note  SKIP preflight in-repo check (git init unavailable)"; fi
rm -rf "$pf_tmp"

echo "-- review_packet offline checks --"
# Temp repo + ok/bad helpers, same isolation style as preflight.
# Bare branch names normalize to <branch>...HEAD (merge-base); unknown refs exit 2.
rpkt_tmp="$(mktemp -d "${TMPDIR:-/tmp}/pfo_rpkt.XXXXXX")"
# Outside a git repo → nonzero (exit 2).
( cd "$rpkt_tmp" && bash "$root/scripts/review_packet.sh" uncommitted "$rpkt_tmp/out" >/dev/null 2>&1 )
rpkt_rc=$?
if [ "$rpkt_rc" -ne 0 ]; then ok "review_packet fails outside a git repo (rc=$rpkt_rc)"
else bad "review_packet should fail outside a git repo"; fi
if ( cd "$rpkt_tmp" && git init -q && git config user.email t@t && git config user.name t ) 2>/dev/null; then
  # Clean repo, empty uncommitted diff → exit 3.
  ( cd "$rpkt_tmp" && printf 'base\n' > f.txt && git add f.txt && git commit -q -m c0 )
  ( cd "$rpkt_tmp" && bash "$root/scripts/review_packet.sh" uncommitted "$rpkt_tmp/out_empty" >/dev/null 2>&1 )
  rpkt_rc=$?
  if [ "$rpkt_rc" -eq 3 ]; then ok "review_packet empty uncommitted diff -> exit 3"
  else bad "review_packet empty uncommitted should exit 3 (rc=$rpkt_rc)"; fi
  # uncommitted happy path: dirty working tree → exit 0, packet.md contains the change.
  ( cd "$rpkt_tmp" && printf 'UNCOMMITTED-MARKER-42\n' >> f.txt )
  ( cd "$rpkt_tmp" && bash "$root/scripts/review_packet.sh" uncommitted "$rpkt_tmp/out_u" >/dev/null 2>&1 )
  rpkt_rc=$?
  if [ "$rpkt_rc" -eq 0 ] && [ -s "$rpkt_tmp/out_u/packet.md" ] && \
     grep -q 'UNCOMMITTED-MARKER-42' "$rpkt_tmp/out_u/packet.md"; then
    ok "review_packet uncommitted happy path (packet contains diff)"
  else bad "review_packet uncommitted happy path broken (rc=$rpkt_rc)"; fi
  # staged happy path.
  ( cd "$rpkt_tmp" && git add f.txt )
  ( cd "$rpkt_tmp" && bash "$root/scripts/review_packet.sh" staged "$rpkt_tmp/out_s" >/dev/null 2>&1 )
  rpkt_rc=$?
  if [ "$rpkt_rc" -eq 0 ] && [ -s "$rpkt_tmp/out_s/packet.md" ] && \
     grep -q 'UNCOMMITTED-MARKER-42' "$rpkt_tmp/out_s/packet.md"; then
    ok "review_packet staged happy path (packet contains staged diff)"
  else bad "review_packet staged happy path broken (rc=$rpkt_rc)"; fi
  # back:2 — ≥3 commits; packet must include changes from the last 2 commits.
  ( cd "$rpkt_tmp" && git commit -q -m c1 && printf 'BACK2-A\n' >> f.txt && git add f.txt && git commit -q -m c2 && \
    printf 'BACK2-B\n' >> f.txt && git add f.txt && git commit -q -m c3 )
  ( cd "$rpkt_tmp" && bash "$root/scripts/review_packet.sh" back:2 "$rpkt_tmp/out_b" >/dev/null 2>&1 )
  rpkt_rc=$?
  if [ "$rpkt_rc" -eq 0 ] && grep -q 'BACK2-A' "$rpkt_tmp/out_b/packet.md" && \
     grep -q 'BACK2-B' "$rpkt_tmp/out_b/packet.md"; then
    ok "review_packet back:2 includes last 2 commits"
  else bad "review_packet back:2 broken (rc=$rpkt_rc)"; fi
  # back:x (non-numeric) → exit 2.
  ( cd "$rpkt_tmp" && bash "$root/scripts/review_packet.sh" back:x "$rpkt_tmp/out_x" >/dev/null 2>&1 )
  rpkt_rc=$?
  if [ "$rpkt_rc" -eq 2 ]; then ok "review_packet back:x (non-numeric) -> exit 2"
  else bad "review_packet back:x should exit 2 (rc=$rpkt_rc)"; fi
  # Bare branch name → normalize to merge-base range (main...HEAD), not tip-diff.
  # Setup: main advances AFTER feature diverges; feature has its own commit.
  ( cd "$rpkt_tmp" && git checkout -q -b main 2>/dev/null || git checkout -q main
    git checkout -q -b feat-norm
    printf 'FEAT-SIDE-CHANGE\n' >> f.txt && git add f.txt && git commit -q -m feat-side
    git checkout -q main
    printf 'MAIN-ONLY-CHANGE\n' >> f.txt && git add f.txt && git commit -q -m main-only
    git checkout -q feat-norm )
  rpkt_err="$rpkt_tmp/norm.err"
  ( cd "$rpkt_tmp" && bash "$root/scripts/review_packet.sh" main "$rpkt_tmp/out_norm" >"$rpkt_tmp/norm.out" 2>"$rpkt_err" )
  rpkt_rc=$?
  if [ "$rpkt_rc" -eq 0 ] && [ -s "$rpkt_tmp/out_norm/packet.md" ] && \
     grep -q 'FEAT-SIDE-CHANGE' "$rpkt_tmp/out_norm/packet.md" && \
     ! grep -q 'MAIN-ONLY-CHANGE' "$rpkt_tmp/out_norm/packet.md" && \
     grep -qi 'normalized' "$rpkt_err"; then
    ok "review_packet bare branch main normalizes to merge-base (not tip-diff)"
  else bad "review_packet bare-branch normalize broken (rc=$rpkt_rc)"; fi
  # Unknown bare ref → exit 2.
  ( cd "$rpkt_tmp" && bash "$root/scripts/review_packet.sh" nosuchbranch "$rpkt_tmp/out_nosuch" >/dev/null 2>&1 )
  rpkt_rc=$?
  if [ "$rpkt_rc" -eq 2 ]; then ok "review_packet unknown scope nosuchbranch -> exit 2"
  else bad "review_packet nosuchbranch should exit 2 (rc=$rpkt_rc)"; fi
else echo "  note  SKIP review_packet in-repo checks (git init unavailable)"; fi
rm -rf "$rpkt_tmp"

echo "-- runner guard checks --"
# Fake CLIs only — never call real paid models. Oversized-prompt / argv / min-output floors.
rg_tmp="$(mktemp -d "${TMPDIR:-/tmp}/pfo_rg.XXXXXX")"
rg_prompt="$(mktemp "${TMPDIR:-/tmp}/pfo_rg_p.XXXXXX")"
rg_out="$(mktemp "${TMPDIR:-/tmp}/pfo_rg_o.XXXXXX")"
# Oversized prompt (>10 bytes) for size-guard tests.
printf 'OVERSIZED-PROMPT-BODY\n' > "$rg_prompt"
# Fake codex: writes a sentinel if ever invoked.
cat > "$rg_tmp/codex" <<EOF
#!/usr/bin/env bash
if [ "\${1:-}" = "--version" ]; then echo "codex fake"; exit 0; fi
: > "$rg_tmp/codex_invoked"
# Capture argv for FUSION_NO_WEB checks; write a plausible-size answer when -o is present.
printf '%s\n' "\$@" >> "$rg_tmp/codex_args"
out=""; prev=""
for a in "\$@"; do [ "\$prev" = "-o" ] && out="\$a"; prev="\$a"; done
cat >/dev/null
[ -n "\$out" ] && { printf 'CODEX-ANSWER '; head -c 300 /dev/zero | tr '\\0' 'x'; echo; } > "\$out"
exit 0
EOF
# Fake gemini (legacy): sentinel on invoke.
cat > "$rg_tmp/gemini" <<EOF
#!/usr/bin/env bash
if [ "\${1:-}" = "--version" ]; then echo "gemini fake"; exit 0; fi
: > "$rg_tmp/gemini_invoked"
cat >/dev/null
printf 'GEMINI-ANSWER '; head -c 300 /dev/zero | tr '\\0' 'g'; echo
exit 0
EOF
# Fake agy: sentinel on invoke; default answer is large enough to pass the floor unless overridden.
cat > "$rg_tmp/agy" <<EOF
#!/usr/bin/env bash
if [ "\${1:-}" = "--version" ]; then echo "agy fake"; exit 0; fi
: > "$rg_tmp/agy_invoked"
while [ "\$#" -gt 0 ]; do
  case "\$1" in
    --print|-p|--prompt)
      if [ "\${FUSION_FAKE_AGY_TINY:-0}" = "1" ]; then printf 'x\n'; else printf 'AGY-ANSWER '; head -c 300 /dev/zero | tr '\\0' 'y'; echo; fi
      exit 0
      ;;
  esac
  shift
done
exit 1
EOF
chmod +x "$rg_tmp/codex" "$rg_tmp/gemini" "$rg_tmp/agy"
# FUSION_MAX_PROMPT_BYTES=10 → run_codex exits 2, fake never invoked.
rm -f "$rg_tmp/codex_invoked"
PATH="$rg_tmp:/usr/bin:/bin" FUSION_MAX_PROMPT_BYTES=10 \
  "$sh_bin" "$root/scripts/run_codex.sh" "$rg_prompt" "$rg_out" >/dev/null 2>&1
rg_rc=$?
if [ "$rg_rc" -eq 2 ] && [ ! -e "$rg_tmp/codex_invoked" ]; then
  ok "run_codex prompt-size guard exits 2 without invoking codex"
else bad "run_codex prompt-size guard broken (rc=$rg_rc, invoked=$([ -e "$rg_tmp/codex_invoked" ] && echo yes || echo no))"; fi
# Same guard on legacy gemini path.
rm -f "$rg_tmp/gemini_invoked"
PATH="$rg_tmp:/usr/bin:/bin" FUSION_GEMINI_BACKEND=gemini FUSION_ALLOW_LEGACY_GEMINI=1 FUSION_MAX_PROMPT_BYTES=10 \
  "$sh_bin" "$root/scripts/run_gemini.sh" "$rg_prompt" "$rg_out" >/dev/null 2>&1
rg_rc=$?
if [ "$rg_rc" -eq 2 ] && [ ! -e "$rg_tmp/gemini_invoked" ]; then
  ok "run_gemini legacy prompt-size guard exits 2 without invoking gemini"
else bad "run_gemini prompt-size guard broken (rc=$rg_rc, invoked=$([ -e "$rg_tmp/gemini_invoked" ] && echo yes || echo no))"; fi
# Antigravity ARG_MAX hard-fail: FUSION_ANTIGRAVITY_MAX_ARG_BYTES=10, fake agy never invoked.
rm -f "$rg_tmp/agy_invoked"
PATH="$rg_tmp:/usr/bin:/bin" FUSION_ANTIGRAVITY_MAX_ARG_BYTES=10 \
  "$sh_bin" "$root/scripts/run_antigravity.sh" "$rg_prompt" "$rg_out" >/dev/null 2>&1
rg_rc=$?
if [ "$rg_rc" -eq 2 ] && [ ! -e "$rg_tmp/agy_invoked" ]; then
  ok "run_antigravity arg-bytes guard exits 2 without invoking agy"
else bad "run_antigravity arg-bytes guard broken (rc=$rg_rc, invoked=$([ -e "$rg_tmp/agy_invoked" ] && echo yes || echo no))"; fi
# Min-output floor: tiny agy stdout → exit 1.
printf 'tiny-prompt\n' > "$rg_prompt"; : > "$rg_out"
rm -f "$rg_tmp/agy_invoked"
PATH="$rg_tmp:/usr/bin:/bin" FUSION_FAKE_AGY_TINY=1 FUSION_MIN_OUTPUT_BYTES=200 FUSION_ANTIGRAVITY_MAX_ARG_BYTES=0 \
  "$sh_bin" "$root/scripts/run_antigravity.sh" "$rg_prompt" "$rg_out" >/dev/null 2>&1
rg_rc=$?
if [ "$rg_rc" -eq 1 ]; then ok "run_antigravity min-output floor rejects tiny answer (exit 1)"
else bad "run_antigravity min-output floor broken (rc=$rg_rc, want 1)"; fi
# FUSION_NO_WEB argv: with =1 → read-only, no web_search; without → web_search present.
printf 'no-web-prompt\n' > "$rg_prompt"; : > "$rg_out"
rm -f "$rg_tmp/codex_args" "$rg_tmp/codex_invoked"
PATH="$rg_tmp:/usr/bin:/bin" FUSION_NO_WEB=1 FUSION_MAX_PROMPT_BYTES=0 FUSION_MIN_OUTPUT_BYTES=0 \
  "$sh_bin" "$root/scripts/run_codex.sh" "$rg_prompt" "$rg_out" >/dev/null 2>&1
if [ -f "$rg_tmp/codex_args" ] && grep -q 'read-only' "$rg_tmp/codex_args" && \
   ! grep -q 'web_search' "$rg_tmp/codex_args"; then
  ok "run_codex FUSION_NO_WEB=1 passes read-only and omits web_search"
else bad "run_codex FUSION_NO_WEB=1 argv assertion failed"; fi
rm -f "$rg_tmp/codex_args" "$rg_tmp/codex_invoked"
PATH="$rg_tmp:/usr/bin:/bin" FUSION_MAX_PROMPT_BYTES=0 FUSION_MIN_OUTPUT_BYTES=0 \
  "$sh_bin" "$root/scripts/run_codex.sh" "$rg_prompt" "$rg_out" >/dev/null 2>&1
if [ -f "$rg_tmp/codex_args" ] && grep -q 'web_search' "$rg_tmp/codex_args"; then
  ok "run_codex default argv enables web_search"
else bad "run_codex default web_search argv assertion failed"; fi
rm -rf "$rg_tmp" "$rg_prompt" "$rg_out"

echo "-- watchdog fallback --"
# Minimal PATH of real binaries WITHOUT timeout/gtimeout so fusion_run_with_timeout uses the
# bash watchdog path. Assert hard kill under the limit, no orphan sleep, and exit-code passthrough.
wd_tmp="$(mktemp -d "${TMPDIR:-/tmp}/pfo_wd.XXXXXX")"
for b in bash sleep kill pkill pgrep date true false; do
  src="$(command -v "$b" 2>/dev/null || true)"
  if [ -n "$src" ] && [ -e "$src" ]; then ln -sf "$src" "$wd_tmp/$b"; fi
done
# Ensure timeout/gtimeout are absent from the sandbox PATH even if linked by name collision.
rm -f "$wd_tmp/timeout" "$wd_tmp/gtimeout"
# The subshell's ok/bad counters are COPIES — export them via a file so a watchdog failure
# actually fails the suite instead of vanishing with the subshell.
wd_counts="$(mktemp "${TMPDIR:-/tmp}/pfo_wd_counts.XXXXXX")"
(
  # Subshell isolation: source backend helpers under the stripped PATH.
  export PATH="$wd_tmp"
  pass=0; fail=0
  # shellcheck disable=SC1091
  . "$root/scripts/gemini_backend.sh"
  # Slow command must be cut short (well under 10s) and return nonzero; no orphan sleep.
  # BASHPID needs bash>=4 (macOS ships 3.2): degrade to $$ there — the orphan probe turns
  # best-effort, the timing/rc assertions keep their teeth either way.
  wd_self="${BASHPID:-$$}"
  SECONDS=0
  fusion_run_with_timeout 1 sleep 10
  wd_rc=$?
  wd_elapsed=$SECONDS
  # Any remaining sleep children of this subshell are orphans ($wd_self: captured before the
  # command substitution forks its own subshell).
  wd_orphans="$(pgrep -P "$wd_self" -x sleep 2>/dev/null || true)"
  if [ "$wd_rc" -ne 0 ] && [ "$wd_elapsed" -le 8 ] && [ -z "$wd_orphans" ]; then
    ok "watchdog fallback kills slow command under limit (rc=$wd_rc, ${wd_elapsed}s, no orphans)"
  else
    bad "watchdog fallback slow-path broken (rc=$wd_rc, ${wd_elapsed}s, orphans='${wd_orphans}')"
  fi
  # Exit codes pass through unchanged.
  fusion_run_with_timeout 5 bash -c 'exit 7'
  wd_rc=$?
  if [ "$wd_rc" -eq 7 ]; then ok "watchdog fallback preserves exit 7"
  else bad "watchdog fallback exit passthrough failed (rc=$wd_rc, want 7)"; fi
  fusion_run_with_timeout 5 bash -c 'exit 0'
  wd_rc=$?
  if [ "$wd_rc" -eq 0 ]; then ok "watchdog fallback preserves exit 0"
  else bad "watchdog fallback success passthrough failed (rc=$wd_rc, want 0)"; fi
  printf '%s %s\n' "$pass" "$fail" > "$wd_counts"
)
read -r wd_pass wd_fail < "$wd_counts" 2>/dev/null || { wd_pass=0; wd_fail=1; }
pass=$((pass + wd_pass)); fail=$((fail + wd_fail))
rm -f "$wd_counts"
rm -rf "$wd_tmp"

echo "-- instruction-layer drift guards --"
# 1. Orphan references: every references/*.md must be mentioned by commands/, SKILL.md, or another
#    reference (transitively-loaded refs are legitimately wired). README mentions do NOT count —
#    the runtime never loads README.
for r in "$root"/references/*.md; do
  b="$(basename "$r")"
  if grep -rlF --include='*.md' "$b" "$root/commands" "$root/SKILL.md" "$root/references" 2>/dev/null \
       | grep -qv "references/$b$"; then
    ok "reference wired: $b"
  else
    bad "ORPHAN reference (never mentioned by commands/SKILL/other refs): $b"
  fi
done
# 2. Invariant-count drift: fusion-remind's cheat-sheet list must mirror SKILL.md's core invariants.
n_skill="$(awk '/^## Core invariants/{f=1; next} f && /^## /{exit} f' "$root/SKILL.md" | grep -cE '^[0-9]+\. ')"
n_remind="$(awk '/^## Invariants/{f=1; next} f && /^## /{exit} f' "$root/commands/fusion-remind.md" | grep -cE '^[0-9]+\. ')"
if [ "$n_skill" -gt 0 ] && [ "$n_skill" -eq "$n_remind" ]; then
  ok "invariant count SKILL.md == fusion-remind.md ($n_skill)"
else
  bad "invariant drift: SKILL.md=$n_skill fusion-remind.md=$n_remind"
fi
# 3. Retired-model guard: the previous GPT panelist label must not creep back via copy-paste.
#    (The pattern is spelled so this file's own source never matches itself.)
if grep -rqiE "gpt-?5[.]5" "$root" --exclude-dir=.git --exclude-dir=.fusion --exclude-dir=__pycache__ 2>/dev/null; then
  bad "retired GPT panelist label found — finish the rename: $(grep -rliE "gpt-?5[.]5" "$root" --exclude-dir=.git --exclude-dir=.fusion 2>/dev/null | head -3 | tr '\n' ' ')"
else
  ok "no retired GPT panelist labels remain"
fi
# 4. Path rule: command files must never invoke scripts by bare repo-relative path — always <skill-root>.
if grep -qE '(bash|python3) scripts/' "$root"/commands/*.md 2>/dev/null; then
  bad "bare 'scripts/' invocation in commands/ (must use <skill-root>/scripts/): $(grep -lE '(bash|python3) scripts/' "$root"/commands/*.md | head -3 | tr '\n' ' ')"
else
  ok "all command script invocations honor <skill-root>"
fi
# 5. Honest-degrade boilerplate presence (tokens, not exact wording) in the five panel commands.
for c in fusion fusion-review fusion-ultra fusion-investigate fusion-optimize; do
  if grep -q 'PANEL_STATE' "$root/commands/$c.md" && grep -q 'FUSION_ALLOW_DEGRADED' "$root/commands/$c.md"; then
    ok "degrade disclosure tokens present: $c.md"
  else
    bad "degrade disclosure tokens missing in commands/$c.md"
  fi
done

echo "-- efficiency guards (load-stack budgets) --"
# 1. Per-command mandatory load stack must stay under budget. The cap has ~15% headroom over the
#    heaviest stack at the time it was set (review ~5.2k) — raising it is a deliberate choice.
if bash "$root/scripts/load_stack_report.sh" --assert-max 6000 >/dev/null 2>"$err_tmp"; then
  ok "all command load stacks within 6000-token budget"
else
  bad "load stack over budget: $(tr '\n' ' ' < "$err_tmp")"
fi
# 2. SKILL.md frontmatter description is loaded into EVERY session — hard byte ceiling.
desc_bytes="$(awk '/^---$/{n++; next} n==1 && /^description:/{f=1} f && n==1 {print} /^---$/ && n==2{exit}' "$root/SKILL.md" | wc -c | tr -d ' ')"
if [ "$desc_bytes" -gt 0 ] && [ "$desc_bytes" -le 1000 ]; then
  ok "SKILL.md frontmatter description ${desc_bytes}B <= 1000B ceiling"
else
  bad "SKILL.md frontmatter description ${desc_bytes}B exceeds 1000B ceiling (or missing)"
fi
# 3. No single always-loadable reference balloons past 2500 tokens.
ref_over=""
for r in "$root"/references/*.md; do
  rb="$(wc -c < "$r" | tr -d ' ')"; rt=$(( (rb * 105 + 399) / 400 ))
  [ "$rt" -gt 2500 ] && ref_over="${ref_over}$(basename "$r")(${rt}) "
done
if [ -z "$ref_over" ]; then ok "no single reference exceeds 2500 tokens"
else bad "reference(s) over 2500 tokens: $ref_over"; fi
# 4. Routing-table row parity: SKILL.md is the source of truth; the three synced copies
#    (fusion-remind, README EN, README 中文) must keep the same row count.
count_rows() { # $1=file  $2=header-cell pattern
  awk -v pat="$2" '
    $0 ~ pat && /^\|/ {in_t=1; next}
    in_t && /^\|[ :-]*\|/ {next}          # separator row
    in_t && /^\|/ {n++; next}
    in_t {exit}
    END {print n+0}' "$1"
}
r_skill="$(count_rows "$root/SKILL.md" "The user is")"
r_remind="$(count_rows "$root/commands/fusion-remind.md" "The situation")"
r_readme_en="$(count_rows "$root/README.md" "When you.re trying to")"
r_readme_zh="$(count_rows "$root/README.md" "你想干的")"
if [ "$r_skill" -gt 0 ] && [ "$r_skill" = "$r_remind" ] && [ "$r_skill" = "$r_readme_en" ] && [ "$r_skill" = "$r_readme_zh" ]; then
  ok "routing-table row parity across SKILL/remind/README-EN/README-中文 ($r_skill rows)"
else
  bad "routing-table drift: SKILL=$r_skill remind=$r_remind README-EN=$r_readme_en README-中文=$r_readme_zh"
fi

echo
echo "== result: $pass passed, $fail failed =="
[ "$fail" -eq 0 ] || exit 1
echo "SMOKE OK"
