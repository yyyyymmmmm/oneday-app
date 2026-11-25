# CLOSURE-114 · 伴生 1.0.14 监测通知补联动键（配合 App §123 H2）施工报告

日期：2026-11-11。触发：App 闭环包 §123 题二（通知中心点达对象）——监测变化通知在桥侧没有留监测/变化 id，App 点条目无从直达。版本：伴生 1.0.13 → **1.0.14**，已按伴生自动部署授权（2026-11-11 05:17 用户拍板）上线。改动面：`modules/oneday_bridge.py`＋`modules/overview_bridge.py` 两文件＋compose/env 版本位。

## 改动

- `oneday_bridge._notify_locked`：通知记录新增 `refId`＝监测 id、`changeId`＝变化 id（此前记录只有 id/kind/title/body/createdAt/read，通知 id 还是从 change id 切片派生的，App 拿不到完整变化 id）。
- `overview_bridge._make_monitor_notification`：两字段透传（旧记录无此二字段时为 None）。
- `overview_bridge._public`：通知列表出口白名单加 `changeId`（`refId` 原已透传；注释同步更正——旧注释「monitor ones carry none」自此不成立）。

## 兼容与降级

- 存量通知（1.0.14 前落的 monitor-notifications.jsonl 行）无 refId/changeId：overview 照常回、两字段为 null，App 落点如实降级为「只达枢纽监测段」，不拿标题等弱信号猜具体监测。
- App 侧 `OverviewNotification.changeId` 为可选解码，旧桥/新桥双向兼容；审批回执路径未动。

## 施工与回滚基线

- 部署前服务器内存实查：7725MB 总量、已用约 51%（红线 80% 内）；部署后约 51%。
- 回滚基线：服务器 `/root/companion-114-deploy-20261111/`（生产 docker-compose.yml、companion.env、两容器 inspect、部署前内存、1.0.13 版 `oneday_bridge.py.113`／`overview_bridge.py.113`、build.log）。回滚＝基线 compose+env 拷回＋`docker compose up -d companion`（1.0.13 镜像保留在服务器）。
- 构建：`/root/build-114`＝build-113 副本仅替换上述两文件，`diff -rq` 对 build-113 证明恰两文件不同；新文件 md5：oneday_bridge.py `1df75489080a03ef16379c1483fb8d2e`、overview_bridge.py `5cd7562221b4ebe8f45d64e44b129d48`（与本地一致）；镜像 `oneday/companion:1.0.14`（sha256:9829c4ff…）。生产 compose 第 3 行镜像、第 24 行与 companion.env 第 4 行 `COMPANION_VERSION` 均已置 1.0.14。

## 本地自测（全绿，计数与 1.0.13 基线一致）

overview 8／p2 34／p3 29／p4 19／p5 21／p6 45／device OK／write-gate 22／device_sync OK／model-combos OK／ledger 60。另加函数级直验（本地）：`_notify_locked` 产出的记录带 refId＋changeId；overview `_make_monitor_notification`＋`_public` 链路透传两字段；无字段的旧式记录回 null——三断言全过。overview 既有自测「monitor item refId is null」针对旧式记录，仍绿。

## 上线验收

- 容器 `oneday-companion` 运行镜像 1.0.14，进程内 `COMPANION_VERSION=1.0.14`。
- front `build_info()`（以 front 进程真实 environ 复刻探活口径实测）：companionVersion=**1.0.14**、hermesUp=true、五模块全 up（oneday degraded=**false**）。注记：裸 `docker exec` 进程调 build_info 会因缺探活钥把 writeGate/overview 误报 down——与 1.0.13 同一测量假象，本次按原口径排除后面板真值如上。
- 桥 /health（8646）：ok、degraded=false、台账 90 条、采集 lag 18.3 秒。
- Hermes 本体未动：StartedAt 部署前后同为 `2026-11-10T14:21:47.024396739Z`。
- 公网 `/api/companion/info` 未登录回「未登录」，鉴权口径未变。

## 未验（待观察）

生产当前监测变化为 0 条，没有真通知可核 refId 落字；端到端（真变化产生→通知带 id→App 点达具体变化）等第一条真实监测变化出现后随 App §123 真机验收一并核。机制本身已在本地以函数级直验穿过全链（产出→透传→出口）。
