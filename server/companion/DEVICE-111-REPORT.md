# 伴生 1.0.11 部署记录（2026-11-11，用户新规：伴生自动修复自动部署）

为 App 设备扩容批四（DESIGN §115，feat/device-x4 预制）在
device-bridge 侧接线，配合 §115.5 桥侧待办清单全五项。至此
设备 A 档四批工具在桥侧全部接线完毕：

- TOOLS 表补十五件，名与 App 侧 DeviceToolRegistry 逐字一致
  （施工前已对 x4 worktree 的 DeviceSources.swift 名册逐字
  核源）：location_current／location_search_places／
  location_geocode／media_library_search／media_playlists／
  media_playlist_create／media_playback_control／call_start／
  compose_sms／compose_email／share_sheet／shortcut_run／
  device_info／file_preview／file_print，入参/回执契约按
  §115.1 表。工具全集 38→53。
- permissions 门控分清两档：新键 location/media 是**真权限
  键**——App 报系统原态，桥先行回 permission_denied（不唤醒
  手机），与 alarm/notifications/camera 同档；compose/
  shortcuts/deviceinfo 是 notApplicable 恒通组，
  NO_PERMISSION_SOURCES 由七件扩至十件，门控只认注册 tools
  清单。file_preview/file_print 不设新键，随既有 files 键
  放行。两档不许混，代码注释已写明。
- 写桥侧去重：WRITE_TOOLS 只加 media_playlist_create／
  media_playback_control 两件。**在场七件点名禁回放**
  （call_start/compose_sms/compose_email/share_sheet/
  shortcut_run/file_preview/file_print）：它们不改任何状态、
  只把系统面交到用户手上，回放旧「已打开」回执会把在场前
  提放掉——沿 1.0.10 的双闸先例：其一七件均不进 WRITE_TOOLS
  且契约无 idempotencyKey；其二 NEVER_REPLAY_TOOLS 由
  {auth_biometric} 扩至八件，_live_tool_call 取键条件硬排除，
  即使日后有人照写工具模板误加也回放不了。自测与生产探针
  均验：compose_sms/shortcut_run 连同键入参连调两次、手机
  真实执行两次、无一回 idempotentReplay。
- 在场类超时：TOOL_TIMEOUTS 扩入 compose_sms/compose_email/
  share_sheet/shortcut_run/file_preview/file_print 六件
  =150 秒（与批三同一张表、同一环境变量
  DEVICE_PRESENCE_TIMEOUT_SEC），§115.5.4 口径；shortcut_run
  的 App 侧回执等待上限 100 秒在桥侧 150 秒之内，先到先回。
  call_start 不入此表：它只打开系统拨号确认面便即时回
  initiated、从不等通话发生（§115.5.4 枚举亦未含它）；
  location_*/media_*/device_info 现读现回，走普通 30 秒。
- COMPANION_VERSION 升 1.0.11（工作区 Dockerfile ARG、
  compose 镜像标签与 COMPANION_VERSION 同步改）。

部署：基线 1.0.10；回滚基线 /root/companion-111-deploy-20261111/
（1.0.10 的生产 compose、companion.env、两容器 inspect、运行
容器内 device_bridge.py.110、src-110.tgz 与 src-111.tgz、
build.log/up.log、生产探针 probe111.py 与 probe.log）。回滚＝
基线 compose+env 拷回 /www/dk_project/dk_app/companion 后
docker compose up -d companion（镜像 1.0.10 仍在服务器）。
构建上下文 /root/build-111（build-110 副本仅替换
modules/device_bridge.py，diff -rq 全树比对恰一文件；新文件
md5 d5d6a1b3… 与本地工作树一致，旧文件 35cc3a95… 与运行中
1.0.10 容器内副本及 1.0.10 报告记录一致），docker build
--build-arg COMPANION_VERSION=1.0.11；镜像层全文件比对
（/opt/companion 共 14 文件）1.0.10↔1.0.11 仅
device_bridge.py 不同。生产 compose 镜像标签与
COMPANION_VERSION、companion.env [global] COMPANION_VERSION
三处同步改 1.0.11。只重建伴生容器，Hermes StartedAt 前后
逐字不变（2026-11-10T14:21:47Z），内存部署前 50.7%、部署后
50.6%。

自测：部署前本地（TZ=Asia/Shanghai）全套 11 套件全 OK，只增
不减：overview 8／p2 34／p3 26／p4 19／p5 21／p6 26／
write-gate 22／ledger 60／device_sync 30／model-combos 14／
device 桥 52（原 35，+17：工具名册 53、定位三件往返、媒体
检索/歌单列表往返、media_playlist_create 与
media_playback_control 各执行一次同键回放、device_info 在
载荷报 denied 时仍放行（恒通口径）、call_start 往返、
compose_sms 与 shortcut_run 带键入参两次都真下发不回放、
compose_email/share_sheet/file_preview/file_print 往返、
翻转会话里 location 与 media denied 各自先行拦截且手机零
执行）；另有静态断言 10 项全过（十五件名与源分工逐字、
WRITE_TOOLS 恰为旧 12＋媒体两件、NEVER_REPLAY 八件且与
WRITE_TOOLS 不相交、恒通组新增三件、location/media 不在
恒通组、六件新在场超时 =150、call_start 不在超时表、批三
三件超时不回归）。

公网复验（App 同款单钥）：/api/companion/info 报
companionVersion=1.0.11、apiLevel 1、hermesUp=true、五模块
全 up（writeGate/overview/box/oneday/device，oneday
degraded=false）；台账 /api/companion/ledger 总 57 条、
degraded=false，collector sources 的 sessions 与 kanban 两
源均 ok:true。

生产桥探针（服务器本机 127.0.0.1:8647，模拟注册载荷，探针
脚本与日志存回滚基线目录）：14/14 全过——tools/list 共 53
件含批四十五件；location_current 往返；media_playlist_create
与 media_playback_control 同键两次各只执行一次、第二次回
idempotentReplay；device_info 在载荷报 denied 时仍往返
（恒通口径对照）；compose_sms 与 shortcut_run 带键入参两次
都真实下发（执行计数各 2）、无一回放；file_preview/
file_print 往返；unknown_tool；location 与 media 报 denied
时各自先行 permission_denied 且手机零执行。探针执行时生产
无真机会话在线（device_status online=false），未顶掉用户
会话，探针后会话已断开、online 复归 false；探针在
write-keys.json 留 PROBE111-* 元数据键（无内容），审计日志
有对应条目，均可按前缀辨认。

未验（如实）：真机端到端（App 0.46.0 合并发后，手机注册带
十五件新工具的会话实调定位现读＋附近检索、媒体检索/建歌
单/播放控制、拨号确认、短信与邮件的发出/取消各一、分享、
带回执的快捷指令跑通一条、设备信息、文件预览/打印各一，
含定位与媒体库真机授权）等 App 侧上线后另验，本单不假装
已通。
