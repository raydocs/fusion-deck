# Context Pack: add-health-endpoint

> Example `/fusion-context` output. Sections are in the FIXED order; files mix density tiers; the whole
> pack is kept under a budget. Token estimates use `ceil(bytes/4*1.05)`.

## user_instructions
Add a `GET /health` endpoint returning `200 {"status":"ok"}`. (Repeated at top as a primacy hedge.)

## file_map
```
app/
  router.py          # routes registered here
  handlers/
    orders.py        # handler pattern to mirror
    health.py        # (to be created)
tests/
  test_health.py     # (to be created)
```

## file_contents

File: app/handlers/orders.py   (codemap — orientation only)
```py
Imports: from app.db import session; from app.schema import Order
def list_orders(req) -> Response: ...
def get_order(req, order_id: int) -> Response: ...
```

File: app/router.py   (lines 12-30: where routes are registered — edit target)
```py
ROUTES = [
    ("/users", users.list_users),
    ("/orders", orders.list_orders),
    # new route goes here
]
def dispatch(path, req): ...
```

## git_diff
(none — clean working tree at HEAD)

## meta_prompts
- Handlers return `Response(status, json_body)`; mirror `orders.list_orders`.
- Tests use `pytest` + the `client` fixture in `tests/conftest.py`.

## user_instructions
Add `GET /health` returning HTTP 200 with body `{"status":"ok"}`, wired through `app/router.py`, with a
focused test in `tests/test_health.py`. Estimated pack size: ~0.4k tokens (budget: paste).
