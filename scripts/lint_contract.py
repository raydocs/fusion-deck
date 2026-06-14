#!/usr/bin/env python3
"""lint_contract.py — lint a Claude Code Workflow Contract (the /fusion-plan output).

This is the SINGLE SOURCE OF TRUTH for contract lint rules. references/contract-lint-rules.md is a
pointer to this file — do not duplicate the rules in prose (they would drift and false-green).

Design (audited): STRICT on structure, ADVISORY on quality.
  * Block (exit 1) on deterministic structural facts: a missing required section, a work item missing
    a required field, an empty/placeholder required field, an invalid status value, or a forbidden
    `/goal` reference (Claude Code has no /goal — the contract must replace it, not invoke it).
  * Warn (exit 0) on heuristic quality smells (a finishing criterion that looks unverifiable), because
    a regex heuristic WILL have false positives and a false-red makes people disable the linter.

Usage:
  lint_contract.py <contract.md>      lint a contract file
  lint_contract.py --list-rules       print the rule catalogue and exit
  lint_contract.py -h | --help        this help

Exit codes: 0 = ok (warnings allowed) | 1 = lint failure (>=1 error) | 2 = usage error
"""

from __future__ import annotations

import re
import sys

# Required ## sections. Each maps to the set of accepted (case-insensitive) heading texts / synonyms.
REQUIRED_SECTIONS: dict[str, tuple[str, ...]] = {
    "Objective": ("objective",),
    "Finishing Criteria": ("finishing criteria", "definition of done", "acceptance criteria"),
    "Current State": ("current state", "current state ledger", "state ledger", "current truth"),
    "Work Items": ("work items", "work item"),
    "Escape Hatch": ("escape hatch", "pause conditions"),
    "Verifier Plan": ("verifier plan", "verification plan", "verify plan"),
}

# Each work item must carry these fields with non-empty, non-placeholder content.
WORK_ITEM_FIELDS = ("Goal", "Done-when", "Key files", "Dependencies", "Size", "Status")

# qiaomu honest-status vocabulary. A work item Status must be one of these (brackets optional).
VALID_STATUSES = ("todo", "doing", "done", "blocked", "incomplete", "abandoned")

# An [incomplete] work item must carry this honesty payload in its body (the qiaomu discipline).
INCOMPLETE_PAYLOAD = ("reason", "proof", "attempted", "impact", "next")

# Unfilled-template markers → treated as empty. NOTE: "none"/"n/a" are NOT here — they are legitimate
# answers (e.g. "Dependencies: none"). Status is exempt from this check entirely (it has its own C006).
PLACEHOLDERS = {"", "tbd", "todo", "...", "-", "—", "?", "xxx", "fixme"}

# Tokens that make a finishing criterion look concretely verifiable (advisory check only).
VERIFIABLE_HINTS = (
    "test", "grep", "run ", "runs", "exit", "returns", "passes", "compile", "py_compile", "bash -n",
    "http", "status code", "assert", "lint", "build", "output", "file:", ".py", ".sh", ".md", ".ts",
    ".js", "diff", "screenshot", "log", "==", "<=", ">=", "%", "ms", "request",
)
# Vague words that, alone, do not make a criterion verifiable.
VAGUE_WORDS = ("works", "working", "clean", "good", "nice", "proper", "properly", "fine", "ok", "done", "better")

# Forbidden: the Codex /goal slash command. Match it as a command token (preceded by start/space/
# backtick/paren, not followed by a word char or hyphen) so paths like `runs/goal/` don't false-trip.
GOAL_RE = re.compile(r"(?<![\w/])/goal(?![\w-])", re.IGNORECASE)

RULES = {
    "C001": "missing required section",
    "C002": "no work items found under Work Items",
    "C003": "work item missing a required field",
    "C004": "required field is empty or a placeholder (TBD/TODO/FIXME/…)",
    "C005": "forbidden /goal reference (Claude Code has no /goal; the contract replaces it)",
    "C006": "invalid Status value (must be one of: %s)" % ", ".join(VALID_STATUSES),
    "C007": "[incomplete] work item missing its reason/proof/attempted/impact/next-decision payload",
    "C008": "work item Size must be 'small' or 'large'",
    "W101": "finishing criterion looks unverifiable (advisory)",
}


def list_rules() -> None:
    print("lint_contract.py rule catalogue (C### = blocking error, W### = advisory warning):")
    for rid, desc in RULES.items():
        print(f"  {rid}  {desc}")
    print(f"\nRequired sections : {', '.join(REQUIRED_SECTIONS)}")
    print(f"Work-item fields  : {', '.join(WORK_ITEM_FIELDS)}")
    print(f"Valid statuses    : {', '.join(VALID_STATUSES)}")


def split_sections(lines: list[str]) -> list[tuple[int, str, list[str]]]:
    """Return [(level, heading_text, body_lines)] for each ATX heading section."""
    sections: list[tuple[int, str, list[str]]] = []
    cur_level, cur_head, cur_body = 0, "", []
    for line in lines:
        m = re.match(r"^(#{1,6})\s+(.*?)\s*#*\s*$", line)
        if m:
            if cur_head or cur_body:
                sections.append((cur_level, cur_head, cur_body))
            cur_level, cur_head, cur_body = len(m.group(1)), m.group(2).strip(), []
        else:
            cur_body.append(line)
    if cur_head or cur_body:
        sections.append((cur_level, cur_head, cur_body))
    return sections


def find_section(sections, synonyms) -> tuple[int, str, list[str]] | None:
    for sec in sections:
        head = sec[1].lower().strip().lstrip("0123456789.) ").strip()
        if any(head == syn or head.startswith(syn + " ") for syn in synonyms):
            return sec
    return None


def field_value(block: list[str], field: str) -> str | None:
    """Extract the value of 'Field:' from a work-item block (value may span continuation lines)."""
    pat = re.compile(r"^\s*[-*]?\s*\*{0,2}%s\*{0,2}\s*:\s*(.*)$" % re.escape(field), re.IGNORECASE)
    for line in block:
        m = pat.match(line)
        if m:
            return m.group(1).strip().strip("`*_ ")
    return None


def is_placeholder(value: str | None) -> bool:
    return value is None or value.strip().lower() in PLACEHOLDERS


def incomplete_value(body: list[str], key: str) -> str | None:
    """Value for an [incomplete]-payload key — same line as the key, or an indented continuation line.
    Returns None if the key line is absent, '' if the key is present but carries no value."""
    key_re = re.compile(r"^(\s*)[-*]?\s*%s\b[\w /-]*:(.*)$" % key, re.IGNORECASE)
    for i, line in enumerate(body):
        m = key_re.match(line)
        if not m:
            continue
        indent, same = len(m.group(1)), m.group(2).strip()
        if same:
            return same
        for nxt in body[i + 1:]:
            if not nxt.strip():
                continue
            # a new bullet, a heading, or a same/less-indented line is NOT this key's continuation
            if re.match(r"^\s*[-*]\s", nxt) or nxt.lstrip().startswith("#") \
               or (len(nxt) - len(nxt.lstrip())) <= indent:
                break
            return nxt.strip()
        return ""
    return None


def lint(path: str) -> int:
    try:
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
    except OSError as exc:
        print(f"error: cannot read {path}: {exc}", file=sys.stderr)
        return 2

    lines = text.splitlines()
    sections = split_sections(lines)
    errors: list[str] = []
    warnings: list[str] = []

    # C005 — forbidden /goal reference, anywhere in the document.
    for i, line in enumerate(lines, 1):
        if GOAL_RE.search(line):
            errors.append(f"C005 line {i}: {RULES['C005']} -> {line.strip()!r}")

    # C001 — required sections present.
    present = {}
    for canonical, synonyms in REQUIRED_SECTIONS.items():
        sec = find_section(sections, synonyms)
        if sec is None:
            errors.append(f"C001: {RULES['C001']}: '## {canonical}'")
        else:
            present[canonical] = sec

    # C002/C003/C004/C006 — work items.
    if "Work Items" in present:
        wi_level = present["Work Items"][0]
        idx = sections.index(present["Work Items"])
        # Work items are the deeper subsections that follow, until the next same-or-higher heading.
        items = []
        for sec in sections[idx + 1:]:
            if sec[0] <= wi_level:
                break
            if sec[0] == wi_level + 1:
                items.append(sec)
        if not items:
            errors.append(f"C002: {RULES['C002']} (expected '{'#' * (wi_level + 1)} <item>' subsections)")
        for level, head, body in items:
            label = head or "(unnamed)"
            for field in WORK_ITEM_FIELDS:
                val = field_value(body, field)
                if val is None:
                    errors.append(f"C003: work item '{label}' missing field '{field}'")
                    continue
                if field == "Status":
                    # Status has its own value check (C006); it is exempt from the placeholder check
                    # so a valid bare status like "todo" isn't mistaken for an unfilled field.
                    norm = val.strip().lower().strip("[]").strip()
                    if norm not in VALID_STATUSES:
                        errors.append(f"C006: work item '{label}' Status {val!r} invalid")
                    elif norm == "incomplete":
                        # Each payload key must be present with a REAL value (same line OR an indented
                        # continuation). `\b` rejects prefix-junk ("reasoning:"); the value must not be
                        # empty, a placeholder, or punctuation-only (must contain an alphanumeric char).
                        miss = []
                        for p in INCOMPLETE_PAYLOAD:
                            v = incomplete_value(body, p)
                            if v is None or is_placeholder(v) or not re.search(r"[0-9A-Za-z]", v):
                                miss.append(p)
                        if miss:
                            errors.append(
                                f"C007: work item '{label}' is [incomplete] but missing payload: {', '.join(miss)}")
                elif is_placeholder(val):
                    errors.append(f"C004: work item '{label}' field '{field}' is empty/placeholder")
                elif field == "Size" and val.strip().lower().rstrip(".") not in ("small", "large"):
                    errors.append(f"C008: work item '{label}' Size {val!r} must be 'small' or 'large'")

    # W101 — advisory: finishing criteria that look unverifiable.
    if "Finishing Criteria" in present:
        for line in present["Finishing Criteria"][2]:
            stripped = line.strip().lstrip("-*0123456789.) ").strip()
            if not stripped:
                continue
            low = stripped.lower()
            has_hint = any(h in low for h in VERIFIABLE_HINTS)
            looks_vague = any(re.search(r"\b%s\b" % re.escape(w), low) for w in VAGUE_WORDS)
            if looks_vague and not has_hint:
                warnings.append(f"W101: {RULES['W101']}: {stripped!r}")

    for w in warnings:
        print(f"warning: {w}", file=sys.stderr)
    if errors:
        for e in errors:
            print(f"error: {e}", file=sys.stderr)
        print(f"\nFAIL: {len(errors)} error(s), {len(warnings)} warning(s) in {path}", file=sys.stderr)
        return 1
    print(f"OK: {path} is a valid Workflow Contract ({len(warnings)} warning(s)).")
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
        print("usage: lint_contract.py <contract.md> | --list-rules | --help", file=sys.stderr)
        return 2
    return lint(args[0])


if __name__ == "__main__":
    sys.exit(main(sys.argv))
