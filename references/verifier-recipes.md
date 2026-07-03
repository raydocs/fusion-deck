# Verifier recipes

Use `scripts/detect_verifiers.sh` to discover likely checks.

| Project signal | Candidate verifier |
| --- | --- |
| `package.json` scripts | `npm test`, `npm run lint`, `npm run typecheck` |
| `pyproject.toml`, `pytest.ini`, `tests/` | `pytest -q`, `ruff check .`, `mypy .` |
| `Cargo.toml` | `cargo test`, `cargo clippy -- -D warnings` |
| `go.mod` | `go test ./...` |
| `Makefile` | `make test`, `make lint` |

Use `scripts/run_verifier.sh --command '<cmd>'` to run the chosen check and capture a report.
