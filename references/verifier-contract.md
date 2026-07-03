# Verifier contract

Verification is a first-class v2 step. More model output is not a substitute for a concrete check.

## Verifier Types

- Deterministic verifier: tests, lint, typecheck, repro, benchmark, grep, schema validation.
- Evidence verifier: checks `file:line`, primary sources, assumptions, and omitted constraints.
- Model verifier: finds holes only; it does not rewrite the full answer.

## Output Shape

```json
{
  "verdict": "pass | fail | uncertain",
  "blocking_issues": [],
  "non_blocking_issues": [],
  "evidence_checked": [],
  "what_would_settle_uncertainty": []
}
```

## Rule

Early stop requires a passing deterministic verifier when the task is deterministically verifiable. If no
deterministic verifier exists, say that plainly and ground the answer in inspected evidence.
