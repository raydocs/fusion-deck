# Optimize scoreboard — format + loop discipline

The scoreboard is what keeps `/fusion-optimize` honest. Optimization is the easiest place to fool yourself:
a change *feels* faster, the panel *sounds* confident, and nobody measured. The discipline below makes every
claim trace back to a number you actually recorded.

## The cardinal rule — no baseline, no optimization claim

You may not say "faster", "smaller", "cheaper", or "improved" without a **recorded baseline** and a
**post-change measurement of the same metric by the same probe.** A change with no before/after pair is not an
optimization — it's a guess. If you can't measure it, you can't claim it; say so plainly and stop. This mirrors
the skill's cardinal rule for panels (`degraded-mode.md`): never fake a capability you didn't actually run.

## Step 1 — define ONE metric, ONE probe, ONE stop criterion (before any change)

Pick a **single** metric. One. Not "latency and memory and bundle size" — those are three runs and three
scoreboards. Multiple goals dilute attribution and let you cherry-pick whichever moved.

Write down, in this order, before touching code:

- **Metric** — the one number, with its unit (`p95 request latency, ms`; `wall-clock, s`; `RSS peak, MB`;
  `bundle gzip, KB`). Lower-is-better or higher-is-better — state it.
- **Probe** — the *exact* command that emits the number, copy-pasteable, deterministic inputs, fixed N. Same
  machine, same load, same data every run. A probe you can't paste is not a probe. It must also be a
  **discriminating** measurement, not an arbitrary-sleep or a no-crash check (see
  `references/probe-quality.md`); the delta it reports must clear the baseline noise floor to count.
- **Stop criterion** — the target that ends the loop (`p95 ≤ 200ms`, or `≥ 30% under baseline`), AND the hard
  iteration cap (below). Define "done" before you start so you don't optimize forever chasing noise.

If any of the three is fuzzy, you are not ready to optimize. Tighten it first.

## Step 2 — establish the baseline (run the probe 3–5×, record variance)

Run the probe **3–5 times** and record **every** value, not just the best or the mean. One run is not a
baseline — it's a sample of one, and you'll mistake noise for signal all loop long.

- Record min / median / max (or mean ± spread). The **spread is the noise floor** — the bar every later change
  must clear to count.
- If the baseline is wildly unstable (max > ~2× min), the probe or the environment is too noisy to optimize
  against. Fix the harness — pin inputs, quiet the machine, increase N — before continuing. A noisy probe makes
  every delta a coin flip.
- The baseline row is iteration `0`, change `baseline`. It is the first append. Nothing is "vs baseline" until
  it exists.

## Step 3 — instrument behind a gate, never in the hot path

Measurement must not perturb what it measures, and must not ship.

- Put timers / counters / allocators behind a **debug or test gate** (env flag, build tag, test-only harness).
- **NEVER** instrument inside the measured hot path (the timing call becomes part of the time) and **NEVER**
  leave instrumentation in production code. Prefer measuring from *outside* the unit — wrap the probe, not the
  function.
- If the only way to get the number is to perturb the hot path, say so and mark the metric **approximate** —
  don't pretend it's clean.

## Step 4 — one attributed change per iteration

Each iteration changes **exactly one thing** and gets **exactly one row**. Two changes in one row and you can
no longer attribute the delta — you've destroyed the experiment. If a change is really two ideas, that's two
iterations and two rows. The whole value of the scoreboard is that every number has one named cause.

After the change: re-run the **same probe, same N**, append the row, compute delta vs baseline.

## Step 5 — keep only what beats the noise

Compare the delta against the baseline **spread**, not against a single baseline run.

- Delta **inside** the noise floor → **revert.** It did not do anything you can prove; carrying it is just risk
  with no evidence. "Looks a bit faster" is not a measurement.
- Delta **clears** the noise floor in the right direction → **keep**, and the new measurement becomes the
  reference the *next* iteration must beat.
- A change that regresses the metric, or breaks correctness, is reverted regardless of how clever it is.

Reverted is a first-class, honest outcome — a recorded revert is signal (this avenue is dead), not failure.

## The scoreboard — an append-only table

One markdown table. **Append-only**: never edit or delete a prior row. A rewritten history is a lie about what
you tried; the dead ends are half the value. Columns, exactly:

| iteration | change | metric (samples) | delta vs baseline | decision |
|-----------|--------|------------------|-------------------|----------|

- **iteration** — `0` for baseline, then `1, 2, …`.
- **change** — the single attributed change, one per row. `baseline` for row 0.
- **metric (samples)** — the recorded values + summary, e.g. `181/184/190 → med 184`. Show the samples, not
  just the median, so the noise is visible.
- **delta vs baseline** — signed, against the baseline median, e.g. `-29%` / `+4ms (noise)`.
- **decision** — `kept` or `reverted` (or `baseline` for row 0). Every non-baseline row resolves to one.

## Step 6 — the panel is consulted ONLY at the decision point

`/fusion-optimize` does not fan out every iteration — that burns the panel on routine execution. The panel is
consulted **only at a decision point**: continue / stop / try-next, or when the loop stalls (a few iterations
with nothing beating noise) and you need the next hypothesis.

When you do consult it, pass it **the scoreboard + the diff** — the structured evidence and the change that
produced it. **NEVER** pass raw logs, full profiler dumps, or the whole repo; that's the curation failure
`context-pack-format.md` exists to prevent, and it drowns the signal the panel needs. The scoreboard *is* the
context pack for an optimization decision.

## Hard iteration cap (default 5)

Stop at the cap even if the stop criterion isn't met. Also stop early when: the stop criterion is met; several
iterations in a row fail to beat noise (diminishing returns — you're polishing noise); a change would trade
correctness for speed; or the probe/environment proves too unstable to measure against. Looping without
measurable progress is the signal to stop and surface, not to keep grinding — same escape-hatch instinct as
`orchestration-rubric.md`.

## Worked example

Metric: **p95 request latency (ms), lower better.** Probe: `bash bench.sh --n 500 --warmup 50` (fixed seed,
quiet box). Stop: `p95 ≤ 150ms` or `≥ 25%` under baseline; cap 5.

| iteration | change | metric (samples) | delta vs baseline | decision |
|-----------|--------|------------------|-------------------|----------|
| 0 | baseline | 203/207/211/205 → med 206 (spread ±5, ~2.5%) | — | baseline |
| 1 | cache compiled regex at module load | 178/181/184 → med 181 | -12% | kept |
| 2 | swap list scan for dict lookup in `route()` | 142/145/149 → med 145 | -30% | kept |
| 3 | add 64-entry LRU on `render()` | 143/146/144 → med 144 | -1% (within ±2.5% noise) | reverted |
| 4 | batch DB round-trips in `load_user()` | 121/124/127 → med 124 | -40% | kept |

Read it back: baseline noise floor is ~2.5%, so iteration 3's -1% is inside noise → reverted (correctly — the
LRU bought nothing provable and added a cache to maintain). Iteration 4 hits 124ms, clearing both stop
criteria (≤150ms AND ≥25% under 206), so the loop stops at 4 of 5 with an honest, attributed trail: three kept
changes, one recorded dead end, every number traceable to one cause.

## Disclosure

If you could not establish a clean baseline, or had to perturb the hot path to measure, or the environment was
too noisy to trust — **say so in the rollup** and label the affected claims `approximate` or `unverified`. A
loud, honest "couldn't measure this cleanly" beats a confident number you can't stand behind. That's the
skill's whole posture: degrade gracefully and loudly, never fake the capability.
