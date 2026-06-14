# fusion-deck

<p align="center">
  <img src="assets/hero.png" alt="fusion-deck — a panel of models, one judged answer" width="100%">
</p>

> 🃏 Three B-tier models gang up and out-argue the one A-tier star.
> A Claude Code skill that turns a panel of models into one judged answer — plus a workflow toolkit that
> plans, gathers context, splits tasks, and hands off.

![Claude Code Skill](https://img.shields.io/badge/Claude%20Code-Skill-8A63D2)
![License: MIT](https://img.shields.io/badge/License-MIT-3da639.svg)

**English** · [简体中文](#简体中文)

---

## The story

OpenRouter published a fun result: a **panel of models, judged by one of them, beats the best single
frontier model** (“Fusion beats frontier”). Two snags with just using theirs:

1. The single strongest model in that test — **Claude Fable 5 — is off the table for me. I can't run it.**
2. OpenRouter's Fusion is a **metered API**: every call costs.

So fusion-deck does the same trick, **on your own machine**: it rounds up **three models you already pay a
flat subscription for** — Claude Opus 4.8, GPT‑5.5 (via the `codex` CLI), and Gemini 3.1 Pro (via the
`gemini` CLI) — has Opus 4.8 judge them, and **beats the lone star anyway**. No extra per‑token API meter:
it just rides the CLIs you're already logged into. Three cobblers, one Zhuge Liang. 🧠

```mermaid
flowchart LR
    Q(["Your question"]) --> O["Opus 4.8"]
    Q --> G["GPT-5.5"]
    Q --> M["Gemini 3.1 Pro"]
    O --> J{{"Opus 4.8 judges<br/>consensus · conflicts · blind spots"}}
    G --> J
    M --> J
    J --> R(["One cross-checked answer"])
```

> **The catch:** the full panel needs all three subscriptions/CLIs. Missing one? No drama — it runs with
> whatever you've got and always tells you exactly which models answered.

## The proof

OpenRouter's **DRACO** deep‑research benchmark — 100 tasks across 10 domains:

| Setup | DRACO | vs. best solo model |
| --- | --- | --- |
| 🃏 **fusion-deck's panel** — Opus 4.8 + GPT‑5.5 + Gemini 3.1 Pro, judged by Opus 4.8 | **68.3%** | **+3.0** 🟢 |
| Opus 4.8 + GPT‑5.5, judged by Opus 4.8 | 67.6% | +2.3 |
| 🌟 Claude Fable 5 — the lone star, solo | 65.3% | — _(baseline)_ |
| GPT‑5.5, solo | 60.0% | −5.3 |
| Opus 4.8, solo | 58.8% | −6.5 |

The three underdogs land **68.3% — that's +3.0 over the star (Fable 5) and ~+9.5 over Opus 4.8 on its
own.** Three independent tries catch each other's mistakes; even the *same* model run twice and judged
jumps +6.7. Not luck — that's the whole point.

*Data: OpenRouter, “[Fusion beats frontier](https://openrouter.ai/blog/announcements/fusion-beats-frontier/).”
fusion-deck runs the same panel locally via the Claude / `codex` / `gemini` CLIs — no router, nothing
leaves for a third party.*

## Two superpowers

**① Think hard — open the panel.**
`/fusion <question>` and `/fusion-review <code or diff>` fan your question (or your code) out to the panel,
blind and in parallel, then Opus 4.8 judges it into **one cross‑checked answer** — or one prioritized
findings list, must‑fix first. For the calls where being confidently wrong is expensive.

**② Work smart — run the workflow.** This is the part people sleep on:

- 🧩 **`/fusion-plan <one fuzzy line>`** → a real plan: the goal, a concrete “done‑when”, the steps, the
  risks. Stop hand‑holding the AI through vague asks — pin down what you actually meant first.
- 📦 **`/fusion-context <task>`** → a tidy, **token‑budgeted context pack of only the files that matter**.
  The model finally reasons about your real code instead of drowning in the whole repo.
- 🔀 **`/fusion-orchestrate <task>`** → **splits the work into pieces, runs each in a focused sub‑agent, and
  verifies each one before starting the next.** Big changes done carefully — not one hopeful mega‑prompt.
- 🔎 **`/fusion-investigate <bug or "why is it like this">`** → evidence first, then the panel adjudicates
  the competing theories. A root‑cause report, not a confident guess.
- ⏱️ **`/fusion-optimize <metric>`** → a measure → change → re‑measure loop: baseline first, one change at a
  time, the panel calls continue/stop. No baseline, no bragging.
- ♻️ **`/fusion-refactor <target>`** → structure analysis → behavior‑preserving plan → one steered agent.
  Cleaner code, same behavior (proven by the tests that stay green).
- 🤝 **`/fusion-handoff <work>`** → a clean handoff note (done / verified / risks / next steps) so the next
  agent — or future‑you — picks up in seconds.

Chain them and you go from a vague one‑liner to a verified, shipped change:

```text
fuzzy idea → /fusion-plan → /fusion-context → /fusion-orchestrate → /fusion-handoff
```

Under the hood it's tuned to actually *get* you: panelists answer **blind** (no echo chamber), the judge
**reconciles** consensus vs. contradictions (it doesn't average), context is **curated not dumped**, and
every step is **verified before the next**.

## Install

```bash
git clone https://github.com/raydocs/fusion-deck.git
bash fusion-deck/install.sh
```

Then run **`/reload-skills`** in Claude Code (or restart). Done — `/fusion`, `/fusion-plan`, … are ready.

**For the full 3‑model panel**, install the two optional CLIs (and be logged into each):

- [`codex`](https://developers.openai.com/codex) — adds the GPT‑5.5 panelist
- [`gemini`](https://github.com/google-gemini/gemini-cli) — adds the Gemini 3.1 Pro panelist

Check anytime:

```bash
bash ~/.claude/skills/fusion-deck/scripts/detect_panel.sh   # which models are available right now
bash ~/.claude/skills/fusion-deck/scripts/smoke_test.sh     # offline self-check (never calls a paid model)
```

## Examples

```text
/fusion Should we use optimistic or pessimistic locking for the booking flow? Trade-offs at our scale.
/fusion-review git diff main...HEAD
/fusion-investigate the cart total is wrong for multi-currency orders
/fusion-plan add a /health endpoint with a test
/fusion-context the checkout flow, so I can hand it to another agent
/fusion-orchestrate docs/plans/add-health.md
/fusion-optimize cut p95 latency of /search under load; stop at 200ms
/fusion-refactor the payments module
/fusion-handoff the auth refactor
```

## Good to know

- **Where the savings come from.** It reuses the subscriptions you're already logged into (Claude /
  `codex` / `gemini`) — no per‑token API bill the way OpenRouter's Fusion API charges. *You just need the
  three subscriptions.* The full panel costs more quota and runs as slow as its slowest model, so only
  `/fusion` and `/fusion-review` open the whole table by default; the rest are fast single‑model commands.
- **Nothing is faked.** Every panel answer states which models actually answered; a smaller panel is never
  dressed up as the full one.
- **No secrets in the repo.** Auth lives in the CLIs; nothing private is hardcoded.

## License

[MIT](LICENSE)

---

## 简体中文

> 🃏 三个臭皮匠合起来，比那个独苗状元还能打——这回状元叫 Fable。
> 一个 Claude Code 技能：把一桌模型拧成一个被评审过的答案，外加一套会规划、会备上下文、会拆活、会交接的工作流。

[English](#fusion-deck) · **简体中文**

### 来历

OpenRouter 发了个挺好玩的结论：**一桌模型 + 其中一个当评审，分数能压过最强的单个前沿模型**（《Fusion beats frontier》）。但直接用他们的有俩坎：

1. 那场里最能打的单模型 —— **Claude Fable 5，我这儿根本用不了，被封了。**
2. OpenRouter 的 Fusion 是 **按量计费的 API**：一调一掏钱。

所以 fusion-deck 把这套搬到**你自己电脑上**：拉上**三个你本来就按月订阅、早就登录好的模型** —— Claude Opus 4.8、GPT‑5.5（走 `codex`）、Gemini 3.1 Pro（走 `gemini`）—— 让 Opus 4.8 当评审，**照样把那个单飞的状元比下去**。不额外按 token 收费，直接复用你已经登录的订阅。三个臭皮匠，顶个诸葛亮。🧠

```mermaid
flowchart LR
    Q(["你的问题"]) --> O["Opus 4.8"]
    Q --> G["GPT-5.5"]
    Q --> M["Gemini 3.1 Pro"]
    O --> J{{"Opus 4.8 评审<br/>共识 · 冲突 · 盲点"}}
    G --> J
    M --> J
    J --> R(["一个交叉核对过的答案"])
```

> **小前提：** 想凑齐整桌，你得有这三家的订阅 / CLI。少一个也不耽误 —— 它会用现有的接着跑，而且每次都老老实实告诉你这回到底上了谁。

### 实测

OpenRouter 的 **DRACO** 深度研究基准 —— 10 个领域、100 道题：

| 配置 | DRACO | 比最强单模型 |
| --- | --- | --- |
| 🃏 **fusion-deck 的阵容** —— Opus 4.8 + GPT‑5.5 + Gemini 3.1 Pro，Opus 4.8 评审 | **68.3%** | **+3.0** 🟢 |
| Opus 4.8 + GPT‑5.5，Opus 4.8 评审 | 67.6% | +2.3 |
| 🌟 Claude Fable 5 —— 独苗状元，单飞 | 65.3% | —（基准） |
| GPT‑5.5，单飞 | 60.0% | −5.3 |
| Opus 4.8，单飞 | 58.8% | −6.5 |

三个臭皮匠落在 **68.3% —— 比状元 Fable 5（65.3%）高 3.0 分**，比 Opus 4.8 单飞高了将近 9.5 分。三次各自独立的尝试会互相挑错；哪怕同一个模型跑两遍再合并，也能高 6.7 分。不是运气，这就是整件事的核心。

*数据来自 OpenRouter 的《[Fusion beats frontier](https://openrouter.ai/blog/announcements/fusion-beats-frontier/)》（DRACO 基准）。fusion-deck 是用你本机的 Claude / `codex` / `gemini` 直接跑同一套阵容 —— 不经过任何 router，也不往第三方发东西。*

### 两样看家本领

**① 想得狠 —— 开一桌。**
`/fusion <问题>`、`/fusion-review <代码 / diff>`：把问题（或代码）甩给一桌模型，各自盲答、并行跑，再由 Opus 4.8 评审成**一个交叉核对过的答案** —— 或者一份排好优先级、必改的排最前的问题清单。专治"答错了很贵"的场合。

**② 干得巧 —— 跑工作流。** 这部分最容易被低估：

- 🧩 **`/fusion-plan <一句模糊的话>`** → 一份真计划：目标、怎样算做完、分几步、有哪些坑。别再手把手哄着 AI 猜你想要啥 —— 先把你真正的意思钉死。
- 📦 **`/fusion-context <任务>`** → 一份卡着 token 预算、**只装该看的文件**的上下文包。让模型对着你真正的代码动脑子，而不是被整个仓库淹死。
- 🔀 **`/fusion-orchestrate <任务>`** → **把活拆成小块，每块交给一个专注的子 agent，做完一块先验过再开下一块。** 大改动也能稳稳落地，而不是赌一个超长 prompt 一把梭。
- 🔎 **`/fusion-investigate <bug 或"它为啥长这样">`** → 先把证据查清，再让一桌模型裁决相互打架的假设。给你一份有根因的报告，而不是一个自信的猜测。
- ⏱️ **`/fusion-optimize <指标>`** → 度量 → 改一处 → 复测的循环：先立 baseline，一次只动一处，由 panel 拍板继续还是收手。没 baseline 就不准吹。
- ♻️ **`/fusion-refactor <目标>`** → 结构分析 → 保行为的计划 → 一个被引导的 agent 落地。代码更干净、行为不变（靠一直绿的测试证明）。
- 🤝 **`/fusion-handoff <工作>`** → 一份干净的交接（做了啥 / 验了啥 / 有啥风险 / 下一步），下一个 agent —— 或者明天的你 —— 接手秒上手。

串起来用，一句模糊需求就能走到一个验证过、能交付的改动：

```text
模糊想法 → /fusion-plan → /fusion-context → /fusion-orchestrate → /fusion-handoff
```

底层都是冲着"更懂你"调的：几个模型**盲答**（不搞回声室）、评审**分清共识和冲突**（不是求平均）、上下文**精挑而非乱塞**、每一步**验过再走**。

### 安装

```bash
git clone https://github.com/raydocs/fusion-deck.git
bash fusion-deck/install.sh
```

然后在 Claude Code 里跑一下 **`/reload-skills`**（或者直接重启），就齐活了 —— `/fusion`、`/fusion-plan`…… 拿来就能用。

**想凑齐三个模型的完整阵容**，再装两个可选 CLI（并各自登录好）：

- [`codex`](https://developers.openai.com/codex) —— 接上 GPT‑5.5
- [`gemini`](https://github.com/google-gemini/gemini-cli) —— 接上 Gemini 3.1 Pro

想随时检查一下：

```bash
bash ~/.claude/skills/fusion-deck/scripts/detect_panel.sh   # 现在能用上哪几个模型
bash ~/.claude/skills/fusion-deck/scripts/smoke_test.sh     # 本地自检（不花钱、不碰付费模型）
```

### 来几个例子

```text
/fusion 预订流程到底用乐观锁还是悲观锁？按我们这个量级帮我权衡下
/fusion-review git diff main...HEAD
/fusion-investigate 多币种订单的购物车总价算错了
/fusion-plan 加一个带测试的 /health 接口
/fusion-context 把结账流程整理一下，我要交给另一个 agent
/fusion-orchestrate docs/plans/add-health.md
/fusion-optimize 把 /search 的 p95 延迟压下来，目标 200ms
/fusion-refactor 支付模块
/fusion-handoff 这次的鉴权重构
```

### 几点说明

- **省钱省在哪。** 它复用你电脑里已经登录的订阅（Claude / `codex` / `gemini`），不像 OpenRouter Fusion 那样按 token 收 API 费 —— **前提是你有这三家的订阅。** 整桌一起上更费额度、也得等最慢的那个，所以默认只有 `/fusion` 和 `/fusion-review` 才开整桌；其余命令走单模型，图个快。
- **不糊弄。** 每个面板答案都会写明这回到底是哪几个模型回答的；小阵容绝不冒充满配。
- **仓库里不放密钥。** 登录的事交给各家 CLI，绝不往代码里塞私密信息。

### 许可证

[MIT](LICENSE)
