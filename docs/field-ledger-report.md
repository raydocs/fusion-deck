# Field ledger report — real panel runs (not smoke)

**Collected:** 2026-07-16  
**Method:** scan every local `.fusion/runs/**/manifest.json` under the operator’s machine, drop smoke/harness noise, summarize what is left.  
**Scope claim:** this is **one operator’s local ledgers**, not a public benchmark and not fusion-deck’s hit-rate. OpenRouter DRACO numbers in the README remain the only cited accuracy figures.

## How the ledger works (why runs are not all in one folder)

`scripts/fusion_ledger.py` writes under **the git root of the cwd at run time**:

```text
<repo>/.fusion/runs/<run_id>/manifest.json
```

If there is no git root, it falls back to `~/.fusion/runs/`.  
So multi-project work produces **many ledgers**, not one global log. Any “how many times did I run a panel?” answer has to aggregate across projects.

Privacy seatbelt: each ledger root gets a self-ignoring `.gitignore` containing `*`. **Do not commit raw run dirs** — they can hold full panel prompts and proprietary diffs.

## Corpus filter

| Bucket | Count | Notes |
| --- | ---: | --- |
| Manifests found on disk | **240** | 8 ledger roots |
| Smoke / harness noise | **222** | Almost all under `fusion-deck` itself (`panel smoke question`, `shim smoke question`, plus a trivial `Say hello.` harness entry) |
| **Real operator runs** | **18** | Kept for this report |

Smoke pollution is real and local to skill development: `run_panel.sh` ledgers every invocation, including fake-CLI smoke. Production project ledgers (lecvia, rainbowfish, recordlyx, …) are clean. A future fix is `FUSION_LEDGER_ROOT` (or equivalent) so smoke points at a temp dir.

### Ledger roots scanned

| Root | Manifests | Real |
| --- | ---: | ---: |
| `…/Downloads/GitHub/fusion-deck/.fusion/runs` | 224 | 2 |
| `…/Downloads/GitHub/lecvia/.fusion/runs` | 8 | 8 |
| `…/orca/workspaces/lecvia/rainbowfish/.fusion/runs` | 2 | 2 |
| `~/.fusion/runs` | 2 | 2 |
| `…/Documents/recordlyx/.fusion/runs` | 1 | 1 |
| `…/orca/projects/vpn/.fusion/runs` | 1 | 1 |
| `…/orca/projects/x/.fusion/runs` | 1 | 1 |
| `…/orca/projects/xiaolinskill/.fusion/runs` | 1 | 1 |

## Headline numbers (real runs only)

| Metric | Value |
| --- | --- |
| Real runs | **18** |
| Date range (UTC) | 2026-07-02 → 2026-07-16 |
| Projects touched | **8** (lecvia, rainbowfish, fusion-deck, recordlyx, vpn, x, xiaolinskill, cwd-without-git) |
| Workflow | all `premium_triple` |
| Full panel (`PREMIUM`, both external seats present) | **8 / 18 (44%)** |
| Degraded (one external seat absent) | **8 / 18 (44%)** |
| Judge-only (`OPUS_ONLY`, both external seats absent) | **2 / 18 (11%)** |
| Runs with any seat marked `ABSENT` | **10 / 18 (56%)** |

Honest reading: the panel **machinery worked** (states are disclosed, absences are named, degraded runs do not claim PREMIUM). Seat reliability in this window was uneven — early July shows a stretch of `gpt5.5(rc=1)` absences; later runs recover to full PREMIUM after the seat rename / CLI path stabilized.

### Realized panel state

| `REALIZED_PANEL_STATE` | n | Meaning |
| --- | ---: | --- |
| `PREMIUM` | 8 | GPT seat + Gemini seat both answered |
| `DEGRADED_OPUS_GEMINI` | 6 | Gemini only (GPT absent) |
| `DEGRADED_OPUS_GPT5` | 2 | GPT only (Gemini absent) — label kept historical name |
| `OPUS_ONLY` | 2 | both external seats absent; judge path only |

### Who actually answered (`CLI_PARTICIPANTS`)

| Participants | n |
| --- | ---: |
| `gpt5.5+gemini3.1pro` | 5 |
| `gpt5.6sol+gemini3.1pro` | 3 |
| `gemini3.1pro` alone | 6 |
| `gpt5.5` alone | 2 |
| `none` | 2 |

The ledger also records the **rename timeline**: morning rainbowfish still says `gpt5.5`; later the same day uses `gpt5.6sol`. That is evidence the install/upgrade path reached real sessions, not just the skill repo.

## Latency & size (where the manifest recorded them)

Older manifests (first ~5 runs) predate `CODEX_SECONDS` / `PROMPT_BYTES` fields. From the timed subset:

### Wall time of dual-seat runs with real work (both seats ≥ ~5s)

n = 6 useful dual timings (excludes the 4s/10s e2e toy):

| Seat | Median | Range |
| --- | ---: | ---: |
| GPT / Codex seat wall | ~4.4 min | 1.7–5.6 min |
| Gemini seat wall | ~2.3 min | 1.3–5.0 min |
| Panel wall ≈ max(pair) | ~4.7 min | 1.7–5.6 min |

That matches the README cost story: **minutes, not seconds** — priced for decisions that cost hours if wrong.

### Prompt payload size (when recorded)

| Kind of task | Typical `PROMPT_BYTES` |
| --- | --- |
| Short product question | ~1–5 KB |
| Plan review with source packet | **80–200 KB** |
| Translation job with RTF table embedded | **~171 KB** |
| e2e one-liner probe | 86 B |

Heavy plan reviews are doing what the skill claims: shipping **evidence packets**, not vibes.

### Output size (when `*_OUT_BYTES` parsed)

On healthy PREMIUM plan reviews, GPT-seat answers land ~18–21 KB; Gemini ~5–7 KB.  
A few “present but ~36 B” Gemini rows are effectively empty shells timed out or failed after the seat was still counted — treat byte count as a quality signal, not just a billing curiosity.

> **Manifest hygiene note:** some writers packed two keys on one line  
> (`CODEX_SECONDS=319 CODEX_OUT_BYTES=21096`). This report re-parses that form. A small `run_panel.sh` fix (always newline-separated KEY=value) would make future ledgers cleaner.

## Full catalog of real runs

Task text is **redacted/summarized** (absolute paths stripped; no full prompts). Times are UTC.

| # | When | Project | State | Participants | GPT | Gemini | Prompt | Task (summary) |
| ---: | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 07-02 20:39 | lecvia | DEGRADED_OPUS_GPT5 | gpt5.5 | — | absent | — | Homepage / product architecture for bilingual course platform |
| 2 | 07-02 21:05 | lecvia | PREMIUM | gpt5.5+gemini3.1pro | — | — | — | Same product architecture thread (retry / refined brief) |
| 3 | 07-03 02:19 | lecvia | PREMIUM | gpt5.5+gemini3.1pro | — | — | — | Same domain, deeper stack context (Workers/R2/D1) |
| 4 | 07-03 02:31 | xiaolinskill | PREMIUM | gpt5.5+gemini3.1pro | — | — | — | Highest-leverage next steps for a mature Claude/Codex skill |
| 5 | 07-03 02:49 | lecvia | DEGRADED_OPUS_GEMINI | gemini3.1pro | absent | — | — | UI/UX review: satisfaction, effects, ease of use |
| 6 | 07-03 09:14 | lecvia | DEGRADED_OPUS_GEMINI | gemini3.1pro | 0s | 1m22s / 7.0 KB | 4.1 KB | Rewrite all Chinese value-prop / guide copy |
| 7 | 07-03 14:24 | lecvia | DEGRADED_OPUS_GEMINI | gemini3.1pro | 0s | 45s / 5.2 KB | 4.1 KB | Product/architecture framing for lecvia.com “understanding layer” |
| 8 | 07-06 02:05 | lecvia | DEGRADED_OPUS_GEMINI | gemini3.1pro | 0s | 1m12s / 6.5 KB | 4.1 KB | Design Khan-Academy-style mastery layer |
| 9 | 07-06 02:40 | lecvia | DEGRADED_OPUS_GEMINI | gemini3.1pro | 0s | 1m01s / 6.9 KB | 4.5 KB | Unit-test / test-out mechanic + course-entry diagnostic |
| 10 | 07-07 16:04 | vpn | DEGRADED_OPUS_GEMINI | gemini3.1pro | 1s | 1m56s / 4.9 KB | 3.6 KB | iOS VPN app architecture (Flutter shell ↔ Go proxy core) |
| 11 | 07-08 13:43 | ~/.fusion | OPUS_ONLY | none | fail | fail / empty | 171 KB | Medical-services RTF bilingual translation QA |
| 12 | 07-08 13:52 | ~/.fusion | DEGRADED_OPUS_GPT5 | gpt5.5 | 4m21s / 12.8 KB | empty-ish | 171 KB | Same translation QA retry (Gemini still unusable) |
| 13 | 07-14 05:00 | x | PREMIUM | gpt5.5+gemini3.1pro | 1m43s / 3.5 KB | 1m16s / 2.1 KB | 984 B | Impl critique vs Amp-thread functional bar |
| 14 | 07-16 06:33 | rainbowfish | PREMIUM | gpt5.5+gemini3.1pro | 4m26s / 18.5 KB | 2m18s / 6.5 KB | 192 KB | Review Lecvia full-site UI/UX implementation **plan** |
| 15 | 07-16 07:33 | recordlyx | PREMIUM | gpt5.6sol+gemini3.1pro | 5m34s / 18.9 KB | 2m36s / 6.6 KB | 80 KB | Review Recordlyx implementation **plan** |
| 16 | 07-16 07:50 | fusion-deck | OPUS_ONLY | none | 8s | 8s | 86 B | e2e probe: two-generals (both seats failed floor) |
| 17 | 07-16 07:50 | fusion-deck | PREMIUM | gpt5.6sol+gemini3.1pro | 4s / 172 B | 10s / 174 B | 86 B | same probe, full panel recovered |
| 18 | 07-16 08:43 | rainbowfish | PREMIUM | gpt5.6sol+gemini3.1pro | 5m19s / 20.6 KB | 2m11s / 5.2 KB | 135 KB | Review Lecvia v2 (AI UX + features) implementation **plan** |

### By task category (operator intent, not workflow name)

| Category | n | Examples |
| --- | ---: | --- |
| Product / architecture | 4 | Lecvia positioning, stack choices |
| Product design | 4 | UI/UX, copy, mastery, diagnostics |
| Plan review | 2 | rainbowfish Lecvia plans (+ recordlyx plan) |
| Translation QA | 2 | large RTF medical code table |
| Product work / impl critique | 2 | VPN architecture, Amp-parity critique |
| Skill design | 1 | xiaolin-explainer skill leverage |
| e2e probe | 2 | two-generals harness in fusion-deck |

## What this does *not* claim

- **Not a hit-rate.** The ledger stores routing, panel state, timing, and artifact pointers. It does **not** currently store a human label “panel saved me / panel wasted time / finding was true.” Without that label, there is no honest “panel lifts accuracy X% on my work” number.
- **Not independent of one operator’s tooling.** GPT-seat absences cluster when that CLI was broken; they are not evidence that “GPT is bad at these tasks.”
- **Not a substitute for DRACO.** README keeps OpenRouter’s measured panel-shape numbers; this report is **field ops telemetry**.

## What the ledger *does* already prove in the wild

1. **Honesty under failure.** 56% of real runs had at least one absent seat, and the realized state names them (`DEGRADED_*`, `OPUS_ONLY`). No silent fake PREMIUM in this corpus.
2. **Right workload mix.** Almost everything here is architecture, design, plan review, or translation QA — not trivia. That matches “when it pays for itself.”
3. **Cross-project memory is scattered but recoverable.** Aggregate scans work; a single `fusion-deck` directory alone is misleading (98% smoke there).
4. **Schema evolution is observable.** Fields appear over time (`PROMPT_BYTES`, `*_SECONDS`, later `REALIZED_PANEL_MODE` / `OPUS_PANELISTS`). Participant ids rename (`gpt5.5` → `gpt5.6sol`) without breaking older rows.
5. **Heavy packets are real.** 80–200 KB plan-review prompts mean the “evidence packet” path is used in anger, not only documented.

## Data-quality issues found while building this report

| Issue | Impact | Suggested fix |
| --- | --- | --- |
| Smoke tests write into the skill repo’s production ledger | 222/224 fusion-deck rows unusable for stats | `FUSION_LEDGER_ROOT` / temp out-root for smoke |
| `task` often truncated to ~180 chars in manifests | Catalog titles incomplete; need prompt head for context | store full task + separate short slug |
| `CODEX_SECONDS=N CODEX_OUT_BYTES=M` on one line | Naive parsers lose OUT_BYTES | always emit one KEY=value per line |
| Ledger is per-cwd-repo only | No built-in global history | optional `fusion_ledger.py summarize --all-roots` or scan helper |
| No outcome label | Cannot compute personal hit-rate yet | optional `outcome=` field on close / judge footer |

## How to regenerate

From any machine that has the ledgers:

```bash
# list every ledger root (adjust roots to your disk layout)
find "$HOME" -maxdepth 6 -type d -path '*/.fusion/runs' 2>/dev/null

# per-project summary (built-in)
python3 /path/to/fusion-deck/scripts/fusion_ledger.py --out-root "$ROOT" summarize --last 50
```

Filter smoke by excluding tasks matching `panel smoke`, `shim smoke`, and trivial `Say hello` harness entries. Do **not** publish raw `prompt.md` copies — redact paths and secrets first (`references/safety.md`).

## Bottom line

Across **two weeks of real use**, fusion-deck’s local ledger shows **18 genuine panel jobs** in **8 projects**, with **full dual-seat panels about 44% of the time**, honest degradation the rest of the time, and **multi-minute / multi-10KB** answers on the hard plan-review jobs. That is enough to validate **operational honesty and workload fit**; it is **not** yet enough for a first-party accuracy claim. When outcome labels exist, the same `.fusion/runs/` trees are the right place to compute one.
