# 回执运行时化应用记录（包 1.20.0／能力 #33，2026-11-24）

设计正本：`~/workspace/oneday-design-review/receipt-runtime-design-20261124.md`；预制工地：`~/workspace/hermes-deploy-receiptrt/`（REGISTRATION 草案原拟 1.18.0/#27，应用时按时序终定 **1.20.0／#33**——1.18.0 已由 §444 技能硬闸占用、批三占 #31/#32）。

## 三方对账（应用前）
- 生产容器五文件哈希＝包 1.19.0 登记值；api_server_runs.py／react_to_message_tool.py／oneday_prompt.py／self_reaction_pending.py 与预制基线逐字一致；api_server.py 漂移＝批三 +117 行（预期内），以 `git merge-file` 三方合并（零冲突），合并增量与预制增量逐行同数（15 行）。
- 合并树自测：receipt_runtime_selftest.py 68 项全绿＋oneday_prompt_selftest.py 7/7＋py_compile 全过。
- 新哈希：api_server.py `c7435761…`／api_server_runs.py `515b8c37…`（修订一后 `9cd40e93…`）／react_to_message_tool.py `70316471…`／oneday_prompt.py `7b72d19c…`（后两件与预制登记新哈希逐字一致，交叉验证通过）。

## 应用
- 回滚基线：`/root/receipt-runtime-baseline-20261124/`（容器五文件原样＋SHA256SUMS＋PATHS＋data-snapshot：receipt_rt 键 0、agent 反应行基线 10 条/10 entries、sessions 1072、messages 4908）；修订一前件留 `rev1/`。
- 内存：应用前 55%、全程约 54%（<80% 红线）；每次重启前查在飞（gateway_state active_runs/active_agents 均为 0）。
- hermes 重启共 **2 次**：①计划内（1.20.0 首装，install.sh 在 compose recreate 后 SSH 隧道断开、脚本尾段未及落日志；文件四件与容器回读哈希经人工复核全对齐、健康检查人工补齐全过）；②纠正性（修订一，install.sh 完整跑完「安装完成」）。companion 未动。
- MCP 五门面：首装后 11:35:23 全 revived（启动竞态约 300 秒 park，存量口径）；修订一后 verify 的 MCP 探针同齐。
- verify：首装与修订一后各一份，均为 **齐 72／缺 0／规划中 1／未验 14**（与 1.19.0 终值同数；未验 14 均为默认不跑的写型探针）：`verify-output-1.20.0-applied-20261124.txt`、`verify-output-1.20.0-rev1-applied-20261124.txt`。

## 修订一（应用当日，电池实证，同版号重应用）
- 实证：提问轮判定必死——`agent.secret_scope.UnscopedSecretError`（ONEDAY_PROVIDER_AILEY_KEY）：判定守护线程脱离 per-turn secret scope，多路复用网关上 call_llm 解析 provider 凭据被拒（agent.log 2026-11-24 11:44:11 回溯全文在案）。
- 修法：`_social_judge_worker` 在 call_llm 前按 kanban watcher 先例自装 profile secret scope（`build_profile_secret_scope(get_hermes_home())`＋`set_secret_scope`、调用后 `reset_secret_scope`，装配失败则按旧路直调——单 profile 部署无需 scope）；runs 哈希 `515b8c37…→9cd40e93…`，预制自测复跑全绿。

## 行为电池（真口径，测试会话；脚本 /root/receipt-battery.py、/root/receipt-battery2.py，日志同名 .log）
1. **干活轮（门 1/2/3 上半）**：两段联网搜索轮，模型 react 工具行 **0**；时间线 👀（+9.1s）→🤔（+11.1s，满 2 秒）→✅（+20.4s 终态），终态恰 1 条；计数 received/thinking/done 各 +1；正文扫描 clean。时序精测（T1）：👀 落库 `at=1795492475.937` 早于首个工具结果行 `ts=1795492477.760`（早 1.82s）——运行时先行、非模型。
2. **失败轮（门 3 下半）**：bogus provider 轮在首个工具前即 failed——状态机正确惰性（无条目、无计数、无反应）。❌ 迁移与 ✅ 共用 `_receipt_terminal` 同钩子（仅 status 分支），工具后失败的 ❌ 替换由预制自测（真模块＋真 Tapback 语义桩）覆盖；生产侧未能以公开 API 确定性构造「工具已开工后整轮失败」，如实登记为**分工证据**（运行时直证缺一角，见开放项）。
3. **杀 run（门 4）**：干活轮 stop——角标停在 🤔（stop 时已由 👀 迁移），65 秒后复查不变、恰 1 条，计数无 done/failed 增量。
4. **纯聊天＋判定（门 5）**：分享轮 ×7（两批）——模型主路自贴 6 轮（🎉/❤️，均六盘内、写时即挂、判定不覆写不重复判）；1 轮模型未贴→**判定兜底 judge_written +1**，写回 😂（六盘内），终态后 +1.4s（≤30s 线）；提问轮 ×2——修订前 judge_failed（见修订一）、修订后 **judge_none +1、零反应**。分母 chat_turn_completed 累计 9，与电池轮数逐项对账一致。
5. **正文扫描（门 6 前半）**：全部电池轮回复正文零回执型表情字面（句首/独立成段判据）。语义对照轮（门 6 后半）未单独构造，留开放项。
6. **坏行诱发（门 7）**：👀 落库后删目标 user 行——🤔 与 ✅ 两次迁移各失败一次（transition_failed +2）、warning 在案、run 正常 completed、正文 clean。
7. **判定器模型（适配点首验）**：agent.log 实锤 `Auxiliary reaction_judge: using custom:ailey (claude-sonnet-4-6) at https://aikey.example.com/v1/`（11:53:02、11:54:27 两次判定调用同路）；task 名 reaction_judge 走 call_llm 阶梯、解析至主 provider/model（非 fast 替换，与 NOTES 适配 1 一致）。修订后无新增「social judge call failed」。
8. **计数总账（应用后终值）**：received_written 4／thinking_written 3／done_written 2／transition_failed 2／chat_turn_completed 9／judge_written 1／judge_none 1／judge_failed 1（修订前遗留）——与电池逐轮增量全等。agent 反应行 10→20 条（+10 与电池各轮终态角标逐条对上）。

## 开放项（如实）
- **门 8（App 亲发）未验**：须用户在 OneDay App 亲发干活＋分享各一条合并验收（主线已排）。
- ❌ 生产运行时直证缺一角（见电池 2）；语义对照轮（门 6 后半）未构造。
- 闸关回归门（附加门）未跑：关闸属生产配置变更，本轮未动；状态机/判定读闸失败即惰性的口径由预制自测覆盖。
