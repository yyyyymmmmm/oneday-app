# 伴生 1.0.6 部署记录（2026-11-11，用户新规：伴生自动修复自动部署）

为 OneDay 0.38.0 动态换代包部署伴生侧：oneday_bridge.py 段二换代
（动态五步链：规划→Tavily 检索→深读抓图→著帖→验真落库）＋简报
两层（meta.briefInterest 兴趣层／meta.brief 执行层，兴趣真变更触发
扩写、执行层真变更触发调研轮），p3 Phase B 换测新链、p4 新自测
19 项，companion.env.example 补 TAVILY/FIRECRAWL 钥位。

部署：基线 1.0.5；回滚基线 /root/companion-106-deploy-20261111/
（1.0.5 的 compose、companion.env、两容器 inspect、运行容器内
oneday_bridge.py.105、本次 build.log/up.log 与新源码包 src.tgz）。
回滚＝基线 compose+env 拷回 /www/dk_project/dk_app/companion 后
docker compose up -d（镜像 1.0.5 仍在服务器）。COMPANION_VERSION
在 companion.env [global] 与 compose 同步改 1.0.6；TAVILY_API_KEY、
FIRECRAWL_API_KEY 自武装库总账注入 companion.env [oneday] 段
（0600 不变，传输用临时钥文件已在服务器与本地双删）。只重建伴生
容器，Hermes StartedAt 前后不变（2026-11-10T14:21:47Z），内存
部署前后约 50–51%。

自测（部署前本地以生产时区 TZ=Asia/Shanghai 全套跑通，只增不
减）：overview 8／p2 34／p3 26／p4 19／p5 21／write-gate 22／
ledger 60／device 桥 OK／device_sync OK／model-combos OK。

真调研验收（生产实跑一轮，非桩链）：触发前实查生产简报两层皆
空（用户尚未在 App 填写，App 按设计不静默预填）——以规格定版的
三方向原文经正式入口 PUT /meta/brief 写入兴趣层：扩写约 15 秒
落地成结构化执行简报（三方向各带取舍标准），执行层真变更自动
触发调研轮（trigger=brief），全程约 100 秒，status=ok、
produced=2、dropped=0：
- AI 实质进展：产帖《Kimi K3.1 Pro 发布：开放权重模型在编码
  Agent 任务上逼近闭源前沿》，2 条来源链接（搜狐/DataCamp，
  抽查 301/403 均为站点对裸 UA 的常规处理，内容已经 Tavily
  Extract 深读入链）；
- 搞钱与副业：产帖《X 停掉流量分成，改为首页原创内容奖励》，
  来源链接抽查 200；
- GitHub 开源项目：如实空产——Trending/Trendshift 两份材料只
  抓到页面框架、无可核验仓库条目，著帖步拒绝硬凑（验真门按
  设计工作）；两帖均无图（深读未得可用图，宁无图不假图）、
  无 GitHub 卡（该方向未产帖）。
验收后简报两层已按部署前状态复原为空（复原的 brief 清空按契约
触发一轮并如实记 skipped「简报为空」）；两篇真帖保留在动态流
（feed 3→5 条），用户可在 App 内删除。

公网复验（App 同款单钥）：/api/companion/info 报 1.0.6、
hermesUp=true、五模块全 up、oneday degraded=false；台账
/ledger/summary 总 33 条、degraded=false、采集器心跳新鲜，
sessions 与 kanban 两源均 ok:true（1.0.4 空板修复保持）。
