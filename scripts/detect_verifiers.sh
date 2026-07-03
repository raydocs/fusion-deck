#!/usr/bin/env bash
# detect_verifiers.sh - discover deterministic verifier commands for the current repo.

set -uo pipefail

root="${1:-$(pwd)}"
cd "$root" 2>/dev/null || { echo "VERIFIER_STATE=NO_ROOT"; exit 2; }

names=(); commands=(); reasons=()
add() { names+=("$1"); commands+=("$2"); reasons+=("$3"); }

if [ -f package.json ]; then
  pkg_mgr="npm"
  [ -f pnpm-lock.yaml ] && command -v pnpm >/dev/null 2>&1 && pkg_mgr="pnpm"
  [ -f yarn.lock ] && command -v yarn >/dev/null 2>&1 && pkg_mgr="yarn"
  scripts="$(python3 - <<'PY' 2>/dev/null || true
import json
try:
    data=json.load(open("package.json", encoding="utf-8"))
    for name in ("test","lint","typecheck","check"):
        if name in data.get("scripts", {}):
            print(name)
except Exception:
    pass
PY
)"
  for s in $scripts; do
    case "$s" in
      test) add "js_test" "$pkg_mgr test" "package.json scripts.test" ;;
      lint) add "js_lint" "$pkg_mgr run lint" "package.json scripts.lint" ;;
      typecheck) add "js_typecheck" "$pkg_mgr run typecheck" "package.json scripts.typecheck" ;;
      check) add "js_check" "$pkg_mgr run check" "package.json scripts.check" ;;
    esac
  done
fi

# A bare tests/ dir is NOT evidence of a Python project (it may hold fixtures for anything) —
# require a Python config file, or actual test_*.py files inside tests/.
py_repo=false
if [ -f pyproject.toml ] || [ -f pytest.ini ] || [ -f setup.cfg ] || [ -f setup.py ]; then
  py_repo=true
elif [ -d tests ] && ls tests/test_*.py tests/*_test.py >/dev/null 2>&1; then
  py_repo=true
fi
if $py_repo; then
  command -v pytest >/dev/null 2>&1 && add "pytest" "pytest -q" "python tests detected"
  command -v ruff >/dev/null 2>&1 && add "ruff" "ruff check ." "ruff available"
  command -v mypy >/dev/null 2>&1 && add "mypy" "mypy ." "mypy available"
fi

[ -f Cargo.toml ] && command -v cargo >/dev/null 2>&1 && {
  add "cargo_test" "cargo test" "Cargo.toml"
  add "cargo_clippy" "cargo clippy -- -D warnings" "Cargo.toml"
}
[ -f go.mod ] && command -v go >/dev/null 2>&1 && add "go_test" "go test ./..." "go.mod"
[ -f Makefile ] && grep -qE '^test:' Makefile && add "make_test" "make test" "Makefile test target"
[ -f Makefile ] && grep -qE '^lint:' Makefile && add "make_lint" "make lint" "Makefile lint target"

count="${#names[@]}"
if [ "$count" -eq 0 ]; then
  echo "VERIFIER_STATE=NONE"
  echo "VERIFIER_COUNT=0"
  exit 0
fi

echo "VERIFIER_STATE=FOUND"
echo "VERIFIER_COUNT=$count"
i=1
while [ "$i" -le "$count" ]; do
  idx=$((i - 1))
  echo "VERIFIER_${i}_NAME=${names[$idx]}"
  echo "VERIFIER_${i}_COMMAND=${commands[$idx]}"
  echo "VERIFIER_${i}_REASON=${reasons[$idx]}"
  i=$((i + 1))
done
