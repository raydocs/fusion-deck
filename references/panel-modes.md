# Panel modes - intentional v2 panel choices

Pair panels are first-class workflows in v2. They are not degraded runs unless the requested pair could
not be realized.

| Mode | Meaning |
| --- | --- |
| `single_claude` | One Claude panelist/judge path. |
| `claude_self_consistency` | Two cold Claude panelist runs, then Claude judge. |
| `claude_gpt_pair` | Claude panelist + GPT/Codex panelist, then Claude judge. |
| `claude_gemini_pair` | Claude panelist + Gemini/Antigravity panelist, then Claude judge. |
| `gpt_gemini_pair_plus_claude_judge` | GPT + Gemini panelists, Claude as judge only. |
| `premium_triple` | Claude + GPT + Gemini, blind, then Claude judge. |
| `premium_wide` | **Claude ×2 (cold) + GPT + Gemini** — 4 panelists: cross-family diversity + same-model self-consistency. Max-quality single round. |
| `ultra_two_round` | **Wide** first round (Claude ×2 + GPT + Gemini), contradiction matrix, targeted probes, verifier, final judge. |

Scripts:

```bash
bash scripts/assert_panel.sh --mode claude_gpt_pair
out=$(mktemp -d "${TMPDIR:-/tmp}/fusion-panel.XXXXXX")   # fresh dir — fixed paths collide across sessions
bash scripts/run_panel.sh --mode claude_gpt_pair "$out/prompt.md" "$out" medium
```

`run_panel.sh` runs only external CLI panelists. The orchestrator still spawns Claude panelist(s) and
performs judgment. If a requested panelist fails at runtime the script exits **13** (honest manifest
written) unless `FUSION_ALLOW_DEGRADED=1` — see `references/degraded-mode.md`.
