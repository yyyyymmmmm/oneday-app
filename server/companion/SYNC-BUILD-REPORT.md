# 伴生侧同步制施工报告（2026-11-10）

> 范围：规格 `oneday-design-review/device-sync-design-20261110.md` 的伴生包（§7.1）——存储、同步接收、查库工具、兜底衔接、面板同步区、Hermes 配置侧本地可验部分。**全程本地构建与自测，未动生产、未部署、未重启任何服务。** 两处用户拍板（2026-11-10 21:58）已落进实现与规格 §8：①权限撤销＝完全停供；②照片＝全量资产索引。

## 1. 做了什么

**新增 `modules/device_sync.py`（同步库与查询层）**
- SQLite 单文件 `sync.db`（落在 device 模块 DATA_DIR，建库即 0600，只有 device 进程打开）：表＝sync_state（每数据集一行：同步/收到时刻、条数、授权范围、覆盖窗口、权限态、未同步写入标记、同步中标记、最近错误、提醒聚合）＋ contacts / calendar_events / reminders / photos_assets / motion_days 五张数据表＋批次暂存两张表。
- 字段最小化照规格 §2.2：通讯录只存标识/姓名/电话/邮箱/公司/分组/指纹（备注、地址、生日、头像不进）；日历只存场次最小字段；照片按 21:58 拍板改**全量资产索引**（每资产一行：标识、创建时间、类型/子类型、宽高/时长、收藏、相册名、是否有地点），聚合在索引上现算；原图与坐标永不进。
- 静态保护选型（规格 §2.3 二选一）：**不启用 SQLCipher**——口令与数据同机时边际收益有限，不为它加依赖拖施工；靠文件 0600＋卷隔离＋只走既有 HTTPS 单钥通道。

**`modules/device_bridge.py`（接收接口＋工具重塑＋兜底）**
- 同步接口（与设备会话同前缀、同 Bearer 鉴权）：`POST /device/sync/batch`（分批暂存、每批 ≤500 的口径在 App 侧，桥侧按批次号管理、新批次自动作废未完成的旧批次）、`POST /device/sync/complete`（核对应到总数才整批换入；对不上回 409 并丢弃暂存、旧副本原样保留）、`POST /device/sync/manifest`（通讯录标识＋指纹清单比对，回新增/有变与已消失两张小单——§3.3 增量衔接位，含授权范围变化时整本重灌的判定）、`POST /device/sync/state`（App 上报权限/范围变化；范围变化回 `reimport_required`）、`POST /device/sync/delete`（单件或全部删副本，清表＋VACUUM 回收文件空间）、`GET /device/sync/status`（只出状态、无任何记录内容）。同步完成与删除写元数据审计（只记数据集/条数/成败）。
- 查库工具全套（MCP，工具总数 10 → 21）：新增 `contacts_count`、`contacts_stats`（总数/有电话占比/有邮箱占比/按分组成/查重候选组数，全在库上算完只回答案）、`contacts_list`（limit/offset → total_matches/returned/has_more、最小字段）、`contacts_get`、`calendar_search`、`calendar_count`、`reminders_count`、`reminders_search`、`photos_stats`、`photos_recent`、`motion_steps_summary`（逐日聚合＋区间合计、标注「手机计步」来源）；`contacts_search` 改查库版（按名/号/邮箱，号码做数字归一化匹配）。
- **统一结果外壳**：每个查库结果带 `source: "sync_copy"`、`synced_at`、实现侧生成的人话新鲜度（「数据截至今天 09:41，约 20 分钟前同步」／超 24 小时明说「已过期」／有未同步写入时带「刚写入的一条可能还没反映在副本里」）、`auth_range`（limited 时带 range_note）、日历另带 coverage。工具说明按 §4.4 纪律写：第一句写明是手机整本同步副本、写明何时用何时不用（如 count 不要用 list 自己数）、点名不要去云连接器找人。
- **兜底衔接**：副本从未同步/已删除时，同名工具（contacts_search、reminders_list、calendar_list_events）自动转现行现调并在结果里打 `servedBy: "live_fallback"`＋留痕说明；只有查库形态的工具回结构化错误 `sync_copy_empty` 并把两头状态说清（副本空＋手机在线/离线）。日历问到覆盖窗口外：副本段与现查段分开标注（segments），现查不到的段进 `uncovered` 明示，不冒充。
- **停供开关**：`device_sync.REVOKED_SERVES_COPY = False` 定死在停供档——权限态被上报为 revoked 后，该数据集全部查库工具只回 `permission_revoked` 状态错误、零记录；副本保留，状态里仍可见条数；重开权限（上报 granted 或一次成功同步）即恢复。
- 写工具（日历/提醒的嘴下单四件）成功后给对应数据集打「有未同步写入」标记，下一次同步完成自动清除；`device_status` 扩展了 `sync` 段（逐数据集条数/同步时刻/是否过期/授权范围/权限态）。
- 门禁口径留痕：查库门的依据是副本状态（撤销停供）；现调门沿旧纪律看会话权限。同步本身只在 App 侧三层开关都开时才会发生（App 包职责），桥侧不重复造门。

**front 面板「数据同步」区**
- `front/front.py` 新增 `GET /api/companion/sync`（代理 device 的状态面，只出状态）与 `POST /api/companion/sync/delete`（走既有登录＋CSRF 纪律）。
- 总览页新增「本地数据同步」卡：五行（通讯录/日历/提醒/照片/步数），每行只有条数、同步时刻、授权范围与状态字（已同步/已过期/权限已撤销/正在同步/还没有同步）；**不渲染任何记录明细**。区尾「删除全部同步副本」按钮，二次确认文案按 Muse 删除语义写明：删的是服务器副本，手机数据/权限/配对不受影响；同步开关还开着的话下次同步会重新生成。

**Hermes 配置侧（只做本地可验部分）**
- `HERMES-SYNC-CONFIG-NOTES.md`：变更建议稿——device 服务器保持注册、工具可见性二选一落法（按服务器豁免优先）、静默过滤三查、生效流程定为运维规矩；明确标注生产现值须在部署窗口先读再落改，本稿未动任何生产配置。
- `tests/hermes_sync_acceptance.py`：规格 §5.3 三问验收脚本（新开会话、依次问、打印原答＋启发式核对），部署窗口、Hermes 重载后执行；本次未对生产运行。

**规格落盘**：`device-sync-design-20261110.md` §8 已改为拍板记录（两处决定＋日期＋用户原话要点），§2.2 照片表、§3.4 照片口径、§3.5 撤销口径、§4.3 照片工具四处现稿同步修订。

## 2. 自测证据（全本地，本次实跑）

| 套件 | 结果 |
|---|---|
| supervisor_selftest | 12 passed, 0 failed |
| front_selftest | **29 passed, 0 failed**（原 26，+3：同步状态视图只出状态无记录、删除代理、cookie 无 CSRF 删除 403） |
| overview / oneday p2 / oneday p3 | 全 OK（无回归） |
| device_bridge_selftest | OK（工具清单断言已更新为 21 件精确集合） |
| **device_sync_selftest（新增，30 项）** | **ALL PASS** |
| run_local_stack 整栈演练 | 18 passed, 0 failed |

device_sync_selftest 用模拟数据逐项对数（节选）：7 人通讯录（含同名同号、无电话、空分组样本）→ count=7；stats 有电话 6（85.7%）、有邮箱 4（57.1%）、分组 家人3/同事2、查重候选组=2；list 分页 total/returned/has_more 三页对齐；按纯数字搜中带空格存的号码；上传半途不完成→旧副本不变；完成时应到总数对不上→409 且旧副本不变；清单比对 changed/removed 名单精确、增量换入后更新/新增/删除都对；部分授权后结果带 range_note 且 state 接口回 reimport_required；日历窗口内纯副本、越界自动补现查段并分段标注；提醒 incomplete/due_today/overdue/today_completed 四数对齐；照片 1200 条全量索引分 3 批灌入→总数/类型 960+240/收藏 12/截图 8/按月 10 个月逐月对数；步数旧副本新鲜度明说「已过期」、按日合并同日新盖旧且 7 天前靠历史攒住；写日程后 pending 标记出现、下一次同步后消失；权限撤销→工具只回错误且结果里无 total、副本条数仍在、重开即恢复；删通讯录副本→search 自动回落实查并留痕；删全部→状态清零且 sync.db 文件体积实测变小（VACUUM 生效）。

## 3. 部署所需生产变更清单（供主线另行报批，本次未执行）

1. **伴生镜像重建**：新增 `modules/device_sync.py`，改动 `modules/device_bridge.py`、`front/front.py`、`front/static/index.html`、`front/static/app.js`、`front/static/app.css`、`companion.env.example`（仅注释）。Dockerfile 是整目录 COPY，无需改；建议镜像版本 1.0.1 → 1.0.2，compose 同步标签后 `docker compose up -d companion` 重建（五桥短暂中断，量级同 1.0.1 那次，约数秒）。
2. **数据卷**：无需新卷——sync.db 落在既有 device-data 卷（DATA_DIR=/opt/device-data），首次启动自动建库（0600）。
3. **Hermes 配置**（照 `HERMES-SYNC-CONFIG-NOTES.md`）：先读生产 `tools.tool_search` 现值留痕 → 落可见性口径（二选一）→ 静默过滤三查。device 服务器注册项本身不变（工具面自动更新为 21 件）。
4. **Hermes 重载/重启一次**：让新工具面进入会话工具集——生产动作，须单独报批；重载后**必须新开会话**跑 `tests/hermes_sync_acceptance.py` 三问验收，旧会话不作数。
5. **回滚**：镜像标签改回 1.0.1 重建即回滚桥与面板；sync.db 文件可留置不管（旧版不读它），或一并删除。
6. **App 包依赖**：本次只立契约（同步接口＋工具面＋兜底）。App 侧同步引擎未施工前，副本为空，工具走兜底现调，行为与现状一致、不退化。

## 4. 诚实边界

- 三问验收未实跑（依赖已部署＋已重载的生产 Hermes），属部署窗口收尾段，不在本报告的已验范围。
- 工具说明对模型的实际引导效果（§4.4 第 5 条「模型实测」）同样要等部署后用线上模型验，本次只保证文案按纪律写就。
- 清单比对只对通讯录定义了指纹口径；其余数据集走整换/合并（规格原案如此）。
