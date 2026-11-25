# FEED-IDEM-126-REPORT — 动态版次 0 帖事故根因修复（伴生 1.0.26）

事故：2026-11-11 动态 B 版（20261111-B，19:30 真轮）0 帖。生成账本该轮 rec 实况（生产 data.json feedGen.history 末条）：status empty、produced 0、dropped 4、error＝「著帖步提交失败：提交生成失败（HTTP 409）{"error": {"message": "Idempotency-Key was already used …」。

## 根因（生产实证）

- feed 版次轮（`_run_research_round`）的下游席位幂等键只有日期＋版次成分：plan＝`feed-research-plan-{YYYYMMDD[B]}`、著帖＝`feed-research-{stamp}-{idx}`、编辑＝`feed-editor-{stamp}`、finish＝`feed-finish-{stamp}-{rnd}`。同版次的任何两次调用共用同一组键。
- 白天一次沙盒干跑（台账 run_862fef820b3a427e89ceec1b1ee669c5，16:32 起，标题为动态报社宪法）以同键提交了副本载荷，先把这组键在 Hermes 侧「烧」掉；晚间真轮同键异载荷被 Hermes 判 409，四方向著帖全灭，后续席位无候选可走。
- 小时线不受影响：其 stamp 本就是 `{日期}-{int(started)}`，天然带轮次成分——这也是本次修法取的既有先例。

## 修法（modules/oneday_bridge.py，仅 `_run_research_round` 内）

- 版次轮新增 `key_stamp`：schedule／schedule-b 时＝`{stamp}-{int(started)}`（started 为本轮起始 epoch，每次调用唯一）；其余 trigger 的 stamp 本已含 int(started)，key_stamp＝stamp 不变。
- 四个席位（plan／著帖／编辑／finish）的提交键全改走 key_stamp；轮内键保持稳定，同轮同载荷的真重试仍可被 Hermes 幂等去重。
- rec 新增 `keyStamp` 字段落账，事后可从生成账本直接审计每轮实际用的键基。
- 作用域说明：ideas／goal 等其他线的键未动（不在本事故面）；小时线原本已唯一，未动。

## 附带项核查：失败轮 Tavily 消耗入账——查实已入账，未重复加

施工单称今晚真轮 12 次未入账。生产实查结论相反，证据链：

- B 轮 rec 自带 tavilyCalls＝12；`_feed_record_locked`（唯一入账路径，全仓仅此一处调用 `_tavily_month_add_locked`）在轮次 finally 中以 rec.tavilyCalls 折进 feedPolicy.monthCalls。
- 生产现值 monthCalls＝12，与 feedGen.history 全部 rec 的 tavilyCalls 之和（12，其余轮次为该字段上线前的老 rec、无计数）逐一相等。
- 已部署 1.0.25 镜像内模块与本地源码 md5 一致（0e96267c…），入账代码在线上同样存在。
- 结论：这 12 次已经在账上，再加一遍会双记并污染降级档位口径，故未执行重复入账。若后续以 Tavily 官方后台用量对账发现别的缺口，那是 tavilyCalls 字段上线前老轮次的无计数问题，属另一口径，需单独拍板。

## 验收证据

1. **自测**：p3 新增 phase F 四项全过——同版次（20261111-B）两轮调用（干跑形态＋真轮形态，时间桩控制）版次相同、keyStamp 分别为 `20261111B-{epoch1}`／`20261111B-{epoch2}`、四席位键两轮零交集、finish 键同带后缀。p3 全套 72 passed（基线 68＋4），其余套件全绿（overview 8／p2 34／p4 20／p5 23／p6 53／rules 22／anchor 13／spreadsheet 20／ledger 60／delivery＋sentinel OK／device OK／device_sync OK）。rendition 套件在本机仍红：失败形态为清一色 503（模块繁忙门，本机内存约 89% 触发；连预期 415 的用例也回 503），与本次改动路径无关，属既有本机环境问题；生产侧 rendition 正常。
2. **生产等值验证**（部署后，容器内借运行进程钥、临时 DATA_PATH、假版次 20990101B，不碰生产数据）：干跑形态键提交被接受 → 同键换不同载荷提交得 HTTP 409「Idempotency-Key was already used with a different request payload」（事故机制在生产 Hermes 上原样复现）→ 同版次段＋新轮后缀键提交同一载荷被接受（修复点实证）。探针 run 均已 stop。
3. **次日两版确认**：生产 feedGen 排程 nextRunAt＝2026-11-12 08:30（A 版）、nextRunAtB＝2026-11-12 19:30（B 版），两轮都将跑在已上线的 1.0.26 代码上，键必带后缀且 rec.keyStamp 落账可查——事后审计点即此二轮的 rec。

## 部署纪律账

- 版本：伴生 **1.0.26**，镜像 oneday/companion:1.0.26（sha256 852e6a72ccd2…）；构建目录 /root/build-1.0.26（克隆 build-1.0.25 后替换 modules/oneday_bridge.py＋Dockerfile 两文件，md5 与本地逐字一致：模块 22aa96d5…）。
- 回滚点：/root/companion-126-deploy-20261111/docker-compose.yml.1.0.25（还原到现行目录 /www/dk_project/dk_app/companion 后 up -d 即回 1.0.25，旧镜像在机）。
- 部署前后：内存约 52%；Hermes StartedAt 逐字不变（2026-11-10T14:21:47.024396739Z）；探活同部署前口径（8643/8644→401 需钥、8645/8646/8647→200、8646 /health ok、哨兵 lastError null）。
