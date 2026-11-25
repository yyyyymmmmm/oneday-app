# 伴生 1.0.12 部署记录（2026-11-11，用户新规：伴生自动修复自动部署）

为 App 对标包 0.47.0（DESIGN §117，feat/muse-align 预制）在
oneday-bridge 侧做呈现数据补齐与两处格式修复。全部为纯增量
与格式收口：旧记录、旧客户端均不受影响。

- **ideas 增 emoji＋deliverables**：生成提示词增两字段说明
  （emoji 按内容选一个；deliverables＝详情页「包含哪些
  内容」清单 1–3 项 {name, summary}）；_parse_generated_
  cards 宽容收下（_clean_emoji/_clean_deliverables 清洗，
  形状不对丢字段不丢卡）；生成落卡、POST /ideas 可选入参、
  _idea_view 三处透传。旧记录回 emoji=null、deliverables=[]。
- **feed 抓图修复（审计定根因）**：_tavily_extract 此前未带
  include_images，Tavily 恒不返回 images 数组，图池恒空——
  1.0.6 两篇调研帖无图即此故（部署前以同一页面双跑实证：
  缺省 0 图、带参 4 图且首图为 og:image）。修复：请求加
  include_images: true；每个 kept 来源页的候选图按序组装
  （_ordered_page_images：①桥直抓 og:image/twitter:image
  meta ②Tavily images ③正文 Markdown 首图，去重保序、上限
  6）。图池纪律不变：只收本轮来源页、HEAD 校验、坏图丢弃
  帖子照落，宁无图不假图。
- **feed 帖增 emoji**：著帖提示词增 emoji 输出，
  _verify_research_post 宽容透传；digest 落帖固定 📰；
  _feed_view 透传（旧帖 null，App 按 kind 兜底）。
- **汇编帖格式修干净**：事件文案去掉自带类别标签（点子行
  只留《标题》、监测行《名》：摘要、简报行《目标》周简报：
  标题），分组头成唯一标注——旧形「## 新点子／- 07:30
  新点子《…》」的标签重复自新汇编起消除。存量已存事件
  文案不回改（7 天自然过期）。
- COMPANION_VERSION 升 1.0.12（工作区 Dockerfile ARG、
  compose 镜像标签与 COMPANION_VERSION、生产 companion.env
  三处同步）。

部署：基线 1.0.11；回滚基线 /root/companion-112-deploy-
20261111/（1.0.11 的生产 compose、companion.env、两容器
inspect、运行容器内 oneday_bridge.py.111＝md5 77d4f182…、
build.log）。回滚＝基线 compose+env 拷回 /www/dk_project/
dk_app/companion 后 docker compose up -d companion（镜像
1.0.11 仍在服务器）。构建上下文 /root/build-112（build-111
副本仅替换 modules/oneday_bridge.py，diff -rq 全树比对恰
一文件；新文件 md5 94a4c0a5… 与本地工作树一致），docker
build --build-arg COMPANION_VERSION=1.0.12。

验收（2026-11-11 部署后实查）：
- 公网 /api/companion/info：companionVersion=1.0.12、五模块
  全 up、oneday degraded=false、hermesUp=true。
- 桥 /health：ok、degraded=false、台账 70 条、采集器 lag 19s。
- 公网 /feed：5 帖全带 emoji 键（旧帖 null，App 兜底）；
  /ideas：6 条全带 emoji/deliverables 键（旧记录 null/[]）。
- Hermes StartedAt 前后逐字不变（2026-11-10T14:21:47Z）；
  内存部署前 51.5%、部署后 50.9%。
- 本地全套桥自测绿：overview 8／p2 34／p3 29（含汇编新格式
  3 断言）／p4 19／p5 21／p6 31（含 §117 phase C 5 断言）／
  device／write-gate 22／device_sync／model-combos／ledger 60。

未验：新一轮调研帖带图落库须等下一轮生成（每日 08:30 或
简报变更触发）后看生产帖 images 非空；ideas 新字段须等
明早 07:30 生成轮产新卡后看真值。
