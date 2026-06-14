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

> 一个难题，甩给一桌顶尖模型同时作答，再让 Opus 4.8 拍板给你一个靠谱答案。
> 顺手还帮你把需求理成计划、把上下文备好、把活拆开、把交接写清——全在 Claude Code 里。

[English](#fusion-deck) · **简体中文**

### 这是什么

**fusion-deck** 是一个 [Claude Code](https://claude.com/claude-code) 技能。一句话说清它最值钱的那招：**别再只问一个模型了。** 同一个难题，它会同时丢给三个顶尖模型——Claude Opus 4.8、GPT‑5.5、Gemini 3.1 Pro——让它们各答各的、互不通气；然后 Opus 4.8 把三份答案一起读完、互相对照、挑出彼此的毛病，最后写一份它觉得最靠得住的给你。越是要紧的判断，越能帮你躲开那种「听着特别有道理、其实是错的」坑。

光会答还不够，它还带了五个干活的命令：把一句模糊需求理成能验收的计划、把该看的文件打包成刚好够用的上下文、把大活拆成一步步能验证的小任务、最后再替你把交接写好。

### 命令清单

| 命令 | 干什么 | 什么时候用 |
| --- | --- | --- |
| `/fusion <问题>` | 三个顶尖模型同时开答，Opus 4.8 当评委、综合出一个答案 | 拿不准的关键问题、架构选型、难缠的 bug——答错很贵的时候 |
| `/fusion-review <代码 / diff>` | 三个模型各看各的，汇成一份排好优先级的问题清单（必须改的排最前） | 合 PR 前、方案定稿前 |
| `/fusion-plan <模糊需求>` | 把一句话需求变成清楚的计划：目标、怎样算做完、分几步、有哪些坑 | 需求还没想明白就得动手时 |
| `/fusion-context <任务>` | 只挑相关的文件，打包成一份干净、控制了大小的上下文 | 要把活交给另一个模型 / agent，又不想把整个仓库砸过去 |
| `/fusion-orchestrate <任务>` | 把活拆开，每块交给一个专注的子 agent，做完一块先验过再做下一块 | 多步骤改动想稳着来、别一锅乱炖 |
| `/fusion-handoff <工作>` | 写一份干净的交接：做了啥、验了啥、有啥风险、接下来该干啥 | 收尾，或者上下文快被清空之前 |

### 安装

```bash
git clone https://github.com/raydocs/fusion-deck.git
bash fusion-deck/install.sh
```

然后在 Claude Code 里跑一下 **`/reload-skills`**（或者直接重启），就齐活了——`/fusion`、`/fusion-review`…… 拿来就能用。

**想凑齐三个模型的完整阵容**，再装两个可选 CLI 就行：

- [`codex`](https://developers.openai.com/codex) —— 接上 GPT‑5.5
- [`gemini`](https://github.com/google-gemini/gemini-cli) —— 接上 Gemini 3.1 Pro

没装也不耽误用：它会拿现有的模型接着跑，而且每次都老老实实告诉你这回到底用了哪几个模型——绝不糊弄你说「满配」。

想随时检查一下：

```bash
bash ~/.claude/skills/fusion-deck/scripts/detect_panel.sh   # 现在能用上哪几个模型
bash ~/.claude/skills/fusion-deck/scripts/smoke_test.sh     # 本地自检（不花钱、不碰付费模型）
```

### 来几个例子

```text
/fusion 预订流程到底用乐观锁还是悲观锁？按我们这个量级帮我权衡下
/fusion-review git diff main...HEAD
/fusion-plan 加一个带测试的 /health 接口
/fusion-orchestrate docs/plans/add-health.md
/fusion-handoff 这次的鉴权重构
```

### 几点说明

- **花多少、用了谁，都摆在明面上。** 三个模型一起上更费 token，也得等最慢的那个，所以默认只有 `/fusion` 和 `/fusion-review` 才这么干；其余命令默认走单模型，图个快。
- **不糊弄。** 每个面板答案都会写明这回到底是哪几个模型回答的。
- **仓库里不放密钥。** 登录的事交给各家 CLI，绝不往代码里塞私密信息。

### 许可证

[MIT](LICENSE)
