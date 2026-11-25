# 伴生 1.0.8 部署记录（2026-11-11，用户新规：伴生自动修复自动部署）

为 App 设备扩容批一（DESIGN §111，feat/device-x1 预制）做 device-bridge
侧接线，配合 §111.5 桥侧待办清单全四项：

- TOOLS 表补五件，名与 App 侧 DeviceToolRegistry 逐字一致：
  clipboard_get／clipboard_set／files_list／files_read／files_write，
  入参/回执契约按 §111.1 表（写件必带 idempotencyKey、文件 256 KB
  上限与列表 500 条上限写进工具描述）；工具全集 21→26。
- permissions 门控：新增 NO_PERMISSION_SOURCES={clipboard, files}，
  这两源不走 permission_denied 拦截（App 按 §111.2 恒报 granted，
  桥无论载荷报什么都不拦），门控只认注册 tools 清单（不在清单→
  tool_unavailable，与既有件同路）。
- 写桥侧去重：WRITE_TOOLS 加 clipboard_set／files_write，桥侧
  write-keys 一层去重同样启用（App 账本为第二层）。
- COMPANION_VERSION 升 1.0.8（工作区 Dockerfile ARG 与 compose
  模板同步改，防 1.0.5 式版本漂移复发）。

部署：基线 1.0.7；回滚基线 /root/companion-108-deploy-20261111/
（1.0.7 的 compose、companion.env、两容器 inspect、运行容器内
device_bridge.py.107、本次 build.log/up.log、build-107 源码包
src-107.tgz、生产探针 probe108.py 与 probe.log）。回滚＝基线
compose+env 拷回 /www/dk_project/dk_app/companion 后 docker
compose up -d companion（镜像 1.0.7 仍在服务器）。构建上下文
/root/build-108（build-107 副本仅替换 modules/device_bridge.py，
diff -rq 全树比对恰一文件；新文件 md5 6f3bfbf6… 与本地工作树
一致，旧文件 cac5391c… 与运行中 1.0.7 容器内副本一致），
docker build --build-arg COMPANION_VERSION=1.0.8；镜像层全文件
比对（/opt/companion 共 14 文件）1.0.7↔1.0.8 仅 device_bridge.py
不同。生产 compose 镜像标签与 COMPANION_VERSION、companion.env
[global] COMPANION_VERSION 三处同步改 1.0.8。只重建伴生容器，
Hermes StartedAt 前后不变（2026-11-10T14:21:47Z），内存部署前
50.5%、部署后 50.6%。

自测：部署前本地（TZ=Asia/Shanghai）全套跑通，只增不减：
overview 8／p2 34／p3 26／p4 19／p5 21／p6 26／write-gate 22／
ledger 60／device_sync 30／model-combos 14／device 桥 19（原 11，
+8：工具名册 26、clipboard 载荷报 denied 仍放行、clipboard_set
与 files_write 各执行一次同键回放、files_list/files_read 往返、
未知工具 unknown_tool、未注册工具 tool_unavailable＋最小会话
复验）。

公网复验（App 同款单钥）：/api/companion/info 报
companionVersion=1.0.8、apiLevel 1、hermesUp=true、五模块全 up
（writeGate/overview/box/oneday/device，oneday degraded=false）；
台账 /api/companion/ledger 总 37 条、degraded=false、采集器心跳
新鲜，sessions 与 kanban 两源均 ok:true。

生产桥探针（服务器本机 127.0.0.1:8647，模拟注册载荷，探针脚本
与日志存回滚基线目录）：9/9 全过——tools/list 含五件新工具
（共 26）；clipboard 权限在载荷里故意报 denied，clipboard_get
仍放行往返；clipboard_set／files_write 同键两次各只执行一次、
第二次回 idempotentReplay；files_list／files_read 放行；未知
工具回 unknown_tool；第二会话不列 files_read 时回
tool_unavailable、clipboard_get 照常放行。探针执行时生产无真机
会话在线（device_status online=false），未顶掉用户会话；探针在
write-keys.json 留两条 PROBE108-* 元数据键（无内容），审计日志
有对应条目，均可按前缀辨认。

未验（如实）：真机端到端（App 0.43.0 合并发出后，手机注册带
五件工具的会话实调剪贴板/文件）等 App 侧上线后另验，本单不
假装已通。
