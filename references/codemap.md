# Codemap — honest-degrade for context density

A **codemap** is a signatures-only view of source files — `Imports:` lines plus class/function/type
signatures, **no bodies**. It is the cheap-but-oriented density tier of a Context Pack: peripheral files
that the consumer needs to *navigate*, not edit, get their shape for a fraction of the tokens of full
content (see `references/context-pack-format.md`).

`scripts/codemap.sh` produces it at the best fidelity the machine can honestly support, and **discloses
which fidelity actually ran**. This is the same discipline as the panel's degraded mode
(`references/degraded-mode.md`), applied to context instead of models: never claim a capability you did
not run; degrade loudly via a greppable state line.

```bash
bash <skill-root>/scripts/codemap.sh <path> [<path> ...]   # files and/or directories
```

## The three tiers

Best-available-first, auto-detected. Each tier yields the same block shape; they differ in parse fidelity.

| Tier | Requires | What it yields |
|------|----------|----------------|
| `TREESITTER` | python `tree_sitter_languages` (the bundled grammars) | real parse trees — exact definition headers, methods inside classes, per-language correctness |
| `CTAGS` | Universal/Exuberant `ctags` (must support `--version`) | signatures from the ctags index, tagged by kind + line |
| `REGEX` | nothing — pure `grep` | the zero-dependency floor: import lines + keyword/`name()` signature lines |

The **default is `REGEX`**. It has no dependencies and always works. `ctags` and `tree-sitter` are
**OPTIONAL auto-detected upgrades** — if one is installed and runs, `codemap.sh` uses it; if not, it
silently picks the next tier down and says so. You never have to install anything to get a usable codemap;
you *may* install an upgrade to get a sharper one.

A tool counts as available only if it's on PATH **and** actually runs (a `--version` probe, bounded so a
hung tool can't wedge the run — same portable watchdog as `detect_panel.sh`, since macOS ships no GNU
`timeout`). Note the common trap: macOS/Xcode ships a **BSD `ctags`** that does not understand
`--version` or kind/signature fields. `codemap.sh` correctly rejects it and degrades to `REGEX` rather
than emitting the BSD tool's unreliable cross-reference as if it were the real CTAGS tier — an honest
degrade, not a silent half-capability.

## The disclosure lines

Every run ends with two greppable lines — how much was actually mapped, and the tier that **actually ran**:

```
CODEMAP_FILES=<n>
CODEMAP_STATE=TREESITTER | CTAGS | REGEX
```

This is the codemap's analogue of `PANEL_STATE`. A `/fusion-context` build that used codemaps records the
realized `CODEMAP_STATE` so the pack reader knows whether the signatures are parser-exact or grep-approximate.

**An empty map is a failure, not a result.** If no source file was collected, `codemap.sh` prints
`CODEMAP_FILES=0`, says why on stderr, and **exits 3** — it never emits a codemap-shaped artifact with no
map in it. The two ways to get there, both remediable: the language's extension is unmapped (add it to
`collect_files`, and to `EXT`/`DEF_TYPES` for the tree-sitter tier), or the path was pruned as build output
(pass the files explicitly — explicit FILE arguments bypass the prune list). Callers must treat exit 3 as
"no context was produced" and say so, exactly as a missing panelist is reported ABSENT rather than silently
counted as agreement.

## Language coverage

Directory walks cover the keyword-declared languages plus the **modifier-led** ones (C#, Swift, Kotlin,
Objective-C, PHP, Scala, Lua). Modifier-led languages matter disproportionately because they declare methods
with **no keyword at all** — `public void Bind(Actor a)` — so a keyword-only signature pattern maps their
types and silently misses every method. The REGEX floor therefore accepts an optional repeated modifier
prefix before the keyword group, and separately matches `<modifier>+ <return-type> <name>(`; requiring at
least one modifier there keeps `if (` / `while (` and ordinary call sites out of the map.

## Forcing a tier — `FUSION_CODEMAP_TIER`

```bash
FUSION_CODEMAP_TIER=regex|ctags|treesitter  bash <skill-root>/scripts/codemap.sh <path> ...
```

The override **caps** fidelity; it can never conjure a missing tool. Force `regex` and you always get the
floor exactly. Force `treesitter` on a machine without it and you get a loud stderr note plus an honest
**degrade** to the best available tier — and `CODEMAP_STATE` reports what truly ran, never the tier you
asked for. You cannot trick the script into claiming `TREESITTER` when it executed `REGEX`.

## How `/fusion-context` uses it

In a Context Pack, files carry a **density tier**: full content (edit targets), line slices (large,
partly-relevant), **codemap** (peripheral orientation), or tree-only (path in `file_map`, no block).
For the codemap tier, `/fusion-context` calls `scripts/codemap.sh` on the file or subtree and pastes the
`File:` / `Imports:` / signatures block straight into `## file_contents`. The format already matches the
per-file block in `context-pack-format.md`, and the upgrade is transparent: the same command yields a
sharper map wherever a richer parser happens to be installed, without changing how the pack is assembled.

## Deliberately NOT a mini-RepoPrompt

`codemap.sh` is a thin, optional helper (honest `CODEMAP_STATE` tiering; zero-dep REGEX floor + opt-in
upgrades) — not a port of RepoPrompt's tree-sitter engine.
