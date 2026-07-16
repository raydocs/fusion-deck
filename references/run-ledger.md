# Run ledger - local v2 memory

The run ledger records routing and verification evidence under `.fusion/runs/`. It is private by
default: `fusion_ledger.py` writes a self-ignoring `.gitignore` (containing `*`) into the ledger root on
first use, so it stays out of git in the **user's** repo too — not just in checkouts whose top-level
`.gitignore` happens to cover `.fusion/`.

Use it to answer:

- Which workflow was chosen?
- Which panelists actually participated?
- Did a verifier run?
- Was the run escalated or early-stopped?
- Which workflow patterns are worth keeping? (The panel manifest records per-panelist wall-clock
  seconds and output bytes — `CODEX_SECONDS`/`CODEX_OUT_BYTES`, `GEMINI_SECONDS`/`GEMINI_OUT_BYTES`,
  plus `PROMPT_BYTES` — so cost/latency comparisons are grounded in data, not vibes.)

Basic commands:

```bash
python3 scripts/fusion_ledger.py new --command fusion-auto --workflow pair_blind_panel --task "..."
python3 scripts/fusion_ledger.py show latest
python3 scripts/fusion_ledger.py summarize --last 20
```

The ledger is not a transcript dump. Store compact manifests and artifact paths; do not store secrets.
Before sharing a ledger entry, apply `references/safety.md`.

## Privacy

`.fusion/runs/` is local and private project state. Do not commit it; the self-ignoring `.gitignore`
is a seatbelt, not permission to put secrets there. Note the ledger copies full panel prompts, which
for a review run include the diff/code under review.

- Do not copy secrets into ledger artifacts.
- Do not include private absolute paths in shared exports.
- Redact or drop `.env*`, keys, credentials, tokens, passwords, and bearer strings.
- Store enough evidence to improve routing, not raw chat history.
