# Verifier plan — template

A Verifier Plan pairs each work item with the **exact narrowest check** that confirms its Done-when. It is
written **with the plan** (before dispatch) and run by the orchestrator **after** each item, before
dispatching the next. The orchestrator runs the probe itself — it does **not** take the subagent's word.

**Narrowest useful check first.** A single focused test or a grep on the named deliverable beats running
the whole suite. Broaden only when the change crosses shared contracts.

## Fill-in template

```
## Verifier Plan
- Item 1 (<name>): <probe>            # e.g. grep -n "def health" app/handlers/health.py
- Item 2 (<name>): <probe>            # e.g. pytest tests/test_health.py::test_route -q
- Item 3 (<name>): <probe>            # e.g. curl -s localhost:8080/health | grep '"status":"ok"'
- Final: <whole-surface check>        # e.g. pytest -q   (no regressions)
```

## What makes a good probe

A probe must pass the discriminating-oracle test in `references/probe-quality.md` (it must FAIL on the
pre-change state); reject the non-probes listed there.

## On a failed probe
Steer a correction: re-dispatch the item **once** with a tightened brief naming exactly what's missing.
**Second failure → Escape Hatch:** STOP, mark the item `[blocked]`/`[incomplete]`, surface to the user.
Record the exact command and the verbatim decisive line(s) of its output — never a paraphrase — including
failures.
