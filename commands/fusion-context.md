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

If the repo has a **`.fusionignore`** (gitignore-style; a leading `!` force-includes), honor it here too:
**drop any matched file from the pack** even if it looks relevant — same exclusion the `--discover` linter
enforces as S012, just applied by hand in the mechanical path. It keeps big vendored/build/generated dirs
out of every pack while `!` keeps must-have docs in.

## Step 2 — Assign a density tier per file

Assign each selected file one density tier (**full / line-slice / codemap / tree-only**). Tier semantics,
slice anchors, `+` legend, and codemap invocation details live only in
`references/context-pack-format.md` § Per-file block format. For codemap-tier paths, generate with:

```bash
bash <skill-root>/scripts/codemap.sh <path>
```

It discloses `CODEMAP_STATE=<TREESITTER|CTAGS|REGEX>` (honest-degrade; see `references/codemap.md`). If
`codemap.sh` or `selection_lint.py` fails to RUN (script error, not lint findings), say so, do that pass
manually against the reference, and label the pack's tier honestly.

## Step 3 — Assemble in the FIXED order, under budget

Emit the **fixed pack** as exactly these five sections, in order: **file_map → file_contents → git_diff →
meta_prompts → user_instructions** (format, optional preface, and `+` legend only in
`context-pack-format.md`). Per-file blocks use `File: <path>` then a fenced code block.

Pick a budget by consumer (**paste / handoff / agent** — numbers in the reference). Estimate tokens with:

```bash
bytes=$(wc -c < FILE); python3 -c "import math,sys; print(math.ceil(int(sys.argv[1])/4*1.05))" "$bytes"
```

Sum the selection; if over budget, **prune the least-relevant, slice large files, or downgrade full→
codemap** until it fits. For a single file that alone busts the budget, **middle-truncate**
deterministically (equal head+tail, line boundary):

```bash
head -n 120 FILE > part; echo '[content truncated]' >> part; tail -n 120 FILE >> part
```

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
