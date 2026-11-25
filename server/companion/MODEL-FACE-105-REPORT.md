# 伴生 1.0.5 部署记录（2026-11-11，用户新规：伴生自动修复自动部署）

为 OneDay 0.37.0 模型包补两个伴生侧端点（App 已按契约先行解码，契约
真源＝App 仓 pkg-model 分支 Core GatewayChannels / ModelCombos 与
DESIGN-V4 §100.6 欠账①②）：

1. **GET /api/companion/gateway-channels**（front）：front 持 New API
   网关管理凭据（root 系统访问令牌＋用户 id，只存服务器 companion.env
   [front] 段 NEWAPI_*）只读代理渠道清单。回执字段与 App 解码模型
   逐字对齐：{channels:[{id(字符串),name,status,models[],priority,
   weight,group}]}；网关 status 整数映射 1→enabled／2→disabled／
   3→auto_disabled；models 逗号串切数组；渠道 key 永不转发。网关
   不可达回 502、未配置回 503，如实错误态、不冒充空列表。
2. **GET/PUT /api/oneday-bridge/meta/model-combos**（oneday 桥）：
   组合文档 {combos, activeComboID} 整体存取，与 /meta/brief 同构；
   存 meta.modelCombos（附服务端 savedAt），data.json 0600；PUT 有
   结构校验（坏文档 400 且不动存量）；PUT 回执＝存后文档（App 按
   ModelComboDocument 解码回执）。

顺带修复一处存量配置漂移：服务器 companion.env [global] 的
COMPANION_VERSION 一直停在模板值 1.0.0（监督者分段注入覆盖 compose
值，/info 因此长期报 1.0.0），本次改为 1.0.5 并重启伴生容器生效。

自测（只增不减）：front 33/33（+4 渠道用例）；新增
oneday_model_combos_selftest 全过（14 项，含重启持久化/坏 PUT 不动
存量/0600）；overview 8、p2 34、p3 25、device 桥全过、write-gate 22、
ledger 60 不回退。device_sync 在本机 UTC 环境有 1 项日期假红，按
生产时区 TZ=Asia/Shanghai 复跑全过（存量环境问题，与本版无关）。

部署：基线 1.0.4；回滚基线 /root/companion-105-deploy-20261111/
（compose、companion.env、两容器 inspect、1.0.4 的 front.py/
oneday_bridge.py、构建日志与源码包）。回滚＝基线 compose+env 拷回
/www/dk_project/dk_app/companion 后 docker compose up -d（镜像
1.0.4 仍在服务器）。验收（公网、App 同款单钥）：info 报 1.0.5、
gateway-channels 200 且 9 条渠道字段逐项对齐（渠道 14 DeepSeek 官方
＝deepseek-flash/v4-pro）、model-combos 空→PUT 回显→GET 往返→恢复
空文档全周期、front 首页 200、Hermes /health 200 且 StartedAt
部署前后不变（2026-11-10T14:21:47Z）、台账 26 条 degraded=false、
kanban 源 ok（1.0.4 修复保持）、内存约 50%。
