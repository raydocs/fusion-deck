#!/usr/bin/env bash
# install.sh — install fusion-deck as a Claude Code skill (idempotent).
#
# Symlinks this repo into your Claude Code skills directory so the /fusion* commands are available.
# No private paths or secrets are hardcoded — the target is derived from $HOME or $CLAUDE_SKILLS_DIR.
#
# Usage:
#   bash install.sh              # symlink into ~/.claude/skills/fusion-deck
#   CLAUDE_SKILLS_DIR=/path bash install.sh   # install into a custom skills dir
#   bash install.sh --copy       # copy instead of symlink

set -uo pipefail

src="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The skill name is taken from SKILL.md (which the smoke test requires to equal the install dir), NOT
# from the clone folder name — so cloning into any directory still installs as the canonical skill.
name="$(awk '/^---$/{n++; next} n==1 && /^name:/{sub(/^name:[[:space:]]*/,""); gsub(/[[:space:]]/,""); print; exit}' "$src/SKILL.md")"
name="${name:-fusion-deck}"
skills_dir="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
dest="$skills_dir/$name"
mode="symlink"
[ "${1:-}" = "--copy" ] && mode="copy"

echo "== install fusion-deck =="
echo "source : $src"
echo "target : $dest  ($mode)"

mkdir -p "$skills_dir"

if [ -e "$dest" ] || [ -L "$dest" ]; then
  if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
    echo "already linked — nothing to do."
  else
    echo "note: $dest already exists. Remove it first if you want to replace it:"
    echo "    rm -rf \"$dest\"   # then re-run"
    exit 1
  fi
else
  if [ "$mode" = "copy" ]; then
    cp -R "$src" "$dest"
  else
    ln -s "$src" "$dest"
  fi
  echo "installed."
fi

chmod +x "$src"/scripts/*.sh "$src"/scripts/*.py 2>/dev/null || true

# --- slash-command wrappers --------------------------------------------------------------------------
# A skill's own commands/*.md are NOT slash commands. Claude Code registers /<name> from a skill dir OR
# from ~/.claude/commands/<name>.md. So generate thin wrapper commands that delegate to this skill's
# procedures. Override the target dir with CLAUDE_COMMANDS_DIR. (If a separate skill named `fusion` is
# also installed, that skill takes precedence for /fusion — this skill does not assume one is present.)
commands_dir="${CLAUDE_COMMANDS_DIR:-$HOME/.claude/commands}"
mkdir -p "$commands_dir"
echo
echo "-- slash-command wrappers -> $commands_dir --"
gen_wrapper() {
  cmd="$1"; desc="$2"; hint="$3"
  cat > "$commands_dir/$cmd.md" <<EOF
---
description: $desc
argument-hint: $hint
---
Run the **fusion-deck** skill's \`/$cmd\` procedure.

This skill is installed at: $dest
First Read the procedure file at $dest/commands/$cmd.md and follow it EXACTLY. IMPORTANT: any
\`scripts/…\` or \`references/…\` path in that procedure (or in the references it loads) is relative to the
skill root above — run scripts as \`bash $dest/scripts/<name>\` and read references from
\`$dest/references/<name>\`, NOT relative to your current working directory.

Input: \$ARGUMENTS
EOF
  echo "  wrote /$cmd"
}
gen_wrapper fusion             "Fan a hard question to the premium model panel (Opus 4.8 + GPT-5.5 + Gemini 3.1 Pro), Opus judges and writes the answer." "<the hard question or task>"
gen_wrapper fusion-review      "Audit code/a plan with the premium panel (Opus 4.8 + GPT-5.5 + Gemini 3.1 Pro), Opus-judged structured findings." "<diff, files, or design to review>"
gen_wrapper fusion-investigate "Investigate a bug/'why is it like this' evidence-first; the panel adjudicates competing hypotheses; ends at a root-cause report." "<the bug or question> [--panel]"
gen_wrapper fusion-plan        "Turn a vague request into a verifiable Claude Code Workflow Contract (not a Codex /goal)." "<the vague request> [--panel] [--deep]"
gen_wrapper fusion-context     "Build a RepoPrompt-style Context Pack (fixed order, density tiers, token budget)." "<task the pack is for> [paste|handoff|agent]"
gen_wrapper fusion-orchestrate "Decompose a task, dispatch scoped subagents, verify each, roll up (orchestrator never implements)." "<contract path or task> [--panel] [--worktrees]"
gen_wrapper fusion-optimize    "Measure→change→re-measure loop; baseline first, one attributed change per iteration, the panel calls continue/stop." "<metric + scope + stop criterion> [--cap N]"
gen_wrapper fusion-refactor    "Analyze structure, plan behavior-preserving steps, steer one agent through them (structure, not behavior)." "<files, directory, or system>"
gen_wrapper fusion-handoff     "Emit a Handoff Capsule (purpose, summary, files, verification, risks, next steps)." "<what to hand off>"
gen_wrapper fusion-remind      "Re-anchor a drifting session: a one-screen cheat-sheet of which fusion command fits which situation, plus the invariants." "[a situation to route]"

echo
echo "-- panel availability on this machine --"
bash "$src/scripts/detect_panel.sh" || true
echo
echo "Done. Reload in Claude Code with /reload-skills (or restart). Then these slash commands work:"
echo "      /fusion-review  /fusion-investigate  /fusion-plan  /fusion-context"
echo "      /fusion-orchestrate  /fusion-optimize  /fusion-refactor  /fusion-handoff  /fusion-remind"
echo "      Plain fusion: use the existing /fusion skill, or invoke /fusion-deck."
echo "      Offline self-check anytime:  bash \"$src/scripts/smoke_test.sh\""
echo "      For the PREMIUM triple panel, install the codex and gemini CLIs (see detect_panel output)."
