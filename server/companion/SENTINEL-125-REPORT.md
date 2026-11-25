# SENTINEL-125-REPORT — 交付哨兵·伴生侧（1.0.25）

依据：structured-delivery-benchmark-20261111.md 案 A（用户 2026-11-11 19:33 拍板「用市面上最成熟办法」）。把「登记」从智能体自觉改成伴生自动：哨兵尾读 state.db 新助手消息，扫描正文自动登记并关联到消息，App 按消息查附件索引。App 侧接线不在本单（另包）。

## 前置核查（施工单第 3 项，生产实证）

- state.db（容器内 /opt/data/state.db，伴生同挂此卷）：messages 表 id 为全库自增 INTEGER 主键、落库后不变，(session_id, id) 是稳定定位键；role/content/timestamp/active 列齐备。
- 目标消息实况：id 1852、session oneday-side-e389ad26-bfb9-4e68-9dd1-e1b69c3aff7e、role=assistant、content 恰为 `/opt/data/cloud_pc.jpg`、文件实存 57,102 字节，且为当时全库最大 id。定位键成立，未触发「停下回报」。

## 实现（modules/oneday_bridge.py 新增 sentinel 段＋三处接线）

- 触发：oneday 模块内守护线程，每 20s 一轮（DELIVERY_SENTINEL_INTERVAL 可调），mode=ro 只读开 state.db，取 id>水位、role=assistant、active=1、timestamp 至少 2 秒前的行（批上限 500）。水位存 /opt/oneday-data/delivery-sentinel.json（0600，原子替换）；初始水位＝DELIVERY_SENTINEL_START_ID（生产默认 1851，即 1852 为第一条被扫消息）。降级模式（_degraded_reason）下哨兵停写，与登记制同口径；哨兵任何异常只记 /health 的 lastError 与 stderr，绝不拖垮桥（本机无 state.db 环境实测验证）。
- 扫描规则（对齐 Hermes Deliverable Mode）：先掩码代码围栏与行内代码；摘 MEDIA: 目标与裸绝对路径（~/ 按登记根解释）；扩展名白名单＝图片/视频/音频/表格/演示/文档/压缩包/应用/pdf/md/txt/epub——源码类与 .log 故意排除（手动 POST /deliveries 不受影响）；每个候选过与手动登记同一套 _delivery_resolve（根内/非敏感/真实存在）才登记。
- 登记与关联：复用 _delivery_register（指纹去重与手动同账：已手动登记者只关联不重登），随后向同一本 deliveries.jsonl 追加关联行 {"link": true, "kind": "auto", "deliveryId", "sessionId", "messageId", "path", "linkedAt"}；关联行无 "id" 键，_delivery_load 等既有读者天然跳过，老口径零影响。
- 新端点（纯加法）：GET /deliveries/by-message?session_id=<id>[&message_id=<n>] → 单消息 {deliveries:[登记 meta＋实时状态]} 或整会话 {messages:[{messageId, deliveries}]}；未知会话回空 200、缺 session_id 400、message_id 非数字 400；仍走桥钥鉴权。/health 增 deliverySentinel {lastRunAt, lastMessageId, lastError, autoLinks}。
- Hermes 零改动、消息格式零改动、state.db 只读。

## 部署

- 版本：伴生 **1.0.25**，镜像 oneday/companion:1.0.25（sha256 cc2d1d0a55eb…）；构建目录 /root/build-1.0.25（克隆 build-1.0.24 后仅替换 5 个改动文件，oneday_bridge.py md5 0e96267c0fd91a14c756951bac8298fc 本地/服务器逐字一致）。
- 回滚点：/root/companion-125-deploy-20261111/docker-compose.yml.1.0.24（回滚＝还原该 compose 后 up -d，旧镜像 1.0.24 仍在机上）。
- 部署前后：内存约 51%（红线内）；Hermes StartedAt 逐字不变（2026-11-10T14:21:47.024396739Z）；五模块探活与部署前同口径（8643/8644→401 需钥、8645/8647→200、8650 在线、8646 health 200 带哨兵状态）。

## 验收证据

1. **自测**：新增 tests/oneday_delivery_sentinel_selftest.py **23 项全过**（MEDIA/裸路径摘取、围栏与行内代码豁免、缺失文件跳过、源码扩展名排除、user 角色不扫、同文件两消息共用一登记、实时尾随新消息、重启水位防重、索引端点形态与鉴权、health 状态），已挂 run_bridge_selftests.sh。全套自测其余全绿（overview/p2–p6/device/write-gate rules+anchor/device_sync/spreadsheet/ledger/delivery 40 项）；rendition 在本机直跑因其自测写死同目录副本路径而误报，按套件 staging 方式补跑 **22/22 全过**，与 1.0.23 报告的本机内存门环境性失败同源、与本次改动无关（生产侧 rendition 1.0.23 已实测 200）。
2. **生产自证（19:22 真实场景）**：上线首轮哨兵即处理消息 1852——GET /deliveries/by-message?session_id=oneday-side-e389ad26-bfb9-4e68-9dd1-e1b69c3aff7e&message_id=1852 回 {deliveries:[{id: **dlv_63f5476e6f98cc06c1ae**, name: cloud_pc.jpg, size: 57102, kind: image, width/height: 1280×800, sha256: e10e4c1e…, status: ok, cover: {thumb: true, cover: true}}]}；sha256 与 hermes 容器内对实文件 sha256sum 逐字一致、size 与 stat 一致；账本尾部登记行＋kind=auto 关联行俱在；封面实产 thumb.jpg 8,713 B / cover.jpg 49,550 B；/health 哨兵状态 lastMessageId=1852、autoLinks=1、lastError=null；水位文件已落盘 {"lastMessageId": 1852}。

## 覆盖范围（如实说明）

- 存量不回溯：初始水位 1851 ⇒ 覆盖消息 id ≥1852（2026-11-11 19:21:44 起）的全部助手消息及其后新消息；更早消息无索引，App 继续走既有回拼兜底。
- 固有边界（案 A 已知）：智能体生成了文件但正文只字未提的形态仍漏；正文「只是提及」的已存在文件会被挂卡（呈现层、可逆、无数据副作用），与上游 Deliverable Mode 同口径。
- App 侧接线（按索引渲染、路径行降级）不在本单，另包跟进；在此之前用户面不变，索引仅供查询与验收。
