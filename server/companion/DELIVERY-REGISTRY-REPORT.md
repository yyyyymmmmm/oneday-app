# DELIVERY-REGISTRY-REPORT — 文件交付登记制·伴生侧（1.0.23）

规格：~/workspace/oneday-design-review/delivery-registry-spec-20261111.md（全链定版，含 App 消费契约与 SOUL 条款文本 §9——SOUL 落盘归主线，本单未动 SOUL）。

## 部署

- 版本：伴生 **1.0.23**（顺延 1.0.22）。镜像 `oneday/companion:1.0.23`，sha256 f5ea6c231e66…；构建目录 /root/build-1.0.23；回滚点 /root/companion-123-deploy-20261111/（内含切版前生产 compose 备份；回滚＝compose 两处版本位改回 1.0.22 后 up -d，旧镜像仍在）。
- 实现位置：**挂 oneday 模块**（modules/oneday_bridge.py 新增 deliveries 段＋Handler._dispatch_deliveries），复用 `/api/oneday-bridge/` 单钥网关与既有桥钥，未新增端口/nginx/钥。
- 本地树同步改动：modules/oneday_bridge.py、modules/assets/NotoSansSC-subset.ttf（新增，见下）、tests/oneday_delivery_selftest.py（新增）、tests/run_bridge_selftests.sh（挂新自测＋staging 带 assets）、Dockerfile/docker-compose.yml 版本位 1.0.23。服务器构建目录模块 md5 与本地逐字一致（oneday_bridge.py 865928476cf56d03b9afcf0224f15a69）。
- 部署前后：内存 54%→53%（红线内）；Hermes StartedAt 逐字不变（2026-11-10T14:21:47.024396739Z）；Hermes 未重启、配置未动。五桥探活正常（8643/8644 无钥回 unauthorized 为其常态；8646 oneday ok、台账 172 条）。

## 端点契约（as-built，与规格一致）

- `POST /deliveries`，body 只有 `{"path": "<绝对路径>"}`。路径规则镜像 spreadsheet 口径：根＝DELIVERY_ROOT（默认 /opt/data）、resolve 后必须在根内（400）、敏感名 403、不存在 404、非文件 400。回执 201（去重命中 200＋`deduped:true`）：`{id, marker, status, name, path, size, mime, kind, width, height, sha256, registeredAt, cover:{thumb, cover}}`。幂等键 (path, sha256, size)。
- `GET /deliveries/{id}` → meta＋读时状态（ok/stale/gone 按 size+mtime 实时复核）；未知/坏形 id 404。
- `GET /deliveries/{id}/thumb|cover` → 登记时快照 JPEG（Cache-Control immutable）；无此封面 404；文件已删 410。
- 登记号 `dlv_`＋20 位十六进制（secrets 80 bit）；标记 `[[deliver:dlv_…]]` 独立成行；登记账 append-only `/opt/oneday-data/deliveries.jsonl`（实测 0600）；封面落 `/opt/oneday-data/deliveries/<id>/{thumb,cover}.jpg`。
- 封面分工 as-built：image＝Pillow 双档（360/1080，EXIF 校正）；video＝ffmpeg 1s 海报帧双档；文本类（md/txt/log/csv/tsv＋code）＝840×560 纸面首屏渲染（标题＋正文行）；pdf/office/表格/压缩包等 cover=false，留 App §32 客户端管线。空白守卫（近白 ≥98%）只作用于服务端渲染类（文字/海报），不作用于真实图片文件（文档截图本就近白，误杀教训已写进代码注释）。源文件 >64MB 或图片 >100MP 跳过封面、登记照常。
- 文字封面字体：NotoSansCJK-Regular.ttc 的 SC 面子集化（U+0020-007E＋常用标点/箭头＋CJK 基本＋扩展 A＋全角），实产 **12,057,012 字节**（比预估大；功能已验，镜像增重约 12MB，如需瘦身可再收 unicode 范围，非阻塞）。

## 验收证据

1. **自测**：新 oneday_delivery_selftest **40 项全过**（鉴权/路径四错/元数据逐项对账真文件/指纹去重不追加/图封面几何/840×560 文本画布/ok→stale→gone/410）。全套自测其余全绿，**唯一例外 oneday_bridge_rendition_selftest 在本机失败**：其生成路径有「主机内存 >85% 回 503」的设计门，本开发 VM 内存约 91%，属环境性失败、非代码问题；证据：该路由缓存命中路径已单独烟测通过（200＋ETag＋immutable＋If-None-Match 304），且**生产实测生成 200**（见 3）。
2. **真登记对账**（生产，桥钥容器内取用未打印）：
   - 图 `/opt/data/screenshot_20261111_1709.png` → `dlv_93c016547852c522bbba`；size 68026 与 stat 一致；sha256 `72edc19c…e576` 与宿主机 sha256sum 一致；宽高 1280×800 与 Pillow 实测一致；thumb 8,390 B / cover 47,841 B 经 HTTP 取回，thumb 拉到本地亲眼验＝真截图内容。
   - 文档 `/opt/data/通讯录人数口径.md` → `dlv_db244d5043c8ed612ac8`；size 6377、sha256 `d3e82dfa…bf1` 均与实文件一致；cover 85,144 B 拉到本地亲眼验＝840×560 纸面渲染、标题「通讯录总人数 · 口径备注（可直接引用）」与正文中文完整可读、无豆腐块（渲染保留原始 markdown 记号，属首屏实况）。
3. **§138 rendition 生产复验**（与本单同树上线）：GET /media/rendition?w=360 对同一 PNG 生成 200、image/jpeg、ETag、immutable、8,390 B。
4. **智能体试验**（测试会话 `delivery-registry-trial-20261111`，未改 Hermes 配置、未重启）：智能体按规格 §9 流程自助完成——写文件 /opt/data/delivery-trial-20261111.md → 用自身进程环境 API_SERVER_KEY 经**公开通道**登记（HTTP 201）→ 回复正文独立成行粘贴标记。state.db 回读该条助手消息，标记原文坐实：
   `[[deliver:dlv_a6fc654739fd597ff861]]`
   登记账现 3 行（验收 2＋试验 1）；试验 meta GET 回读 status ok、size 82、sha256 与智能体自述一致。

## 并发注记（须主线知悉）

施工期间 §138 影音线（797953d9 线）的桥侧代码在同一棵本地树落地（modules/oneday_bridge.py 于 17:26 CST 有一次他们的收尾写入：统一 `_send_bytes` 为带 etag 版，与本单调用点兼容）。本单部署的树同时包含其 rendition 端点，已一并验活（见验收 3）。本单自测与部署均以该最终树为准，md5 见上。

## App 包接线清单（规格 §11 冻结，样本现成）

- Core：标记正则 `\[\[deliver:(dlv_[0-9a-f]{20})\]\]` 解析（独立行）＋钉测（独立行/多标记/坏 id/与 MEDIA 行共存）。
- Client：走既有 oneday-bridge 通道三口（meta/thumb/cover），meta 按 id 永久缓存。
- 呈现：image 内联复用 §130 定高卡＋§33 递进口径；其余 kind 复用 §125 白卡（cover 图＋文件名＋类型·大小行），点开走 FileOpenView（meta.path 走既有 download）。
- 降级：gone → 一行「<文件名>（文件已删除）」不可点；id 404 → 标记按纯文本原样显示；cover 404 → §32 客户端管线→C8 图标面。
- 验收样本登记号：图 dlv_93c016547852c522bbba、文档 dlv_db244d5043c8ed612ac8、试验 dlv_a6fc654739fd597ff861（会话 delivery-registry-trial-20261111）。
