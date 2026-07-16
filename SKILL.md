---
name: fusion-deck
description: Higher-confidence answers and careful execution. `/fusion` fans a hard question to a panel of top models and writes one judged cross-checked answer; `/fusion-review` audits the same way. Companions: `/fusion-auto` `/fusion-ultra` `/fusion-investigate` `/fusion-plan` `/fusion-context` `/fusion-orchestrate` `/fusion-optimize` `/fusion-refactor` `/fusion-handoff` `/fusion-remind`. Always discloses which models answered. Use whenever the user wants a multi-model / panel / ensemble answer — e.g. "run it through fusion", "fusion-review this", "fusion-plan", "fusion-context", "fusion-orchestrate", "fusion-handoff". Best for high-stakes, contested, or hard-to-reverse work.
---

# fusion-deck

A premium decision-and-execution toolkit. It does two things well: **think hard** (fan a question out to
the strongest models in parallel, blind, and let Opus 4.8 judge) and **orchestrate** (turn a vague ask
into a verifiable contract, curate context, decompose into scoped subagent work, verify each step, and
hand off cleanly). It is a Claude Code **skill** — markdown commands plus small bash/python helpers.
There is no MCP server, no UI, no OpenRouter, no model-config platform.

## The three lineages it fuses

It fuses three lineages — **panel→judge** (fusion-fable), **contract+honesty** (goal-meta; not Codex
`/goal`), and **context+orchestration** (RepoPrompt CE) — see README → "The three lineages".

## The panel and its honest-degrade rule

The PREMIUM panel is the full triple. Availability is reported by `scripts/detect_panel.sh` as a
`PANEL_STATE`:

| PANEL_STATE | Panel | Slug |
| --- | --- | --- |
| `PREMIUM` | Opus 4.8 + GPT-5.6 Sol + Gemini 3.1 Pro (`agy` by default) | `opus4.8-gpt5.6sol-gemini3.1pro` |
| `DEGRADED_OPUS_GPT5` | Opus 4.8 + GPT-5.6 Sol | `opus4.8-gpt5.6sol` |
| `DEGRADED_OPUS_GEMINI` | Opus 4.8 + Gemini 3.1 Pro | `opus4.8-gemini3.1pro` |
| `OPUS_ONLY` | two cold Opus 4.8 runs | `opus4.8-4.8` |

**The cardinal rule: never silently fake the premium triple.** Premium commands call
`scripts/assert_triple_panel.sh`, which hard-fails unless `codex` and a Gemini backend are present. An operator who
*knowingly* wants a smaller panel sets `FUSION_ALLOW_DEGRADED=1` — then the run proceeds but is loudly
marked degraded. The rule holds at **runtime** too: if a panelist fails mid-run (rate limit, timeout of
`FUSION_PANEL_TIMEOUT`, implausibly tiny output), the runner writes the honest manifest and exits **13**
unless degrade was explicitly allowed — stop and disclose, never silently continue. **Every panel answer
must disclose the PANEL_STATE it actually ran.** See `references/degraded-mode.md`.

## Commands — and where the panel is worth its cost

A triple panel costs ~N× tokens and runs as slow as its slowest panelist. So fan out **only where
independent cross-checking changes the answer's risk profile**; everywhere else, one model is correct.

| Command | What it does | Panel by default? |
| --- | --- | --- |
| `/fusion` | Fan a hard question to the panel; Opus judges and writes the answer. `--wide` adds a second cold Opus (4 panelists). | **Yes** |
| `/fusion-auto` | Route a task through v2: pick workflow, verify, and escalate only when needed. | Router decides |
| `/fusion-ultra` | Max-quality two-round workflow: **wide** blind panel (Opus ×2 + GPT + Gemini) → contradiction matrix → targeted probes → verifier. | **Yes + targeted probes** |
| `/fusion-review` | Audit code/a plan via the panel; structured, cross-checked findings. | **Yes** |
| `/fusion-investigate` | Evidence-first root-cause investigation; panel adjudicates competing hypotheses. | By exception — only when ≥2 hypotheses survive the evidence; `--panel` forces it |
| `/fusion-plan` | Turn a vague request into a Claude Code Workflow Contract; `--deep` adds involvement + a critique pass. | No — single model; `--panel` to escalate a genuinely ambiguous, high-stakes planning question |
| `/fusion-context` | Build a RepoPrompt-style Context Pack; `--discover` adds evidence-gated agentic curation. | No — curation is mechanical |
| `/fusion-orchestrate` | Decompose, dispatch scoped subagents, verify each, roll up; `--worktrees` isolates parallel items. | No — single-model orchestrator; `--panel` to review a thorny decomposition |
| `/fusion-optimize` | Measure→change→re-measure loop; the panel calls continue/stop at each decision point. | By exception — only at the stop/continue decision points |
| `/fusion-refactor` | Structure analysis → behavior-preserving plan → steer-one-agent execution. | No — composes review/plan/orchestrate |
| `/fusion-handoff` | Emit a Handoff Capsule. | No — summarization |
| `/fusion-remind` | Re-anchor a drifting session: cheat-sheet of situation→command + the invariants. | No — pure recall |

All twelve install as `~/.claude/commands/<name>.md` wrappers (see README → Install); the whole skill is also
invocable as `/fusion-deck`. (If a separate skill named `fusion` is also installed, that
skill takes precedence for `/fusion` — this skill does not assume one is present.)

Each command file in `commands/` is the procedure; it loads the matching `references/*.md` on demand.

## Routing — match the situation to the command

When the user **describes a situation** instead of naming a command, map it to the fitting `/fusion-*` and
**offer it** — they shouldn't have to know the catalogue. **Suggest, don't silently run:** the panel and
orchestration commands cost quota and time, so name the command + why and let them say go. For a quick
factual question, just answer directly — don't route a trivial ask into a panel.

<!-- SOURCE OF TRUTH for routing. On change: sync README.md EN + 中文 tables and commands/fusion-remind.md. -->
| The user is… | Offer |
| --- | --- |
| stuck on a hard call / trade-off, or wants one cross-checked | `/fusion` |
| asking "choose the right fusion workflow for this" or wanting cheaper/faster unless risk says otherwise | `/fusion-auto` |
| asking for maximum quality / strongest possible answer / hard high-risk decision | `/fusion-ultra` |
| asking you to review code, a diff, or a plan before it ships | `/fusion-review` |
| reporting a bug, or asking "why is it built like this / where does this come from" | `/fusion-investigate` |
| handing you a vague, underspecified ask to build | `/fusion-plan` (`--deep` for a full design doc) |
| about to send code to another model/agent, or working an unfamiliar repo | `/fusion-context` (`--discover` to auto-curate) |
| asking for a big, multi-step change done carefully | `/fusion-orchestrate` (`--worktrees` for parallel siblings) |
| asking to make something measurably faster / smaller / cheaper | `/fusion-optimize` |
| asking to clean up or consolidate code without changing behavior | `/fusion-refactor` |
| wrapping up and passing work on (to another agent or future-them) | `/fusion-handoff` |
| drifting in a long session / a fresh agent needs the map and the invariants | `/fusion-remind` |

Compose, don't silo: a feature is usually `/fusion-plan → /fusion-context → /fusion-orchestrate →
/fusion-handoff`; a bug is `/fusion-investigate → /fusion-plan → /fusion-orchestrate`. If two fit, prefer
the cheaper/narrower one and say what the other would add.

## Core invariants (do not violate)

1. **Never fake premium.** Disclose the real PANEL_STATE; degrade only explicitly. (`degraded-mode.md`)
2. **Blind panel.** Panelists never see each other's work; only the judge sees all answers, and only
   after every panelist returns. **Opus 4.8 always judges.** (`panel-prompt.md`, `judge-rubric.md`)
3. **Orchestrator never implements.** In `/fusion-orchestrate`, the orchestrator only plans, decomposes,
   delegates, and verifies; it reads files **only to verify** and makes all code changes **inside Task
   subagents**. One level of fan-out. (`orchestration-rubric.md`)
4. **Verify, then dispatch fresh.** Check each item against its Done-when with a concrete probe (grep /
   read / test — not a skim) before moving on. **Never proceed with unresolved gaps.**
5. **v2 routes, it does not guess.** `/fusion-auto` chooses a workflow only, writes a ledger entry, verifies
   when possible, and escalates by explicit policy. It does not replace `/fusion`'s full-panel meaning.
6. **Contract, not `/goal`.** `/fusion-plan` emits a Workflow Contract; `scripts/lint_contract.py` rejects
   any `/goal` reference. (`workflow-contract.md`, `contract-lint-rules.md`)
7. **Honesty path.** Use the status states `[todo]/[doing]/[done]/[blocked]/[incomplete]/[abandoned]`;
   `[incomplete]` carries reason / proof / attempted / impact / next-decision. Report failures plainly.
8. **Safety.** Never hardcode keys, accounts, or private paths; never leak secrets into a Context Pack;
   the smoke test never calls paid models (even under `FUSION_LIVE=1` — that flag only marks the mode
   for the commands). Panel prompts embedding **untrusted content** (a diff under review) run with
   `FUSION_NO_WEB=1` so injected instructions have no exfiltration path. (`references/safety.md`,
   `references/panel-prompt.md`)
9. **Honest-degrade beyond the panel.** The new helpers obey the same rule: `codemap.sh` discloses
   `CODEMAP_STATE` and falls back tree-sitter→ctags→grep; `selection_lint.py` gates discovered context on
   evidence (S007); `--deep`/`--discover`/`--worktrees` are opt-in. Use the best available, disclose what
   ran, fall back loudly. (`references/codemap.md`, `references/context-discovery.md`, `references/worktrees.md`)

## Skill root & paths

When a command or reference says `scripts/…` or `references/…`, that path is relative to **this skill's
root directory** (the folder containing this `SKILL.md`) — resolve it against that directory, e.g.
`bash <skill-root>/scripts/detect_panel.sh`, **not** against your current working directory. The installed
location is `~/.claude/skills/fusion-deck/` (or wherever `CLAUDE_SKILLS_DIR` points); the
generated `/fusion-*` command wrappers pass you this absolute path.

## Quick start

```bash
# from the skill root (resolve these against <skill-root> if your shell is elsewhere):
bash scripts/detect_panel.sh        # what panel can this machine run right now?
bash scripts/smoke_test.sh          # offline self-check (no paid calls)
```
