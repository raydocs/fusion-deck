# Worktree isolation — parallel dispatch on separate checkouts

`/fusion-orchestrate` runs sibling work items in parallel only when they touch **independent files**
(see `orchestration-rubric.md`). Even then, two subagents editing the same checkout can collide on
build artifacts, lockfiles, or a half-saved file. `--worktrees` gives each parallel item its own
**git worktree** — a separate working directory sharing the repo's object store, on its own branch —
so their edits can never step on each other, and the judge reviews each diff before any merge.

**Default is OFF.** In-place sequential dispatch needs no worktrees and is the common case. Opt in only
when you are actually fanning out parallel siblings that could collide.

## Prefer native isolation when the harness has it

Some Claude Code harnesses expose **native subagent worktree isolation** (the `EnterWorktree` tool —
it creates a worktree under `.claude/worktrees/` on a fresh branch and switches the agent's cwd into
it). When that's available, **use it** — it's integrated with the harness's cwd and cleanup. This
script is the **portable fallback** for harnesses without it: a plain `git worktree` wrapper that runs
anywhere git does. Pick one; don't run both for the same item.

## Lifecycle

```
create  -> git worktree add  .fusion-worktrees/<id>  on branch fusion/<id>   (+ copy .worktreeinclude)
   ...      a fresh subagent works ENTIRELY inside that path; commits to fusion/<id>
review  -> the judge reads `git -C .fusion-worktrees/<id> diff <base>` BEFORE merge
merge   -> orchestrator merges/cherry-picks the reviewed branch back into the working branch
cleanup -> git worktree remove  .fusion-worktrees/<id>   (deletes the branch only if merged; keeps it otherwise)
```

```bash
bash scripts/fusion_worktree.sh create  item-2          # off current HEAD
bash scripts/fusion_worktree.sh create  item-3 origin/main
bash scripts/fusion_worktree.sh list
bash scripts/fusion_worktree.sh cleanup item-2
```

Each `create` emits greppable lines the orchestrator keys on:

```
WORKTREE_STATE=OK
WORKTREE_PATH=/abs/repo/.fusion-worktrees/item-2
WORKTREE_BRANCH=fusion/item-2
COPIED=3
```

`<id>` must be a single safe segment (`[A-Za-z0-9._-]`, no slashes, no leading dot/dash). It names both
the directory and the branch suffix, so keep it boring (`item-2`, not `../oops`).

**Baseline before work.** Run the item's focused test command in the fresh worktree *before* the subagent
starts. A failure found later is only attributable to the new work if the baseline was green — without it,
pre-existing breakage and the subagent's bug are indistinguishable at review time. If the baseline fails,
surface it; don't dispatch onto a broken base.

## The judge reviews every worktree diff before merge

A worktree's branch is **not trusted until reviewed.** Before merging, the judge — Claude (the session model) — reads each
worktree's diff against its base — the same scrutiny a panel answer gets — and only then does the
orchestrator merge. A subagent never merges its own worktree; isolation without review just hides the
collision instead of preventing it.

## `.worktreeinclude` — opt-in carry-over of ignored local files

A new worktree is a **clean checkout**: it has every tracked file but **none** of the git-ignored local
files a sibling might need to actually run — `.env.local`, a built `node_modules/`, a `.venv/`, a local
cache. `.worktreeinclude` (repo root, **gitignore syntax**) is the explicit allowlist of which ignored
files to copy into the new worktree.

The gate is **doubled** — a file is copied only if **both** hold:

1. **git already ignores it** — we never copy tracked files (the worktree already has those) or files
   destined to be tracked. Carrying a tracked file would mask a dirty edit.
2. **`.worktreeinclude` positively matches it** — opt-in only. An ignored file you didn't list stays out.

Plus per-file safety: **regular files only** (symlinks are refused), and the destination must stay
**inside the worktree** (a path that would escape the repo is refused). Dirty/tracked files are never
copied. Secrets are your call — if you list `.env.local` you've chosen to carry it into the sibling
checkout; nothing else copies it for you. When a copied file matches a known secret shape (`.env*`,
`*.pem`, `*.key`, `id_rsa*`, `credentials*`, `secrets*`, `*.p12`, `*.keystore`) the script still copies it
but prints a loud stderr note, so a broad glob like `*.local` that incidentally sweeps one in never does so
silently (see `references/safety.md`).

### Syntax

Standard gitignore rules, evaluated against the repo's currently-ignored files:

- `#` begins a comment line.
- A blank line matches nothing.
- A bare pattern (`.env.local`, `*.local`, `config/local.json`) selects matching ignored files.
- A trailing `/` selects an ignored **directory**; its regular files are copied (recursively).
- `!pattern` **negates** — re-exclude something a broader line pulled in. **Caveat (a git rule, not ours):
  once a directory is matched as a whole, you cannot re-include/re-exclude a file underneath it.** `.venv/`
  followed by `!.venv/**/__pycache__/` does **not** carve out the cache — git stops descending at the
  matched dir. To exclude part of a tree, don't match the parent dir; list the wanted children instead.

### Example `.worktreeinclude`

```gitignore
# Carry these git-ignored locals into each parallel worktree so siblings can run.
.env.local            # local env the app needs at runtime
config/local.json     # machine-local overrides

# Bring the built venv. (Listing .venv/ as a whole — see the negation caveat above —
# means its __pycache__ rides along too; that's harmless for a sibling that just runs.)
.venv/
```

This copies `.env.local`, `config/local.json`, and the `.venv/` tree — **only if** git already ignores
each one. If `.env.local` is actually tracked, it is **not** copied (gate 1 fails); the worktree already
has the tracked version, and you'd see that in review.

## Failure & degrade

- **Not inside a git repo** → `WORKTREE_STATE=NO_GIT`, non-zero exit. Worktree isolation is simply
  unavailable; fall back to sequential in-place dispatch — never fake an OK.
- **`<id>` already exists** (directory, branch, or registered worktree) → `WORKTREE_STATE=EXISTS`,
  non-zero exit. Pick a fresh id or `cleanup` the old one; we won't clobber another item's work.
- **`git worktree remove` refuses** (uncommitted changes in the worktree) → `WORKTREE_STATE=ERROR`.
  Review/commit or discard the diff first; cleanup never force-destroys unreviewed work.
- **No `.worktreeinclude`** → `COPIED=0`, clean create. The carry-over is purely opt-in.

The greppable `WORKTREE_STATE` line always reflects what **actually** happened — an honest degrade, not
a claimed capability.
