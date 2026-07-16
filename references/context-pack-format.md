# Context Pack format

A Context Pack is a single curated file that another agent (or model) consumes to do a task. The thesis:
**curation is the bottleneck.** Don't dump the repo; assemble the right files at the right density, in a
fixed order, under an explicit token budget.

By default this is **prompt-driven** — `/fusion-context` runs the token-estimate recipe and emits the
file. An **optional** agentic `--discover` mode (evidence-gated; see `references/context-discovery.md`)
proposes a reviewable selection manifest instead — a thin, lint-checked helper, not a mini-RepoPrompt.

## Fixed section order

The **fixed pack** is these five sections (file_map → … → user_instructions), in this exact order —
consumers rely on the layout (it matches RepoPrompt CE's `defaultSectionOrder`). A leading
`user_instructions` is an OPTIONAL preface above the five, not part of them:

```
# Context Pack: <slug>

## user_instructions            (OPTIONAL preface — primacy hedge; ABOVE the fixed five, not one of them)
## file_map                     (the project tree / relevant subtree)
## file_contents                (per-file blocks, mixed density tiers)
## git_diff                     (relevant uncommitted/branch diff, if any)
## meta_prompts                 (notes, conventions, gotchas the consumer needs)
## user_instructions            (the authoritative task statement — last)
```

## Per-file block format

```
File: path/to/file.py
```py
<full contents, a line slice, or signatures>
```
```

- **Full content** — true edit targets only.
- **Line slices** — large, partially relevant files: only the relevant ranges, each labeled before its
  fence: `(lines 40-90: the auth-retry path)`. Line numbers **drift** once a file is edited downstream, so
  if a pack will be re-opened after edits, anchor the slice to content, not just numbers: note a short
  unique anchor string from the slice's first line (e.g. `(lines 40-90 @ "func retry(" : the auth-retry
  path)`). On re-build, re-find the anchor and re-slice around it; if the anchor is gone, the slice is
  stale — regenerate it (or downgrade the file to codemap) rather than pasting now-wrong line ranges.
- **Codemap** (signatures only) — peripheral orientation files: `Imports:` bullets + class/function/type
  signatures, **no bodies**. Generate via `scripts/codemap.sh` (tree-sitter → ctags → grep; discloses
  `CODEMAP_STATE` — see `references/codemap.md`). Zero-dependency floor:
  `grep -nE '^(import |from |class |def |func |type |interface |export )' path/to/file`.
- **Tree-only** — the path appears in `file_map`; no content block.

In `file_map`, mark any path that also has a **codemap block** in `file_contents` with a trailing ` +`
and add one legend line (`(+ denotes code-map available)`), matching RepoPrompt CE's tree annotation — so
a model reading the pack knows which files it can see signatures for without scanning the whole pack:

```
src/
  auth.py +        (codemap below)
  billing.py       (full content below)
  util/log.py      (tree-only)
(+ denotes code-map available)
```

## Token budget (enforced)

Pick a budget by consumer: **paste** ≈24–32k · **handoff** ≈60k · **agent working** ≈120–160k tokens.
Estimate with `ceil(utf8_bytes / 4 * 1.05)` — the bash recipe lives in `/fusion-context` Step 3 (invocation
site); no real tokenizer. Sum the selection. If over budget, in this order: **prune the least-relevant
files → slice large files → downgrade full→codemap** until it fits. Bias to **inclusion** when selecting
(keep related files; prune only the clearly-unrelated), but to **concision** in prose.

### Deterministic middle-truncate
If one file alone busts the budget, keep equal head + tail and drop the middle on a line boundary with a
`[content truncated]` marker (idempotent; still contributes signal without blowing the budget).

### Budget ledger (optional, in `meta_prompts`)
When a pack is near or over budget, show **what ate the budget** instead of just asserting it fit — a few
lines in `meta_prompts` make the curation auditable and the next prune obvious:

```
Budget: 60000 (handoff) · estimated 57.8k used
By tier:  full 6 files (41k) · slice 3 (9k) · codemap 5 (7.8k) · tree 12 (—)
Heaviest: src/engine.py 18k (full) · src/api.py 9k (full)
Decisions: downgraded src/legacy.py full→codemap (-14k); pruned vendor/* (unrelated)
```

This is RepoPrompt CE's component-breakdown idea (it accounts tokens per section/file) scaled to a skill:
the cheap `bytes/4` estimate per file, summed by tier, plus the prune/downgrade decisions you made. Skip it
for small packs comfortably under budget; include it whenever you had to prune to fit, so an over-budget
result reads as an explained trade-off, not a silent truncation.

## Un-opinionated discovery
The pack gathers **what exists** (files, key symbols, relationships) and must **not** propose a solution —
keep it separate from "what to do" so it doesn't anchor the consumer.

## Safety
Before emitting, scan for secrets and drop/redact them — see `references/safety.md`. Never include `.env`,
API keys, tokens, credentials, or private absolute paths in a pack. Also honor a repo-local
**`.fusionignore`** (gitignore-style, `!` force-includes): drop any matched file from the pack — this
applies to **both** the mechanical builder and the `--discover` path (where it's the linter's S012 gate).

Persist the pack to a real file (default `docs/context-packs/<slug>.md`) so it's inspectable and
re-openable by path. See `examples/context-pack.example.md`.
