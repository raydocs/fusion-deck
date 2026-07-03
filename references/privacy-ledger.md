# Ledger privacy

`.fusion/runs/` is local and private project state. It is kept out of git by a self-ignoring
`.gitignore` (`*`) that `fusion_ledger.py` writes into the ledger root on first use — but treat that as
a seatbelt, not permission to put secrets there. Note the ledger copies full panel prompts, which for a
review run include the diff/code under review.

Rules:

- Do not commit `.fusion/runs/`.
- Do not copy secrets into ledger artifacts.
- Do not include private absolute paths in shared exports.
- Redact or drop `.env*`, keys, credentials, tokens, passwords, and bearer strings.
- Store enough evidence to improve routing, not raw chat history.
