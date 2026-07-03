# Panel modes - intentional v2 panel choices

Pair panels are first-class workflows in v2. They are not degraded runs unless the requested pair could
not be realized.

| Mode | Meaning |
| --- | --- |
| `single_opus` | One Opus panelist/judge path. |
| `opus_self_consistency` | Two cold Opus panelist runs, then Opus judge. |
| `opus_gpt_pair` | Opus panelist + GPT/Codex panelist, then Opus judge. |
| `opus_gemini_pair` | Opus panelist + Gemini/Antigravity panelist, then Opus judge. |
| `gpt_gemini_pair_plus_opus_judge` | GPT + Gemini panelists, Opus as judge only. |
| `premium_triple` | Opus + GPT + Gemini, blind, then Opus judge. |
| `premium_wide` | **Opus ×2 (cold) + GPT + Gemini** — 4 panelists: cross-family diversity + same-model self-consistency. Max-quality single round. |
| `ultra_two_round` | **Wide** first round (Opus ×2 + GPT + Gemini), contradiction matrix, targeted probes, verifier, final judge. |

Scripts:

```bash
bash scripts/assert_panel.sh --mode opus_gpt_pair
out=$(mktemp -d "${TMPDIR:-/tmp}/fusion-panel.XXXXXX")   # fresh dir — fixed paths collide across sessions
bash scripts/run_panel.sh --mode opus_gpt_pair "$out/prompt.md" "$out" medium
```

`run_panel.sh` runs only external CLI panelists. The orchestrator still spawns Opus panelist(s) and
performs judgment. If a requested panelist fails at runtime the script exits **13** (honest manifest
written) unless `FUSION_ALLOW_DEGRADED=1` — see `references/degraded-mode.md`.
