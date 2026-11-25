# 动态配图自托管＋搜图兜底（部署包 2.6.0）应用记录

授权：用户 2026-11-25 02:39 亲批。基线：`/root/deploypkg-2.6.0-20261125/baseline/`（oneday_seg_feed.py.host-pre `8d3de658…`、data.json.pre、hermes.example.com.conf.pre；应用当日补强中间件 oneday_seg_feed.py.amend1-2f5f2f57／amend2-296d24c1；补图前 data.json.pre-minimig）。应用前内存 55%、/v1/runs 无在飞轮。应用后 verify.sh 全量（最终代码）：**齐 111 / 缺 0**（未验 17 全为设计内默认不跑的写型/人工探针；存档 verify-output-2.6.0-applied-20261125.txt）；health ok；GEN_MODEL 口径未动（verify genmodel-funded-route 探针齐，deepseek-v4-pro）。

## 1. 定因（双层，均实证）

1. **列表不显示（主因）**：App `FeedView.swift` §486.3 `isLinkCoverImage`——首图 sourceUrl ∈ post.links 或 == sourceCard.url 即判「链接出处图」，抑制列表通栏封面、改由链接预览卡承载；而 `FeedLinkPreviewCard` 是纯文字卡（站点名＋标题＋域名、无图）。生成侧组装给每图写 `"sourceUrl": image_pool[url]`，image_pool 恒为 {图 URL→提取页 URL}、提取页恒在 links 里——存量 6/6 带图帖全命中抑制，生成帖列表永远无图。详情页逐张 LazyImage 不设防（详情能看、列表没有，与用户观感一致）。
2. **外链脆弱（次因）**：6 条图全为外链热链（其一为 dev.to media2 缩放代理 URL），本机实测当时全 200——不是链死，是形态问题：随外链存活漂移、与自家存储口径不符。
- App 图片管线实查：公开 http(s) URL 走 Nuke 默认 URLSession 直通（HermesImageDataLoader 其余路由才拦截），无鉴权、无域名白名单——自家图地址只须公网无鉴权可达。App 中 sourceUrl 仅被 isLinkCoverImage 使用，置空安全（FeedView 注释明示「空 sourceUrl 不命中」）。

## 2. 落点口径（照 Muse 自家 Feed 形态）

- 存储：网关数据区 `/opt/data/oneday/media/feed`（宿主 `/www/dk_project/dk_app/hermes/data/oneday/media/feed`），文件名＝内容 sha256＋扩展名，内容不可变。
- 地址：`https://hermes.example.com/feed-media/<sha256>.<ext>`，nginx hermes vhost 新增静态 location（alias 直出、immutable 长缓存、无鉴权），形态登记 `services/nginx-feed-media-shape.conf`。
- 帖子条目：`{url: 自家地址, sourceUrl: "", originUrl: 提取页, originImageUrl: 原图 URL}`——sourceUrl 置空解开列表抑制，溯源信息保全。
- 两条运维口径（应用当日实证，写进形态文件）：①数据根目录原为 700（属主 10000），www 穿行被拒致公网 404——`chgrp www`＋`chmod 710`（只穿行、不可列目录，文件本体权限不动）；②media 目录树须网关进程属主（uid 10000）可写，带外预置后必须 `chown -R 10000:10000`（见 §5 事故二）。

## 3. 代码变更（patches/oneday_seg_feed.py，8d3de658…→8d2686cc…，能力 #44）

- `_selfhost_image_entry`／`_selfhost_post_images`：落地前下载（≤10MB）→复核 §122 形状口径（高宽比 >1.2 或宽 <400 丢弃）→内容寻址落盘→条目改写；失败/非图/形状不过一律丢图、绝不留外链；已自托管 URL 幂等直通。挂两个落地流锁外（定版轮 `_run_research_round` 发布前、小时/visit 流落地前）。
- `_fallback_search_images`：候选页提取零图时以页面标题调 Tavily /search（include_images）兜底，命中仍过 `_http_head_ok`＋`_image_shape_ok` 双门、最多 2 张、计入 counts.tavilySearch；挂两处候选构建（reground 与主研究流，均为 `or` 后备）。
- `_landing_fallback_image`（应用当日补强，见 §5）：帖子落地时仍无图（写手未选池图）且非编辑 dropImage 亲摘者，按标题搜图兜底并托管；定版流与小时流两落地口调用，全程留痕（hosted／no-hit／unhostable／search failed 四态进 gateway.log——§441 教训：丢弃路径不许静默）。
- 包内自测 `feed_media_selftest.py` **18/18**（托管改写/幂等/失败丢弃/形状门/兜底双门与计数/本地 HTTP 真下载/落地兜底三态）。

## 4. 存量处理（迁移时点 34 帖：research 23／digest 3／event 8）

方式：网关在跑时 A 段在容器内按同口径下载落盘产 manifest（只写 media＋manifest、不碰 data.json）→停机窗口 B 段按 manifest 改写 data.json（备份在基线）→install 应用新代码→nginx 上线。逐条结果：

- **转存 6/6**（原外链图自托管）：f_00b8890f50da（2400×1260）、f_f463e7b18a89（1280×640）、f_be4ca7ea44a9（803×420）、f_be15964bfc96（1300×731）、f_12899b62a971（1200×630）、f_27c6b0521106（1200×630）。
- **无图 research 补图 17/17**：og 直取 5（f_531413d0dea3 2560×1280、f_6b47605a0297 1200×630、f_9a4226bc984c 1200×630、f_de08e7fb4ec4 1200×630、f_b1a51cce37ce 1200×600）；Tavily 搜图兜底 12（f_054aa78e8b4d 1915×821、f_7b2e9b58f39a 1200×913、f_3d38afe3e3f4 1223×691、f_d80f37d790bf 3488×2158、f_03f16f7a2f43 1280×720、f_c794fe273934 1920×1199、f_10a05fc47c57 1200×630、f_b47ff6b4bd4f 2560×1600、f_46869984dee7 1080×1080、f_6413fc840276 600×375、f_0bd7d99adbd4 1441×1566、f_83650316ee21 600×540）。
- **跳过 11**：digest 3＋event 8——无 links、按设计不成图（本地事件/摘要帖形态）。
- **验证轮新帖补图 8/8**（§5 三轮验证产出的无图帖，收尾时同口径补，og 直取）：f_7230e7a4cd02（1200×630）、f_d8d5355b737e（1280×720）、f_65642bf8b686（1200×630）、f_1201eae83345（900×420）、f_3e916839ded6（1408×768）、f_d6498d2ba05a（2048×1024）、f_bc80860f7599（3836×2038）、f_4ac2f1d1957f（1077×539）。此段全程以 hermes 身份在容器内执行（文件生而属主正确）。

## 5. 应用过程与当日三跤（均已闭环）

- **跤一·install 语义探针误触**：首轮 install 前我手动停了容器，install 的语义就绪探针靠 docker exec、必然探不到，误入 3e 依赖安装并失败退出（seg 本体已正确应用）。处置：起容器→重跑 install 幂等收尾。此后 install 一律不预停容器（停机只为数据改写、且在 install 之前单独完成）。
- **跤二·media 目录属主（真 bug，静默三轮）**：迁移 A 段以 root 在容器内执行，media 目录树 root 属主 755；网关进程以 hermes（uid 10000）运行，托管写盘被拒、条目静默丢图。表现：验证轮 1–2 新帖无图（当时定因在写手未选图——属实但不完整）、轮 3 加留痕后 gateway.log 实证三帖全 `landing fallback unhostable`（搜到图、托管写不进）。处置：`chown -R 10000:10000` media 树；以 hermes 身份本地 HTTP 探针图实测新图落盘成功；口径写进形态文件（§2②）。
- **跤三·写手不选图（管线老毛病，非本包引入）**：候选段备有池图时写手组版常不选（存量 23/29 无图同因）；编辑环 dropImage 是另一条摘图路（本轮实证 repairs 仅 clamp、无 dropImage）。处置即 §3 的落地兜底：落地无图且非编辑亲摘者，标题搜图补一张——编辑裁决不被覆盖。
- SSH 隧道当日多次 broken pipe：install 两次断线均先查实落盘（哈希＋健康）未盲目重跑；第二次起 install/verify 改 setsid 后台＋日志回读。

## 6. 实证（关账门逐项）

- **真实触发轮**：manual 共 5 轮——轮 1 ok 产 2（无图，跤三）、轮 2 ok 产 3（无图，跤二＋跤三叠加）、轮 3 ok 产 3（兜底留痕实证跤二）、轮 4 empty（候选全部被编辑环退稿，管线固有随机结果）、**轮 5 ok 产 1 带自家图**：f_1ae29b2c117c《Micro-SaaS：小额订阅软件的生意账》，images[0]＝`https://hermes.example.com/feed-media/e106b173e801a83d89bc7afc000bddebe25ea120bab9cec20563fdf13fb7113b.webp`、sourceUrl 空、originUrl/originImageUrl 溯源齐（ideaproof.io og 图，写手选图→主钩子托管路径）。
- **公网可达**：上图 curl 200＋image/webp＋17,098B；迁移图抽验 b3f1d34a…jpg 200＋image/jpeg＋310,211B（与磁盘逐字节同数）；补图抽验 dd44d1e6…png 200＋image/png＋564,696B。
- **回读统计（最终态）**：store 43 帖（research 32／digest 3／event 8），**research 32/32 全带图、全自家地址、外链图 0、非空 sourceUrl 0**；API（days=3650）37 条在窗、32 带图、同口径全绿。media 目录 36 文件／6.9MB（32 在册引用＋4 探针/测试孤儿，无害）。
- **verify**：最终代码齐 111 / 缺 0（存档同包）；三读面无扰动（本包只动 feed 段与 feed 数据）。

## 7. 回滚方法

1. 代码：`cp /root/deploypkg-2.6.0-20261125/baseline/oneday_seg_feed.py.host-pre /www/dk_project/dk_app/hermes/patches/oneday_seg_feed.py`（原地覆回保 inode），再跑包内 install.sh（或直接以基线件重跑 /root/hermes-deploy-pkg-2.6.0 的 install 并把三处 sha 钉回 8d3de658…——更稳妥是整包回退到 2.5.1 态）。
2. 数据：停容器→`cp baseline/data.json.pre`（或 .pre-minimig，按需选点）覆回 data/oneday/data.json→起容器。
3. nginx：`cp baseline/hermes.example.com.conf.pre` 覆回 vhost（或用应用时备份 .bak-2.6.0-feedmedia）→`nginx -t`→reload；data 目录权限恢复 `chgrp 10000`＋`chmod 700`。
4. media 目录可留置不管（无引用即不可达）；删帖图引用后文件成孤儿，不影响任何读面。

## 8. App 侧待验（用户 verdict）

服务端实证到此为止；以下须 iPhone 真机在 OneDay 里亲眼验：
1. 动态列表：research 帖应出现通栏封面图（修复前全无图）——尤其最新几条（Micro-SaaS、Sutra-OS、DeepSeek 改计费等）。
2. 点进详情：图正常加载；链接预览卡仍是纯文字形态（设计如此、未动）。
3. 个别补图为搜图兜底（如个别 Tavily 命中图与题面相关性）请扫一眼是否离题；离题的报帖名，可单条摘图。
4. 注意：应用当日 05:04 前后 App 已在拉新图并撞过一轮 404（权限修复前），Nuke 若缓存了失败结果，个别图可能需冷启动 App 后才显示。
