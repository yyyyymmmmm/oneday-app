# IDEAS-CATEGORY-134 部署报告（伴生 1.0.34，2026-11-12）

点子分类桥侧包：App §177 呈现包的前置（合并顺序：本包先上线）。
分类枚举与目标创建流同表七类，桥为单一真源——直接复用
GOAL_CATEGORIES（health/relationships/finance/career/interest/
efficiency/other），不另立第二张表。

## 版本对齐（动手前）
- 目标版本原定 1.0.33，施工中接纠正：1.0.33 已被网页端线占用
  （web-login 登录桥），本包改 1.0.34。
- 对齐实查：本地模板与生产 1.0.33 逐字一致才动手——容器内
  oneday_bridge.py md5 7367b0bf…、front.py md5 7780a7a4… 与本地
  同值；生产 COMPANION_VERSION=1.0.33、内存 55%、Hermes
  StartedAt=2026-11-10T14:21:47.024396739Z（基线值）。
- 部署树除本包改动外，带入了主线同版 front 改动（登录限速按
  X-Real-IP 分桶，front.py 1309–1324 行 _client_ip）与四处版本
  号预切（compose 镜像标签＋COMPANION_VERSION、Dockerfile ARG、
  本地 compose）；生产 companion.env [global] 一处由本包 sed
  切到 1.0.34。web-login 代码本体一行未动（见回归验）。

## 改动（modules/oneday_bridge.py）
1. `_clean_idea_category`：枚举值原样、其余（缺失/非法/错型）
   一律折「other」，永不抛错、永不丢卡；CATEGORY_LABELS 中文
   标签表同处定义。
2. `_idea_view` 输出 category（存量无值/非法值读 "other"，
   视图恒不发 null）。
3. 生成链：IDEAS_GEN_PROMPT 新增 category 字段（必填、七值
   枚举＋中文标签）；解析器 `_parse_generated_cards` 宽容折值；
   改写提示词字段表与改写入参带 category；落卡写 category；
   每轮账本 rec 新增 `categoryDist`（本轮落卡分类分布，有
   落卡才有此键）。
4. 建卡接口 POST /ideas 收 category 键：合法存原值、无键
   缺省「other」、非法折「other」——旧调用零感知，不 400。
5. STATUS-CONTRACT 变更记账已登记（第 6 面 history 新增
   categoryDist、GET /ideas 新增 category 字段）。

## 存量回填（一次性，随部署在停机窗口执行）
- 脚本 backfill_idea_categories.py＋分类器 modules/
  idea_category_backfill.py：桥停机后以新镜像一次性容器挂
  生产数据卷运行（桥内存持库，运行中回填会被覆盖，故必须
  停机窗口）；凭据由脚本在容器内解析挂载的 companion.env
  取 HERMES_API_KEY，不经命令串、不打印。
- 三路裁定：模型一遍（/v1/runs，deepseek-flash，只输出枚举
  值）→ 关键词规则兜底 → 「other」；逐卡独立降级，不整批倒。
- 目标集＝未终态（pending）且无合法分类：共 4 张。结果账
  （id → 分类 → 来源），全数走模型路：
  - i_3076b62405cc → efficiency（模型）《汇总近 7 天 P3TEST
    验收任务的通过与驳回结果》
  - i_aa49c10fe1f5 → efficiency（模型）《开源热点素材门槛
    核对表，避免检索再空跑》
  - i_200afdbc66ae → career（模型）《Marc Lou 副业复盘做成
    标注来源的案例卡》
  - i_0eb9cda50447 → finance（模型）《方舟 Agent Plan 免费
    额度边界做成一页核对清单》
  三路计数：模型 4／规则 0／兜底 0。回填后脚本内复查＋独立
  回读双验：pending 无合法分类＝0 张。完整账另存于 data.json
  的 meta.ideasCategoryBackfill。
- adopted 4 张属终态、不在回填范围（按任务书口径）；其
  category 经 _idea_view 折叠读 "other"，呈现层零缺失。

## 自测
- 新增 tests/oneday_bridge_p9_selftest.py（28 项：清洗折值／
  view 输出／建卡收键三态／解析器不丢卡／提示词契约／回填
  三路与目标集判定），已登记进 run_bridge_selftests.sh。
  p9：28 passed / 0 failed。
- 全套对账：改后 FAIL 集合与部署前基线一致（p3 的
  hour 相关 1 项——基线 hour=18、复跑 hour=19，同例随时钟
  变文案；device_sync reminders 1 项；rendition 7 项 503；
  共 9 行、3 个套件，均为存量红、与本包无关）。

## 部署验收（生产实查）
- 内存 55%（部署前/后同值，<80%）；Hermes StartedAt 部署后
  逐字不变（2026-11-10T14:21:47.024396739Z）。
- 五模块：8643/8644 鉴权应答在位、8645 box ok、8646 oneday
  ok（degraded=false）、8647 device ok；front 进程 environ
  COMPANION_VERSION=1.0.34；容器内新桥 md5 faa89dd2… 与本地
  改后同值。
- web-login 回归：运行中 front.py 与 1.0.33 部署件的 diff
  只有主线 _client_ip 改动（web-login 本体未动）；POST
  /api/companion/web-login 空体探测回 401（路由在、非 404）。
- GET /ideas：9 卡全带 category、缺失 0；pending 四张与回填
  账逐字一致。
- 真实生成轮（手动触发）：rec trigger=manual、status=ok、
  produced=1、dropped=1、categoryDist={interest: 1}；新卡
  i_5bf1c711f5bc category=interest 与分布账一致。

## 回滚点
- /root/companion-134-deploy-20261112/：docker-compose.yml
  .1.0.33、companion.env.1.0.33、oneday_bridge.py.1.0.33、
  front.py.1.0.33、data.json.pre-backfill（回填前数据原件）、
  build.log、backfill.log。构建目录 /root/companion-134-build/。
- 回滚＝compose 镜像标签与 env 改回 1.0.33＋docker compose
  up -d companion；数据回滚用 data.json.pre-backfill（注意
  会丢回填后新落的生成卡，分类字段本身是增量、无破坏性）。
