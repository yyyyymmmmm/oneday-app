---
name: oneday-memory
description: OneDay 分层记忆的维护程序：写入确认门与轮末自检、日结提炼（对账两段式）、周体检、检索纪律、遗忘程序、技能准入与洞见治理。凡涉及记事、回忆、整理记忆、被纠正、建技能时，先读本技能再动手。
---

# OneDay 记忆程序

记忆本体是文件（`memories/` 树），确定性机器在 oneday_memory 模块（网关端点 `/v1/memory/*`，或容器内 CLI `python3 /opt/hermes/gateway/platforms/oneday_memory.py <子命令>`）。语义判断归你，机械活归模块——不要手工拼 JSONL、不要手工维护 INDEX 与热度账。

## 0. 分层地图

| 层 | 路径 | 放什么 |
|---|---|---|
| 核心 | `memories/MEMORY.md` | 红线＋核心原则＋索引（常驻，保持精简） |
| 用户档 | `memories/USER.md` | 用户基本事实 |
| 入口 | `memories/oneday/inbox/INBOX.md` | 一切笔记先入此：已确认/待确认两区 |
| 场景 | `memories/oneday/scenes/*.md` | 按场景的事实与口径 |
| 人物/群体 | `memories/oneday/people/`、`groups/` | 一人/一组一页＋INDEX |
| 日志 | `memories/oneday/journal/YYYY-MM-DD.md` | 每日流水与提炼回执 |
| 整理库 | `memories/oneday/bank/*.md` | world/experience/opinions/reflections 四账 |
| 洞见 | `memories/oneday/insights/insights.jsonl` | 规矩候选与投票（走模块 insight 子命令） |
| 身份 | `SOUL.md`、`memories/oneday/identity/{IDENTITY,RULES}.md` | 人格/自我定义/工作规矩 |

条目格式见 `memories/oneday/scenes/README.md`（小节＋odmem 尾注）。尾注字段：id/first/last/src/status/valid_from/invalid_from/superseded_by，另可加 links（关联条目 id，逗号分隔）。

**通道归一（2026-11-24 定版）**：长期记忆本体只有一棵——`memories/` 文件树（上表）。会话库（state.db／sessions/）只是历史会话的归档与检索，不是记忆本体，不许把会话内容当长期记忆直接引用（要留的事实须经提炼落进文件树）；外部记忆引擎（byterover／retaindb 等 provider 插件）已在 config 显式关停（`memory.provider: builtin`），不许启用为第二记忆通道。

## 1. 写入纪律（随时）

- **确认门**：用户亲口确认或亲手写下的，进 INBOX 已确认区；你代记的推测、外部信息、未拍板草稿，只进待确认区。未确认内容不进长期层、不跨场景引用。
- **轮末自检**：每轮收尾自问——本轮有无①新事实 ②用户的纠正 ③拍板决定 ④交付/失败结果？有，按层落盘：基本事实走 memory 工具（USER/MEMORY），场景事实写场景文件，流水写当日 journal，纠正走第 5 节洞见程序。没有就跳过，不许为凑数写记忆。
- **写前先搜**：写新条目前先用 search 查同主题已有条目，能 UPDATE/SUPERSEDE 的不另起新条（防双账）。
- **双时序**：事实变了，旧条目标 superseded＋invalid_from＋superseded_by 指向新条目，不删旧条目（用户明令彻底删的除外，走第 4 节）。

## 2. 日结提炼（cron「OneDay 记忆日结」驱动，程序在此）

1. 采集：读当日 journal 全文；用会话检索（session_search）抽当日新会话的要点清单。
2. 抽候选：每条候选写成一句话事实/决定/纠错，带来源（会话 id 或 journal 行）。
3. 对账：逐条调模块 `reconcile <候选文本>` 拿机械建议与近重复排名；你做终判：ADD（新条目）/UPDATE（改旧条目正文并更新 last）/SUPERSEDE（旧条目标失效＋写新条目）/NOOP（重复或不值得记，丢弃）。
4. 落盘：L0 走 memory 工具（write_approval 开着时走 App 审批，不要绕）；层文件按第 1 节格式写，尾注 src=distill:<日期>。
5. 回执：在当日 journal 尾部追加「日结提炼回执」：候选数、四种动作各几条、被丢弃候选一句话清单。回执是给人抽查的，不许省略。
6. 顺手项：INBOX 已确认区里已分发的条目划掉（移入当日 journal 存档行）；待确认区不动。

## 3. 周体检（cron「OneDay 记忆周体检」驱动）

1. 读模块清扫产出：`state/admission_audit.json`（技能准入差异）、INDEX.md（各层体量与溯源覆盖）。
2. 热度重排：search 热度长期为零的场景文件，在 journal 写「冷层建议」（只建议，不自动搬动正文）。
3. 洞见维护：复核 candidate 洞见——本周有正例的 upvote、有反例的 downvote（走模块 insight 子命令）；升 active 的洞见同步写进 RULES.md 对应节并注明洞见 id。
4. 准入复核：审计报告里的未登记技能，逐个补验证或标记待验（第 6 节）；验证不过的不许在汇报里称「可用」。
5. 体检报告写当日 journal：覆盖率变化、洞见升降级、准入差异处理结果。

## 4. 遗忘程序（用户下令才走）

1. 列计划：按用户描述检索命中条目，列清单（条目 id＋所在文件＋拟处置：标失效/物理删）。
2. 用户确认清单后执行：默认标失效（status=retired＋invalid_from）；用户明令彻底删才物理删除。
3. 关联处理：links 边指向被处理条目的，在新条目/回执里注明失效；洞见表对应行 retire。
4. 回读复验：search 复查命中条目已不可见（include_retired 可见且状态正确），在 journal 记一笔（只记条目 id 与事由，不记被删内容）。

## 5. 纠错→洞见（被纠正的当轮）

用户纠正你之后，除当场改正，还要把「下次怎么做」写成一条洞见 candidate 入账（模块 insight 子命令 op=add，src 记当日 journal 或会话 id）。不要直接改 RULES.md——规矩要经过投票治理升 active 才进 RULES（第 3 节第 3 步）。同一错误复发时，给对应洞见 upvote 并 relapse 计数 +1。

## 6. 技能准入（建/改技能时）

新技能（或大改）完成前：①给技能配一条可复跑的验证（自测脚本、演练步骤，写在技能文件内）；②亲自跑一遍，输出留证；③往 `memories/oneday/admission/skill_admission.jsonl` 记一行（格式见 admission/README.md，evidence 指向证据文件）。三步缺一，技能只能称「草稿」，不许称可用。

## 7. 检索纪律（回忆时）

- 先看 MEMORY.md 索引判断场景，只读对应层文件（不全树乱翻）。
- 需要跨层找时用模块 search（端点或 CLI），命中看尾注判断时效：status 非 active、invalid_from 已过的，不当现行事实用。
- 引用记忆时说得出处（文件＋条目 id）；查不到就说查不到，不许拿印象补。
