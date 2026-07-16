# /fusion-review output (example)

> Example Track-B review synthesis. Leads with the findings report; the five-section audit trail follows.
> Microscopic — shows the shape, not real findings. Shape matches Step 3 of `commands/fusion-review.md`:
> ≤5 Must-fix, ≤5 Suggestions, ≤3 Questions (consensus-first), then the five-section audit trail.

**Panel:** `PANEL_STATE=PREMIUM` (`opus4.8-gpt5.6sol-gemini3.1pro`) — Opus 4.8, GPT-5.6 Sol, Gemini 3.1 Pro.

## Must-fix (≤5, consensus-first)

1. **severity: high · `app/auth.py:42`** — token compared with `==`, timing-attack-prone.
   Evidence: flagged independently by GPT-5.6 Sol and Gemini; confirmed by reading the line.
   Fix: use `hmac.compare_digest`.
2. **severity: medium · `app/router.py:18`** — `/health` added but not registered in `ROUTES`.
   Evidence: Opus + GPT-5.6 Sol; verified the route is unreachable.
   Fix: append to `ROUTES`.
3. **severity: medium · `app/db.py:30`** — bare `except:` swallows `KeyboardInterrupt`.
   Evidence: GPT-5.6 Sol called it a bug; Opus called it intentional; adjudicated by reading the line.
   Fix: catch the specific expected exception type, not bare `except:`.

## Suggestions (≤5)

1. **severity: low · `app/handlers/health.py:7`** — dict rebuilt per request.
   Evidence: only Gemini examined the handler hot path; minor.
   Fix: hoist the constant.
2. Missing test for the error branch (Opus unique insight) — add a focused negative-path test.

## Questions (≤3)

1. None of the panelists checked input size limits on the endpoint — worth a follow-up?

## Audit trail

- **Consensus:** Must-fix 1 and 2 (≥2 reviewers, independently) — highest confidence.
- **Contradictions:** GPT-5.6 Sol vs Opus on `app/db.py:30` bare `except:` — adjudicated; GPT-5.6 Sol
  right → Must-fix 3.
- **Partial coverage:** only Gemini examined the handler hot path (Suggestion 1).
- **Unique insights:** Opus noted the missing test for the error branch (Suggestion 2).
- **Blind spots:** none checked input size limits on the endpoint (judge-added; Question 1).
