# fusion-deck

> One question → a panel of the best models → one judged answer.
> Plus a small toolkit to plan, gather context, orchestrate, and hand off — all inside Claude Code.

![Claude Code Skill](https://img.shields.io/badge/Claude%20Code-Skill-8A63D2)
![License: MIT](https://img.shields.io/badge/License-MIT-3da639.svg)

**English** · [简体中文](#简体中文)

---

## What it is

**fusion-deck** is a [Claude Code](https://claude.com/claude-code) skill. Its headline trick: instead of
asking one model, it asks **three top models the same question at the same time** — Claude Opus 4.8,
GPT‑5.5, and Gemini 3.1 Pro — each answering independently. Then **Opus 4.8 reads all three, cross‑checks
them, and writes the single best answer**. On the calls that actually matter, you get far fewer
confident‑but‑wrong answers.

It also ships five companion commands for real work: turn a vague idea into a checkable plan, package
just‑the‑right context, run a task as verified sub‑steps, and write a clean handoff.

## Commands

| Command | What it does | Use it when |
| --- | --- | --- |
| `/fusion <question>` | Asks 3 top models in parallel; Opus 4.8 judges them and writes one answer. | A high‑stakes question, design call, or nasty bug where being wrong is costly. |
| `/fusion-review <code or diff>` | 3 models review independently; you get one prioritized findings list (must‑fix first). | Before merging a PR or committing to a design. |
| `/fusion-plan <vague idea>` | Turns a fuzzy ask into a clear plan: goal, “done when…”, steps, risks. | Starting from an unclear request. |
| `/fusion-context <task>` | Bundles only the relevant files into one tidy, size‑budgeted context pack. | Briefing another model/agent without dumping the whole repo. |
| `/fusion-orchestrate <task>` | Splits the work, runs each piece in a focused sub‑agent, verifies each before the next. | Multi‑step changes you want done carefully. |
| `/fusion-handoff <work>` | Writes a clean handoff note: what’s done, what’s verified, risks, next steps. | Wrapping up, or before a context reset. |

## Install

```bash
git clone https://github.com/raydocs/fusion-deck.git
bash fusion-deck/install.sh
```

Then run **`/reload-skills`** in Claude Code (or restart). Done — `/fusion`, `/fusion-review`, … are ready.

**For the full 3‑model panel**, install the two optional CLIs:

- [`codex`](https://developers.openai.com/codex) — adds the GPT‑5.5 panelist
- [`gemini`](https://github.com/google-gemini/gemini-cli) — adds the Gemini 3.1 Pro panelist

No CLIs? fusion-deck still works with fewer models — and it **always tells you which panel it actually
used**. It never pretends.

Check anytime:

```bash
bash ~/.claude/skills/fusion-deck/scripts/detect_panel.sh   # which models are available right now
bash ~/.claude/skills/fusion-deck/scripts/smoke_test.sh     # offline self-check (never calls a paid model)
```

## Examples

```text
/fusion Should we use optimistic or pessimistic locking for the booking flow? Trade-offs at our scale.
/fusion-review git diff main...HEAD
/fusion-plan add a /health endpoint with a test
/fusion-orchestrate docs/plans/add-health.md
/fusion-handoff the auth refactor
```

## Good to know

- **Cost & panel are transparent.** The 3‑model panel costs more tokens and runs as slow as its slowest
  model, so only `/fusion` and `/fusion-review` use it by default; the rest are fast single‑model commands.
- **Nothing is faked.** Every panel answer states which models actually answered.
- **No secrets in the repo.** Auth lives in the CLIs; nothing private is hardcoded.

## License

[MIT](LICENSE)

---

## 简体中文

> 一个问题 → 一桌顶尖模型 → 一个被评审过的答案。
> 外加规划 / 整理上下文 / 编排 / 交接的小工具，全部在 Claude Code 里。

[English](#fusion-deck) · **简体中文**

### 这是什么

**fusion-deck** 是一个 [Claude Code](https://claude.com/claude-code) 技能。核心玩法：不是只问一个模型，
而是**同时把同一个难题抛给三个顶尖模型** —— Claude Opus 4.8、GPT‑5.5、Gemini 3.1 Pro —— 各自独立作答，
再由 **Opus 4.8 通读三份答案、交叉核对后写出唯一的最优答案**。在真正关键的判断上，大幅减少“自信却答错”。

它还附带五个干活用的命令：把模糊想法变成可验收的计划、打包刚刚好的上下文、把任务拆成可验证的小步执行、
写出干净的交接说明。

### 命令一览

| 命令 | 作用 | 什么时候用 |
| --- | --- | --- |
| `/fusion <问题>` | 三个顶尖模型并行作答，Opus 4.8 评审后写出最终答案。 | 高风险问题、架构决策、棘手 bug —— 答错代价大时。 |
| `/fusion-review <代码或 diff>` | 三个模型各自独立评审，汇成一份按优先级排序的问题清单（必修在前）。 | 合并 PR、定方案之前。 |
| `/fusion-plan <模糊需求>` | 把模糊需求变成清晰计划：目标、“完成标准”、步骤、风险。 | 需求还不清楚就要动手时。 |
| `/fusion-context <任务>` | 只把相关文件打包成一份整洁、控制了体积的上下文包。 | 要把任务交给另一个模型/agent，又不想丢一整个仓库给它。 |
| `/fusion-orchestrate <任务>` | 把活拆开，每块交给一个聚焦的子 agent，做完一块先验证再做下一块。 | 想稳妥完成多步骤改动，而不是一锅乱炖。 |
| `/fusion-handoff <工作>` | 写一份干净的交接：做了什么、验证了什么、风险、下一步。 | 收尾，或上下文即将被清空之前。 |

### 安装

```bash
git clone https://github.com/raydocs/fusion-deck.git
bash fusion-deck/install.sh
```

然后在 Claude Code 里执行 **`/reload-skills`**（或重启）。完成 —— `/fusion`、`/fusion-review`…… 就能用了。

**想用完整的三模型阵容**，装上两个可选 CLI：

- [`codex`](https://developers.openai.com/codex) —— 接入 GPT‑5.5
- [`gemini`](https://github.com/google-gemini/gemini-cli) —— 接入 Gemini 3.1 Pro

没装也能用：fusion-deck 会用更少的模型继续，并且**始终告诉你这次实际用了哪些模型** —— 绝不假装。

随时自检：

```bash
bash ~/.claude/skills/fusion-deck/scripts/detect_panel.sh   # 当前能用哪些模型
bash ~/.claude/skills/fusion-deck/scripts/smoke_test.sh     # 离线自检（不花钱、不调用付费模型）
```

### 例子

```text
/fusion 预订流程该用乐观锁还是悲观锁？按我们的量级权衡一下。
/fusion-review git diff main...HEAD
/fusion-plan 加一个带测试的 /health 接口
/fusion-orchestrate docs/plans/add-health.md
/fusion-handoff 这次的鉴权重构
```

### 一些说明

- **成本和阵容都透明。** 三模型阵容更贵、也跟最慢的模型一样慢，所以只有 `/fusion` 和 `/fusion-review`
  默认用它；其余命令默认走快速的单模型。
- **绝不造假。** 每个面板答案都会注明本次实际由哪些模型作答。
- **仓库里没有密钥。** 鉴权交给各 CLI，不硬编码任何私密信息。

### 许可证

[MIT](LICENSE)
