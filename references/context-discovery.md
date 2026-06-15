# Context discovery — `/fusion-context --discover`

`--discover` is an **OPTIONAL** front-end to `/fusion-context`. The default `/fusion-context` stays
**mechanical**: you (the model) walk the repo, slot files into the fixed pack at the right density, and
emit it (`context-pack-format.md`). `--discover` adds one step *before* that: a fast subagent explores the
repo and proposes a **selection manifest** — a `.fusion/selection.json` that names exactly which files go
into the pack, at what density, **and why** — which the mechanical builder then consumes.

The point is the **evidence gate**. Curation is the bottleneck; a discovery pass that pulls in files on a
hunch just launders hallucination into the pack. So every proposed file must carry *evidence it was
actually found* — a grep match, an import edge, a git-diff hunk, a test reference. **A file with no
evidence is DROPPED.** If discovery yields nothing usable, you **degrade to the mechanical pack** — loudly,
never silently — and say so in the pack's `meta_prompts`.

`--discover` is opt-in for a reason: it spends a subagent and adds a verification step. Reach for it on a
large or unfamiliar repo where the right files aren't obvious; skip it when you already know the targets —
the mechanical default is faster and just as honest.

**Clarify gate (before spending the subagent).** If the *task itself* is ambiguous enough that discovery
couldn't tell relevant files from irrelevant ones — a load-bearing ambiguity — surface **one specific,
evidence-grounded question** with 2–4 concrete options and **halt** rather than launching a discovery pass
that curates toward a guess. A discovery run aimed at the wrong intent just launders that guess into the
pack. Ask only when it's load-bearing; otherwise state the assumption and proceed.

## Step 1 — Explore (the subagent)

Dispatch ONE scoped Explore/general-purpose subagent (`Agent`/`Task` tool). Its brief: given the task,
find the files that matter and **record the evidence for each**. It does not edit anything and does not
spawn its own subagents (one level of fan-out — see `orchestration-rubric.md`). Steer it toward concrete
discovery moves, each of which *is* an evidence kind:

- **grep** — a symbol, error string, route, or config key the task names → `"grep:<match>"`.
- **import** — a file that imports/is-imported-by a known target (the dependency edge) → `"import:<path>"`.
- **diff** — a file touched by the relevant uncommitted or branch diff → `"diff"`.
- **test** — a test that exercises the behavior under change → `"test:<name>"`.

It returns the manifest below — both what it **selected** and what it **rejected** (the false hits it
chased and dropped). The rejected list is not noise; it is the audit trail that makes the selection
reviewable.

## Step 2 — Write `.fusion/selection.json`

Persist the manifest to a real file so it's inspectable and re-runnable by path. Use **repo-relative
paths** — never private absolute paths (`safety.md`).

### Manifest schema

```json
{
  "task": "<non-empty: the task the pack serves>",
  "budget_tokens": 60000,
  "selected": [
    {
      "path": "scripts/selection_lint.py",
      "mode": "full",
      "reason": "<non-empty: why THIS file, at THIS density>",
      "evidence": ["grep:def list_rules", "test:selection.example.json passes"]
    },
    {
      "path": "references/context-discovery.md",
      "mode": "slice",
      "lines": "1-60",
      "reason": "<non-empty>",
      "evidence": ["grep:evidence gate", "diff"]
    }
  ],
  "rejected": [
    { "path": "references/judge-rubric.md", "reason": "false grep hit on 'rules' — about judging, not lint rules" }
  ]
}
```

Field rules (enforced by the linter — `scripts/selection_lint.py` is the source of truth):

- `task` — non-empty string. `budget_tokens` — positive integer (matches the pack budget).
- `selected[]` — non-empty array. Each entry:
  - `path` — required, repo-relative.
  - `mode` — one of `full` | `slice` | `codemap` | `tree` (the pack's density tiers, `context-pack-format.md`).
  - `lines` — `"START-END"`, **required iff `mode == "slice"`**.
  - `reason` — required, non-empty. *Why this file, at this density.*
  - `evidence` — required, non-empty array of non-empty strings. **THE GATE.** Each item is a discovery
    fact: `"grep:<match>"`, `"import:<path>"`, `"diff"`, `"test:<name>"`.
- `rejected[]` — OPTIONAL: `{ "path", "reason" }` for files looked at and dropped. Keep it — it's the
  reviewable record of what discovery *didn't* trust.
- Any `path` matching a secrets deny-pattern (`.env*`, `*.pem`, `*.key`, `id_rsa*`, `credentials*`,
  `secrets*`, `*.p12`, `*.keystore`) is **blocked** (`safety.md`).
- Any `path` excluded by a repo-local **`.fusionignore`** (gitignore-style; a leading `!` force-includes)
  is **dropped — `S012`** — even with valid evidence. This lets a repo declare big vendored/build/generated
  dirs that should never enter a pack, while `!` keeps must-have docs in. The linter finds `.fusionignore`
  by walking up from the manifest to the repo root (a `.git` dir), so one file at the root covers the repo.

## Step 3 — Validate (the gate runs here)

```bash
python3 <skill-root>/scripts/selection_lint.py .fusion/selection.json
```

- **Exit 0** — manifest is valid; an over-budget estimate prints as a `W101` warning (advisory: the
  byte/4 estimate is fuzzy; do not red-light on it). Proceed to build.
- **Exit 1** — a blocking error. The common one is **`S007`: a selected file with no evidence.** That file
  is a hallucinated inclusion — **drop it from `selected` and re-run.** Do not invent evidence to satisfy
  the gate; that is exactly the failure the gate exists to catch (`safety.md` honesty rule). Other blocks:
  `S006` (no reason), `S008`/`S009` (bad mode / slice without `lines`), `S010` (secrets path).

Run `selection_lint.py --list-rules` for the full catalogue. A valid example lives at
`examples/selection.example.json`.

## Step 4 — Build the pack, disclose the provenance

Feed the **validated** `selected[]` into the mechanical builder: each entry's `path` + `mode` (+ `lines`)
maps straight onto a per-file block in `file_contents` at its density tier (`context-pack-format.md`).
Then **disclose** in the pack's `meta_prompts`: that `--discover` ran, how many files it selected vs
rejected, and any file it **dropped** for missing evidence. A discovered pack must read as discovered, and
a degrade must read as a degrade.

## Degrade rule

If the subagent is unavailable, returns nothing usable, or the manifest can't pass the linter after a
fair correction pass — **fall back to the mechanical `/fusion-context`** and say so in `meta_prompts`
(`STATE: discovery skipped — mechanical pack`). The mechanical pack is the floor; it always works. Never
present a degraded discovery as if a clean evidence-backed selection ran.
