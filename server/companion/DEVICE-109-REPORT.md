# 伴生 1.0.9 部署记录（2026-11-11，用户新规：伴生自动修复自动部署）

为 App 设备扩容批二（DESIGN §113，feat/device-x2 预制）做 device-bridge
侧接线，配合 §113.5 桥侧待办清单全四项：

- TOOLS 表补五件，名与 App 侧 DeviceToolRegistry 逐字一致：
  alarm_set／alarm_list／alarm_cancel／notify_post／open_target，
  入参/回执契约按 §113.1 表（闹钟 at/afterSeconds 恰一、倒计时
  5 秒～24 小时；通知 delaySeconds 上限 7 天、待发 64 条上限；
  open_target 只认白名单 id、任意 URL 不入桥面）；表面图草案名
  （alarm_schedule/notify_schedule/open_link 等）不留双轨。
  工具全集 26→31。
- permissions 门控分清三档：新源 alarm/notifications 是**真权限
  键**——App 报系统原态，桥在 `_live_tool_call` 既有权限检查处
  先行回 permission_denied（不唤醒手机）；opener 无系统权限，
  NO_PERMISSION_SOURCES 由 {clipboard, files} 扩为加 opener，
  门控只认注册 tools 清单。alarm/notifications 不许混入恒通组，
  代码注释已写明三档分工。
- 写桥侧去重：WRITE_TOOLS 加 alarm_set／alarm_cancel／
  notify_post／open_target，桥侧 write-keys 一层去重同样启用
  （App 账本为第二层）；open_target 重点验：同键重发回放原
  回执、不再跳第二次。
- COMPANION_VERSION 升 1.0.9（工作区 Dockerfile ARG 与 compose
  模板同步改，防 1.0.5 式版本漂移复发）。

部署：基线 1.0.8；回滚基线 /root/companion-109-deploy-20261111/
（1.0.8 的 compose、companion.env、两容器 inspect、运行容器内
device_bridge.py.108、本次 build.log/up.log、build-108 源码包
src-108.tgz、build-109 源码包 src-109.tgz、生产探针 probe109.py
与 probe.log）。回滚＝基线 compose+env 拷回
/www/dk_project/dk_app/companion 后 docker compose up -d
companion（镜像 1.0.8 仍在服务器）。构建上下文 /root/build-109
（build-108 副本仅替换 modules/device_bridge.py，diff -rq 全树
比对恰一文件；新文件 md5 36bffd75… 与本地工作树一致，旧文件
6f3bfbf6… 与运行中 1.0.8 容器内副本及 1.0.8 报告记录一致），
docker build --build-arg COMPANION_VERSION=1.0.9；镜像层全文件
比对（/opt/companion 共 14 文件）1.0.8↔1.0.9 仅
device_bridge.py 不同。生产 compose 镜像标签与
COMPANION_VERSION、companion.env [global] COMPANION_VERSION
三处同步改 1.0.9。只重建伴生容器，Hermes StartedAt 前后不变
（2026-11-10T14:21:47Z），内存部署前 50.5%、部署后 50.6%。

自测：部署前本地（TZ=Asia/Shanghai）全套跑通，只增不减：
overview 8／p2 34／p3 26／p4 19／p5 21／p6 26／write-gate 22／
ledger 60／device_sync 30／model-combos 14／device 桥 26（原 19，
+7：工具名册 31、alarm_set 与 alarm_cancel 各执行一次同键回放、
alarm_list 往返、notifications 报 denied 时 notify_post 先行
拦截且手机零执行、opener 报 denied 仍放行且 open_target 同键
回放不二跳、翻转会话里 notify_post 放行回放与 alarm_set 先行
拦截）。

公网复验（App 同款单钥）：/api/companion/info 报
companionVersion=1.0.9、apiLevel 1、hermesUp=true、五模块全 up
（writeGate/overview/box/oneday/device，oneday degraded=false）；
台账 /api/companion/ledger 总 44 条、degraded=false、采集器
心跳 3 秒内新鲜，collector sources 的 sessions 与 kanban 两源
均 ok:true。

生产桥探针（服务器本机 127.0.0.1:8647，模拟注册载荷，探针脚本
与日志存回滚基线目录）：11/11 全过——tools/list 含五件新工具
（共 31）；alarm_set／alarm_cancel／open_target 同键两次各只
执行一次、第二次回 idempotentReplay；alarm_list 放行；
notifications 报 denied 时 notify_post 回 permission_denied 且
手机零执行；alarm 报 denied（翻转会话）时 alarm_set 同样
先行拦截；opener 在载荷里故意报 denied，open_target 仍放行
往返；clipboard_get 恒通口径对照仍成立；未列工具回
tool_unavailable；未知工具回 unknown_tool。探针执行时生产无
真机会话在线（device_status online=false），未顶掉用户会话，
探针后会话已断开、online 复归 false；探针在 write-keys.json
留 PROBE109-* 元数据键（无内容），审计日志有对应条目，均可
按前缀辨认。

未验（如实）：真机端到端（App 0.44.0 合并发出后，手机注册带
五件新工具的会话实调闹钟/通知/拉起，含 AlarmKit 真机授权与
schedule 落位）等 App 侧上线后另验，本单不假装已通。
