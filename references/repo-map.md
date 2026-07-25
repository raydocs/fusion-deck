# The shared repo map — `scripts/fusion_map.sh`

`codemap.sh` (see `references/codemap.md`) maps files you name. `fusion_map.sh` builds the **repo-level**
artifact a panel shares.

```bash
bash scripts/fusion_map.sh <out_dir> [focus_path ...]      # -> <out_dir>/map.md
```

It emits `file_map` (every tracked source path, ` +` marking those with signatures below) then `codemap`
(the signature blocks). Inventory comes from `git ls-files`, so gitignored build output costs nothing —
the same reason the caller-context step uses `git grep`, not `grep -r`.

**Why share a map but never a selection.** The panel's highest-confidence signal is consensus, and
consensus only carries information while the seats' errors are *independent*. A curated pack handed to
every seat destroys that: whatever curation omitted, all seats miss together, and they then "independently
agree" on a shared blind spot — a failure that reports as high confidence. A map has no such effect. It is
mechanical: it ranks nothing, excludes nothing on relevance grounds, and leaves every seat to choose what
to examine. Share the territory; let each seat do its own navigation.

**Density tiers.** `full` for focus paths under `FUSION_MAP_FULL_MAX_BYTES` (default 16000) — those come
from `git diff --name-only`, so the tier is deterministic, not curated; signatures say a function exists,
only the body says whether the change fits the file it landed in. `codemap` for everything else. A file
whose block would carry no structure degrades to **tree-only** — named in `file_map`, no block, and no
` +` marker, because marking it would claim signatures that do not exist. Markdown contributes its
**heading outline** (capped by `FUSION_CODEMAP_MD_MAX_HEADINGS`, default 40) rather than nothing.
`MAP_TREEONLY` is reported separately from `MAP_DROPPED`: "nothing to show" and "budget went elsewhere"
are different facts, and collapsing them hides a budget problem behind a coverage one.

**Drop order.** focus → code → prose. Under a byte ceiling the tail is what goes, and a doc's outline is
worth less to a review than a source file's signatures — measured, a 150-file docs tree (session logs,
changelogs) otherwise crowded out real code purely by ordering. This is a fixed policy keyed on file type
and applied identically to every run, so unlike relevance curation it adds no task-specific blind spot.

**Cache.** Keyed on the git **blob SHA**, not mtime — content-addressed, so it survives checkouts and
stays warm across worktrees, and a rebuild costs O(changed files). Cache misses are built in **batches**
(one `codemap.sh` invocation amortizes its tier-detection start-up across ~200 files) and fanned into
per-SHA entries. `git ls-files -s` reports the **index** SHA, which is stale for an unstaged edit — so
dirty files are re-hashed from the working tree and untracked (non-ignored) source files are included.
Without that, `/fusion-review uncommitted` — the most common scope — would be handed a map of the
pre-edit code. A path still in the index but **gone from disk** is dropped: otherwise its old blob stayed
a cache hit and the map showed signatures for functions the diff had just deleted. The re-hash pairs
paths to SHAs by position, so a count mismatch **aborts** (exit 5) rather than shifting every later path
onto another file's blob.

**Budget — two ceilings, the tighter wins.**

`FUSION_MAP_BUDGET_TOKENS` (default 60000) expresses curation intent and governs the **codemap section
only**. `FUSION_MAP_MAX_BYTES` (default 150000) is the one that usually binds, and it exists because the
real constraint is **bytes on the tightest seat's prompt transport, not tokens**: the Antigravity seat
passes its prompt via **argv** and hard-fails above `FUSION_ANTIGRAVITY_MAX_ARG_BYTES` (default 200000),
while codex accepts 400000. Sizing the map to the looser cap silently costs the panel its Gemini seat —
measured: a 498-file repo produced a 186 KB map, 96% of the argv cap before the diff was even added.
The default leaves room for the packet.

`file_map` is always complete: it is just paths, and hiding that a file *exists* is the one thing a map
must never do. So `MAP_TOKENS_EST` legitimately exceeds the token budget — compare
`MAP_CODEMAP_TOKENS_EST` against it. Over budget, codemap blocks drop in reverse focus order and the run
reports `MAP_STATE=TRUNCATED` with `MAP_DROPPED=<n>`; a dropped file is still **named**, so a seat knows
to go read it.

When `file_map` *alone* busts the byte ceiling, both invariants cannot hold at once — so the run
**refuses**: `MAP_STATE=OVERSIZE`, exit 4, with the remedy (scope the map to a subtree). Truncating
file_map would hide files; emitting anyway would kill a seat at launch. Neither is an acceptable silent
outcome. Not a repo → exit 2 (`MAP_STATE=NO_GIT`); no source files → exit 3.

