#!/usr/bin/env python3
"""route_task.py - explainable rule router for fusion-deck v2."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any


RISK_WORDS = {
    "high": (
        "security",
        "auth",
        "authentication",
        "authorization",
        "payment",
        "billing",
        "money",
        "migration",
        "data loss",
        "delete",
        "production",
        "privacy",
        "compliance",
        "secret",
    ),
    "medium": ("database", "schema", "api", "refactor", "performance", "latency", "concurrency", "locking"),
}


# CJK trigger words are matched with plain substring checks: Python's \b never matches between
# two CJK word characters, so a \b-wrapped CJK alternation silently never fires inside a sentence.
CJK_MAX_QUALITY = ("开全桌", "最高质量")
CJK_UNCERTAIN = ("不知道", "不确定")


def has_any(text: str, words: tuple[str, ...]) -> bool:
    """Whole-word match — 'auth' must not fire inside 'author', 'api' not inside 'rapid'."""
    return any(re.search(rf"\b{re.escape(w)}\b", text) for w in words)


def classify(task: str, quality: str = "balanced") -> dict[str, Any]:
    text = task.lower()
    reason: list[str] = []
    task_type = "answer"
    risk = "low"
    verifiability = "weak"
    context_need = "none"
    ambiguity = "clear"
    budget = quality
    workflow = "single_model"
    initial_panel_size = 1
    escalation_threshold = "none"
    expected_cost = "low"
    expected_latency = "low"
    confidence = "medium"
    early_stop_allowed = True

    if has_any(text, RISK_WORDS["high"]):
        risk = "high"
        reason.append("high-risk keyword present")
    elif has_any(text, RISK_WORDS["medium"]):
        risk = "medium"
        reason.append("medium-risk keyword present")

    if re.search(r"\b(review|audit|diff|staged|pull request|pr)\b", text):
        task_type = "code_review"
        workflow = "pair_review_then_verify"
        verifiability = "high"
        context_need = "repo_packet"
        initial_panel_size = 2
        escalation_threshold = "triple_on_blocking_conflict_or_failed_verifier"
        expected_cost = "medium"
        expected_latency = "medium"
        reason.append("review/diff intent")
    elif re.search(r"\b(root cause|why|bug|flaky|wrong|broken|fails?|error|investigate)\b", text):
        task_type = "bug_investigation"
        workflow = "evidence_first_investigate"
        verifiability = "high" if re.search(r"\b(repro|test|trace|log|stack)\b", text) else "weak"
        context_need = "repo_packet"
        initial_panel_size = 1
        escalation_threshold = "panel_only_if_two_hypotheses_survive_evidence"
        expected_cost = "medium"
        expected_latency = "medium"
        reason.append("evidence-first investigation intent")
    elif re.search(r"\b(optimi[sz]e|latency|p95|benchmark|faster|smaller|memory|throughput)\b", text):
        task_type = "optimization"
        workflow = "measure_change_remeasure"
        verifiability = "high"
        context_need = "repo_packet"
        initial_panel_size = 1
        escalation_threshold = "panel_at_stop_continue_decision"
        expected_cost = "medium"
        expected_latency = "medium"
        reason.append("optimization requires measurement loop")
    elif re.search(r"\b(implement|add|fix|change|build|ship)\b", text):
        task_type = "implementation"
        workflow = "single_worker_verified"
        verifiability = "high" if re.search(r"\b(test|lint|typecheck|repro)\b", text) else "weak"
        context_need = "repo_packet"
        initial_panel_size = 1
        escalation_threshold = "pair_or_triple_on_failed_verifier_or_high_risk"
        expected_cost = "low-medium"
        expected_latency = "medium"
        reason.append("implementation intent")
    elif re.search(r"\b(architecture|trade-?off|should we|design|approach|locking|consistency)\b", text):
        task_type = "architecture"
        workflow = "pair_blind_panel"
        verifiability = "weak"
        context_need = "small_packet"
        initial_panel_size = 2
        escalation_threshold = "triple_on_high_risk_or_unresolved_contradiction"
        expected_cost = "medium"
        expected_latency = "medium"
        reason.append("architecture/trade-off intent")
    elif re.search(r"\b(context|handoff|summari[sz]e|pack)\b", text):
        task_type = "context_or_handoff"
        workflow = "single_model"
        context_need = "repo_packet"
        initial_panel_size = 1
        reason.append("mechanical summarization/context task")
    else:
        reason.append("default low-risk answer route")

    if (
        re.search(r"\b(max|maximum|ultra|full panel|hard question)\b", text)
        or any(w in text for w in CJK_MAX_QUALITY)
        or quality == "max"
    ):
        workflow = "ultra_two_round_panel" if quality == "max" or "ultra" in text else "full_blind_panel"
        initial_panel_size = 3
        expected_cost = "high"
        expected_latency = "high"
        escalation_threshold = "already_max_quality"
        early_stop_allowed = False
        reason.append("user requested maximum quality/full panel")
    elif risk == "high":
        if workflow in ("single_model", "single_worker_verified", "pair_blind_panel", "pair_review_then_verify"):
            workflow = "full_blind_panel"
            initial_panel_size = 3
            expected_cost = "high"
            expected_latency = "high"
            early_stop_allowed = False
            reason.append("high risk upgrades to full panel")

    if re.search(r"\b(maybe|not sure|unclear|ambiguous)\b", text) or any(w in text for w in CJK_UNCERTAIN):
        ambiguity = "underspecified"
        reason.append("underspecified language")
    if context_need == "repo_packet" and re.search(r"\b(this|repo|project|codebase|our)\b", text):
        reason.append("repo-local context likely needed")

    if workflow in ("single_model", "single_worker_verified") and risk == "low":
        confidence = "high"
    elif workflow in ("full_blind_panel", "ultra_two_round_panel") and risk == "high":
        confidence = "high"
    else:
        confidence = "medium"

    return {
        "task_type": task_type,
        "risk": risk,
        "context_need": context_need,
        "verifiability": verifiability,
        "ambiguity": ambiguity,
        "budget": budget,
        "recommended_workflow": workflow,
        "initial_panel_size": initial_panel_size,
        "escalation_threshold": escalation_threshold,
        "expected_cost": expected_cost,
        "expected_latency": expected_latency,
        "confidence": confidence,
        "early_stop_allowed": early_stop_allowed,
        "reason": reason,
    }


def parse_cases(path: Path) -> list[dict[str, str]]:
    """Parse a tiny YAML subset used by tests/router_cases.yml."""
    cases: list[dict[str, str]] = []
    current: dict[str, str] | None = None
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("- "):
            if current:
                cases.append(current)
            current = {}
            line = line[2:].strip()
            if line and ":" in line:
                k, v = line.split(":", 1)
                current[k.strip()] = v.strip().strip('"')
        elif current is not None and ":" in line:
            k, v = line.split(":", 1)
            current[k.strip()] = v.strip().strip('"')
    if current:
        cases.append(current)
    return cases


def check_cases(path: Path) -> int:
    failures = 0
    for case in parse_cases(path):
        task = case.get("task", "")
        expected = case.get("workflow", "")
        quality = case.get("quality", "balanced")
        got = classify(task, quality=quality)["recommended_workflow"]
        if got == expected:
            print(f"PASS {case.get('id', task)} -> {got}")
        else:
            failures += 1
            print(f"FAIL {case.get('id', task)} expected {expected}, got {got}")
    return 1 if failures else 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Route a task to a fusion-deck v2 workflow.")
    parser.add_argument("--task", help="task text to route")
    parser.add_argument("--quality", choices=("fast", "balanced", "max"), default="balanced")
    parser.add_argument("--check", help="run router fixture checks")
    parser.add_argument("--list-rules", action="store_true")
    args = parser.parse_args()

    if args.list_rules:
        print("workflows: single_model, single_worker_verified, pair_review_then_verify, pair_blind_panel,")
        print("           evidence_first_investigate, measure_change_remeasure, full_blind_panel, ultra_two_round_panel")
        print("principle: rules choose workflow only; they never answer the task.")
        return 0
    if args.check:
        return check_cases(Path(args.check))
    if not args.task:
        print("route_task.py: --task is required unless --check/--list-rules is used", file=sys.stderr)
        return 2
    print(json.dumps(classify(args.task, quality=args.quality), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
