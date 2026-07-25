#!/usr/bin/env bash
# fusion_map.sh — build the SHARED repo map (file_map + codemap) ONCE per run, cached on git blob SHA.
#
# Why this exists: a panel's non-Claude seats run sandboxed and a Claude seat with repo access spends most
# of its wall-clock on serial "where do I even look" tool round-trips. The fix is the RepoPrompt insight —
# give every seat a cheap, mechanical MAP of the territory, and let each one slice what it wants from it.
#
# The map is deliberately MECHANICAL, not curated. It ranks nothing and excludes nothing on relevance
# grounds, so sharing it does NOT give the panel a common blind spot: seats still choose independently
# what to look at, so their errors stay uncorrelated and `consensus` keeps meaning what judge-rubric.md
# says it means. A curated selection shared to every seat would break exactly that.
#
# Usage:
#   fusion_map.sh <out_dir> [focus_path ...]
#
#   <out_dir>     where map.md is written (the fusion run's out dir)
#   [focus_path]  paths to place FIRST when the budget forces truncation (e.g. the files in the diff).
#                 Ordering only — a focus path is never the sole content, and nothing is dropped silently.
#
# Env:
#   FUSION_MAP_BUDGET_TOKENS  token ceiling for the codemap section (default 60000 = the "handoff" tier
#                             in context-pack-format.md). file_map is always emitted in full — it is just
#                             paths, and a truncated file_map would hide that files exist at all.
#   FUSION_MAP_CACHE          cache ROOT (default ${XDG_CACHE_HOME:-~/.cache}/fusion-deck). Deliberately
#                             OUTSIDE the repo: a context builder that writes into the tree it describes
#                             is a surprising contract, and the cache grows without bound.
#                             Entries live at <root>/<repo-key>/<tier>/<blob-sha>.map
#   FUSION_MAP_NO_CACHE=1     bypass the cache entirely (for benchmarking a cold build)
#
# Caching: keyed on (repo, TIER, git BLOB SHA) — not mtime. Content-addressed, so it survives checkouts
# and stays warm across worktrees. The TIER is part of the key because a block built at REGEX must not be
# reused once tree-sitter is installed: the artifact would then report a fidelity it did not produce.
# Cached bodies are stored WITHOUT their `File:` header, so two files with identical content (same blob)
# cannot inherit each other's path. Rebuild cost is O(changed files), not O(repo).
#
# Greppable output lines (callers key on these):
#   MAP_FILES=<n>        source files git can see (tracked + untracked-not-ignored), by FUSION_SOURCE_EXT
#   MAP_MAPPED=<n>       files whose codemap block made it into map.md under budget
#   MAP_DROPPED=<n>      files listed in file_map but with no codemap block (budget) — NEVER silent
#   MAP_TREEONLY=<n>     files with no extractable structure (tree-only tier) — distinct from DROPPED
#   MAP_TOKENS_EST=<n>   ceil(bytes/4*1.05) of map.md
#   CACHE_HIT=<n> CACHE_MISS=<n>
#   CODEMAP_STATE=<TREESITTER|CTAGS|REGEX>
#   MAP_STATE=<FULL|TRUNCATED>
#
# Honest-degrade: not a git repo => MAP_STATE=NO_GIT + non-zero exit. No source files => non-zero exit,
# same rule as codemap.sh: an empty map is a failure, never a result.

set -uo pipefail

_self="${BASH_SOURCE[0]}"
_dir="${_self%/*}"; [ "$_dir" = "$_self" ] && _dir="."
here="$(cd "$_dir" && pwd)"
. "$here/gemini_backend.sh"   # FUSION_SOURCE_EXT, fusion_is_source_path

out_dir="${1:?usage: fusion_map.sh <out_dir> [focus_path ...]}"
shift || true
focus=("$@")

budget="${FUSION_MAP_BUDGET_TOKENS:-60000}"
case "$budget" in ''|*[!0-9]*) echo "fusion_map: bad FUSION_MAP_BUDGET_TOKENS '$budget'" >&2; exit 2 ;; esac

repo="$(git rev-parse --show-toplevel 2>/dev/null)"
if [ -z "$repo" ]; then
  echo "fusion_map: not a git repository — the map is built from 'git ls-files' and cannot be built here." >&2
  echo "MAP_STATE=NO_GIT"
  exit 2
fi

mkdir -p "$out_dir" || exit 2
tmp="$(mktemp -d "${TMPDIR:-/tmp}/fusion-map.XXXXXX")" || exit 2
# The cache staging dir lives under $cache (so the rename is same-filesystem), which $tmp's trap does not
# cover — an interrupted run would strand .stage.<pid> in the cache forever. INT/TERM too: the EXIT trap
# alone does not fire when the panel is Ctrl-C'd or the parent times out.
# The INT/TERM handlers must EXIT. A bash signal handler that merely returns hands control back to the
# script: an interrupted run continued with $tmp already deleted and still emitted MAP_STATE=FULL and
# exit 0. Cleaning up is not the same as stopping. (EXIT also fires on the way out; rm -rf is idempotent.)
_fm_stage=""
_fm_cleanup() { rm -rf "$tmp" ${_fm_stage:+"$_fm_stage"}; }
trap '_fm_cleanup' EXIT
trap '_fm_cleanup; exit 130' INT
trap '_fm_cleanup; exit 143' TERM

# Ask codemap.sh which tier it would run (it owns that logic; re-deriving it here would drift) and key the
# cache on it. Without a tier in the key, blocks built at REGEX are reused verbatim after tree-sitter is
# installed, and the run reports a fidelity it did not produce.
tier="$(bash "$here/codemap.sh" --print-tier 2>/dev/null | cut -d= -f2)"
[ -n "$tier" ] || tier=REGEX

# HOME is not guaranteed (cron, CI, some container runtimes) and `set -u` turns a bare $HOME into a
# hard crash partway through. Fall back to a temp cache: slower, never fatal, and it says so.
if [ -n "${FUSION_MAP_CACHE:-}" ]; then
  cache_root="$FUSION_MAP_CACHE"
elif [ -n "${XDG_CACHE_HOME:-}" ]; then
  cache_root="$XDG_CACHE_HOME/fusion-deck"
elif [ -n "${HOME:-}" ]; then
  cache_root="$HOME/.cache/fusion-deck"
else
  cache_root="$tmp/cache"
  echo "fusion_map: neither FUSION_MAP_CACHE, XDG_CACHE_HOME nor HOME is set — caching to a temp dir," >&2
  echo "fusion_map: so this run cannot reuse or leave a warm cache." >&2
fi
[ "${FUSION_MAP_NO_CACHE:-0}" = "1" ] && cache_root="$tmp/nocache"
# Namespaced by repo so two projects never share entries, and kept OUT of the repo: a context builder
# that writes into the tree it is describing is a surprising contract, and the cache grows without bound.
repo_key="$(printf '%s' "$repo" | cksum | tr -d ' ' | cut -c1-16)"
cache="$cache_root/$repo_key/$tier"
mkdir -p "$cache" || exit 2

# ── 1. The tracked source inventory, with each file's blob SHA ────────────────────────────────────────
# `git ls-files -s` emits "<mode> <sha> <stage>\t<path>". Using git (not find) is the whole point: it sees
# ONLY tracked files, so gitignored build output (node_modules, Library/, target/) costs nothing — the
# same reason /fusion-review's caller-context step uses `git grep` rather than `grep -r`.
( cd "$repo" && git ls-files -s ) \
  | awk -F'\t' '{ split($1, m, " "); print m[2] "\t" $2 }' > "$tmp/index_sha_path"

# The INDEX sha is stale for a file edited but not staged — and `/fusion-review uncommitted` (the most
# common scope) is exactly that case, where a stale map would describe the pre-edit code while claiming
# to be the map of what is under review. So re-hash the working-tree content of dirty files, and include
# untracked-but-not-ignored source files, which `git ls-files` cannot see at all.
: > "$tmp/rehash_paths"
( cd "$repo" && git diff --name-only; git ls-files -o --exclude-standard ) 2>/dev/null \
  | sort -u > "$tmp/dirty_or_new"
while IFS= read -r path; do
  [ -n "$path" ] || continue
  fusion_is_source_path "$path" || continue
  [ -f "$repo/$path" ] || continue          # deletions: nothing to hash; they drop out of the map
  printf '%s\n' "$path" >> "$tmp/rehash_paths"
done < "$tmp/dirty_or_new"

: > "$tmp/rehash_sha_path"
if [ -s "$tmp/rehash_paths" ]; then
  # One batched hash-object call; its output is one sha per input path, in order.
  ( cd "$repo" && tr '\n' '\0' < "$tmp/rehash_paths" | xargs -0 git hash-object -- ) \
    > "$tmp/rehash_shas" 2>"$tmp/rehash_err"
  # `paste` pairs by POSITION. If git declines even one path (unreadable file, a race with the editor),
  # the output is one line short and every subsequent path is joined to the WRONG blob — which then
  # resolves to another file's cache entry, i.e. file A's signatures printed under file B's name.
  # Nothing downstream could detect that, so a count mismatch must fail here, loudly.
  n_p=$(wc -l < "$tmp/rehash_paths" | tr -d ' ')
  n_s=$(wc -l < "$tmp/rehash_shas" | tr -d ' ')
  if [ "$n_s" != "$n_p" ]; then
    echo "fusion_map: git hash-object returned $n_s sha(s) for $n_p path(s) — refusing to pair by position," >&2
    echo "fusion_map: which would attach one file's signatures to another file's name." >&2
    sed 's/^/fusion_map:   /' "$tmp/rehash_err" >&2
    echo "MAP_STATE=HASH_MISMATCH"
    exit 5
  fi
  paste "$tmp/rehash_shas" "$tmp/rehash_paths" > "$tmp/rehash_sha_path"
fi

# Merge: a re-hashed entry WINS over the index entry for the same path, and new paths are appended.
awk -F'\t' '
  NR == FNR { win[$2] = $1; order[++n] = $2; next }
  !($2 in win) { print $1 "\t" $2 }
  END { for (i = 1; i <= n; i++) print win[order[i]] "\t" order[i] }
' "$tmp/rehash_sha_path" "$tmp/index_sha_path" > "$tmp/all_sha_path"

# A path in the index that is GONE from disk is a deletion under review. Without this test its old blob
# SHA stays a cache HIT, so the map both lists the file and emits signatures for functions that no longer
# exist — verified: `rm src/b.py` left `src/b.py` in map.md twice with its `deleted_fn` block intact.
#
# One awk pass, not a shell loop. The `while read` form ran ~800 iterations calling a shell function and
# a `[ -f ]` per line: measured 532 ms of a 978 ms warm build, on bash 3.2 loop overhead alone. Deletions
# now come from a single `git ls-files -d` rather than one stat per file.
# Checked, not swallowed: an empty `deleted` list is indistinguishable from "nothing was deleted", and
# it silently restores the exact defect this block exists to prevent — a removed file keeping its
# file_map entry and a full signature block for functions that no longer exist.
if ! ( cd "$repo" && git ls-files -d ) 2>"$tmp/del_err" | sort -u > "$tmp/deleted"; then
  echo "fusion_map: could not list deleted files; a removed file would keep its stale signatures." >&2
  sed 's/^/fusion_map:   /' "$tmp/del_err" >&2
  echo "MAP_STATE=DELETED_UNKNOWN"
  exit 6
fi
awk -F'\t' -v exts="$FUSION_SOURCE_EXT" -v del="$tmp/deleted" '
  BEGIN { n = split(exts, a, " "); for (i = 1; i <= n; i++) ok["." a[i]] = 1 }
  FILENAME == del { gone[$0] = 1; next }
  {
    p = $2
    if (p in gone) next
    d = p; sub(/^.*\./, ".", d)          # extension, dot included; no dot => unchanged, cannot match
    if (index(p, ".") == 0 || !(d in ok)) next
    print
  }
' "$tmp/deleted" "$tmp/all_sha_path" > "$tmp/src_sha_path"

n_files=$(wc -l < "$tmp/src_sha_path" | tr -d ' ')
if [ "$n_files" -eq 0 ]; then
  echo "fusion_map: no source files matched FUSION_SOURCE_EXT (tracked or untracked-not-ignored) —" >&2
  echo "fusion_map: refusing to emit an empty map." >&2
  echo "fusion_map: extensions searched: $FUSION_SOURCE_EXT" >&2
  echo "MAP_FILES=0"
  echo "MAP_STATE=EMPTY"
  exit 3
fi

# ── 2. Split into cache hits and misses ───────────────────────────────────────────────────────────────
# List the cache ONCE and partition in awk: the per-entry `[ -s ]` loop cost 291 ms of a 978 ms warm
# build. Keyed on FILENAME, never NR==FNR — the listing is empty on a cold cache, and an empty first
# file makes NR==FNR true for every record of the second.
find "$cache" -maxdepth 1 -name '*.map' -size +0 2>/dev/null \
  | sed 's|.*/||; s|\.map$||' | sort -u > "$tmp/have"
awk -F'\t' -v have="$tmp/have" -v hit="$tmp/hit" -v miss="$tmp/miss" '
  FILENAME == have { h[$0] = 1; next }
  { print > (($1 in h) ? hit : miss) }
' "$tmp/have" "$tmp/src_sha_path"
: >> "$tmp/hit"; : >> "$tmp/miss"
n_hit=$(wc -l < "$tmp/hit" | tr -d ' ')
n_miss=$(wc -l < "$tmp/miss" | tr -d ' ')

# ── 3. Build the misses in BATCHES, then fan the batch output into per-SHA cache entries ──────────────
# One codemap.sh call per file would pay its fixed start-up cost (tier detection + probes) every time —
# measured ~67 ms alone vs ~7 ms marginal inside a batch. So batch, then split the output by 'File:'.
if [ "$n_miss" -gt 0 ]; then
  chunk=200
  : > "$tmp/batch_out"
  start=1
  while [ "$start" -le "$n_miss" ]; do
    files=()
    while IFS="$(printf '\t')" read -r _sha path; do files+=( "$repo/$path" ); done \
      < <(sed -n "${start},$((start + chunk - 1))p" "$tmp/miss")
    [ "${#files[@]}" -eq 0 ] && break
    # codemap.sh exits 3 on an empty map; with explicit tracked source files that means a real problem,
    # so surface it rather than caching nothing and calling the map complete.
    if ! bash "$here/codemap.sh" "${files[@]}" >> "$tmp/batch_out" 2>"$tmp/batch_err"; then
      rc=$?
      if [ "$rc" -eq 3 ]; then
        echo "fusion_map: codemap.sh mapped nothing for a batch of ${#files[@]} tracked source files." >&2
        sed 's/^/fusion_map:   /' "$tmp/batch_err" >&2
        exit 3
      fi
    fi
    start=$((start + chunk))
  done
  batch_tier="$(grep -h '^CODEMAP_STATE=' "$tmp/batch_out" | tail -1 | cut -d= -f2)"
  # If codemap.sh degraded mid-run (e.g. tree-sitter selected but no file parsed), the blocks we just
  # wrote are NOT the tier we keyed them under. Re-key rather than mislabel them.
  if [ -n "$batch_tier" ] && [ "$batch_tier" != "$tier" ]; then
    # Switch where THIS run publishes; do NOT move what is already there. The previous code did
    # `mv "$cache"/*.map` into the new tier dir, which relabelled blocks EARLIER runs had correctly
    # produced at the old fidelity — the exact lie the tier key exists to prevent. It also could never
    # have moved "this batch": these blocks are still in the staging dir at this point.
    echo "fusion_map: codemap.sh realized $batch_tier, not the probed $tier — publishing under" >&2
    echo "fusion_map: $batch_tier. Existing $tier entries are left alone; they were produced at $tier." >&2
    tier="$batch_tier"; cache="$cache_root/$repo_key/$tier"
    mkdir -p "$cache" || exit 2
  fi

  # Fan out: one awk pass writes each file's block to $cache/<sha>.map. Absolute paths are mapped back to
  # repo-relative on the way in, so a cached block is portable across worktrees of the same repo.
  # Staged inside the cache dir on purpose: `mv` is only an atomic rename WITHIN a filesystem, and
  # $TMPDIR need not share a volume with the cache. Staged elsewhere, a concurrent reader could still
  # observe a half-copied block.
  stage="$cache/.stage.$$"; _fm_stage="$stage"
  mkdir -p "$stage"
  awk -v stage="$stage" -v repo="$repo/" '
    NR == FNR { sha[$2] = $1; next }
    /^CODEMAP_(FILES|STATE)=/ { next }
    /^File: / {
      if (out != "") { close(out); out = "" }
      p = substr($0, 7)
      sub("^" repo, "", p)
      # Store the body only. The File: header is written at ASSEMBLY from the current path, because two
      # files with identical content share a blob SHA and would otherwise inherit whichever path was
      # cached first.
      if (p in sha) { out = stage "/" sha[p] ".map"; printf "" > out }
      next
    }
    { if (out != "") print > out }
    END { if (out != "") close(out) }
  ' FS='\t' "$tmp/miss" FS=' ' "$tmp/batch_out"
  # One mv for the whole batch: rename is atomic per file, so a concurrent reader sees either the old
  # entry or the complete new one, never a partial block.
  staged_n=$(find "$stage" -name '*.map' 2>/dev/null | wc -l | tr -d ' ')
  # A glob `mv` in one shot (fast, and POSIX-correct — `find -exec mv {} DEST +` is INVALID because {}
  # must sit immediately before +, and BSD find rejects it outright, which silently published nothing).
  # Fall back to one mv per file only if the single call fails, which is where ARG_MAX would bite on a
  # very large cold batch.
  if ! mv "$stage"/*.map "$cache"/ 2>"$tmp/publish_err"; then
    find "$stage" -name '*.map' -print0 2>/dev/null \
      | while IFS= read -r -d '' _blk; do mv "$_blk" "$cache/" 2>/dev/null; done
  fi
  left_n=$(find "$stage" -name '*.map' 2>/dev/null | wc -l | tr -d ' ')
  if [ "${left_n:-0}" -gt 0 ]; then
    # Silence here would be permanent: the run reports its CACHE_MISS count as if the blocks landed, and
    # every later run re-misses exactly the same files, forever, with no symptom but slowness.
    echo "fusion_map: published $((staged_n - left_n))/$staged_n cache block(s); $left_n could not be" >&2
    echo "fusion_map: written to '$cache'. The map for THIS run is complete, but the cache did not warm." >&2
    sed 's/^/fusion_map:   /' "$tmp/publish_err" >&2
  fi
  rm -rf "$stage"; _fm_stage=""
fi


# ── 4. Priority order: focus paths first, then the rest (order only matters when the budget bites) ────
: > "$tmp/focus_hits"
for f in ${focus[@]+"${focus[@]}"}; do
  rel="${f#$repo/}"                                   # accept absolute or repo-relative
  awk -F'\t' -v want="$rel" '$2 == want { print }' "$tmp/src_sha_path" >> "$tmp/focus_hits"
done
# De-duplicate, order-preserving: the same path given twice (or listed twice by `git diff --name-only`
# across a rename) emitted its block twice and made MAP_MAPPED exceed MAP_FILES.
awk '!seen[$0]++' "$tmp/focus_hits" > "$tmp/focus_hits.u" && mv "$tmp/focus_hits.u" "$tmp/focus_hits"

# Order: focus → code → prose. Under a byte ceiling the tail is what gets dropped, and a doc's heading
# outline is worth less to a code review than a source file's signatures — a 150-file docs tree (session
# logs, changelogs) would otherwise crowd out real code purely by being listed first. This is a fixed
# policy keyed on file type, applied identically to every run; it is NOT relevance curation, so it adds
# no task-specific blind spot. Keyed on FILENAME, never NR==FNR: focus_hits is empty whenever no focus
# path was given, and an empty first file makes NR==FNR true for the entire second file.
{
  cat "$tmp/focus_hits"
  awk -F'\t' -v fh="$tmp/focus_hits" '
    FILENAME == fh { seen[$2] = 1; next }
    ($2 in seen) { next }
    { if ($2 ~ /\.(md|markdown|txt|rst)$/) prose[++np] = $0; else print }
    END { for (i = 1; i <= np; i++) print prose[i] }
  ' "$tmp/focus_hits" "$tmp/src_sha_path"
} > "$tmp/order"

# ── 4b. FULL tier for focus files ─────────────────────────────────────────────────────────────────────
# context-pack-format.md's density ladder reserves full content for "true edit targets". The focus paths
# ARE that set — they come from `git diff --name-only`, so this stays deterministic and introduces no
# curation into the shared artifact. Signatures tell a reviewer a function exists; only the body tells
# them whether the change fits the file it landed in. Capped per file so one large target cannot eat the
# whole budget — over the cap it silently keeps its codemap block, which is the honest degrade.
full_cap="${FUSION_MAP_FULL_MAX_BYTES:-16000}"
mkdir -p "$tmp/full"
if [ "${#focus[@]}" -gt 0 ] && [ "$full_cap" -gt 0 ] 2>/dev/null; then
  for f in "${focus[@]}"; do
    rel="${f#$repo/}"
    [ -f "$repo/$rel" ] || continue
    fusion_is_source_path "$rel" || continue
    fsz=$(wc -c < "$repo/$rel" | tr -d ' ')
    [ "$fsz" -gt "$full_cap" ] && continue
    fsha=$(awk -F'\t' -v w="$rel" '$2 == w { print $1; exit }' "$tmp/src_sha_path")
    [ -n "$fsha" ] || continue
    # Body only. Two focus paths with identical content share a blob SHA; keeping the `File:` header in
    # the block made the second one overwrite the first, so the map showed one path twice and lost the
    # other entirely. Identical content means identical body, so the shared key is fine once the header
    # is written at assembly instead.
    { cat "$repo/$rel"; printf '\n'; } > "$tmp/full/$fsha.map"
  done
fi

# ── 5. Assemble map.md under budget ───────────────────────────────────────────────────────────────────
# Budget applies to the codemap section only. file_map is always complete: it is just paths, and a
# truncated file_map would hide that a file EXISTS, which is the one thing a map must never do.
map="$out_dir/map.md"

# The REAL ceiling is bytes on the tightest seat's prompt transport, not a token preference: the
# Antigravity seat passes its prompt via argv and hard-fails over FUSION_ANTIGRAVITY_MAX_ARG_BYTES
# (default 200000), while codex accepts 400000. A map sized to the looser limit silently costs the panel
# its Gemini seat. So cap total map bytes and leave the caller room for the packet.
max_bytes="${FUSION_MAP_MAX_BYTES:-150000}"
case "$max_bytes" in ''|*[!0-9]*) echo "fusion_map: bad FUSION_MAP_MAX_BYTES '$max_bytes'" >&2; exit 2 ;; esac

# Size file_map first — it is emitted in full, so it is a fixed cost the codemap must fit around.
# Worst case each path also carries the 2-byte ' +' marker.
filemap_bytes=$(awk -F'\t' '{ n += length($2) + 3 } END { print n + 0 }' "$tmp/src_sha_path")
header_bytes=400
avail=$(( max_bytes - filemap_bytes - header_bytes ))

if [ "$avail" -le 0 ]; then
  # file_map alone busts the transport. Truncating it would hide that files EXIST — the one thing a map
  # must not do — so fail loudly and make the operator scope the map instead of silently shipping a lie
  # or silently killing a seat.
  echo "fusion_map: file_map alone is ~${filemap_bytes} bytes, over FUSION_MAP_MAX_BYTES=${max_bytes}." >&2
  echo "fusion_map: refusing to truncate file_map (that would hide that files exist) and refusing to" >&2
  echo "fusion_map: emit a map the panel cannot transport. Scope the map to a subtree by running from" >&2
  echo "fusion_map: it, or raise FUSION_MAP_MAX_BYTES only if every seat's prompt cap allows it." >&2
  # Remove any map.md from an earlier run in this out_dir: a caller must never consume a map that THIS
  # run refused to produce. Same reason run_panel.sh clears stale panel artifacts before launching.
  rm -f "$map"
  echo "MAP_FILES=$n_files"
  echo "MAP_STATE=OVERSIZE"
  exit 4
fi

# Two ceilings; the tighter one wins. The token budget expresses curation intent, max_bytes expresses
# what the panel can actually carry.
budget_bytes=$(( budget * 4 * 100 / 105 ))
[ "$budget_bytes" -gt "$avail" ] && budget_bytes="$avail"

# ONE awk pass, not a shell loop: a per-file `wc -c` fork cost ~5 ms each and dominated the warm-cache
# run (the case that must stay cheap, since the map is rebuilt before every fan-out).
: > "$tmp/codemap_body"; : > "$tmp/mapped_paths"
read -r mapped dropped used treeonly <<EOF
$(awk -F'\t' -v cache="$cache" -v full="$tmp/full" -v budget="$budget_bytes" \
      -v body="$tmp/codemap_body" -v mp="$tmp/mapped_paths" '
  {
    # A full-tier block (focus file) wins over the cached codemap block for the same content hash.
    sz = 0; buf = ""; useful = 0
    blk = full "/" $1 ".map"
    while ((getline line < blk) > 0) {
      if (useful == 0) { buf = "File: " $2 "  [full content — focus file]\n"; sz = length(buf) }
      buf = buf line "\n"; sz += length(line) + 1; useful = 1
    }
    close(blk)
    if (sz > 0) {
      if (used + sz <= budget) { printf "%s\n", buf > body; print $2 > mp; used += sz; mapped++ }
      else                     { dropped++ }
      next
    }
    blk = cache "/" $1 ".map"
    buf = "File: " $2 "\n"; sz = length(buf)
    while ((getline line < blk) > 0) {
      buf = buf line "\n"; sz += length(line) + 1
      # A block whose only lines are the header and a bare "Imports:" carries no structure. Emitting it
      # spends budget on nothing AND makes file_map mark it " +" — claiming signatures that do not exist.
      # Such a file belongs in the tree-only tier: named in file_map, no block, no marker.
      if (line !~ /^File: / && line !~ /^Imports:$/ && line ~ /[^ \t]/) useful = 1
    }
    close(blk)
    if (sz == 0 || !useful)      { treeonly++; next }
    if (used + sz > budget)      { dropped++; next }
    printf "%s\n", buf > body
    print $2 > mp
    used += sz; mapped++
  }
  # treeonly and dropped are DIFFERENT facts — "nothing to show" vs "shown to someone else first" —
  # and collapsing them would hide a budget problem behind a language-coverage one.
  END { print mapped + 0, dropped + 0, used + 0, treeonly + 0 }
' "$tmp/order")
EOF

{
  printf '# Repo map — %s\n\n' "$(basename "$repo")"
  printf 'Mechanical: every source file git can see — tracked, plus untracked-and-not-ignored — is listed\n'
  printf 'here, and nothing was selected or dropped for RELEVANCE to any particular task. Under a byte\n'
  printf 'ceiling, code outranks prose and focus paths come first; that is a fixed policy applied to every\n'
  printf 'run, not a judgement about this one. Signatures only — read the real file for anything named but\n'
  printf 'not shown.\n\n'
  printf '## file_map\n\n```\n'
  # ' +' marks paths that have a codemap block below (context-pack-format.md tree annotation).
  # Keyed on FILENAME, not NR==FNR: when the budget drops EVERY block, mapped_paths is empty, and with an
  # empty first file NR==FNR stays true for every record of the SECOND file — which would swallow the
  # whole file_map and emit a map that lists nothing. A fully-truncated map must still name every file.
  awk -F'\t' -v mp="$tmp/mapped_paths" '
    FILENAME == mp { m[$0] = 1; next }
    { print $2 (($2 in m) ? " +" : "") }
  ' "$tmp/mapped_paths" "$tmp/src_sha_path" | sort
  printf '```\n(+ denotes a codemap block below)\n\n'
  printf '## codemap\n\n'
  cat "$tmp/codemap_body"
} > "$map"

bytes=$(wc -c < "$map" | tr -d ' ')
# ceil(bytes/4*1.05) — the context-pack-format.md estimator, in awk so the warm path forks no python.
tokens=$(awk -v b="$bytes" 'BEGIN { t = b / 4 * 1.05; print (t == int(t)) ? t : int(t) + 1 }')
state=FULL
[ "$dropped" -gt 0 ] && state=TRUNCATED

# Two separate numbers on purpose. The budget governs the CODEMAP section only; file_map is always
# complete, so the total legitimately exceeds the budget and must not read as a budget violation.
cm_tokens=$(awk -v b="$used" 'BEGIN { t = b / 4 * 1.05; print (t == int(t)) ? t : int(t) + 1 }')

if [ "$dropped" -gt 0 ]; then
  echo "fusion_map: codemap budget ${budget} tokens (used ~${cm_tokens}) — $dropped file(s) are listed in" >&2
  echo "fusion_map: file_map with NO codemap block. They are named, not hidden; a seat that needs one can" >&2
  echo "fusion_map: read the real file. Raise FUSION_MAP_BUDGET_TOKENS or pass focus paths to steer this." >&2
fi

echo "MAP_PATH=$map"
echo "MAP_FILES=$n_files"
echo "MAP_MAPPED=$mapped"
echo "MAP_DROPPED=$dropped"
echo "MAP_TREEONLY=$treeonly"
echo "MAP_CODEMAP_TOKENS_EST=$cm_tokens"
echo "MAP_TOKENS_EST=$tokens"
echo "CACHE_HIT=$n_hit"
echo "CACHE_MISS=$n_miss"
echo "CODEMAP_STATE=$tier"
echo "MAP_STATE=$state"
