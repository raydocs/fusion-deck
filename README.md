<p align="center">
  <img src="assets/readme/hero.svg" alt="fusion-deck sends one hard question to independent model panelists and produces a judged synthesis with a disclosed panel state" width="100%" />
</p>

# fusion-deck

**A Claude Code decision-and-execution skill that spends extra models only when the risk earns it.** It can fan a hard question to independent panelists, keep answers blind, have Claude judge the result, and disclose the panel that actually ran. Around that core are mechanical workflows for planning, context curation, investigation, orchestration, optimization, refactoring, and handoff.

It is Markdown procedures plus Bash / Python helpers—not an MCP server, model dashboard, or OpenRouter replacement.

## What ships

| Situation | Command | Default behavior |
| --- | --- | --- |
| Hard decision / trade-off | `/fusion` | Blind panel → judge |
| Let risk choose the workflow | `/fusion-auto` | Rule-based routing; escalate only when needed |
| Maximum-quality pass | `/fusion-ultra` | Wide panel, contradiction matrix, targeted probes, verifier |
| Review a diff or plan | `/fusion-review` | Panel-backed prioritized findings |
| Investigate a bug | `/fusion-investigate` | Evidence first; panel only if hypotheses survive |
| Turn a vague ask into a contract | `/fusion-plan` | Single-model Workflow Contract by default |
| Curate only relevant repo context | `/fusion-context` | Token-budgeted Context Pack |
| Execute a multi-step change | `/fusion-orchestrate` | Scoped agents with verify-before-next dispatch |
| Improve a measured metric | `/fusion-optimize` | Baseline → one change → re-measure |
| Preserve behavior while cleaning structure | `/fusion-refactor` | Analyze → plan → guided execution |
| Transfer work cleanly | `/fusion-handoff` | Handoff Capsule |
| Re-anchor a drifting session | `/fusion-remind` | Compact command / invariant map |

The exact contracts live in [`commands/`](commands/) and [`references/`](references/). The executable checks live in [`scripts/`](scripts/).

## Install

```bash
git clone https://github.com/raydocs/fusion-deck.git
bash fusion-deck/install.sh
```

By default this symlinks the repo to `~/.claude/skills/fusion-deck` and writes twelve wrappers to `~/.claude/commands/`. Then run `/reload-skills` in Claude Code or restart it.

Alternatives:

```bash
bash install.sh --copy       # install an allowlisted copy
bash install.sh --force      # replace an existing install
bash install.sh --uninstall  # remove skill + generated wrappers
```

`CLAUDE_SKILLS_DIR` and `CLAUDE_COMMANDS_DIR` override the destinations.

## Panel requirements and runtime honesty

Claude is the in-process panelist and judge. External seats are discovered from:

- `codex` for the GPT seat
- `agy` for the Gemini seat; legacy `gemini` is opt-in

A missing or failed seat is never silently presented as a full panel. Premium commands stop unless the required external CLIs are available; deliberate degraded execution requires `FUSION_ALLOW_DEGRADED=1`, and the result must still disclose `PANEL_STATE`. Runtime failures write a manifest and use a non-zero exit rather than fabricating success.

Check this machine without calling paid models:

```bash
bash scripts/detect_panel.sh
bash scripts/smoke_test.sh
```

## First use

```text
/fusion Should this checkout path use optimistic or pessimistic locking?
/fusion-auto review my staged diff
/fusion-plan add a health endpoint with tests
/fusion-context prepare the checkout code for another agent
/fusion-handoff authentication refactor
```

Use a panel for expensive-to-reverse judgment, not trivia. A common feature chain is:

```text
/fusion-plan → /fusion-context → /fusion-orchestrate → /fusion-handoff
```

## Safety boundaries

- Panel prompts may contain source code; review mode disables web access for untrusted diffs.
- Local ledgers live under `.fusion/runs/` and self-ignore; prompts and code should not be committed accidentally.
- Do not put credentials in prompts, Context Packs, command files, or manifests.
- All `scripts/…` paths in procedures resolve from the installed skill root, not the target project.

## Development verification

```bash
bash scripts/smoke_test.sh
python3 scripts/route_task.py --check tests/router_cases.yml
```

The smoke test is offline and must not invoke paid model calls.

## License

[MIT](LICENSE)
