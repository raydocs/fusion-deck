# Contract lint rules — pointer

The lint rules for a Workflow Contract live in **one place: `scripts/lint_contract.py`** (the single
source of truth). Do not memorize or duplicate them here — a prose copy would drift and produce false
confidence. Just run the linter.

```bash
python3 <skill-root>/scripts/lint_contract.py <contract.md>     # lint a contract
python3 <skill-root>/scripts/lint_contract.py --list-rules       # print the rule catalogue
```

Summary of the policy (authoritative version: `--list-rules`):

- **Blocking errors (exit 1):** missing required section; no work items; a work item missing a required
  field; an empty/placeholder required field; an invalid `Status`; any forbidden `/goal` reference;
  **dangerous vague language** (C009 — unbounded permission like "edit anything", infinite-retry like
  "keep trying", or vague success like "until it looks good"; bilingual EN + 中文).
- **Advisory warnings (exit 0):** a finishing criterion that looks unverifiable.

Required sections: Objective · Finishing Criteria · Current State · Work Items · Escape Hatch · Verifier
Plan. Work-item fields: Goal · Done-when · Key files · Dependencies · Size · Status. See
`references/workflow-contract.md` for what each means and `examples/workflow-contract.example.md` for a
passing example.
