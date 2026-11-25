# 伴生 1.0.10 部署记录（2026-11-11，用户新规：伴生自动修复自动部署）

为 App 设备扩容批三（DESIGN §114，feat/device-x3 预制）在
device-bridge 侧接线，配合 §114.5 桥侧待办清单全五项：

- TOOLS 表补七件，名与 App 侧 DeviceToolRegistry 逐字一致：
  camera_capture／vision_document_scan／vision_ocr／
  vision_scan_code／translate_text／ondevice_model_run／
  auth_biometric，入参/回执契约按 §114.1 表（拍照/扫描必带
  idempotencyKey；翻译 source 必填、target 缺省按源语言定；
  端上模型每次新会话不带上文；本人确认 reason 必填且无
  idempotencyKey）。工具全集 31→38。
- permissions 门控分清两档：新源 camera 是**真权限键**——App
  报系统原态，桥先行回 permission_denied（不唤醒手机），与
  alarm/notifications 同档；vision/translate/ondevice/
  biometric 是 notApplicable 恒通组，NO_PERMISSION_SOURCES 由
  {clipboard, files, opener} 扩至七件，门控只认注册 tools
  清单。ondevice_model_run 随机型可用性在 tools 清单里出现/
  消失属正常，桥不判异常（自测与探针均以 tool_unavailable
  平常路验证）。两档不许混，代码注释已写明。
- 写桥侧去重：WRITE_TOOLS 只加 camera_capture／
  vision_document_scan 两件。**auth_biometric 点名禁回放**：
  回放旧「确认通过」会把在场门放掉——双闸防之：其一它不进
  WRITE_TOOLS 且契约无 idempotencyKey；其二新增
  NEVER_REPLAY_TOOLS={auth_biometric}，_live_tool_call 的
  取键条件硬排除，即使日后有人照写工具模板把它误加进
  WRITE_TOOLS 也不会回放。自测与生产探针均验：相同入参连调
  两次、手机真实执行两次、无一回 idempotentReplay。
- 在场类超时：新增按工具超时表 TOOL_TIMEOUTS，
  camera_capture/vision_document_scan/auth_biometric 三件
  =150 秒（环境变量 DEVICE_PRESENCE_TIMEOUT_SEC 可调），
  其余工具仍走全局 DEVICE_CALL_TIMEOUT_SEC（默认 30 秒）。
  落数依据：§114.5.4 要求 ≥120 秒量级，150＝120 下限＋多页
  扫描与面容重试的余量；桥内无更低的单调用上限（手机长轮询
  25 秒一循环反复轮询、待答调用记录不依赖轮询节奏；App 侧
  等待被取消会自关界面回错误收尾，不挂死）。注：Hermes 本体
  若另有 MCP 调用超时，不在本包文件面内，未验。
- COMPANION_VERSION 升 1.0.10（工作区 Dockerfile ARG、
  compose 镜像标签与 COMPANION_VERSION 同步改）。

部署：基线 1.0.9；回滚基线 /root/companion-110-deploy-20261111/
（1.0.9 的生产 compose、companion.env、两容器 inspect、运行
容器内 device_bridge.py.109、src-109.tgz、src-110.tgz、
build.log/up.log、生产探针 probe110.py 与 probe.log）。回滚＝
基线 compose+env 拷回 /www/dk_project/dk_app/companion 后
docker compose up -d companion（镜像 1.0.9 仍在服务器）。构建
上下文 /root/build-110（build-109 副本仅替换
modules/device_bridge.py，diff -rq 全树比对恰一文件；新文件
md5 35cc3a95… 与本地工作树一致，旧文件 36bffd75… 与运行中
1.0.9 容器内副本及 1.0.9 报告记录一致），docker build
--build-arg COMPANION_VERSION=1.0.10；镜像层全文件比对
（/opt/companion 共 14 文件）1.0.9↔1.0.10 仅
device_bridge.py 不同。生产 compose 镜像标签与
COMPANION_VERSION、companion.env [global] COMPANION_VERSION
三处同步改 1.0.10。只重建伴生容器，Hermes StartedAt 前后
不变（2026-11-10T14:21:47Z），内存部署前 50.5%、部署后
51.0%。

自测：部署前本地（TZ=Asia/Shanghai）全套跑通，只增不减：
overview 8／p2 34／p3 26／p4 19／p5 21／p6 26／write-gate 22／
ledger 60／device_sync 30／model-combos 14／device 桥 35
（原 26，+9：工具名册 38、camera_capture 与
vision_document_scan 各执行一次同键回放、vision_ocr 在载荷
报 denied 时仍放行（恒通口径）、vision_scan_code／
translate_text／ondevice_model_run 往返、auth_biometric 同
入参两次都真下发不回放、翻转会话里 camera denied 先行拦截
且手机零执行、ondevice 未列回 tool_unavailable）；另有静态
断言一组（七件名册与源分工、WRITE_TOOLS 只含两件、
NEVER_REPLAY 双闸、恒通组四件、camera 不在恒通组、三件
超时 ≥120）全过。

公网复验（App 同款单钥）：/api/companion/info 报
companionVersion=1.0.10、apiLevel 1、hermesUp=true、五模块
全 up（writeGate/overview/box/oneday/device，oneday
degraded=false）；台账 /api/companion/ledger 总 50 条、
degraded=false、采集器心跳 6 秒内新鲜，collector sources 的
sessions 与 kanban 两源均 ok:true。

生产桥探针（服务器本机 127.0.0.1:8647，模拟注册载荷，探针
脚本与日志存回滚基线目录）：11/11 全过——tools/list 共 38
件含批三七件；camera_capture／vision_document_scan 同键
两次各只执行一次、第二次回 idempotentReplay；vision_ocr
在载荷报 denied 时仍往返（恒通口径对照）；translate_text／
ondevice_model_run 往返；auth_biometric 相同入参两次都真实
下发（执行计数 2）、无一回放；camera 报 denied 时
camera_capture 先行 permission_denied 且手机零执行；
ondevice 未列回 tool_unavailable。探针执行时生产无真机会
话在线（device_status online=false），未顶掉用户会话，探
针后会话已断开、online 复归 false；探针在 write-keys.json
留 PROBE110-* 元数据键（无内容），审计日志有对应条目，均
可按前缀辨认。

未验（如实）：真机端到端（App 批三包合并发出后，手机注册
带七件新工具的会话实调真拍＋OCR 组合、扫文档、翻译已装
语言对、端上问答、本人确认过/取消各一，含相机真机授权）
等 App 侧上线后另验，本单不假装已通。
