# 收官窗口执行报告：AI 内部权限四门面注册＋全集复验（2026-11-13）

## 结论先行

**注册全成，Hermes 只重启了一次。** mcp_servers 由 3 条（notion/github/device）增至 7 条，新增 oneday-goals（4 工具）、oneday-sessions（1）、oneday-automation（6）、identity（6）全部 Connected 并逐门面真调冒烟通过；真会话端到端证明成立（运行中的 AI 真调了新工具并答对）。设备桥 53 件与桥侧逐名对账 **53/53 全合**，注册冻结旧账就此销。辅助模型写回**热生效实测成立**（改值不重启、运行进程即刻用上，网关日志实证），测完已恢复原值。PAT/GitHub 一件**跳过**：bw CLI 未登录（unauthenticated），本线未能核查条目是否存在——是「未核查」不是「不存在」，待主线经浏览器已解锁库面一查便知；github 既有条目未动。伴生容器全程未动；服务器内存全程 49–57%（红线 80% 内）。

## 一、备份与回滚基线

- 备份（服务器 `/www/dk_project/dk_app/hermes/data/`，0600 区）：
  - `config.yaml.bak-20261113-closing-window`（注册前整份）
  - `.env.bak-20261113-closing-window`（本窗实际未改 .env，备份仅备查）
  - `config.yaml.bak-20261113-auxtest`（注册后、aux 实测前的整份，aux 恢复即以此为准）
- 回滚命令（还原注册前配置＋重启一次）：
  ```bash
  cp /www/dk_project/dk_app/hermes/data/config.yaml.bak-20261113-closing-window \
     /www/dk_project/dk_app/hermes/data/config.yaml
  docker restart hermes
  ```
- nginx **零改动**：四个门面全部走既有单钥网关路由（见下），不需要补任何精确段，原定的 identity /api/identity-mcp 备用方案未启用。

## 二、注册方式与前后对照

注册形态照 device 先例（config.yaml `mcp_servers` 条目＋`${VAR}` 引 .env），但钥匙不新发：四条新门面都指向既有单钥网关地址、Authorization 统一引既有的 `API_SERVER_KEY`（登录钥）——nginx 的 auth_request 验登录钥后自动换成各桥自己的服务钥，与 App 的单钥口径一致。

| 条目 | URL | 钥 | 工具数 |
|---|---|---|---|
| notion（原有） | https://mcp.notion.com/mcp | oauth | — |
| github（原有） | https://api.githubcopilot.com/mcp/ | 原有 | — |
| device（原有） | …/api/device-mcp | DEVICE_BRIDGE_KEY | 53 |
| **oneday-goals（新）** | …/api/oneday-bridge/mcp | API_SERVER_KEY | 4 |
| **oneday-sessions（新）** | …/api/oneday-bridge/mcp-sessions | API_SERVER_KEY | 1 |
| **oneday-automation（新）** | …/api/oneday-bridge/automation-mcp | API_SERVER_KEY | 6 |
| **identity（新）** | …/api/identity-bridge/mcp | API_SERVER_KEY | 6 |

重启前已用登录钥对四个网关地址逐个实调 initialize＋tools/list 全通（serverInfo 与工具数逐一对上），才动配置。配置插入后先用 Hermes 自家 CLI 解析校验（`hermes mcp list` 显示 7 条全 enabled）才重启。

## 三、重启与健康

- 重启前 StartedAt：`2026-11-10T14:21:47.024396739Z`（与各包报告一致）。
- 唯一一次重启：2026-11-13T06:50:37Z 发起 `docker restart hermes`，新 StartedAt **`2026-11-13T06:50:45.797753195Z`**。启动瞬间 /health 短暂 502（进程未就绪），随后 200 并保持；窗口结束复查 StartedAt 未再变化（没有发生第二次重启，aux 实测亦未重启）。
- `hermes mcp test` 逐条：device ✓ Connected 53、oneday-goals ✓ 4、oneday-sessions ✓ 1、oneday-automation ✓ 6、identity ✓ 6。

## 四、逐门面冒烟实证（真接口真调用，非只看 tools/list）

- **goals**：经门面 goals_create 建目标 `g_659f1bcffa22`「收官窗口验证·20261113」→ GET /traces 命中其留痕 `trc_961d2edb046f`（action=goals.create、ok）→ goals_list 在列 → REST DELETE 删除 → 复列已无。删净。
- **identity（只读）**：identity_get_name 回 soulName=「Hermes」（现行回落，符合预期）；identity_get_avatar 回 currentId `av_2e641abbecd6`（preset partner）。**未调 set_name**——第一次真改名留给注册后的 AI 自己，未动 SOUL.md。
- **automation**：cron_list 回 0 条（引擎无任务，符合现状）；kanban_create_task 建卡 `t_ac40cef2` → kanban_get_task 读回 status=ready → 经插件 API 删除（200 deleted:true）→ 复读 404；reach_send 以 dryRun=true 调用回 `{delivered:false, dryRun:true, queued:false}`，未真发（注：正文字段名是 `text`，首调误用 `body` 被桥当场以「消息正文不能为空」拒收、改对后通过——失败留痕纪律正常工作）。
- **sessions**：sessions_create 造旁聊 `oneday-ai-dcf2104b58aa82c9f6ea9cda6acd7d36`，parentSessionId＝现行主线 `oneday-main-bfb4e3ed-…`，briefPosted=true、runId 在列、traceId `trc_f6867ba9bc2c`；GET /traces?targetId 命中 1 条 ok 痕；state.db 实查会话行在（source=api_server、标题原样、正文零污染），简报真跑：assistant 回「收官自验通过」与简报指令逐字一致；围栏 DELETE 200（deleted_ids 含该会话）→ 回读 sessions/messages 均 0 行。**清理口径更正一笔**：围栏参数须走 **query string**（`?request_id=&expected_revision=&expected_generation=`），放 JSON body 会被当作无围栏请求回 409 client_upgrade_required（源码 web_server_sessions.py 的无围栏判定实证）——DESIGN §199.6 记的是 body 形态，建议主线更正该备忘。
- **真会话端到端（本窗最强证据）**：新建 API 会话 `api_1794552904_704e6193`，让 AI「用 goals_list 列目标、用 identity_get_name 查名字、必须真调工具」——state.db 实录两条 tool 结果，来源分别是 `mcp__oneday_goals__goals_list` 与 `mcp__identity__identity_get_name`，最终答复「你有一个目标「吃东西」（已完成），我的名字是 Hermes。」两项事实全对。验证会话已围栏删除（回读 0 行）。

## 五、设备桥 53 件全集复验

- 桥侧 tools/list 基线（重启前经 /api/device-mcp 实取）：恰 53 件，名单存服务器 /tmp/device_tools_baseline.json。
- 重启后 `hermes mcp test device`：Connected、Tools discovered **53**；逐名与基线对账 **53/53 全合、missing 为空**。注册冻结（2026-11-10 启动快照 21 件）旧账就此销账。
- 抽 3 件真调（含实时型）：device_status 回 online:false＋同步新鲜度（通讯录约 7 分钟前同步）；contacts_count 回 **156**（同步副本真数）；location_current（实时型）回 `device_offline` 诚实错误（手机 App 不在线、没读到不编数）——调用链真通、口径如实。

## 六、辅助模型写回热生效实测

- 靶点：config.yaml 唯一 auxiliary 槽 `vision`（provider: auto、model: ''）。
- 方法：**不重启**，把 model 改为 `claude-haiku-4-5-20251001`，新建会话让 AI 用 vision_analyze 看一张 1×1 测试 PNG（图内容本身不重要，要看的是调用落到哪个模型）。
- 数据层证据：以改值时刻 T0=epoch 1794553000 为界查 New API 网关日志（new-api.logs 按 model_name 分组）：T0 后出现 **2 条 claude-haiku-4-5-20251001 请求**（1794553007、1794553042，与 vision 两次调用的时点吻合），其余 10 条为日常 claude-sonnet-4-6。Hermes 进程 StartedAt 全程未变（06:50:45Z），即运行中的进程直接用上了新写入的辅助模型值。
- 机制（源码实证）：`hermes_cli.config.load_config()` 按文件签名缓存（"Cached on the file signature"），文件一变下次调用即重读；vision 解析在调用点现读 load_config()。**结论：辅助模型写回热生效成立，后续 App 侧写回 auxiliary 不需要再重启 Hermes。**
- 收尾：model 已恢复为 ''（以 auxtest 备份整份还原，还原后复查 mcp 7 条仍全 enabled、aux 块逐字回原样）；测试 PNG 两处（/opt/data 与 cache/scratch 副本）已删；aux 测试会话 `api_1794553000_6c3320c0` 已围栏删除。

## 七、PAT/GitHub：跳过（未核查，非不存在）

本机 bw CLI 存在（~/workspace/bin/bw）且已配置指向 vault.example.com，但 `bw status` 为 **unauthenticated**（CLI 从未登录、无会话）。登录需库主密码，按口径不向用户临时索要、也不经聊天传递，故本线无法核查条目「GitHub PAT · Hermes」是否存在。处理：**跳过该件**，未写 /opt/data/.env、未动 github 条目（其既有授权方式照旧工作）。主线如需办，用浏览器已解锁的库面搜一下条目名即可定论；若在，同窗外单独追加一次配置＋重启即可（或等下个重启窗顺带）。

## 八、账面留存（如实登记，均为留痕本职非垃圾）

- traces 新增数条本窗验证痕（goals.create/list、reach.send 干跑、sessions.create 等），按 P0 设计保留。
- aiSessions 出生记录新增 1 条（本窗测试旁聊，会话本体已删净；出生记录按台账设计无删除门，同 P2 口径）。
- kanbanBindings 留 1 条本窗测试卡绑定（卡已删；watcher 缺 kanban.orphaned 清理系 P4 报告 §五.3 已登记的既有小缺口，同类）。
- 两个测试 API 会话、一个测试目标、一张测试卡、一条测试旁聊：全部删净并回读验证。
