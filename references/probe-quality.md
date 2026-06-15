# Probe quality — what makes a verification worth trusting

The single source of truth for "is this check discriminating, or is it theater?" Every command that
**verifies** something — `/fusion-orchestrate` (Done-when probes), `/fusion-optimize` (the metric probe),
`/fusion-investigate` (the fact that nails a hypothesis), `/fusion-review` (confirming a finding) — points
here instead of re-prosing the rules, so the discipline can't drift between commands.

A probe is the concrete thing you run (a test, a grep, a focused command) to decide whether a step is
actually done. The failure mode is a probe that **passes whether or not the work was done** — that is the
verification equivalent of faking green (`safety.md` honesty rule). Catching that *before* the next step
builds on a flawed foundation is the whole value of verify-then-dispatch-fresh.

## The discriminating-oracle test

Before trusting a probe, name two things:

1. **The behavior** the step was supposed to produce, and **a plausible way it could be wrong** (the
   defect you're guarding against).
2. **An oracle that separates them** — the probe must **FAIL against the broken / pre-change state and
   PASS against the fixed state.** If you can't describe an input on which it would fail, it does not
   discriminate, and a green result proves nothing.

The cheapest honest version: run the probe **against the known-bad state first** (the pre-change code, the
unpatched branch, a deliberately broken input) and watch it fail, then against the new state and watch it
pass. A probe never observed failing is a probe of unknown power.

## Reject these non-probes

Each of these can pass on broken code, so a green result is not evidence the step is done:

- **Symbol-presence** — "the function/file/flag now exists." Existence is not behavior.
- **No-crash / exit-0 only** — "it ran without erroring." Running is not being correct.
- **Non-nil / non-empty only** — "it returned something." Returning garbage also returns something.
- **Constant-restatement** — the check hard-codes the same value the code emits; it tests nothing (and
  trips the no-test-cheating rule). A change to the bug would not change the check.
- **Report-only** — "the agent said it did it." Self-report is not verification. Never "did you do it?"
- **Arbitrary-sleep** — `sleep N` then check. Timing-dependent and flaky; control time/ordering with a
  gate, clock, or explicit wait condition, not a guessed delay.
- **Omnibus** — one giant check covering five behaviors at once; when it fails you can't tell which broke.
  Prefer one focused probe per claim.

## Choose the lowest faithful layer

Use the narrowest check that still proves the behavior: a single focused unit test over the whole suite, a
`grep`/file read over a full run, a targeted assertion over an end-to-end pass. Broaden only when the
change crosses a shared contract. (This is the skill's "narrowest verification first" instinct.)

## Honest outcomes

If the only available probe is weak (you genuinely can't execute, or can only seam-reason), say so and
mark the result **unverified** — never let "looks plausible" read as "verified to run." For artifacts,
*verified to run* is done; *looks right* is not.
