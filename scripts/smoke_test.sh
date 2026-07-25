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
  scripts/fusion_map.sh
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
if echo "$gb_default" | grep -q '^PANEL_STATE=DEGRADED_CLAUDE_GPT' && \
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
if PATH=/nonexistent "$sh_bin" "$root/scripts/assert_panel.sh" --mode single_claude >/dev/null 2>&1; then
  ok "assert_panel.sh allows single_claude with no external CLIs"
else bad "assert_panel.sh single_claude should not need external CLIs"; fi
# Recursion guard: a panelist process (FUSION_PANEL_CHILD=1) must be refused with exit 14 everywhere.
FUSION_PANEL_CHILD=1 "$sh_bin" "$root/scripts/assert_panel.sh" --mode single_claude >/dev/null 2>&1
[ $? -eq 14 ] && ok "assert_panel.sh blocks recursive invocation (exit 14)" || bad "assert_panel.sh should exit 14 under FUSION_PANEL_CHILD=1"
FUSION_PANEL_CHILD=1 "$sh_bin" "$root/scripts/assert_triple_panel.sh" >/dev/null 2>&1
[ $? -eq 14 ] && ok "assert_triple_panel.sh blocks recursive invocation (exit 14)" || bad "assert_triple_panel.sh should exit 14 under FUSION_PANEL_CHILD=1"
rec_d="$(mktemp -d "${TMPDIR:-/tmp}/pfo_rec.XXXXXX")"; printf 'x\n' > "$rec_d/p.md"; printf 'keep\n' > "$rec_d/manifest.txt"
FUSION_PANEL_CHILD=1 "$sh_bin" "$root/scripts/run_panel.sh" --mode single_claude "$rec_d/p.md" "$rec_d" >/dev/null 2>&1
rec_rc=$?
if [ "$rec_rc" -eq 14 ] && [ -s "$rec_d/manifest.txt" ]; then
  ok "run_panel.sh blocks recursion BEFORE the stale-clear (exit 14, out_dir untouched)"
else bad "run_panel.sh recursion guard broken (rc=$rec_rc, manifest kept: $([ -s "$rec_d/manifest.txt" ] && echo yes || echo no))"; fi
rm -rf "$rec_d"
if PATH=/nonexistent "$sh_bin" "$root/scripts/assert_panel.sh" --mode claude_gpt_pair >/dev/null 2>&1; then
  bad "assert_panel.sh claude_gpt_pair should fail without codex"
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

# An EMPTY map must be a loud failure, not a silent exit-0 success. The regression this guards: an
# unmapped language (or a fully-pruned path) yielded a codemap-shaped artifact with no signatures in it,
# and /fusion-review's caller-context fallback shipped that to the panel as "context".
cm_empty_dir="$(mktemp -d "${TMPDIR:-/tmp}/pfo_cmempty.XXXXXX")"
: > "$cm_empty_dir/notes.rtf"
cm_empty_out="$(bash "$root/scripts/codemap.sh" "$cm_empty_dir" 2>/dev/null)"; cm_empty_rc=$?
if [ "$cm_empty_rc" -ne 0 ]; then ok "codemap.sh: empty map exits non-zero ($cm_empty_rc)"
else bad "codemap.sh: empty map exited 0 — silent empty success"; fi
echo "$cm_empty_out" | grep -q '^CODEMAP_FILES=0' && ok "codemap.sh: empty map discloses CODEMAP_FILES=0" \
  || bad "codemap.sh: empty map missing CODEMAP_FILES=0"
rm -rf "$cm_empty_dir"

# Modifier-led languages (C#/Java/Swift/Kotlin) declare methods with NO keyword. A keyword-only signature
# pattern mapped zero methods there while still exiting 0 — the same silent-empty class as above.
cm_cs_dir="$(mktemp -d "${TMPDIR:-/tmp}/pfo_cmcs.XXXXXX")"
cat > "$cm_cs_dir/Probe.cs" <<'CSEOF'
using UnityEngine;
public class Probe : MonoBehaviour {
    public void Bind(Actor actor) { }
    private static float Clamp01(float v) => Mathf.Clamp01(v);
}
CSEOF
cm_cs="$(FUSION_CODEMAP_TIER=regex bash "$root/scripts/codemap.sh" "$cm_cs_dir" 2>/dev/null)"
for cs_sym in 'class Probe' 'Bind(' 'Clamp01('; do
  echo "$cm_cs" | grep -qF "$cs_sym" && ok "codemap.sh maps C# '$cs_sym'" \
    || bad "codemap.sh missed C# '$cs_sym' — modifier-led declarations unmapped"
done
rm -rf "$cm_cs_dir"

# /fusion-review's caller-context step must use `git grep` (tracked files only): `grep -r` walks .git and
# gitignored build output and filters afterward — measured 17.7x slower here, orders of magnitude on a
# repo with a multi-GB build dir.
echo "-- fusion_map: cache correctness + honest degrade --"
# Build a throwaway repo so these assertions never depend on the host repo's working-tree state.
fm_repo="$(mktemp -d "${TMPDIR:-/tmp}/pfo_fmrepo.XXXXXX")"
fm_out="$(mktemp -d "${TMPDIR:-/tmp}/pfo_fmout.XXXXXX")"
(
  cd "$fm_repo" || exit 1
  git init -q .
  mkdir -p src
  printf 'def alpha():\n    pass\n'  > src/a.py
  printf 'def beta():\n    pass\n'   > src/b.py
  printf 'public class C { public void Go() { } }\n' > src/C.cs
  # Deliberately the LARGEST block in the fixture: the drop-order guard below is only meaningful if
  # prose is big enough that a binding budget must choose between it and the source blocks.
  { printf '# Doc title\n\n'; i=1; while [ $i -le 30 ]; do printf '## Section %s\n\nprose\n\n' "$i"; i=$((i+1)); done; } > notes.md
  git add -A && git -c user.email=a@b -c user.name=a commit -qm init
) >/dev/null 2>&1
# FUSION_MAP_CACHE pinned to a throwaway dir: without it these runs populate the operator's real
# ~/.cache/fusion-deck, so the suite would leave state behind and could read a previous run's entries.
fm_cache="$(mktemp -d "${TMPDIR:-/tmp}/pfo_fmcache.XXXXXX")"
fm() { ( cd "$fm_repo" && FUSION_MAP_CACHE="$fm_cache" bash "$root/scripts/fusion_map.sh" "$fm_out" "$@" 2>/dev/null ); }
fm_get() { printf '%s\n' "$1" | grep "^$2=" | cut -d= -f2; }

fm_cold="$(fm)"
[ "$(fm_get "$fm_cold" CACHE_MISS)" -gt 0 ] && ok "fusion_map: cold run populates the cache (MISS>0)" \
  || bad "fusion_map: cold run reported no cache misses"
fm_warm="$(fm)"
if [ "$(fm_get "$fm_warm" CACHE_MISS)" -eq 0 ] && [ "$(fm_get "$fm_warm" CACHE_HIT)" -gt 0 ]; then
  ok "fusion_map: warm run is a full cache hit"
else
  bad "fusion_map: warm run did not hit the cache (HIT=$(fm_get "$fm_warm" CACHE_HIT) MISS=$(fm_get "$fm_warm" CACHE_MISS))"
fi

# THE regression this guards: `git ls-files -s` reports the INDEX sha, so an unstaged edit left the cache
# key unchanged and the map silently described the pre-edit code — under `/fusion-review uncommitted`,
# the most common scope of all. The working tree must be re-hashed.
# The edit adds a SIGNATURE (codemap emits signatures, never bodies), so the map's content can be checked.
printf 'def alpha():\n    pass\n\ndef alpha_unstaged():\n    pass\n' > "$fm_repo/src/a.py"
fm_dirty="$(fm)"
if [ "$(fm_get "$fm_dirty" CACHE_MISS)" -eq 1 ]; then
  ok "fusion_map: an unstaged edit invalidates exactly one cache entry"
else
  bad "fusion_map: unstaged edit produced MISS=$(fm_get "$fm_dirty" CACHE_MISS) (want 1) — stale-index bug"
fi
grep -q 'alpha_unstaged' "$fm_out/map.md" 2>/dev/null \
  && ok "fusion_map: the map reflects working-tree content, not the index" \
  || bad "fusion_map: the map does not reflect the unstaged edit"

# An untracked (not ignored) source file is part of an `uncommitted` review and must appear.
printf 'def gamma():\n    pass\n' > "$fm_repo/src/new.py"
fm_new="$(fm)"
grep -q 'src/new.py' "$fm_out/map.md" 2>/dev/null \
  && ok "fusion_map: untracked source files appear in the map" \
  || bad "fusion_map: untracked source file missing from the map"
rm -f "$fm_repo/src/new.py"

# Truncation must be DISCLOSED, and file_map must stay complete — a file dropped from the codemap is
# still named, so a seat knows it exists and can read it.
fm_trunc="$( cd "$fm_repo" && FUSION_MAP_CACHE="$fm_cache" FUSION_MAP_BUDGET_TOKENS=1 bash "$root/scripts/fusion_map.sh" "$fm_out" 2>/dev/null )"
if [ "$(fm_get "$fm_trunc" MAP_STATE)" = "TRUNCATED" ] && [ "$(fm_get "$fm_trunc" MAP_DROPPED)" -gt 0 ]; then
  ok "fusion_map: over-budget run discloses MAP_STATE=TRUNCATED + MAP_DROPPED"
else
  bad "fusion_map: over-budget run did not disclose truncation"
fi
grep -q 'src/C.cs' "$fm_out/map.md" 2>/dev/null \
  && ok "fusion_map: file_map stays complete under truncation" \
  || bad "fusion_map: truncation removed a path from file_map — files must never be hidden"

# The byte ceiling must bind, because the real constraint is the TIGHTEST seat's prompt transport (the
# Antigravity seat passes its prompt via argv), not the token budget. A map sized to codex's looser cap
# silently costs the panel its Gemini seat.
fm_bytes="$( cd "$fm_repo" && FUSION_MAP_CACHE="$fm_cache" FUSION_MAP_MAX_BYTES=900 FUSION_MAP_BUDGET_TOKENS=999999 \
             bash "$root/scripts/fusion_map.sh" "$fm_out" 2>/dev/null )"
if [ -f "$fm_out/map.md" ] && [ "$(wc -c < "$fm_out/map.md" | tr -d ' ')" -le 900 ]; then
  ok "fusion_map: FUSION_MAP_MAX_BYTES caps the map even when the token budget is huge"
else
  bad "fusion_map: byte ceiling did not bind (map.md $(wc -c < "$fm_out/map.md" 2>/dev/null | tr -d ' ') > 900)"
fi
# file_map alone over the ceiling: refuse loudly (exit 4). Truncating file_map would hide that files
# exist; emitting anyway would kill a seat at launch. Neither is an acceptable silent outcome.
( cd "$fm_repo" && FUSION_MAP_CACHE="$fm_cache" FUSION_MAP_MAX_BYTES=10 bash "$root/scripts/fusion_map.sh" "$fm_out" >/dev/null 2>&1 ); fm_rc=$?
[ "$fm_rc" -eq 4 ] && ok "fusion_map: file_map over the byte ceiling exits 4 (OVERSIZE)" \
  || bad "fusion_map: oversize file_map exited $fm_rc (want 4)"

# Density tiers. Each of these was a measured defect, not a hypothetical:
#   - markdown mapped to an EMPTY block while file_map still marked it ' +' (claiming signatures that did
#     not exist) — 150 such blocks in a 498-file repo;
#   - once markdown emitted outlines, append-only docs (session logs) began crowding real source out of
#     the byte budget, so code is ordered ahead of prose;
#   - focus files got signatures only, when the body is what tells a reviewer the change fits the file.
fm_tiers="$(fm src/a.py)"
grep -q '# Doc title' "$fm_out/map.md" 2>/dev/null \
  && ok "fusion_map: markdown contributes a heading outline, not an empty block" \
  || bad "fusion_map: markdown produced no outline"
if ! awk '/^## codemap/{c=1} c&&/^File: /{p=$2; getline l; if (l=="" || l=="Imports:") {getline l2; if (l2=="" ) {print p; exit 1}}}' \
       "$fm_out/map.md" >/dev/null 2>&1; then
  bad "fusion_map: an empty codemap block survived into the map"
else
  ok "fusion_map: no empty codemap blocks (they degrade to the tree-only tier)"
fi
printf '%s\n' "$fm_tiers" | grep -q '^MAP_TREEONLY=' \
  && ok "fusion_map: discloses MAP_TREEONLY separately from MAP_DROPPED" \
  || bad "fusion_map: MAP_TREEONLY not disclosed — 'nothing to show' collapsed into 'budget dropped'"
grep -q 'full content — focus file' "$fm_out/map.md" 2>/dev/null \
  && ok "fusion_map: a focus file is emitted at the full tier" \
  || bad "fusion_map: focus file got signatures only — the body is what shows the change fits"
# Code must outrank prose in the drop order, or a docs-heavy repo starves the map of source.
# Assert against the ## codemap SECTION only: the previous form grepped the whole map.md, and file_map is
# emitted complete by design, so it was green no matter how badly the drop order regressed.
# The invariant is ORDERING, so assert it directly rather than hunting a budget that happens to bite:
# every source block must precede every prose block, so prose is what the byte ceiling eats first.
( cd "$fm_repo" && FUSION_MAP_CACHE="$fm_cache" bash "$root/scripts/fusion_map.sh" "$fm_out" ) >/dev/null 2>&1
fm_last_src="$(awk '/^## codemap/,0' "$fm_out/map.md" | grep -n '^File: src/' | tail -1 | cut -d: -f1)"
fm_first_prose="$(awk '/^## codemap/,0' "$fm_out/map.md" | grep -n '^File: notes.md' | head -1 | cut -d: -f1)"
if [ -n "$fm_last_src" ] && [ -n "$fm_first_prose" ] && [ "$fm_last_src" -lt "$fm_first_prose" ]; then
  ok "fusion_map: every source block precedes every prose block (prose is dropped first)"
else
  bad "fusion_map: drop order wrong — last source block at $fm_last_src, first prose at $fm_first_prose"
fi
# And a budget inside the band where truncation actually happens must drop the prose block, not source.
( cd "$fm_repo" && FUSION_MAP_CACHE="$fm_cache" FUSION_MAP_MAX_BYTES=900 bash "$root/scripts/fusion_map.sh" "$fm_out" ) >/dev/null 2>&1
fm_cm="$(awk '/^## codemap/,0' "$fm_out/map.md" 2>/dev/null)"
if printf '%s' "$fm_cm" | grep -q 'File: src/' && ! printf '%s' "$fm_cm" | grep -q 'File: notes.md'; then
  ok "fusion_map: a binding budget keeps source and drops prose"
else
  bad "fusion_map: binding budget kept $(printf '%s' "$fm_cm" | grep -c 'File: src/') source / $(printf '%s' "$fm_cm" | grep -c 'File: notes.md') prose block(s)"
fi
# OVERSIZE must not leave a previous run's map.md consumable in the out dir.
( cd "$fm_repo" && FUSION_MAP_CACHE="$fm_cache" FUSION_MAP_MAX_BYTES=10 bash "$root/scripts/fusion_map.sh" "$fm_out" ) >/dev/null 2>&1
[ -e "$fm_out/map.md" ] && bad "fusion_map: OVERSIZE left a stale map.md the caller could consume" \
                        || ok "fusion_map: OVERSIZE removes any stale map.md"

# Deletions must leave the map. The old blob SHA stayed a cache HIT, so a deleted file kept both its
# file_map entry and a full signature block — signatures for functions that no longer exist.
printf 'def doomed():\n    pass\n' > "$fm_repo/src/gone.py"
( cd "$fm_repo" && git add -A && git -c user.email=a@b -c user.name=a commit -qm add-gone ) >/dev/null 2>&1
fm_del="$(fm)"; rm -f "$fm_repo/src/gone.py"; fm_del="$(fm)"
if grep -q 'src/gone.py\|doomed' "$fm_out/map.md" 2>/dev/null; then
  bad "fusion_map: a deleted file is still in the map (stale cache hit on its old blob)"
else
  ok "fusion_map: a deleted file leaves the map entirely"
fi

# The cache key must carry the TIER, and the run must report the tier that actually produced the blocks.
# A warm run once reported CODEMAP_STATE=CACHED — a fourth state documented nowhere.
fm_warm2="$(fm)"
case "$(fm_get "$fm_warm2" CODEMAP_STATE)" in
  TREESITTER|CTAGS|REGEX) ok "fusion_map: warm runs report a real tier, not an undocumented state" ;;
  *) bad "fusion_map: warm run reported CODEMAP_STATE=$(fm_get "$fm_warm2" CODEMAP_STATE) — not in the contract" ;;
esac
if bash "$root/scripts/codemap.sh" --print-tier 2>/dev/null | grep -q '^CODEMAP_STATE='; then
  ok "codemap.sh --print-tier lets callers key a cache without re-deriving tier logic"
else
  bad "codemap.sh --print-tier missing — cache keying would have to duplicate tier detection"
fi

# Two files with identical content share a blob SHA. Caching the `File:` header with the body made the
# second one inherit the first one's path.
printf 'def same():\n    pass\n' > "$fm_repo/src/one.py"
printf 'def same():\n    pass\n' > "$fm_repo/src/two.py"
fm_dup="$(fm)"
if [ "$(grep -c '^File: src/one.py$' "$fm_out/map.md")" = 1 ] && [ "$(grep -c '^File: src/two.py$' "$fm_out/map.md")" = 1 ]; then
  ok "fusion_map: identical-content files keep their own paths (cached body is path-independent)"
else
  bad "fusion_map: same-blob files collided — one inherited the other's path"
fi
rm -f "$fm_repo/src/one.py" "$fm_repo/src/two.py"

# Same trap in the FULL tier: two focus paths with identical content share a blob SHA, and keying the
# full block by that SHA made the second overwrite the first — the map then showed one path twice and
# lost the other completely.
printf 'def twin():\n    pass\n' > "$fm_repo/src/t1.py"
printf 'def twin():\n    pass\n' > "$fm_repo/src/t2.py"
fm_twin="$(fm src/t1.py src/t2.py)"
if [ "$(grep -c '^File: src/t1.py  \[full' "$fm_out/map.md")" = 1 ] \
   && [ "$(grep -c '^File: src/t2.py  \[full' "$fm_out/map.md")" = 1 ]; then
  ok "fusion_map: identical-content FOCUS files each get their own full block"
else
  bad "fusion_map: same-blob focus files collided in the full tier — one path replaced the other"
fi
rm -f "$fm_repo/src/t1.py" "$fm_repo/src/t2.py"

# The same focus path given twice emitted its block twice — duplicating a file inside the shared prompt
# and pushing MAP_MAPPED above MAP_FILES.
fm_dupfocus="$(fm src/a.py src/a.py)"
[ "$(awk '/^## codemap/,0' "$fm_out/map.md" | grep -c '^File: src/a.py')" = 1 ] \
  && ok "fusion_map: a repeated focus path is emitted once" \
  || bad "fusion_map: a repeated focus path was emitted more than once"

# Every source file must land in exactly one bucket. If these stop summing, files are going missing
# somewhere between the inventory and the map, and no other assertion would notice.
fm_cons="$(fm)"
fm_f=$(fm_get "$fm_cons" MAP_FILES); fm_m=$(fm_get "$fm_cons" MAP_MAPPED)
fm_d=$(fm_get "$fm_cons" MAP_DROPPED); fm_t=$(fm_get "$fm_cons" MAP_TREEONLY)
if [ $((fm_m + fm_d + fm_t)) -eq "$fm_f" ]; then
  ok "fusion_map: MAPPED + DROPPED + TREEONLY == FILES (no file silently lost)"
else
  bad "fusion_map: counts do not conserve — FILES=$fm_f but $fm_m+$fm_d+$fm_t=$((fm_m+fm_d+fm_t))"
fi

# The cache must not be written into the repo being described.
if [ -e "$fm_repo/.fusion" ]; then
  bad "fusion_map: wrote .fusion into the target repo — a read-side builder must not mutate the tree"
else
  ok "fusion_map: leaves no cache artifacts inside the target repo"
fi

# A signal handler that only cleans up RESUMES the script: an interrupted run continued with $tmp already
# deleted and still printed MAP_STATE=FULL and exit 0. SIGTERM is what this harness can deliver (a
# non-interactive shell ignores SIGINT in background jobs, so no trap of any shape could be tested that
# way); the INT handler is the same shape with a different exit code.
fm_sig_repo="$(mktemp -d "${TMPDIR:-/tmp}/pfo_fmsig.XXXXXX")"
(
  cd "$fm_sig_repo" || exit 1
  git init -q .
  i=1; while [ $i -le 400 ]; do printf 'def f%s():\n    pass\n' "$i" > "f$i.py"; i=$((i+1)); done
  git add -A && git -c user.email=a@b -c user.name=a commit -qm init
) >/dev/null 2>&1
fm_sig_cache="$(mktemp -d "${TMPDIR:-/tmp}/pfo_fmsigc.XXXXXX")"
fm_sig_out="$(mktemp -d "${TMPDIR:-/tmp}/pfo_fmsigo.XXXXXX")"
( cd "$fm_sig_repo" && FUSION_MAP_CACHE="$fm_sig_cache" bash "$root/scripts/fusion_map.sh" "$fm_sig_out" ) \
  >"$fm_sig_out/log" 2>&1 &
fm_sig_pid=$!
sleep 0.4; kill -TERM "$fm_sig_pid" 2>/dev/null; wait "$fm_sig_pid" 2>/dev/null; fm_sig_rc=$?
if [ "$fm_sig_rc" -ne 0 ] && ! grep -q '^MAP_STATE=' "$fm_sig_out/log" 2>/dev/null; then
  ok "fusion_map: a signalled run stops (rc=$fm_sig_rc) instead of finishing with a success state"
else
  bad "fusion_map: signalled run exited $fm_sig_rc and still emitted $(grep -c '^MAP_STATE=' "$fm_sig_out/log" 2>/dev/null) MAP_STATE line(s)"
fi
[ "$(find "$fm_sig_cache" -name '.stage.*' 2>/dev/null | wc -l | tr -d ' ')" = 0 ] \
  && ok "fusion_map: a signalled run strands no staging dir in the cache" \
  || bad "fusion_map: a signalled run left .stage.* behind in the cache"
rm -rf "$fm_sig_repo" "$fm_sig_cache" "$fm_sig_out"

# HOME is not guaranteed under cron/CI, and `set -u` turned a bare $HOME into a crash partway through.
if ( cd "$fm_repo" && env -u HOME -u XDG_CACHE_HOME -u FUSION_MAP_CACHE \
       bash "$root/scripts/fusion_map.sh" "$fm_out" ) >/dev/null 2>&1; then
  ok "fusion_map: survives an unset HOME (falls back to a temp cache)"
else
  bad "fusion_map: crashes when HOME is unset — cron and CI runs would die mid-build"
fi
# A non-numeric timeout is a VARIABLE NAME in bash arithmetic; under set -u that crashed with a message
# naming neither the variable the operator set nor the reason.
tl_bad_dir="$(mktemp -d "${TMPDIR:-/tmp}/pfo_tlbad.XXXXXX")"
printf '#!/usr/bin/env bash\nprintf "%%0.sX" {1..300}\n' > "$tl_bad_dir/agy"; chmod +x "$tl_bad_dir/agy"
printf 'probe\n' > "$tl_bad_dir/p.md"
tl_bad="$(PATH="$tl_bad_dir:$PATH" FUSION_PANEL_TIMEOUT=abc bash "$root/scripts/run_antigravity.sh" \
            "$tl_bad_dir/p.md" "$tl_bad_dir/o.md" 2>&1 | head -1)"
case "$tl_bad" in
  *"must be a whole number"*) ok "run_antigravity: a non-numeric FUSION_PANEL_TIMEOUT is rejected by name" ;;
  *) bad "run_antigravity: bad FUSION_PANEL_TIMEOUT produced '$tl_bad' instead of a named error" ;;
esac
rm -rf "$tl_bad_dir"

# Honest degrade: not a repo => exit 2 + NO_GIT; a repo with no source => exit 3 (never an empty success).
fm_nogit="$(mktemp -d "${TMPDIR:-/tmp}/pfo_fmng.XXXXXX")"
( cd "$fm_nogit" && FUSION_MAP_CACHE="$fm_cache" bash "$root/scripts/fusion_map.sh" "$fm_nogit" >/dev/null 2>&1 ); fm_rc=$?
[ "$fm_rc" -eq 2 ] && ok "fusion_map: outside a git repo exits 2" || bad "fusion_map: outside a git repo exited $fm_rc (want 2)"
( cd "$fm_nogit" && git init -q . && echo x > README.nosrc && git add -A \
    && git -c user.email=a@b -c user.name=a commit -qm x \
    && FUSION_MAP_CACHE="$fm_cache" bash "$root/scripts/fusion_map.sh" "$fm_nogit" >/dev/null 2>&1 ); fm_rc=$?
[ "$fm_rc" -eq 3 ] && ok "fusion_map: a source-free repo exits 3 (no empty map)" \
  || bad "fusion_map: source-free repo exited $fm_rc (want 3) — silent empty map"
rm -rf "$fm_repo" "$fm_out" "$fm_nogit" "$fm_cache"

# The extension list must exist in exactly ONE place; a second copy drifts and silently drops a language.
# Pattern built from fragments so this guard never matches its own source (same trick as the retired-label
# guards above).
# ...and the membership test must not depend on the sourcing shell's word-splitting rules: under zsh the
# old `for e in $LIST` form matched nothing, which reads as "this repo has no source files".
if command -v zsh >/dev/null 2>&1; then
  if zsh -c ". '$root/scripts/gemini_backend.sh'; fusion_is_source_path a.py && fusion_is_source_path b.cs" >/dev/null 2>&1; then
    ok "fusion_is_source_path works under zsh as well as bash (no word-split dependency)"
  else
    bad "fusion_is_source_path matches nothing under zsh — silent empty map for a whole repo"
  fi
fi
# The oracle must be fusion_map.sh ITSELF, not a third copy of the filter pasted in here — a hand copy
# only proves the test agrees with itself, and drifts along with nothing. Drive the real script over a
# fixture containing each path shape and compare against fusion_is_source_path.
_ext_repo="$(mktemp -d "${TMPDIR:-/tmp}/pfo_extr.XXXXXX")"
(
  cd "$_ext_repo" || exit 1
  git init -q .
  mkdir -p "dir.d"
  for _p in a.py b.cs c.md "dir.d/noext" "h.p?" e.tar.gz; do
    printf 'def probe():\n    pass\n' > "$_p" 2>/dev/null || true
  done
  printf 'x\n' > d.png
  git add -A && git -c user.email=a@b -c user.name=a commit -qm init
) >/dev/null 2>&1
_ext_c="$(mktemp -d "${TMPDIR:-/tmp}/pfo_extc.XXXXXX")"
_ext_o="$(mktemp -d "${TMPDIR:-/tmp}/pfo_exto.XXXXXX")"
( cd "$_ext_repo" && FUSION_MAP_CACHE="$_ext_c" bash "$root/scripts/fusion_map.sh" "$_ext_o" ) >/dev/null 2>&1
_map_yes="$(awk '/^## file_map/,/^## codemap/' "$_ext_o/map.md" 2>/dev/null \
             | grep -vE '^```|^\(|^$|^##' | sed 's/ *+*$//' | sort)"
_sh_yes="$( . "$root/scripts/gemini_backend.sh"
            ( cd "$_ext_repo" && git -c core.quotePath=false ls-files ) | while IFS= read -r pth; do
              fusion_is_source_path "$pth" && printf '%s\n' "$pth"; done | sort )"
if [ "$_map_yes" = "$_sh_yes" ]; then
  ok "fusion_map's real filter agrees with fusion_is_source_path end-to-end"
else
  bad "source-filter drift — map:[$(printf '%s' "$_map_yes" | tr '\n' ' ')] shell:[$(printf '%s' "$_sh_yes" | tr '\n' ' ')]"
fi
rm -rf "$_ext_repo" "$_ext_c" "$_ext_o"

_fm_ext_pat="$(printf '%s_SOURCE_EXT=' 'FUSION')"
if [ "$(grep -rl "$_fm_ext_pat" "$root/scripts" | wc -l | tr -d ' ')" -eq 1 ]; then
  ok "fusion_map/codemap share one FUSION_SOURCE_EXT definition"
else
  bad "FUSION_SOURCE_EXT defined in more than one file — the lists will drift"
fi

echo "-- model tiering: retrieval vs analysis --"
# The split is load-bearing, and BOTH directions fail silently when unpinned (an Agent subagent inherits
# the session model): an unpinned panelist quietly seats a weaker model while the run still reports
# PREMIUM; an unpinned discovery subagent spends the top tier on grep.
for c in fusion fusion-ultra; do
  grep -q 'model: opus' "$root/commands/$c.md" \
    && ok "$c.md pins the analysis seat to opus" \
    || bad "$c.md spawns a Claude panelist without pinning the model — silent downgrade risk"
done
grep -q 'model: sonnet' "$root/references/context-discovery.md" \
  && ok "context-discovery.md pins the retrieval subagent to a fast model" \
  || bad "context-discovery.md leaves the discovery subagent unpinned — top-tier model doing grep"
# Edge shapes the awk rewrites must survive. The empty-first-file trap in particular has bitten three
# separate times: with an empty cache listing, `NR==FNR` stays true for every record of the SECOND file
# and silently swallows the whole inventory.
fm_edge="$(mktemp -d "${TMPDIR:-/tmp}/pfo_fmedge.XXXXXX")"
(
  cd "$fm_edge" || exit 1
  git init -q .
  mkdir -p "dir with space" "dir.d"
  printf 'def a():\n    pass\n' > "dir with space/my file.py"   # spaces survive the pipeline
  printf 'def b():\n    pass\n' > "dir.d/noext"                 # a dot in the DIR is not an extension
  printf 'def c():\n    pass\n' > "a.b.py"                      # classified by the LAST extension
  printf 'x\n'                   > img.png                       # non-source stays out
  git add -A && git -c user.email=a@b -c user.name=a commit -qm init
) >/dev/null 2>&1
fm_ec="$(mktemp -d "${TMPDIR:-/tmp}/pfo_fmec.XXXXXX")"
fm_eo="$(mktemp -d "${TMPDIR:-/tmp}/pfo_fmeo.XXXXXX")"
fm_e1="$( cd "$fm_edge" && FUSION_MAP_CACHE="$fm_ec" bash "$root/scripts/fusion_map.sh" "$fm_eo" 2>/dev/null )"
fm_e2="$( cd "$fm_edge" && FUSION_MAP_CACHE="$fm_ec" bash "$root/scripts/fusion_map.sh" "$fm_eo" 2>/dev/null )"
[ "$(fm_get "$fm_e1" MAP_FILES)" = 2 ] \
  && ok "fusion_map: extension filter takes the last extension and ignores dots in directories" \
  || bad "fusion_map: MAP_FILES=$(fm_get "$fm_e1" MAP_FILES) on the edge fixture, expected 2"
[ "$(fm_get "$fm_e1" CACHE_MISS)" = 2 ] \
  && ok "fusion_map: an EMPTY cache listing does not swallow the inventory (awk first-file trap)" \
  || bad "fusion_map: cold MISS=$(fm_get "$fm_e1" CACHE_MISS), expected 2 — empty first file swallowed records"
[ "$(fm_get "$fm_e2" CACHE_HIT)" = 2 ] \
  && ok "fusion_map: warm run hits every entry written by the cold run" \
  || bad "fusion_map: warm HIT=$(fm_get "$fm_e2" CACHE_HIT), expected 2"
grep -q 'my file.py' "$fm_eo/map.md" 2>/dev/null \
  && ok "fusion_map: a path containing spaces survives the awk pipeline" \
  || bad "fusion_map: a path with spaces was lost"
# A TRACKED symlink is mode 120000 and `git ls-files -d` never reports it deleted, because the link
# itself exists — so a broken one was counted, listed and handed to codemap once the per-file [ -f ]
# test was optimised away.
( cd "$fm_edge" && ln -s nowhere.py broken.py && git add -A \
    && git -c user.email=a@b -c user.name=a commit -qm link ) >/dev/null 2>&1
fm_lnk="$( cd "$fm_edge" && FUSION_MAP_CACHE="$fm_ec" bash "$root/scripts/fusion_map.sh" "$fm_eo" 2>/dev/null )"
{ [ "$(fm_get "$fm_lnk" MAP_FILES)" = 2 ] && ! grep -q 'broken.py' "$fm_eo/map.md"; } \
  && ok "fusion_map: tracked symlinks are excluded from the inventory (mode 120000)" \
  || bad "fusion_map: a tracked symlink reached the map — it cannot be read and may point outside the repo"
rm -rf "$fm_edge" "$fm_ec" "$fm_eo"

echo "-- caller_slices behaviour --"
# Functional, not textual: this step has shipped three separate silent-empty bugs, so assert what the
# script DOES on a real repo rather than what its source looks like.
cs_repo="$(mktemp -d "${TMPDIR:-/tmp}/pfo_cs.XXXXXX")"
(
  cd "$cs_repo" || exit 1
  git init -q .
  mkdir -p src
  # one symbol with MANY call-sites, so the per-symbol cap has something to bite on
  printf 'def helper():\n    pass\n' > src/lib.py
  i=1; while [ $i -le 12 ]; do
    printf 'from lib import helper\n\ndef use%s():\n    return helper()\n' "$i" > "src/use$i.py"
    i=$((i+1))
  done
  git add -A && git -c user.email=a@b -c user.name=a commit -qm init
  printf 'def helper():\n    pass\n\ndef helper_two():\n    pass\n' > src/lib.py   # declares a new symbol
) >/dev/null 2>&1
cs_out="$(mktemp -d "${TMPDIR:-/tmp}/pfo_cso.XXXXXX")"
cs_status="$( cd "$cs_repo" && bash "$root/scripts/caller_slices.sh" uncommitted "$cs_out" 2>&1 )"
cs_rc=$?
printf '%s' "$cs_status" | grep -q '^CALLER_SLICES=' \
  && ok "caller_slices discloses a greppable CALLER_SLICES= state" \
  || bad "caller_slices printed no CALLER_SLICES= line"
# ±context, not one line per hit: a bare index tells a reviewer a symbol is used, not HOW.
if [ -f "$cs_out/callers.md" ] && grep -qE '^[^:]+-[0-9]+-' "$cs_out/callers.md"; then
  ok "caller_slices emits context lines around each hit (slices, not an index)"
else
  bad "caller_slices produced no context lines — one line per hit is not reviewable"
fi
# A brand-new symbol has no callers yet, but git grep still finds its declaration. If that tripped the
# empty guard the whole review would stop on the most ordinary kind of diff there is.
( cd "$cs_repo" && git checkout -- src/lib.py \
    && printf 'def helper():\n    pass\n\ndef brand_new():\n    pass\n' > src/lib.py ) >/dev/null 2>&1
cs_new="$( cd "$cs_repo" && bash "$root/scripts/caller_slices.sh" uncommitted "$cs_out" 2>&1 )"
cs_new_rc=$?
{ [ "$cs_new_rc" -eq 0 ] && printf '%s' "$cs_new" | grep -q 'CALLER_SLICES=OK'; } \
  && ok "caller_slices: a brand-new symbol does not false-fire the empty guard" \
  || bad "caller_slices: brand-new symbol exited $cs_new_rc — an ordinary diff would stop the review"

# Word-boundary attribution at the EDGES of a line. `index(WORD, "")` returns 1 in awk — the empty
# string is "found" at position 1 — so an empty neighbour read as a word character and every call-site
# where the symbol starts or ends the line was silently dropped from the packet.
( cd "$cs_repo" && git checkout -- src/lib.py \
    && printf 'edgefn()\n' > src/at_start.py \
    && printf 'y = edgefn\n' > src/at_end.py \
    && printf 'z = edgefnX()\n' > src/not_a_match.py \
    && git add -A && git -c user.email=a@b -c user.name=a commit -qm edges \
    && printf 'def helper():\n    pass\n\ndef edgefn():\n    pass\n' > src/lib.py ) >/dev/null 2>&1
( cd "$cs_repo" && bash "$root/scripts/caller_slices.sh" uncommitted "$cs_out" ) >/dev/null 2>&1
cs_edges=0
grep -q 'src/at_start.py' "$cs_out/callers.md" 2>/dev/null || cs_edges=1
grep -q 'src/at_end.py'   "$cs_out/callers.md" 2>/dev/null || cs_edges=1
[ "$cs_edges" -eq 0 ] \
  && ok "caller_slices: call-sites at the start and end of a line are kept" \
  || bad "caller_slices: an edge-of-line call-site was dropped (index(WORD,\"\") returns 1, not 0)"
grep -q 'edgefnX' "$cs_out/callers.md" 2>/dev/null \
  && bad "caller_slices: matched a substring (edgefnX) — word boundaries are not being enforced" \
  || ok "caller_slices: a longer identifier containing the symbol is not matched"

# A hunk belongs to EVERY symbol matched in it. Owning it by one symbol dropped it whole once that
# owner hit its cap, taking a colder symbol's only call-site with it.
( cd "$cs_repo" && git checkout -- src/lib.py ) >/dev/null 2>&1
(
  cd "$cs_repo" || exit 1
  i=1; while [ $i -le 6 ]; do printf 'alpha()\n' > "src/h$i.py"; i=$((i+1)); done
  printf 'alpha()\nbeta()\n' > src/h6.py
  git add -A && git -c user.email=a@b -c user.name=a commit -qm hot
  printf 'def helper():\n    pass\n\ndef alpha():\n    pass\n\ndef beta():\n    pass\n' > src/lib.py
) >/dev/null 2>&1
( cd "$cs_repo" && bash "$root/scripts/caller_slices.sh" uncommitted "$cs_out" ) >/dev/null 2>&1
grep -q 'beta' "$cs_out/callers.md" 2>/dev/null \
  && ok "caller_slices: a cold symbol sharing a hunk with a hot one is not starved out" \
  || bad "caller_slices: a symbol's only call-site was dropped because a hot symbol owned the hunk"

# THE invariant: every symbol with a call-site contributes at least one hunk containing one of its OWN
# call-sites. Budgets bound how much more a symbol gets, never whether it appears. Two successive
# versions of the cap violated this and a symbol vanished completely — first via the hunk cap, then via
# the line budget after the "fix". The shape that breaks it is a cold symbol buried inside one long
# merged hunk owned mostly by a hot symbol, which is why it needs its own fixture.
(
  cd "$cs_repo" || exit 1
  git checkout -- src/lib.py
  i=1; while [ $i -le 90 ]; do echo 'hotsym()'; i=$((i+1)); done  > src/buried.py
  echo 'coldsym()' >> src/buried.py
  i=1; while [ $i -le 10 ]; do echo 'hotsym()'; i=$((i+1)); done >> src/buried.py
  echo 'coldsym()' > src/coldonly.py
  git add -A && git -c user.email=a@b -c user.name=a commit -qm buried
  printf 'def helper():\n    pass\n\ndef hotsym():\n    pass\n\ndef coldsym():\n    pass\n' > src/lib.py
) >/dev/null 2>&1
( cd "$cs_repo" && bash "$root/scripts/caller_slices.sh" uncommitted "$cs_out" ) >/dev/null 2>&1
grep -q 'coldsym' "$cs_out/callers.md" 2>/dev/null \
  && ok "caller_slices: a symbol buried in a hot merged hunk still contributes a call-site" \
  || bad "caller_slices: a cold symbol contributed NOTHING — budgets must bound how much, not whether"

# The invariant asserted with a CALL-SITE pattern, on a fixture with no escape hatch. The previous
# version grepped for the bare symbol name — which also matches its own `def` line in the declaring
# file — and gave the symbol a private short hunk, so it could not fail. Here the cold symbol exists
# ONLY at the tail of a long merged hunk owned by a hot symbol.
(
  cd "$cs_repo" || exit 1
  git checkout -- src/lib.py
  { i=1; while [ $i -le 200 ]; do echo 'hotpack()'; i=$((i+1)); done; echo 'coldpack()'; } > src/onlyhot.py
  git add -A && git -c user.email=a@b -c user.name=a commit -qm onlyhot
  printf 'def helper():\n    pass\n\ndef hotpack():\n    pass\n\ndef coldpack():\n    pass\n' > src/lib.py
) >/dev/null 2>&1
( cd "$cs_repo" && bash "$root/scripts/caller_slices.sh" uncommitted "$cs_out" ) >/dev/null 2>&1
grep -qE '^src/onlyhot\.py:[0-9]+:coldpack' "$cs_out/callers.md" 2>/dev/null \
  && ok "caller_slices: the floor delivers the symbol's OWN call-site, not just some hunk" \
  || bad "caller_slices: a symbol reachable only past the truncation point contributed no call-site"
# ...and the floor must not disarm the caps while doing it.
cs_body=$(sed -n '/^```$/,$p' "$cs_out/callers.md" 2>/dev/null | sed '1d;$d' | grep -c . | head -1)
[ "${cs_body:-999}" -le 200 ] \
  && ok "caller_slices: honouring the floor keeps the packet bounded ($cs_body lines)" \
  || bad "caller_slices: floor voided the caps — $cs_body lines emitted against a 2x60 ceiling"

# git grep MERGES nearby matches into one hunk, so a hunk count is not a size bound. Without a line
# budget a single hot symbol produced a 400-line hunk while the status still read "<=5 hunks".
(
  cd "$cs_repo" || exit 1
  i=1; while [ $i -le 120 ]; do printf 'packed()\n\n'; i=$((i+1)); done > src/packed.py
  git add -A && git -c user.email=a@b -c user.name=a commit -qm packed
  printf 'def helper():\n    pass\n\ndef packed():\n    pass\n' > src/lib.py
) >/dev/null 2>&1
( cd "$cs_repo" && bash "$root/scripts/caller_slices.sh" uncommitted "$cs_out" ) >/dev/null 2>&1
cs_lines=$(sed -n '/^```$/,$p' "$cs_out/callers.md" 2>/dev/null | grep -c . | head -1)
[ "${cs_lines:-999}" -le 200 ] \
  && ok "caller_slices: a merged hunk is truncated to the per-symbol line budget ($cs_lines lines)" \
  || bad "caller_slices: one merged hunk produced $cs_lines lines — the packet is unbounded"

# git grep is scoped to the CWD subtree; git diff is not. Run from a subdirectory the script found no
# call-sites and hard-stopped the review with EMPTY on a healthy repo.
( cd "$cs_repo" && git checkout -- src/lib.py && mkdir -p sub \
    && printf 'def helper():\n    pass\n\ndef subprobe():\n    pass\n' > src/lib.py \
    && printf 'subprobe()\n' > src/subcall.py ) >/dev/null 2>&1
cs_sub="$( cd "$cs_repo/sub" && bash "$root/scripts/caller_slices.sh" uncommitted "$cs_out" 2>&1 )"
printf '%s' "$cs_sub" | grep -q 'CALLER_SLICES=OK' \
  && ok "caller_slices: runs from a subdirectory (git grep is CWD-scoped, git diff is not)" \
  || bad "caller_slices: from a subdirectory it reported $(printf '%s' "$cs_sub" | grep CALLER_SLICES=) — false hard-stop"

# A diff with no keyword-declared symbols must say so, not write an empty fence.
# `git add -N` so the change actually APPEARS in `git diff`. Creating an untracked file left the diff
# empty, so this asserted the empty-diff path rather than "a real change with no declared symbols".
( cd "$cs_repo" && git checkout -- src/lib.py \
    && printf 'plain prose, no declarations\n' > notes.txt && git add -N notes.txt ) >/dev/null 2>&1
cs_none="$( cd "$cs_repo" && bash "$root/scripts/caller_slices.sh" uncommitted "$cs_out" 2>&1 )"
printf '%s' "$cs_none" | grep -q 'CALLER_SLICES=NO_SYMBOLS' \
  && ok "caller_slices reports NO_SYMBOLS instead of an empty slice set" \
  || bad "caller_slices did not disclose the no-symbol case"
rm -rf "$cs_repo" "$cs_out"
# The symbol list must reach awk through a FILE. BSD awk rejects a -v value containing newlines and then
# emits nothing while still exiting 0 — a silent empty slice set under a status line claiming N symbols.
grep -q 'symfile=' "$root/scripts/caller_slices.sh" && ! grep -qE '\-v +syms=' "$root/scripts/caller_slices.sh" \
  && ok "caller_slices passes symbols by file, not -v (BSD awk rejects newlines in -v)" \
  || bad "caller_slices passes the symbol list via -v — BSD awk will silently emit nothing"

echo "-- panel workspace isolation --"
# A CLI seat pointed at a disposable worktree can read the code under review. Three properties make that
# safe; each has burned us once, so each is asserted.
ws_repo="$(mktemp -d "${TMPDIR:-/tmp}/pfo_wsrepo.XXXXXX")"
ws_dest="$(mktemp -d "${TMPDIR:-/tmp}/pfo_wsdest.XXXXXX")/repo"
(
  cd "$ws_repo" || exit 1
  git init -q .
  printf 'def committed():\n    pass\n' > a.py
  git add -A && git -c user.email=a@b -c user.name=a commit -qm init
  printf 'def committed():\n    pass\n\ndef uncommitted_edit():\n    pass\n' > a.py   # unstaged edit
  printf 'def brand_new():\n    pass\n' > b.py                                        # untracked
  mkdir -p "dir with space"
  printf 'def spaced():\n    pass\n' > "dir with space/un tracked.py"                  # spaces: the
  printf 'def tracked_space():\n    pass\n' > "dir with space/tracked file.py"         # cp->tar rewrite
  git add -A
  mkdir -p .fusion/exports && printf 'PRIOR JUDGED ANSWER\n' > .fusion/exports/old.md  # must NOT leak
  printf 'SECRET-KEY-MATERIAL\n' > ../outside_secret                                     # outside the repo
  ln -s "$(cd .. && pwd)/outside_secret" leak.py                                          # untracked symlink
  ln -s "$(cd .. && pwd)/outside_secret" tracked_leak.py && git add -f tracked_leak.py     # TRACKED symlink
  ln "$(cd .. && pwd)/outside_secret" hard_leak.py 2>/dev/null || true                     # HARDLINK
  git -c user.email=a@b -c user.name=a commit -qm links
) >/dev/null 2>&1
( . "$root/scripts/gemini_backend.sh"; fusion_panel_workspace "$ws_repo" "$ws_dest" ) >/dev/null 2>&1
ws_rc=$?
if [ "$ws_rc" -eq 0 ] && [ -d "$ws_dest" ]; then
  ok "fusion_panel_workspace: builds a disposable worktree"
  grep -q 'uncommitted_edit' "$ws_dest/a.py" 2>/dev/null \
    && ok "fusion_panel_workspace: uncommitted changes are present (seat reviews what the packet describes)" \
    || bad "fusion_panel_workspace: workspace is at HEAD — the seat would review pre-edit code"
  [ -f "$ws_dest/b.py" ] \
    && ok "fusion_panel_workspace: untracked source files are present" \
    || bad "fusion_panel_workspace: untracked file missing — a new file under review would be invisible"
  # The per-file cp loop became one `tar --null -T`; a filename with a space is exactly what that rewrite
  # can drop, and the fixture had none.
  [ -f "$ws_dest/dir with space/un tracked.py" ] \
    && ok "fusion_panel_workspace: untracked paths containing spaces survive the batched copy" \
    || bad "fusion_panel_workspace: an untracked path with a space was lost by the tar copy"
  # THE blindness leak: .fusion/exports holds PRIOR judged answers. A seat that reads one is no longer
  # independent, and panel-prompt.md requires blindness be structural, not hoped-for.
  [ -e "$ws_dest/.fusion" ] \
    && bad "panel workspace: .fusion leaked into the seat workspace — prior judgments readable" \
    || ok "panel workspace: .fusion is absent"
  # ...and absence is not enough: a git WORKTREE's .git is a file pointing at the real repo, so one
  # `git rev-parse --git-common-dir` walked a seat back to the live checkout and read .fusion/exports
  # and .git/config (remote URLs can carry tokens). The snapshot must resolve only to itself.
  ws_common="$( cd "$ws_dest" && git rev-parse --git-common-dir 2>/dev/null )"
  # -P on both sides: macOS mktemp yields /var/... while pwd resolves to /private/var/..., and a
  # symlink-vs-real mismatch would read as a leak.
  ws_back="$( cd "$ws_dest" && cd "$(dirname "$(git rev-parse --git-common-dir 2>/dev/null)")" 2>/dev/null && pwd -P )"
  ws_self="$( cd "$ws_dest" && pwd -P )"
  if [ "$ws_back" = "$ws_self" ]; then
    ok "panel workspace: no backlink — git resolves to the snapshot itself, not the operator's repo"
  else
    bad "panel workspace: git in the snapshot resolves to '$ws_back' (want '$ws_self') — a seat can walk back to the real repo"
  fi
  ( cd "$ws_dest" && git config --get remote.origin.url ) >/dev/null 2>&1 \
    && bad "panel workspace: the snapshot carries a remote URL (can contain a token)" \
    || ok "panel workspace: snapshot has no remote"
  # Untracked SYMLINKS must be refused: [ -f ] and cp both FOLLOW them, so `key.py -> ~/.ssh/id_rsa`
  # had its CONTENT copied into a directory whose entire purpose is to be handed to an external model.
  [ -e "$ws_dest/leak.py" ] \
    && bad "panel workspace: an untracked symlink was dereferenced into the seat workspace (exfiltration)" \
    || ok "panel workspace: untracked symlinks are refused, not dereferenced"
  # git archive faithfully reproduces TRACKED symlinks, so filtering only the untracked list still handed
  # the seat a read-through to arbitrary host files. Verified before the fix.
  [ -e "$ws_dest/tracked_leak.py" ] \
    && bad "panel workspace: a TRACKED symlink survived into the snapshot (reads outside the repo)" \
    || ok "panel workspace: tracked symlinks are stripped from the snapshot"
  # A HARDLINK is the shape neither `[ -L ]` nor `find -type l` can see, yet its bytes live outside the
  # repo just the same. The predicate tests containment, not link type.
  [ -e "$ws_dest/hard_leak.py" ] \
    && bad "panel workspace: a hardlink to an outside file was copied into the snapshot" \
    || ok "panel workspace: a hardlink to an outside file is refused"
  [ "$(find "$ws_dest" -type l 2>/dev/null | wc -l | tr -d ' ')" = 0 ] \
    && ok "panel workspace: the snapshot contains no symlinks at all" \
    || bad "panel workspace: symlinks remain in the snapshot"
  # The seat needs a usable git: an unborn HEAD made diff/log/show exit 128 for a 26 ms saving.
  if ( cd "$ws_dest" && git diff HEAD >/dev/null 2>&1 && git log --oneline >/dev/null 2>&1 ); then
    ok "panel workspace: the snapshot has a real HEAD (git diff/log work for the seat)"
  else
    bad "panel workspace: unborn HEAD — git diff HEAD / git log fail inside the snapshot"
  fi
  ( . "$root/scripts/gemini_backend.sh"; fusion_panel_workspace_cleanup "$ws_repo" "$ws_dest" ) >/dev/null 2>&1
  [ -e "$ws_dest" ] && bad "fusion_panel_workspace_cleanup left the worktree behind" \
                    || ok "fusion_panel_workspace_cleanup removes the worktree"
else
  bad "fusion_panel_workspace: could not build a workspace (rc=$ws_rc)"
fi
rm -rf "$ws_repo" "$ws_dest"

# Both CLI runners must route through the shared helper — a runner that hardcodes an empty scratch dir
# silently keeps its seat blind while the panel reports PREMIUM.
for r in run_codex.sh run_antigravity.sh; do
  grep -q 'fusion_panel_workspace' "$root/scripts/$r" \
    && ok "$r honors FUSION_PANEL_REPO via the shared workspace helper" \
    || bad "$r does not build a panel workspace — that seat answers from the packet alone"
done
# Code access and an egress channel must never be granted together. codex gets the repo only under
# FUSION_NO_WEB=1 (read-only sandbox, no web tool); agy exposes NO sandbox or network switch at all, so
# it is packet-only unless the operator explicitly accepts the risk.
if grep -q 'FUSION_PANEL_REPO' "$root/scripts/run_codex.sh" && grep -qE 'no_web.*!=.*1|"\$no_web" != "1"' "$root/scripts/run_codex.sh"; then
  ok "run_codex.sh refuses repo access without FUSION_NO_WEB=1"
else
  bad "run_codex.sh would grant repo access alongside a web tool — an exfiltration path"
fi
if grep -q 'FUSION_PANEL_REPO_UNSANDBOXED' "$root/scripts/run_antigravity.sh"; then
  ok "run_antigravity.sh is packet-only unless the operator opts in (agy has no sandbox/network switch)"
else
  bad "run_antigravity.sh grants repo access to a seat with no egress control and no opt-in"
fi

# Directory walks must PRUNE build output, not filter it after descending. `! -path '*/Library/*'` still
# stats every file inside a Unity Library/ (hundreds of thousands) before rejecting them.
cm_prune_dir="$(mktemp -d "${TMPDIR:-/tmp}/pfo_cmprune.XXXXXX")"
mkdir -p "$cm_prune_dir/node_modules/deep" "$cm_prune_dir/src"
printf 'def real():\n    pass\n' > "$cm_prune_dir/src/real.py"
printf 'def vendored():\n    pass\n' > "$cm_prune_dir/node_modules/deep/dep.py"
cm_prune="$(bash "$root/scripts/codemap.sh" "$cm_prune_dir" 2>/dev/null)"
if printf '%s' "$cm_prune" | grep -q 'src/real.py' && ! printf '%s' "$cm_prune" | grep -q 'node_modules'; then
  ok "codemap.sh prunes build/vendor trees instead of descending into them"
else
  bad "codemap.sh walked a pruned directory (or missed real source)"
fi
# A tier mismatch must NOT relabel blocks earlier runs produced at the old fidelity.
if grep -q 'mv "\$cache"/\*\.map "\$cache_root' "$root/scripts/fusion_map.sh"; then
  bad "fusion_map: a tier re-key moves existing cache entries — that relabels another run's fidelity"
else
  ok "fusion_map: a tier re-key only redirects future writes, leaving existing entries labelled correctly"
fi
grep -q '\-prune' "$root/scripts/codemap.sh" \
  && ok "codemap.sh directory walk uses -prune" \
  || bad "codemap.sh uses '! -path' — it descends into build trees before rejecting each file"
rm -rf "$cm_prune_dir"

echo "-- panelist timeout layering --"
# agy's own --print-timeout is the graceful limit; fusion_run_with_timeout is the backstop. The graceful
# one must be SHORTER, and both must move with the ONE documented knob. They were independent: a
# hardcoded 300s inner vs a 600s outer meant FUSION_PANEL_TIMEOUT had no effect on this seat at all,
# while codex got twice the budget. Measured seat latencies were 204/240/304s against that 300s cap.
tl_dir="$(mktemp -d "${TMPDIR:-/tmp}/pfo_tl.XXXXXX")"
printf '#!/usr/bin/env bash\nprintf "%%0.sX" {1..300}\n' > "$tl_dir/agy"; chmod +x "$tl_dir/agy"
printf 'probe\n' > "$tl_dir/p.md"
tl() { PATH="$tl_dir:$PATH" env "$@" bash "$root/scripts/run_antigravity.sh" "$tl_dir/p.md" "$tl_dir/o.md" 2>&1 \
         | grep -oE 'PRINT_TIMEOUT=[^ ]*' | head -1; }
tl_def="$(tl FUSION_PANEL_TIMEOUT=600)"
tl_big="$(tl FUSION_PANEL_TIMEOUT=1200)"
tl_ovr="$(tl FUSION_ANTIGRAVITY_PRINT_TIMEOUT=42s)"
[ "$tl_def" = "PRINT_TIMEOUT=570s" ] \
  && ok "run_antigravity: graceful timeout is derived from FUSION_PANEL_TIMEOUT with headroom" \
  || bad "run_antigravity: graceful timeout is $tl_def, not derived from the documented knob"
[ "$tl_big" = "PRINT_TIMEOUT=1170s" ] \
  && ok "run_antigravity: raising FUSION_PANEL_TIMEOUT actually raises this seat's limit" \
  || bad "run_antigravity: FUSION_PANEL_TIMEOUT=1200 gave $tl_big — the knob does not move this seat"
[ "$tl_ovr" = "PRINT_TIMEOUT=42s" ] \
  && ok "run_antigravity: FUSION_ANTIGRAVITY_PRINT_TIMEOUT still overrides explicitly" \
  || bad "run_antigravity: explicit print-timeout override ignored ($tl_ovr)"
rm -rf "$tl_dir"

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
  # Wide panel: premium_wide must realize PREMIUM with TWO Claude panelists (self-consistency seat).
  PATH="$rp_tmp:/usr/bin:/bin" "$sh_bin" "$root/scripts/run_panel.sh" --mode premium_wide "$rp_prompt" "$rp_out" >/dev/null 2>&1
  rp_rc=$?
  if [ "$rp_rc" -eq 0 ] && grep -q '^REALIZED_PANEL_STATE=PREMIUM' "$rp_out/manifest.txt" 2>/dev/null && \
     grep -q '^CLAUDE_PANELISTS=2' "$rp_out/manifest.txt" 2>/dev/null; then
    ok "run_panel premium_wide -> PREMIUM with CLAUDE_PANELISTS=2 (wide round)"
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
  if [ "$rp_rc" -eq 13 ] && grep -q '^REALIZED_PANEL_STATE=DEGRADED_CLAUDE_GEMINI' "$rp_out/manifest.txt" 2>/dev/null; then
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
  if [ "$rp_rc" -eq 13 ] && grep -q '^REALIZED_PANEL_STATE=DEGRADED_CLAUDE_GEMINI' "$rp_out/manifest.txt" 2>/dev/null; then
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
  # Shim parity: healthy fakes → exit 0, v2 realized-state PREMIUM + CLAUDE_PANELISTS=1.
  PATH="$sh_tmp:/usr/bin:/bin" "$sh_bin" "$root/scripts/run_triple_fusion.sh" "$sh_prompt" "$sh_out" >/dev/null 2>&1
  sh_rc=$?
  if [ "$sh_rc" -eq 0 ] && grep -q '^REALIZED_PANEL_STATE=PREMIUM' "$sh_out/manifest.txt" 2>/dev/null && \
     grep -q '^CLAUDE_PANELISTS=1' "$sh_out/manifest.txt" 2>/dev/null; then
    ok "run_triple_fusion shim -> exit 0, REALIZED_PANEL_STATE=PREMIUM, CLAUDE_PANELISTS=1"
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
  # One CLI present (codex only) + override → DEGRADED_CLAUDE_GPT style state + DEGRADED=1.
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
# 3. Retired-model guard: previous panelist labels must not creep back via copy-paste.
#    (Patterns are spelled so this file's own source never matches itself.)
if grep -rqiE "gpt-?5[.]5" "$root" --exclude-dir=.git --exclude-dir=.fusion --exclude-dir=__pycache__ 2>/dev/null; then
  bad "retired GPT panelist label found — finish the rename: $(grep -rliE "gpt-?5[.]5" "$root" --exclude-dir=.git --exclude-dir=.fusion 2>/dev/null | head -3 | tr '\n' ' ')"
else
  ok "no retired GPT panelist labels remain"
fi
#    Claude seat version slug: build the pattern without embedding the banned token as a contiguous
#    substring in this file (so the tree-wide 'op'+'us' grep stays clean, and so the guard never
#    self-matches). Adjacent single-quoted fragments concatenate at runtime.
_retired_claude_seat="$(printf '%s4[.]8' 'op''us')"
if grep -rqiE "$_retired_claude_seat" "$root" --exclude-dir=.git --exclude-dir=.fusion --exclude-dir=__pycache__ 2>/dev/null; then
  bad "retired Claude seat version label found — finish the rename: $(grep -rliE "$_retired_claude_seat" "$root" --exclude-dir=.git --exclude-dir=.fusion 2>/dev/null | head -3 | tr '\n' ' ')"
else
  ok "no retired Claude seat version labels remain"
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
# 4. Routing-table row parity: SKILL.md is the source of truth; the synced copies
#    (fusion-remind, README "What ships") must keep the same row count.
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
r_readme="$(count_rows "$root/README.md" "Situation")"
if [ "$r_skill" -gt 0 ] && [ "$r_skill" = "$r_remind" ] && [ "$r_skill" = "$r_readme" ]; then
  ok "routing-table row parity across SKILL/remind/README ($r_skill rows)"
else
  bad "routing-table drift: SKILL=$r_skill remind=$r_remind README=$r_readme"
fi

# A badge that states a number is a claim, and a stale claim on the front page is the same class of lie
# as a run reporting a panel it did not have. This has to run LAST: the total is only settled here, and
# the badge counts itself, so the target is the total including this assertion.
# head -1: the value appears twice in the SVG (aria-label and the <text>), and two lines make the
# numeric comparison below error out rather than compare.
_badge_n="$(grep -oE '[0-9]+ PASSING' "$root/assets/readme/badges/badge-smoke.svg" 2>/dev/null | grep -oE '^[0-9]+' | head -1)"
if [ -n "$_badge_n" ]; then
  if [ "$_badge_n" -eq "$(( pass + fail + 1 ))" ]; then
    ok "README smoke badge ($_badge_n) matches the suite's assertion count"
  else
    bad "README smoke badge says $_badge_n, suite has $(( pass + fail + 1 )) — rerun scripts/charts/gen_readme_badges.js"
  fi
fi

echo
echo "== result: $pass passed, $fail failed =="
[ "$fail" -eq 0 ] || exit 1
echo "SMOKE OK"
