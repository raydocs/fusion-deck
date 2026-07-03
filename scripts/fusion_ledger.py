#!/usr/bin/env python3
"""fusion_ledger.py - local run ledger for fusion-deck v2.

The ledger is private-by-default local state under .fusion/runs/. Because it
copies full panel prompts (which can embed a proprietary diff), this script
writes a self-ignoring `.gitignore` (containing `*`) into the ledger root on
first use, so a plain `git add .` in the user's repo never commits it.
It records routing, workflow, panel, verifier, timing, and artifact pointers so
router policy can improve without training an answer model.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import shutil
import sys
from pathlib import Path
from typing import Any


def repo_root() -> Path:
    here = Path.cwd()
    for path in (here, *here.parents):
        if (path / ".git").exists():
            return path
    return here


def utc_stamp() -> str:
    return dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H-%M-%SZ")


def slugify(text: str, fallback: str = "run") -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")
    return (slug[:48].rstrip("-") or fallback)


def out_root(path: str | None) -> Path:
    root = Path(path) if path else repo_root() / ".fusion" / "runs"
    root.mkdir(parents=True, exist_ok=True)
    # Self-ignoring ledger: run dirs hold full panel prompts (possibly a proprietary diff), so make
    # the privacy claim true in the USER'S repo too, not just in checkouts that ignore .fusion/.
    gitignore = root / ".gitignore"
    if not gitignore.exists():
        try:
            gitignore.write_text("*\n", encoding="utf-8")
        except OSError:
            pass
    return root


def parse_kv_manifest(path: Path) -> dict[str, str]:
    data: dict[str, str] = {}
    if not path.exists():
        return data
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if not raw or raw.startswith("#") or "=" not in raw:
            continue
        key, value = raw.split("=", 1)
        key = key.strip()
        if key:
            data[key] = value.strip()
    return data


def copy_artifact(path: str | None, dest_dir: Path, label: str) -> str | None:
    if not path:
        return None
    src = Path(path)
    if not src.exists():
        return None
    safe_label = slugify(label, fallback="artifact")
    suffix = src.suffix or ".txt"
    dest = dest_dir / f"{safe_label}{suffix}"
    shutil.copy2(src, dest)
    try:
        return str(dest.relative_to(repo_root()))
    except ValueError:
        return str(dest)


def cmd_new(args: argparse.Namespace) -> int:
    task = args.task or ""
    workflow = args.workflow or "unknown"
    root = out_root(args.out_root)
    base_run_id = f"{utc_stamp()}_{slugify(workflow)}_{slugify(task, 'task')[:24]}"
    run_id = base_run_id
    run_dir = root / run_id
    suffix = 2
    while run_dir.exists():
        run_id = f"{base_run_id}_{suffix}"
        run_dir = root / run_id
        suffix += 1
    run_dir.mkdir(parents=True, exist_ok=False)

    artifacts: dict[str, str | None] = {}
    artifacts["prompt"] = copy_artifact(args.prompt, run_dir, "prompt")
    artifacts["panel_manifest"] = copy_artifact(args.manifest, run_dir, "panel_manifest")
    for item in args.artifact or []:
        if "=" in item:
            label, path = item.split("=", 1)
        else:
            label, path = Path(item).stem, item
        artifacts[label] = copy_artifact(path, run_dir, label)

    panel_manifest = parse_kv_manifest(Path(args.manifest)) if args.manifest else {}
    now = dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
    manifest: dict[str, Any] = {
        "schema_version": 1,
        "run_id": run_id,
        "created_at": now,
        "command": args.command,
        "workflow": workflow,
        "task": task,
        "task_type": args.task_type,
        "risk": args.risk,
        "verifiability": args.verifiability,
        "router_reason": args.router_reason or [],
        "realized_panel_state": panel_manifest.get("REALIZED_PANEL_STATE"),
        "requested_panel_mode": panel_manifest.get("REQUESTED_PANEL_MODE"),
        "realized_panel_mode": panel_manifest.get("REALIZED_PANEL_MODE"),
        "participants": panel_manifest.get("CLI_PARTICIPANTS"),
        "absent": panel_manifest.get("ABSENT"),
        "artifacts": {k: v for k, v in artifacts.items() if v},
        "panel_manifest": panel_manifest,
    }
    (run_dir / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    if args.json:
        print(json.dumps({"run_id": run_id, "run_dir": str(run_dir)}, sort_keys=True))
    else:
        print(f"RUN_ID={run_id}")
        print(f"RUN_DIR={run_dir}")
    return 0


def find_runs(root: Path) -> list[Path]:
    if not root.exists():
        return []
    return sorted([p for p in root.iterdir() if (p / "manifest.json").is_file()])


def load_manifest(path: Path) -> dict[str, Any]:
    return json.loads((path / "manifest.json").read_text(encoding="utf-8"))


def cmd_show(args: argparse.Namespace) -> int:
    root = out_root(args.out_root)
    runs = find_runs(root)
    if not runs:
        print("fusion_ledger: no runs found", file=sys.stderr)
        return 1
    target = runs[-1] if args.run_id == "latest" else root / args.run_id
    if not (target / "manifest.json").is_file():
        print(f"fusion_ledger: run not found: {args.run_id}", file=sys.stderr)
        return 1
    print(json.dumps(load_manifest(target), indent=2, sort_keys=True))
    return 0


def cmd_summarize(args: argparse.Namespace) -> int:
    root = out_root(args.out_root)
    runs = find_runs(root)[-args.last :]
    if not runs:
        print("RUNS=0")
        return 0
    print(f"RUNS={len(runs)}")
    for path in runs:
        data = load_manifest(path)
        print(
            "\t".join(
                [
                    data.get("run_id", path.name),
                    data.get("command") or "unknown",
                    data.get("workflow") or "unknown",
                    data.get("task_type") or "unknown",
                    data.get("risk") or "unknown",
                    data.get("realized_panel_state") or data.get("realized_panel_mode") or "unknown",
                ]
            )
        )
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Create and inspect local fusion-deck run ledger entries.")
    parser.add_argument("--out-root", help="ledger root (default: .fusion/runs under repo root)")
    sub = parser.add_subparsers(dest="cmd", required=True)

    new = sub.add_parser("new", help="create a run ledger entry")
    new.add_argument("--command", required=True)
    new.add_argument("--workflow", required=True)
    new.add_argument("--task", default="")
    new.add_argument("--task-type", default="unknown")
    new.add_argument("--risk", default="unknown")
    new.add_argument("--verifiability", default="unknown")
    new.add_argument("--router-reason", action="append", default=[])
    new.add_argument("--manifest")
    new.add_argument("--prompt")
    new.add_argument("--artifact", action="append", help="copy artifact into run dir, optionally label=path")
    new.add_argument("--json", action="store_true")
    new.set_defaults(func=cmd_new)

    show = sub.add_parser("show", help="print one manifest as JSON")
    show.add_argument("run_id", nargs="?", default="latest")
    show.set_defaults(func=cmd_show)

    summary = sub.add_parser("summarize", help="print a compact summary of recent runs")
    summary.add_argument("--last", type=int, default=20)
    summary.set_defaults(func=cmd_summarize)
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
