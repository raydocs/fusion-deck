---
description: Build a RepoPrompt-style Context Pack — a curated, token-budgeted, fixed-order bundle (file_map, file_contents, git_diff, meta_prompts, user_instructions) for handoff to a subagent or another model.
argument-hint: [the task the pack is for] [budget: paste|handoff|agent]
---

# /fusion-context

Curate context, don't dump it. The bottleneck for downstream work is **context curation**, not model
capability. This command assembles a **Context Pack**: the right files at the right density, in a fixed
section order, under an explicit token budget — a single file another agent (or model) can consume.

Load `references/context-pack-format.md` (the exact format, density tiers, token math) and
`references/safety.md` (never leak secrets into a pack).

## Step 1 — Un-opinionated discovery

Find what's relevant with Grep/Glob/Read. Gather **what exists** — files, key symbols, how they relate —
and **do not** prescribe a solution; the pack must not anchor the consumer. Bias to **inclusion** when
selecting (keep related files; prune only the clearly-unrelated), but to **concision** in any prose.

## Step 2 — Assign a density tier per file

- **Full content** — true edit targets only.
- **Line slices** — large, partially-relevant files: only the relevant ranges, each labeled
  `(lines START-END: one-line description)`.
- **Codemap** — peripheral orientation files: `File: <path>` + `Imports:` bullets + class/function/type
  **signatures only**, no bodies. Generate with `bash <skill-root>/scripts/codemap.sh <path>` — a 3-tier
  honest-degrade map (tree-sitter → ctags → grep) that discloses `CODEMAP_STATE=<TREESITTER|CTAGS|REGEX>`;
  the grep tier is the zero-dependency floor, ctags/tree-sitter are auto-detected upgrades (see
  `references/codemap.md`).
- **Tree-only** — path appears in `file_map` for structure, no content.

## Step 3 — Assemble in the FIXED order, under budget

Emit the **fixed pack** as exactly these five sections, in order: **file_map → file_contents → git_diff →
meta_prompts → user_instructions** (this matches RepoPrompt CE's `defaultSectionOrder`). Per-file blocks
use `File: <path>` then a fenced code block. You MAY *additionally* duplicate `user_instructions` as an
optional preface at the very top (a primacy hedge) — it sits **above** the fixed five, not inside them.

Pick a budget by who consumes the pack: **paste** ≈24–32k, **handoff** ≈60k, **agent** ≈120–160k tokens.
Estimate tokens with the cheap heuristic `ceil(utf8_bytes / 4 * 1.05)` — run it with bash, no tokenizer:

```bash
bytes=$(wc -c < FILE); python3 -c "import math,sys; print(math.ceil(int(sys.argv[1])/4*1.05))" "$bytes"
```

Sum the selection; if over budget, **prune the least-relevant, slice large files, or downgrade full→
codemap** until it fits. For a single file that alone busts the budget, **middle-truncate**
deterministically: keep equal head+tail, insert a `[content truncated]` marker on a line boundary.

## Step 4 — Safety & persist

Scan for secrets before emitting: never include `.env`, API keys, tokens, credentials, or private
absolute paths (see `references/safety.md` deny-patterns); redact or drop them. Write the pack to a real
file (default `docs/context-packs/<slug>.md`) so it's inspectable and re-openable by path.

## `--discover` (optional agentic curation)

If `$ARGUMENTS` contains `--discover`, don't hand-pick files — have a fast subagent explore the repo and
propose a **selection manifest** (`.fusion/selection.json`) where **every selected file carries evidence**
(a grep match, an import path, a git-diff hit, a test reference). Validate it:

```bash
python3 <skill-root>/scripts/selection_lint.py .fusion/selection.json
```

A file with no evidence is **dropped** (the linter's S007 gate), so the pack degrades to mechanical
selection rather than hallucinated relevance; the manifest's `rejected` list records what was cut, so the
pack stays reviewable. Then assemble the fixed five sections from the manifest as in Step 3. This mode is
**optional** — the default `/fusion-context` stays mechanical. See `references/context-discovery.md`.

## Present

The pack path, the chosen budget, the estimated token total, and the per-tier file count. This command is
single-model — curation is mechanical; a panel would just produce divergent packs to reconcile.
