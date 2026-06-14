# Workflow Contract — add a `/health` endpoint

> Example output of `/fusion-plan`. This is a Claude Code Workflow Contract — a self-contained file,
> not a Codex goal-mode artifact. It is what `/fusion-orchestrate` executes and what
> `scripts/lint_contract.py` validates.

## Objective

Add a `GET /health` endpoint to the API service that returns `200 {"status":"ok"}` so the load
balancer can health-check the service. (What should become true.)

## Finishing Criteria

- `curl -s localhost:8080/health` returns HTTP 200 with body `{"status":"ok"}`.
- `pytest tests/test_health.py` passes.
- No existing route handler or test regresses (`pytest -q` exit code 0).

## Current State

What is currently true (the ledger — distinct from the Objective above):

- The service has a router in `app/router.py` registering `/users` and `/orders` only.
- There is no `/health` route and no `app/handlers/health.py`.
- `tests/` has no health test. Last validation: `pytest -q` green at HEAD.

## Work Items

### Item 1 — health handler

- Goal: Add a handler returning `{"status":"ok"}` with HTTP 200.
- Done-when: `app/handlers/health.py` defines `health()` returning the documented body; `grep -n "def health" app/handlers/health.py` matches.
- Key files: `app/handlers/health.py` (new), `app/handlers/orders.py` (pattern to mirror).
- Dependencies: none.
- Size: small.
- Status: [todo]

### Item 2 — register the route

- Goal: Register `GET /health` in the router, wired to the Item 1 handler.
- Done-when: `app/router.py` maps `/health` to `health()`; `curl -s localhost:8080/health` returns 200.
- Key files: `app/router.py`.
- Dependencies: Item 1.
- Size: small.
- Status: [todo]

### Item 3 — focused test

- Goal: Add a test asserting the endpoint's status code and body.
- Done-when: `pytest tests/test_health.py` passes and asserts both 200 and the body.
- Key files: `tests/test_health.py` (new).
- Dependencies: Item 2.
- Size: small.
- Status: [todo]

## Escape Hatch

Pause, ask, or mark a work item `[blocked]` / `[incomplete]` (with reason / proof / attempted /
impact / next-decision) if:

- a Done-when probe fails twice for the same item (do not re-dispatch indefinitely);
- the Current State above disagrees with the repo on disk (re-anchor before proceeding);
- the change would require deleting or rewriting work this contract did not create;
- finishing the item needs a scope change not covered by the Objective.

## Verifier Plan

The narrowest concrete probe per item (run after each item, before dispatching the next):

- Item 1: `grep -n "def health" app/handlers/health.py` and read the returned body literal.
- Item 2: `grep -n "/health" app/router.py`; then `pytest tests/test_health.py::test_route -q`.
- Item 3: `pytest tests/test_health.py -q` (must exit 0).
- Final: `pytest -q` (no regressions).

## References

- `app/handlers/orders.py:1-40` — existing handler pattern to mirror.
- `app/router.py:12-30` — where routes are registered.
