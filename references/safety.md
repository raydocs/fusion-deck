# Safety checklist

Short and load-bearing. Apply across every command and script.

## Secrets & private data
- **Never hardcode** API keys, tokens, accounts, or private absolute paths in any file. Model selection is
  via env override (`FUSION_CODEX_MODEL`, `FUSION_ANTIGRAVITY_MODEL`, `FUSION_GEMINI_MODEL` for legacy);
  auth lives in the CLIs themselves.
- **Never leak secrets into a Context Pack or Handoff Capsule.** Before emitting, scan and drop/redact.
  Deny-patterns to exclude: `.env*`, `*.pem`, `*.key`, `id_rsa*`, `credentials*`, `secrets*`,
  `*.p12`/`*.keystore`, and any line matching `(?i)(api[_-]?key|secret|token|password|bearer)\s*[:=]`.
- Don't include private absolute paths (`/Users/<name>/…`, `/home/<name>/…`) in shared artifacts; use
  repo-relative paths.

## Money & external calls
- The triple panel calls paid models — fan out only where it's worth it (`/fusion`, `/fusion-review`; see
  SKILL.md). `scripts/smoke_test.sh` **never** calls a paid model unless `FUSION_LIVE=1`.
- **Private code stays private.** Panelists may web-search for *public* facts (APIs, docs, error strings),
  but must NOT put proprietary/local source into a web query. For a private-code review, instruct
  panelists: "web search for public facts only — do not search with our code."
- Never present a degraded panel as PREMIUM (see `degraded-mode.md`).

## Don't touch what you don't own
- Don't modify the source skills this one draws from, or the user's unrelated uncommitted work.
- The orchestrator never edits product code — only Task subagents do (see `orchestration-rubric.md`).
- Before deleting/overwriting, look at the target; if it contradicts how it was described, surface that
  instead of proceeding.

## Honesty
- Report verification results faithfully: if a check failed or was skipped, say so. Use `[incomplete]`
  with reason/proof/attempted/impact/next-decision rather than faking green. Never hard-code a value just
  to pass a check.
