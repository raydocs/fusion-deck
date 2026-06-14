# Context Pack format

A Context Pack is a single curated file that another agent (or model) consumes to do a task. The thesis:
**curation is the bottleneck.** Don't dump the repo; assemble the right files at the right density, in a
fixed order, under an explicit token budget.

In v1 this is **prompt-driven with an executable recipe** — you (the model) run the bash below and emit
the file. (A dedicated builder script is roadmap, not v1: it would risk a mini-RepoPrompt.)

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
  fence: `(lines 40-90: the auth-retry path)`.
- **Codemap** (signatures only) — peripheral orientation files: `Imports:` bullets + class/function/type
  signatures, **no bodies**. Get them cheaply, e.g.:
  ```bash
  grep -nE '^(import |from |class |def |func |type |interface |export )' path/to/file
  ```
- **Tree-only** — the path appears in `file_map`; no content block.

## Token budget (enforced)

Pick a budget by consumer: **paste** ≈24–32k · **handoff** ≈60k · **agent working** ≈120–160k tokens.
Estimate with the cheap heuristic `ceil(utf8_bytes / 4 * 1.05)` — no real tokenizer:

```bash
est() { python3 -c "import math,sys; print(math.ceil(int(sys.argv[1])/4*1.05))" "$(wc -c < "$1")"; }
est path/to/file        # tokens for one file
```

Sum the selection. If over budget, in this order: **prune the least-relevant files → slice large files →
downgrade full→codemap** until it fits. Bias to **inclusion** when selecting (keep related files; prune
only the clearly-unrelated), but to **concision** in prose.

### Deterministic middle-truncate
If one file alone busts the budget, keep equal head + tail and drop the middle on a line boundary:

```bash
head -n 120 FILE > part; echo '[content truncated]' >> part; tail -n 120 FILE >> part
```

Idempotent, so the file still contributes signal without blowing the budget.

## Un-opinionated discovery
The pack gathers **what exists** (files, key symbols, relationships) and must **not** propose a solution —
keep it separate from "what to do" so it doesn't anchor the consumer.

## Safety
Before emitting, scan for secrets and drop/redact them — see `references/safety.md`. Never include `.env`,
API keys, tokens, credentials, or private absolute paths in a pack.

Persist the pack to a real file (default `docs/context-packs/<slug>.md`) so it's inspectable and
re-openable by path. See `examples/context-pack.example.md`.
