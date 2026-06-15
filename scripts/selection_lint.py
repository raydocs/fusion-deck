#!/usr/bin/env python3
"""selection_lint.py — lint a context-discovery selection manifest (the /fusion-context --discover output).

This is the SINGLE SOURCE OF TRUTH for selection-manifest lint rules. references/context-discovery.md
points here for the rule catalogue — do not duplicate the rules in prose (they would drift and false-green).

Design (audited): STRICT on structure + the evidence gate, ADVISORY on budget.
  * Block (exit 1) on deterministic structural facts: invalid JSON, a missing/empty task or budget, a
    selected entry missing its path/mode, an invalid mode, a `slice` without a valid line range, a
    path that matches a secrets deny-pattern, or a non-repo-relative path (absolute / `..`).
  * Block (exit 1) on THE EVIDENCE GATE — every selected[] entry MUST carry a non-empty `reason` AND a
    non-empty `evidence` array. A file proposed with no evidence is a hallucinated inclusion; it does not
    enter the pack. This gate is the whole point of the linter.
  * Warn (exit 0) on the budget heuristic (estimated tokens exceed budget_tokens), because the estimate is
    a byte/4 heuristic — a false-red over a fuzzy number makes people disable the linter.

Usage:
  selection_lint.py <manifest.json>   lint a selection manifest
  selection_lint.py --list-rules      print the rule catalogue and exit
  selection_lint.py -h | --help       this help

Exit codes: 0 = ok (warnings allowed) | 1 = lint failure (>=1 error) | 2 = usage error
"""

from __future__ import annotations

import fnmatch
import json
import math
import os
import sys

# A selected[] entry's mode must be one of these. `slice` additionally requires a `lines` range (S009).
VALID_MODES = ("full", "slice", "codemap", "tree")

# Secrets deny-patterns — a selected path matching any of these is blocked outright (mirror safety.md).
# Matched against the basename AND the full path so `cfg/.env.prod` and `.env` both trip.
DENY_GLOBS = (".env*", "*.pem", "*.key", "id_rsa*", "credentials*", "secrets*", "*.p12", "*.keystore")

RULES = {
    "S001": "invalid JSON (manifest does not parse)",
    "S002": "missing or empty 'task'",
    "S003": "'budget_tokens' missing or not a positive integer",
    "S004": "'selected' missing, empty, or not an array",
    "S005": "selected entry missing 'path'",
    "S006": "selected entry missing or empty 'reason'",
    "S007": "selected entry missing or empty 'evidence' (THE GATE — no evidence => dropped)",
    "S008": "selected entry has an invalid 'mode' (must be one of: %s)" % ", ".join(VALID_MODES),
    "S009": "selected entry mode=slice without a valid 'lines' range (START-END)",
    "S010": "selected path matches a secrets deny-pattern (.env*/*.pem/*.key/id_rsa*/credentials*/…)",
    "S011": "selected path is not repo-relative (absolute path or '..' traversal)",
    "S012": "selected path is excluded by .fusionignore and not force-included (! pattern) — dropped",
    "W101": "estimated tokens exceed budget_tokens (advisory; byte/4 heuristic)",
}


def list_rules() -> None:
    print("selection_lint.py rule catalogue (S### = blocking error, W### = advisory warning):")
    for rid, desc in RULES.items():
        print(f"  {rid}  {desc}")
    print(f"\nValid modes     : {', '.join(VALID_MODES)}")
    print(f"Deny-patterns   : {', '.join(DENY_GLOBS)}")
    print("Evidence gate   : every selected[] entry needs a non-empty 'reason' AND 'evidence' array")
    print("                  (e.g. 'grep:<match>', 'import:<path>', 'diff', 'test:<name>').")
    print(".fusionignore   : optional repo-local exclude file (gitignore-ish; '!' force-includes). A")
    print("                  selected file it excludes is dropped (S012) even with valid evidence.")


def is_nonempty_str(value) -> bool:
    return isinstance(value, str) and value.strip() != ""


def is_positive_int(value) -> bool:
    # bool is a subclass of int — reject True/False masquerading as 1/0.
    return isinstance(value, int) and not isinstance(value, bool) and value > 0


def matches_deny(path: str) -> bool:
    base = os.path.basename(path)
    for glob in DENY_GLOBS:
        # Match the basename (catches `cfg/.env.prod` -> base `.env.prod`) and the full path (catches a
        # `secrets/` dir component). NOT `*/`+glob — fnmatch's `*` crosses `/`, so `.env*` would wrongly
        # trip a directory like `app/.environment/…`; the basename check already covers the real cases.
        if fnmatch.fnmatch(base, glob) or fnmatch.fnmatch(path, glob):
            return True
    return False


def is_unsafe_path(path: str) -> bool:
    """A selected path must be repo-relative: not absolute, no '..' segment. The manifest drives what gets
    read into a shared context pack, so an absolute or escaping path is an exfiltration vector
    (context-discovery.md / safety.md: never private absolute paths)."""
    p = path.strip().replace("\\", "/")
    if os.path.isabs(p) or (len(p) >= 2 and p[1] == ":"):   # POSIX absolute, or a Windows drive (C:/…)
        return True
    return ".." in p.split("/")


def find_fusionignore(manifest_path: str) -> str | None:
    """Locate a .fusionignore by walking up from the manifest's directory to the repo root (a dir with a
    .git), capped at 6 levels so a symlinked skill can't reach into $HOME. Returns the path or None."""
    d = os.path.dirname(os.path.abspath(manifest_path)) or "."
    for _ in range(6):
        cand = os.path.join(d, ".fusionignore")
        if os.path.isfile(cand):
            return cand
        if os.path.isdir(os.path.join(d, ".git")):   # repo boundary — stop, don't escape the repo
            break
        parent = os.path.dirname(d)
        if parent == d:                              # filesystem root
            break
        d = parent
    return None


def load_ignore_patterns(path: str) -> list[tuple[str, bool]]:
    """Parse a .fusionignore (gitignore-ish). Returns ordered (pattern, is_negation) tuples. Blank lines
    and '#' comments are skipped; a leading '!' marks a force-include (negation)."""
    patterns: list[tuple[str, bool]] = []
    try:
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                s = line.strip()
                if not s or s.startswith("#"):
                    continue
                neg = s.startswith("!")
                if neg:
                    s = s[1:].strip()
                if s:
                    patterns.append((s.rstrip("/"), neg))
    except OSError:
        return []
    return patterns


def is_ignored(path: str, patterns: list[tuple[str, bool]]) -> bool:
    """gitignore-style last-match-wins: a later matching rule overrides an earlier one; a '!' rule
    force-includes. A bare pattern matches the full repo-relative path, its basename, or any path under a
    matching directory prefix."""
    p = path.strip().replace("\\", "/").lstrip("./")
    base = os.path.basename(p)
    ignored = False
    for pat, neg in patterns:
        hit = (
            fnmatch.fnmatch(p, pat)
            or fnmatch.fnmatch(base, pat)
            or fnmatch.fnmatch(p, pat + "/*")   # directory prefix: 'build' matches 'build/x.js'
            or p == pat
        )
        if hit:
            ignored = not neg
    return ignored


def valid_lines(value) -> bool:
    """A 'lines' value is valid iff it is 'START-END' with 1 <= START <= END (both positive ints)."""
    if not isinstance(value, str):
        return False
    parts = value.strip().split("-")
    if len(parts) != 2:
        return False
    a, b = parts[0].strip(), parts[1].strip()
    if not (a.isdigit() and b.isdigit()):
        return False
    start, end = int(a), int(b)
    return 1 <= start <= end


def estimate_tokens(path: str) -> int | None:
    """Cheap token estimate ceil(bytes/4*1.05) — same heuristic as context-pack-format.md. Returns None
    if the file does not exist on disk (we only estimate what we can actually measure; never guess)."""
    try:
        nbytes = os.path.getsize(path)
    except OSError:
        return None
    return math.ceil(nbytes / 4 * 1.05)


def entry_label(idx: int, entry) -> str:
    if isinstance(entry, dict) and is_nonempty_str(entry.get("path")):
        return entry["path"].strip()
    return f"selected[{idx}]"


def lint(path: str) -> int:
    try:
        with open(path, encoding="utf-8") as fh:
            raw = fh.read()
    except OSError as exc:
        print(f"error: cannot read {path}: {exc}", file=sys.stderr)
        return 2

    errors: list[str] = []
    warnings: list[str] = []

    # S001 — must parse as JSON. A parse failure is terminal; nothing else can be checked.
    try:
        data = json.loads(raw)
    except json.JSONDecodeError as exc:
        print(f"error: S001: {RULES['S001']}: {exc}", file=sys.stderr)
        print(f"\nFAIL: 1 error(s), 0 warning(s) in {path}", file=sys.stderr)
        return 1
    if not isinstance(data, dict):
        print(f"error: S001: {RULES['S001']}: top-level value is not an object", file=sys.stderr)
        print(f"\nFAIL: 1 error(s), 0 warning(s) in {path}", file=sys.stderr)
        return 1

    # S002 — task.
    if not is_nonempty_str(data.get("task")):
        errors.append(f"S002: {RULES['S002']}")

    # S003 — budget_tokens.
    budget = data.get("budget_tokens")
    if not is_positive_int(budget):
        errors.append(f"S003: {RULES['S003']} -> {budget!r}")

    # S004 — selected array.
    selected = data.get("selected")
    if not isinstance(selected, list) or not selected:
        errors.append(f"S004: {RULES['S004']}")
        selected = []

    # S012 input — load repo-local .fusionignore once (if present). Files it excludes are dropped unless
    # force-included with a '!' rule — a repo-local way to keep big vendored/build dirs out of every pack.
    ignore_file = find_fusionignore(path)
    ignore_patterns = load_ignore_patterns(ignore_file) if ignore_file else []

    total_est = 0
    for idx, entry in enumerate(selected):
        label = entry_label(idx, entry)
        if not isinstance(entry, dict):
            errors.append(f"S005: selected[{idx}] is not an object")
            continue

        epath = entry.get("path")
        if not is_nonempty_str(epath):
            errors.append(f"S005: selected[{idx}] {RULES['S005']}")
            epath = None

        # S010 — secrets deny-pattern. Check before anything else uses the path.
        if epath is not None and matches_deny(epath.strip()):
            errors.append(f"S010: '{label}' {RULES['S010']}")

        # S011 — repo-relative only: no absolute paths, no '..' traversal (never read outside the repo).
        if epath is not None and is_unsafe_path(epath):
            errors.append(f"S011: '{label}' {RULES['S011']}")

        # S012 — excluded by .fusionignore and not force-included. A selected file the repo says never
        # belongs in context is a curation error even with valid evidence; '!' in .fusionignore overrides.
        if epath is not None and ignore_patterns and is_ignored(epath.strip(), ignore_patterns):
            errors.append(f"S012: '{label}' {RULES['S012']}")

        # S006 — reason. THE GATE, part 1.
        if not is_nonempty_str(entry.get("reason")):
            errors.append(f"S006: '{label}' {RULES['S006']}")

        # S007 — evidence. THE GATE, part 2: a non-empty array of non-empty strings.
        evidence = entry.get("evidence")
        if (not isinstance(evidence, list) or not evidence
                or not all(is_nonempty_str(e) for e in evidence)):
            errors.append(f"S007: '{label}' {RULES['S007']}")

        # S008 — mode.
        mode = entry.get("mode")
        if mode not in VALID_MODES:
            errors.append(f"S008: '{label}' {RULES['S008']} -> {mode!r}")

        # S009 — slice requires a valid lines range.
        if mode == "slice" and not valid_lines(entry.get("lines")):
            errors.append(f"S009: '{label}' {RULES['S009']} -> {entry.get('lines')!r}")

        # W101 input — accumulate per-file estimate for files that exist on disk.
        if epath is not None:
            est = estimate_tokens(epath.strip())
            if est is not None:
                total_est += est

    # W101 — advisory: estimated tokens over budget. Only meaningful when budget is a real positive int
    # AND at least one selected file existed on disk to measure.
    if is_positive_int(budget) and total_est > 0 and total_est > budget:
        warnings.append(
            f"W101: {RULES['W101']}: estimated {total_est} tokens for on-disk files > budget {budget}")

    for w in warnings:
        print(f"warning: {w}", file=sys.stderr)
    if errors:
        for e in errors:
            print(f"error: {e}", file=sys.stderr)
        print(f"\nFAIL: {len(errors)} error(s), {len(warnings)} warning(s) in {path}", file=sys.stderr)
        return 1
    print(f"OK: {path} is a valid selection manifest ({len(warnings)} warning(s)).")
    return 0


def main(argv: list[str]) -> int:
    args = argv[1:]
    if not args or args[0] in ("-h", "--help"):
        print(__doc__)
        return 0 if args[:1] in (["-h"], ["--help"]) else 2
    if args[0] == "--list-rules":
        list_rules()
        return 0
    if len(args) != 1:
        print("usage: selection_lint.py <manifest.json> | --list-rules | --help", file=sys.stderr)
        return 2
    return lint(args[0])


if __name__ == "__main__":
    sys.exit(main(sys.argv))
