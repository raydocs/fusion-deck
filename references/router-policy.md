# Router policy - fusion-deck v2

The router chooses **how to spend model calls**, not what answer to give. It is deliberately explainable:
the first implementation is rules plus thresholds, not a trained model.

## Inputs

- `task_type`: answer, code_review, bug_investigation, implementation, architecture, optimization,
  context_or_handoff.
- `risk`: low, medium, high. High-risk signals include security, auth, money, migration, data loss,
  production, privacy, and compliance.
- `context_need`: none, small_packet, repo_packet, discovery_gate.
- `verifiability`: none, weak, high.
- `ambiguity`: clear, underspecified, conflicting.
- `budget`: fast, balanced, max.

## Workflows

| Situation | Workflow |
| --- | --- |
| Simple explanation / low-risk question | `single_model` |
| Ordinary implementation with tests | `single_worker_verified` |
| Code review / diff review | `pair_review_then_verify`; escalate on conflict or failed verifier |
| Architecture / hard trade-off | `pair_blind_panel`; high risk escalates to triple |
| Bug root cause | `evidence_first_investigate`; panel only if competing hypotheses survive |
| Optimization | `measure_change_remeasure`; panel stop/continue decisions |
| Security / auth / money / migration / data-loss risk | `full_blind_panel` or `ultra_two_round_panel` |
| User asks maximum quality | `ultra_two_round_panel` |
| Missing context | context pack or discovery gate first |

## Escalation

Escalate when a deterministic verifier fails, two panelists disagree on a blocking claim, judge confidence
is low, the task is high-risk, there are unsupported claims, or the user asks for maximum quality.

## Early Stop

Early stop is allowed only when the task is low/medium risk, verification passed or evidence is grounded,
no blocking contradiction remains, and the final answer states what is verified.
