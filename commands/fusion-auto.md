---
description: Route a task through fusion-deck v2: choose the cheapest workflow that should preserve quality, verify, and escalate only when evidence says to.
argument-hint: [task] [--quality=fast|balanced|max]
---

# /fusion-auto

Use the v2 router instead of manually choosing a fusion command. This command does **not** replace
`/fusion`: explicit `/fusion` still means "open the premium panel." `/fusion-auto` first classifies the
task, chooses a workflow, records a run ledger entry, verifies when possible, and escalates only when the
workflow's policy says the cheaper path is not enough.

Load `references/router-policy.md`, `references/panel-modes.md`, `references/run-ledger.md`,
`references/verifier-contract.md`, and `references/verifier-recipes.md`.

## Step 1 - Route

```bash
python3 <skill-root>/scripts/route_task.py --task "$ARGUMENTS"
```

If the user passed `--quality=max`, route with `--quality max`. Record the JSON decision: task type,
risk, recommended workflow, initial panel size, escalation threshold, early-stop eligibility, and reasons.

## Step 2 - Execute The Chosen Workflow

- `single_model`: answer directly; write a ledger entry.
- `single_worker_verified`: implement or answer with one worker, then run a deterministic verifier when
  one is available (`detect_verifiers.sh` / `run_verifier.sh`).
- `pair_review_then_verify`: build the review packet, run an intentional pair via `run_panel.sh`, verify
  high-severity findings against real code, and escalate to triple only on blocking disagreement or failed
  verifier.
- `pair_blind_panel`: run `opus_gpt_pair` or `opus_gemini_pair` via `run_panel.sh` based on context, then
  judge. Escalate to triple on high risk or unresolved contradiction.
- `evidence_first_investigate`: follow `/fusion-investigate`; only panel surviving hypotheses.
- `measure_change_remeasure`: follow `/fusion-optimize`; panel only stop/continue decisions.
- `full_blind_panel`: follow `/fusion`.
- `ultra_two_round_panel`: follow `/fusion-ultra`.

Intentional pair modes are not degraded. They are valid v2 choices. A degraded state only means the
requested mode could not be realized.

## Step 3 - Verify / Early Stop

Early stop only when all are true:

- low or medium risk;
- deterministic verifier passed, or the task is not deterministically verifiable and the answer is
  grounded in inspected evidence;
- no blocking contradiction remains;
- the final answer states what was verified and what remains uncertain.

If any condition fails, escalate according to the router's `escalation_threshold`. **Escalation to a
triple or ultra panel is a cost jump — name it before spending it** (SKILL.md's "suggest, don't silently
run"): tell the user what failed, that the policy says to escalate, and roughly what it costs (a triple
is ~3× tokens, as slow as its slowest panelist); proceed on their go-ahead. Only skip the ask when the
user already opted into max quality this run (`--quality=max` or an explicit "use the full panel").

## Step 4 - Ledger And Present

Every run gets a ledger entry under `.fusion/runs/` using `scripts/fusion_ledger.py`. Present the final
answer first, then the audit trail: chosen workflow, realized panel state/mode, verifier result, run id,
and why escalation did or did not happen.
