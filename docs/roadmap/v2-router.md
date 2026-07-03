# fusion-deck v2 router roadmap

v2 has two goals:

- Balanced mode: reduce wasted calls while preserving quality.
- Max-quality mode: raise the ceiling with staged probes and verification.

The MVP is:

1. `/fusion-auto` rule router.
2. `.fusion/runs` local ledger.
3. Intentional panel modes (`opus_gpt_pair`, `opus_gemini_pair`, `premium_triple`).
4. Verifier-first early stop discipline.

Later phases:

1. richer eval harness;
2. feedback labels;
3. policy report;
4. small router learner that predicts workflow only.
