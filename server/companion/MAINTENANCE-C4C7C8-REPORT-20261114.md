# 伴生维护窗口包 C-4＋C-7＋C-8 交卷报告（2026-11-14）

施工计划：`~/workspace/oneday-design-review/companion-maintenance-plan-20261114.md`。
纪律遵守：只交码＋自测＋部署配方，未自行部署；目标版本 **1.0.54**（顺延 1.0.53）。
基线：全套 runner 拆分前实测 24 OK／2 FAILED（p9、rendition，均为预存环境问题，签名见下）。

## C-4 工作台账三源收敛（modules/ledger.py 1479→984 行）

- 单一写源＝事件直报：App 上报（runs）＋裁决事件（decisions.jsonl 游标摄入）＋
  device audit 事件（一行一条独立条目）。Collector 只剩事件摄入＋僵尸阶梯，
  15 秒节拍／心跳／每日 compact 不变；构造签名去掉 providers。
- 删除：转录拆轮（split_turns）、run_status/kanban 会话对账四步、device 按窗归因
  与 ambiguous 隔离、_targeted_check 终局纠正、SLOW_STEP_EVERY。
- oneday_bridge 接线（现位于 oneday_seg_ledger.py）：Collector 不再传 providers；
  三个纯对账 provider（_ledger_run_status/_ledger_kanban/_ledger_writegate_pending）
  确认无其他消费方后删除；_ledger_sessions/_ledger_messages/_LedgerDash 另有
  会话门面与生成链消费方，保留，仅改段头注释。
- create_or_merge 默认 origin 由 "reconciled" 改 "reported"（一词对齐新口径）。
- **行为变化登记（如实）**：①无人上报的会话不再被转录补记/落定/纠正，终报丢失
  走僵尸阶梯（>45s 标 evidenceLagging、>1800s 判 stale）；②kanban 不再自动进台账；
  ③待决审批裁决前不出现在台账，裁决事件到达时建条落定；④device 调用不再按窗
  并入运行计数、每条成独立条目。
- 游标为内存态：重启后从文件头重摄入，靠稳定 id（appr:/dev:）＋终局护栏幂等，
  与改前同类行为，无重复条目。
- 自测改写：tests/ledger_selftest.py 按新契约重写（Part A 场景 A1–A13、Part B
  改断言「采集器不从转录落定／kanban 不镜像」），**54 passed, 0 failed**。

## C-7 写闸规则引擎瘦身（modules/write_gate_bridge.py，逻辑收敛、文件 1208→1227 行）

行数微增全部来自三处收敛点的口径注释；重复逻辑净减。裁决语义与红线五类逐次
审批一字未动，四套自测**零改动全绿**（rules 22／anchor 13／blocked 11／
anchor-ledger 10）。

- `_record_head(subsystem, rec)`：_norm_record 与 _append_decision 共用的五字段
  记录头（此前两处各拼一份）；两处字段顺序与输出逐字节不变。
- `_append_jsonl(name, entry)`：decisions 与 decide-attempts 共用的单一 JSONL
  写口（同一把锁、同一行格式）；仅 stderr 失败文案由两句归一为 `{name} write failed`。
- `_cap_reason()`：blocked_reason 与 failure_reason 共用的 500 字截断归一。
- **两条审计原处方不照字面执行，证据如下**：①「reason 合并为一个字段」——
  blocked_reason 是待决记录的预检字段、failure_reason 是裁决失败回执字段，
  2026-11-14 审批卡对齐包（1.0.52 已部署）刚让 App 两路都解码并上卡面，
  删任一路即破已上线契约；本包只归一其生成口径。②「attempts 并入
  decisions.jsonl」——overview_bridge 对 decisions 每条新行铸一条
  write_gate_decision 通知，失败 attempt 混入会多铸假「已处理」通知；且
  write_gate_blocked_selftest 断言 decide-attempts.jsonl 独立成账。

## C-8 伴生单文件拆分（oneday_bridge.py 11533→1712 行＋14 个段文件）

- 拆法＝单命名空间 exec 装载：主文件在每段原位置 `_load_segment("oneday_seg_*.py")`，
  段文件与主文件同目录平铺（runner 的 `cp modules/*.py` 与 Dockerfile 的
  `COPY modules/` 自动覆盖，supervisor 入口不变）。不用 import 的理由：supervisor
  按脚本路径启动，段文件 import oneday_bridge 会加载第二个模块实例（双 _db）；
  且自测对主模块的约 20 个 monkeypatch 接缝与 mod._db 直改将失效。
- 段文件：goals 207／traces 167／goals_facade 149／sessions 255／automation 751／
  goals_activity 669／ideas_pool 419／monitors 508／ideas_gen 1425／briefings 534／
  feed 3367／ledger 346／files 427／delivery 657 行。切割全在顶层语句边界，
  注释随后续段走，定义与执行顺序不变。
- **零变化证据**：①命名空间对账——归一化指令流指纹（抹掉 LOAD_GLOBAL/
  LOAD_ATTR 的 NULL 推送位：同一源码在不同编译单元中该位落在链首或链尾，
  已用微型实验＋全量文件对照实证为编译器等价编码）显示拆分前后 595 个模块级
  名字逐一相同、每个函数/类的指令流与常量一致，唯一新增名字是装载 seam
  `_load_segment`；唯一“差异”_AUTOMATION_RUNNERS 为字典内函数对象的内存地址
  （指纹噪声）。②全套 runner 拆分前后 RESULT 行逐行相同。
- 并发说明：切割基线取 GD-2/GD-3 线落地后的 11582 行版（md5 7632e9dd），
  指纹对账即以该版为拆分前基准，GD 内容 provably 完整保留。

## 全套自测对账（拆分前＝拆分后，逐行一致）

- 24 OK／2 FAILED。ledger_selftest OK（54/54）。
- p9 FAILED 签名（预存）：runner 暂存布局缺 `../scripts/idea_category_backfill.py`
  的 FileNotFoundError；仓库树直跑全绿（基线期实测）。
- rendition FAILED 签名（预存）：本机环境桥回 503，7 PASS 后同点 FAIL。

## 部署配方（主线窗口执行，目标 1.0.54）

1. 叠层法构建新镜像：仅换本包改动模块——modules/ledger.py、
   modules/write_gate_bridge.py、modules/oneday_bridge.py＋14 个
   modules/oneday_seg_*.py（新增文件必须进镜像，Dockerfile 的 COPY modules/
   已覆盖）；tests 不进镜像。
2. companion.env 原地改写 COMPANION_VERSION=1.0.54（保 inode，不换文件），
   重启伴生容器；版本戳三处对齐（env／面板／健康接口回读）。
3. 验收回读：/health ledger 块 collector 心跳推进；新开一轮 App 会话→台账
   出现 running→终报落后落定；decisions.jsonl 新裁决一行→台账落定一条。
4. 回滚基线：1.0.53 镜像＋改前三文件 .bak（ledger.py d83edb7c、
   write_gate_bridge.py 8cbb4950、oneday_bridge.py 以 GD 合并版 7632e9dd 为准）；
   台账事件文件格式未变，回滚无数据迁移。
