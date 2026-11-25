# OneDay 记忆机制 — 通用种子说明

这套种子是 OneDay 部署包自带的**基础记忆**：一套开箱即用的分层文件记忆＋维护程序，给任何部署者起步用。它只含结构模板与通用起始口径，**不含任何人的私人记忆**。

## 落位（install.sh 首装时自动铺，已存在的文件永不覆盖）

| 种子件 | 落点（实例 data/ 下） |
|---|---|
| `SOUL.md` | `SOUL.md`（已有则跳过，部署者的人格不被种子顶替） |
| `memories/MEMORY.md`、`memories/USER.md` | `memories/` 同名（上游策展双文件） |
| `memories/oneday/**` | `memories/oneday/` 分层子树（inbox/scenes/people/groups/journal/bank/insights/identity/state/admission） |
| `skills/oneday-memory/SKILL.md` | `skills/oneday-memory/SKILL.md`（维护程序，agent 与 cron 都读它） |
| 包内 `cron/oneday-memory-jobs.json` | 按 id 合并进 `cron/jobs.json`（日结 23:40、周体检周日 10:30，deliver=local） |
| `config-memory-snippet.yaml` | 不自动落位：部署者按说明与实例 config.yaml 的 memory 段人工对账 |

## 机制一页纸

- **写入**：一切笔记先进 INBOX（已确认/待确认分开）；agent 每轮收尾自检，有货才写；事实变了标失效不删（双时序）。
- **提炼**：每晚日结 cron 把当日日志与会话提炼成长期条目，先经模块机械对账（防重复双账）再由 agent 终判；回执写回日志可抽查。
- **检索**：核心文件常驻进提示；场景文件按需读；跨层用 `/v1/memory/search` 条目级检索（带出处与时效，热度自动加权）。
- **治理**：规矩先进洞见账投票升等，升正式才进 RULES；新技能先验证留证再入准入账；遗忘走「列计划→确认→执行→复验」四步。
- **机器面**：oneday_memory 模块负责检索/对账/热度/索引/准入审计等确定性活，清扫线程每小时一轮，永不改记忆正文。

设计与对位细节见包内 `memory-mechanism-spec-20261124.md`（DESIGN §439）。
