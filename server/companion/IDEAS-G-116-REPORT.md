# IDEAS-G-116 · 伴生 1.0.16 点子生成加强 G1+G2 施工报告

日期：2026-11-11。触发：用户 13:37 拍板「按推荐全做」中的伴生部分——点子加强 G1（锚点进正文）＋G2（蕴含自检）。归因依据＝`~/workspace/oneday-design-review/muse-three-pages-essence-20261111.md` 第 3 节：OneDay 点子「依据很具体、正文仍泛」的根因是锚点被隔离在独立 `evidence` 字段、`detail` 本身不受锚点门约束；且旧自检只看卡面自判、不与素材行对照。版本：伴生 1.0.15 → **1.0.16**，已按伴生自动部署授权上线。改动面：仅 `modules/oneday_bridge.py` 一个文件（ideas 生成环节）＋本地 Dockerfile/compose 版本位；生产存量卡未动。

## 版本号改号说明（与任务单不符，先讲清）

任务单写「顺延 1.0.13、基线 companion-114」，开工实查时已被并行施工先后占用：**1.0.14＝§123 闭环包桥侧配合（CLOSURE-114，基线 /root/companion-114-deploy-20261111/）、1.0.15＝§125 表格转码端点（FILE-115）**。本包顺延为 **1.0.16**，回滚基线 **/root/companion-116-deploy-20261111/**，报告名随号改为 IDEAS-G-116。114/115 两条基线均未覆盖、未复用。

## G1 锚点进正文（生成提示词＋机检门）

- **素材行账本**：`_assemble_material()` 新增返回第五元 `material_lines`（ref→该素材行原文），返回值改五元组，唯一调用方 `_run_generation_round` 同步解包——后续 G1 机检与 G2 对照都以此为据，不再让模型「凭卡面自判」。
- **提示词改约**：`IDEAS_GEN_PROMPT` 的 detail 字段要求改写——正文**前半段**必须织入该卡锚点事实（日期／已拍板口径／红线／专名／数字，来自其素材行）；evidence 字段保留，但正文不许只剩泛话；硬规则新增「正文锚点门」一条。
- **机检门**：新增 `_anchor_tokens(text, anchor)`（从素材行提取日期串／≥2 位数字／拉丁专名／《》引号内容／锚对象标题 CJK 串及其 4 字窗／正文 CJK 串 4 字窗；先剥行首 ref 前缀与 MM-DD 日戳，防脚手架冒充事实）与 `_detail_anchor_ok(detail, source_text, anchor)`（detail 前半段——空白归一化后取字符数前半——须与素材行共享至少一个锚点 token；无素材行时回退用 evidence 句作源，门不静默绕过）。`_parse_generated_cards` 新增可选参 `material_lines=None`，在既有 evidence 锚点门之后、anchor 去重之前插入 G1 门，不合格 `_drop("noDetailAnchor")`；droppedReasons 新增键 `noDetailAnchor`、`unsupported`（旧键 noAnchor/noAction/dupAnchor/other 保留）。

## G2 蕴含自检（候选卡＋素材行对照＋一次改写）

- **自检改对照**：`IDEAS_CHECK_PROMPT` 整段改写——输入改为「候选卡＋对应素材行」，逐条抽卡内具体断言（日期／数字／专名／决定口径）须能在素材行找到支撑，保留标杆具体程度判断；输出格式扩展为 `[{title, ok, issues}]`，issues 逐条写明无支撑断言原句。
- **签名与沉默口径**：`_self_check_cards(cards, idem_suffix, material_lines=None)` 返回改 `(kept, failed, note)`，failed＝[(card, issues)]；基础设施失败仍 keep 全部＋记 note；**质检对某卡沉默＝判 failed（issues 记「自检未给出结论」），永不算通过**。
- **一次改写**：新增 `IDEAS_REWRITE_PROMPT`＋`_rewrite_cards(...)`——改写只许依据素材行说话、删／修正无支撑断言、evidenceRef 保持不变、撑不起就不输出该卡；产出回灌 `_parse_generated_cards` 全套门（去重对象＝本轮快照＋已通过的 kept 卡，防改写重占已用 anchor/title）；改写卡再过一次 `_self_check_cards` 复检，通过才落；仍不过或未被改写覆盖的失败卡由轮次函数逐张记 `unsupported` 进 droppedReasons。轮次记录新增 `rewriteNote` 字段（selfCheckNote 沿用）。

## 本地自测（全绿，两轮实跑）

overview 8／p2 34／p3 29／p4 19／**p5 23（基线 21，+2）**／**p6 53（基线 45，+8＝新 phase E）**／device OK／write-gate 22／device_sync OK／model-combos OK／spreadsheet 20／ledger 60。

- p6 phase E 新增覆盖：`_anchor_tokens` 抽日期＋正文专名；G1 三卡对照（锚点在前半段→落；正文泛→noDetailAnchor 丢；锚点只在后半段→丢）；G2 mock 全链（check 提示词确实携带素材行原文、蕴含通过／驳回分流、改写过全门、复检通过、改写仍编造→复检再驳回停在 failed）。
- 测试夹具同步更新（旧契约编码）：p6 phase C 夹具卡 detail 原本正是「正文泛、事实只在 evidence」的旧形态，已改写为前半段带锚点版；p5 phase B 整轮夹具更新（两张留存卡 detail 织入锚点、fake harness 新增 ideas-rewrite- 路由与两段式 check 输出、断言改为 produced=2（好卡＋改写救回卡）、dropped=4、reasons={noAnchor:2, noAction:0, dupAnchor:1, noDetailAnchor:1, unsupported:0, other:0}、新增「恰一次改写」与「救回卡带 R:mem_wed 落存」两断言）。
- device_sync 的 1 例 FAILED 系 reminders 种子固定日期跨日界、多轮时有时无，属既有项，与本包无关，勿追。

## 沙盒干跑（生产状态副本、零生产写入）

- 做法：拉生产桥 data.json（120,228 字节）两份副本，old 臂＝1.0.15 模块原样、new 臂＝新模块，独立端口 18771/18772、各自 DATA_PATH；凭据经 scp 文件注入、从未打印，干跑后本地 sbx.env 已 shred、服务器侧 /tmp/sbx.env 已删除；沙盒桥进程已全部杀停（健康检查 000 确认）。素材抓取走公开 Dashboard 通道（S/G/M/K 与生产同源）；**R 源在沙盒降级**（本机未配 WRITE_GATE_BRIDGE_KEY，两臂记录均如实带 materialNotes「未配置记忆桥钥匙」，两臂同口径可比）。触发走 POST /ideas/generate 手动轮。
- 脚手架假象（已排除）：旧臂第一轮与新臂同秒触发、手动幂等键 `ideas-gen-manual-<同一秒>` 撞车得 HTTP 409「Idempotency-Key was already used with a different request payload」——系干跑脚手架假象、非代码缺陷；旧臂单独重跑成功。
- **结果对照**：旧臂（1.0.15）：produced=2、dropped=0、droppedReasons 全 0。样例卡：①「我可以把 iCost 账单 2833 条去重记录做成一页支出结构分析」（detail 首段含 21 列／2025/05/31–2026/10/25／约 25.23 万／3893 行去重成 2833 条）②「我可以把 Kimi K3.1 Pro 的 96 个分片整理成本地部署可行性说明」（detail 含 96 个分片、2026-11-02 提交记录、非 OSI 许可限制）。新臂（1.0.16）：produced=1、dropped=1（dupAnchor——模型重提了一个已 live 的 anchor，被既有门拦）、droppedReasons 余键全 0、无 selfCheckNote/rewriteNote（即 G2 质检正常跑完且无驳回、无改写触发）。样例卡：「我可以核对
...[truncated 2705 chars]