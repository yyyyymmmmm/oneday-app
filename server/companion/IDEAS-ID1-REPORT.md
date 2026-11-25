# IDEAS-ID1-REPORT · 点子日程源接入（C 源）预制报告

- 日期：2026-11-12（预制完成，未部署——等主线审后部署）
- 规格依据：`three-pages-muse-parity-20261111.md` §2.4 差距 I-1、§4.2 包 ID-1、验收 I-A1/I-A2
- 范围：仅伴生 `oneday_bridge.py` 点子生成链；`device_sync.py` / `device_bridge.py` 零改动；App 零改动；生产零改动（只读亲验）。

## 一、亲验结论（先查后写）

**生产日历同步副本**（2026-11-12 01:35 只读打开 `/opt/device-data/sync.db`，服务器内存 54%）：
- `sync_state.calendar`：synced_at 距亲验时 **1.38 小时**（新鲜，远低于 24h 过期线）、item_count **18**、permission_state **granted**、auth_range full、覆盖窗 2026-10-12 → 2027-02-10。
- 18 条构成：**17 条是订阅日历「US Holidays」**（Halloween/Thanksgiving/Christmas 等全天节假日）＋1 条「桥测试-已更新」（11-11 21:00，日历「大麦」）。
- 候选窗口 [-3d, +14d] 内 3 条（Veterans Day 11-11、桥测试、Thanksgiving 11-26）；[now, +7d] 内 **0 条**。
- 结论：数据面真实可用、结构稳定；但**个人日程目前几乎是空的**（用户真实日程还没进这个日历），且订阅节假日占绝对多数——C 源的价值要等用户把真实日程放进手机日历后才显现，节假日防噪必须在提示词层立规（见三.4）。

**现行点子生成链**：`_assemble_material()`（oneday_bridge.py）装配 S/G/M/K/R 五路＋简报；锚点注册表 `anchors[ref]={kind, objectId, title}` 贯穿锚点门（`_evidence_has_anchor`）、G1 正文锚点机检（`_detail_anchor_ok`/`_anchor_tokens`）、G2 蕴含自检与改写、锚点级去重（`anchorId="<kind>:<objectId>"`）。素材拼装点唯一，无第二处。

**同步副本的停供真源**：`device_sync.calendar_copy_events()` 内部先过 `_gate()`——未同步过抛 `CopyEmpty`；`permission_state == "revoked"` 时在读任何行之前抛 `SyncError(permission_revoked)`（2026-11-10 21:58 改严口径，`REVOKED_SERVES_COPY = False`，副本留盘不供、granted 即恢复）。设备桥的全部日历查询都走这条路。

## 二、跨模块读法裁定（规格留白项，本包定）

oneday 与 device 是同容器内的两个进程（supervisor 拉起），共享 `./device-data:/opt/device-data` 卷；oneday 进程已有跨读 `/opt/device-data/audit.jsonl` 的先例。裁定：**oneday 进程内懒 `import device_sync`，以其自有查询函数 `calendar_copy_events()` 读副本**——停供/未同步语义直接继承真源实现，不复制判断逻辑、永不直开 SQLite、不现调设备。环境变量用新名 `DEVICE_DATA_DIR`（默认 `/opt/device-data`），与 device 桥的 `DATA_DIR` 隔离，部署无需改 env。sync.db 不存在时 fetcher 先探文件再 init，不在无卷机器上凭空建库。

## 三、落法

1. **新 fetcher `_fetch_calendar_events()`**（与 S/K/R 同形状的 (events, note) 对）：
   - 窗口 **[now-3d, now+14d)**——任务简报口径。依据：生成轮每日 07:30 跑、管家价值＝提前准备＋刚结束跟进；未来 14 天恰等于生成卡 14 天到期寿命，再远的卡会在事件到来前先过期；过去侧只留「已结束 ≤3 天或进行中」（副本无完成标记字段，「未结」只能以近因近似，已在代码注释与本报告明记）；条数上限 **10**（与 K 源 GEN_KANBAN_CAP=10 同档，点子素材是摘要不是倾倒）。
   - 排序：进行中/未到在前（近者先）、刚结束在后（新者先）。
   - 失败全走 note 进轮账（materialNotes.calendar），素材段打印「（无）」，**不静默缺席**（对 I-A1）：未同步→「日历副本尚未同步」；撤销→「日历权限已撤销，同步副本停供」；窗口内零条→「日程窗口内暂无条目」；副本 >24h→「日历副本已过期（截至 …）」（条目仍供，与查询面口径一致）。
2. **素材行形态**（克制摘要）：`C1. 11月13日 14:00–15:00 《牙科复诊》 地点：城南诊所（明天）`——全日期（G1 真令牌而非 MM-DD 脚手架）、时间段、地点、日历名（有才写）、人话临近标签（今天/明天/后天/N 天后/进行中/昨天/N 天前，由代码算，不让模型做日历算术）。锚点 `{"kind": "C", "objectId": occurrence_id, "title": 标题}`——occurrence_id 跨轮稳定，锚点级去重天然生效。
3. **机检同步认 C**：`ANCHOR_REF_RE`、`_ANCHOR_REF_TOKEN_RE`、`_anchor_tokens` 前缀剥离三处字母集 SGMKR→SGMKRC；手记面 POST /ideas 的 ref 形状校验随之前进（注释同步）。
4. **提示词**：素材编号说明加 C；新增「日程门」硬规则——C 的价值在时机（临近做准备、刚过做跟进）；**订阅公共节假日日历条目不是用户本人的安排，单独不得作为出卡依据，只能作背景**（针对亲验到的 17/18 节假日构成；素材行带日历名供模型辨认）。G2 检查/改写提示词不枚举字母，无需改。
5. **三门与既有五路一字未动**；C 段插在 R 段之后、已有卡片段之前。

**与规格的一处偏差（请主线审）**：parity 规格 §4.2 写「近 7 天日程」，本包按任务简报定为 **-3 天/+14 天**（过去侧更紧、未来侧更宽）。理由如上（卡寿命 14 天＋管家提前量）；若主线要回收格口径，改三个常量即可（GEN_CAL_PAST_DAYS / GEN_CAL_FUTURE_DAYS / GEN_CAL_CAP 集中定义）。

## 四、改动文件清单

| 文件 | 改动 |
|---|---|
| `modules/oneday_bridge.py` | 新增 `DEVICE_DATA_DIR` 常量、GEN_CAL_* 四常量、`_fetch_calendar_events` / `_calendar_proximity` / `_calendar_material_line` 三函数；`_assemble_material` 接入 C 段与 notes["calendar"]；IDEAS_GEN_PROMPT 素材编号＋日程门；三处锚点正则认 C；相关注释。与生产 1.0.29 同文件 diff：16 hunk、仅 11 行替换、余皆新增 |
| `tests/oneday_bridge_p7_selftest.py` | 新增：ID-1 专项 26 项（见五） |
| `tests/oneday_bridge_p5_selftest.py` | Phase B 种一份真日历副本（走 device_sync 写入通道），加 1 项断言「素材带 C 行」；既有「无 materialNotes」断言在日历健康时继续成立 |
| `tests/run_bridge_selftests.sh` | p7 加入拷贝清单与运行序列 |
| `IDEAS-ID1-REPORT.md` | 本报告 |

## 五、自测结果

- **p7：26/26 全绿**。覆盖：窗口进出（+20d/-10d 排除）、排序、上限 10、素材行形态（全日期/时段/地点/日历名/临近标签）、锚点注册、三门对 C 的实际裁决（好卡落盘带 `anchorId="C:occ_dent"`；无事实 evidence→noAnchor；正文无锚→noDetailAnchor；未知 ref→noAnchor；已锚定→dupAnchor）、**撤销停供**（零条目、素材无日历内容、轮账带停供原因、**库里 6 行原件仍在**、恢复 granted 后供给恢复）、未同步两态（文件缺失/库空）、过期注记、全轮往返（真 `_run_generation_round` 落一张 C 卡；撤销后再轮 C 引用不可解析被丢且轮账留痕）。种子数据全程只走 stage_batch/complete 正规写入通道；时钟冻结在 2026-11-12 07:30 +08:00。
- **全套自测**（run_bridge_selftests.sh）：overview/p2/p4/p5/p6/**p7**/device_bridge/write-gate×3/device_sync 除外全绿——三处红已逐一对账，**均与本包无关**：
  - p3 红 1 项（adhoc 档位，时间敏感）：把生产 1.0.29 原文件 staged 后同跑，**同一项同数红（97 过 1 红）**，与 FD-1 报告既有记录一致，存量问题。
  - device_sync_selftest 红 1 项（reminders due 分桶对墙钟敏感）：`device_sync.py`/`device_bridge.py` 本包零改动（文件时间戳 11-10），不相干。
  - rendition 红（本机出站 503）：FD-1 报告已记为既存环境问题，不相干。

## 六、部署清单（主线审后执行，本包未做）

1. 文件同步：`modules/oneday_bridge.py`、`tests/` 三文件进镜像（按既有 companion 部署流程，rebuild + 重建 oneday-companion 容器；部署前查内存、Hermes StartedAt 前后核对的既有基线照旧）。
2. 版本号：COMPANION_VERSION 按主线节奏递增（本包未动本地模板 compose 的版本字面，含已知 1.0.28/1.0.29 小账一并对齐与否请主线定）。
3. 无需改 env、无需改 supervisor 配置、无需动 Hermes 本体、不需要重启 Hermes。
4. 部署后验收（对 I-A1/I-A2）：
   - 手动触发一轮点子生成，查 rec.materialNotes 与素材编号分布：C 路在场（当日窗口只有 Thanksgiving 一条未来节假日＋已过的桥测试，模型大概率不出 C 卡——属正常，轮账须能看见 C 段存在）；
   - I-A2 完整形态需用户在手机日历建一条明日真实日程并等副本同步后触发一轮——若出卡，查 evidence/正文锚点含该日程日期与标题原文；不出卡，查三门丢弃原因是否对得上。
5. 回滚：还原 oneday_bridge.py 单文件重部署即可（无数据迁移、无落盘格式变化；已落盘的 C 锚卡与其它卡同构，旧版桥读之无碍）。

## 七、已知边界

- C 源的真实价值依赖用户把个人日程放进手机日历并保持同步开启；当前副本以订阅节假日为主，已用提示词日程门防噪，但模型是否守规矩要靠上线后首轮真流量复核。
- 「同步关闭」在本架构里与「权限撤销」同路（开关即权限开关，关→App 报 revoked），fetcher 继承同一停供；不存在第二种关闭态需要单独处理。
- 跨进程并发：device 进程写库、oneday 进程读库，SQLite 文件锁＋30s timeout 兜底；fetcher 异常一律降级为 note，不拖垮生成轮（自测未模拟锁竞争，属低风险面，部署后首轮留意）。
