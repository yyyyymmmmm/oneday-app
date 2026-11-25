# 待审批裁决未生效查案（2026-11-11 23:28 用户真机截图）

## 结论（定因）

这条审批**永远批不了**，与过期、被取代、App 缓存都无关：

技能 `feed-material-collection` 的 description 有 **82 个字符**，超过 Hermes
技能索引的 **60 字符**描述预算。Hermes 上游的暂存路径（skill_manage 在审批门
开启时只写 pending 文件）**不跑**这项校验；校验只在批准回放落盘时由
`_guarded_write` 执行（`_description_budget_error`）。于是形成结构性死单：
**能暂存、批准必败、记录永不消失**，用户重试多少次都是同一次确定性失败。

校验全链无副作用复现（容器内以 pending 载荷实跑上游纯校验函数）：
`_validate_name/_validate_category/_validate_frontmatter/_validate_content_size`
全部通过、内容安全扫描通过、技能不存在（`_find_skill`=None），唯
`_description_budget_error` 返回：

> Description is 82 chars; a skill description must fit the 60-char skill
> index (one sentence, trigger first, ends with a period, without repeating
> the category name). The index clips anything longer. Move detail into the
> skill body.

## 证据链（时间均为 CST）

- 审批本体：id `62927061`，skills / batch(1 op: create) /
  feed-material-collection（category=research，内容 5,396 字节），
  origin=`background_review`，产生于 **2026-11-11 22:58:53**
  （pending 文件 /opt/data/pending/skills/62927061.json 逐字核对；
  截图「29 分钟前」@23:28 与之吻合）。
- 用户裁决请求（write-gate access log，docker logs -t）：
  - 23:22:55 `POST /pending/skills/62927061/approve -> 200`
  - 23:23:01 同上 `-> 200`
  - 23:28:50 同上 `-> 200`，紧接 `GET /pending/skills/62927061 -> 200`
    （App 按红字提示「重新打开核对」的行为）
  三次均为 HTTP 200 但响应体 `success=false`：桥 `_decide` 的成功判据是
  「回放后记录已消失」，上游 `_approve` 遇失败不 discard，记录至今仍在
  （当前 /pending 实测仅此 1 条）。
- 排除项逐项坐实：①无过期机制（桥与上游均无 TTL，记录有效 pending）；
  ②无同技能第二条 pending（counts skills=1），不存在被新版本取代；
  ③App 提交的 id 正确、桥每次都命中记录并执行回放（非 404），
  不是 App 缓存版本问题；④技能未被他路落地（见下）。

## 技能现状与改造依赖

- 技能**至今未落地**：/opt/data/skills/research/feed-material-collection
  不存在，全盘 find 无此技能。
- 动态检索改造（1.0.28，agent-first）**不依赖它**：取材规程是伴生
  oneday_bridge.py 内联提示词 `FEED_MATERIAL_PROMPT`，生成线不按名加载
  该技能；改造的生产验证轮（produced 3、零 Tavily）就是在无此技能时
  跑通的。这条审批是 Hermes 后台自审（background_review）把同套取材
  规程沉淀为技能的自发提炼——落不落地不影响改造运行，影响仅是这套
  规程没有沉淀成智能体可复用的技能资产。

## 已修（伴生 1.0.29，自动部署授权内）

改 `modules/write_gate_bridge.py` 一处文件，镜像 oneday/companion:1.0.29
（sha256 ba2b441fd82c…），回滚点
/root/companion-129-deploy-20261111/docker-compose.yml.1.0.28：

1. **确定性批不了预检 `blocked_reason`**：/pending 列表与详情的每条
   skills 记录，现以与上游落盘完全同口径的纯校验函数（校验链＋描述
   预算＋已存在检查，仅 create 型）复算可落盘性；命中确定性失败时
   记录带 `blocked_reason`（上游原文）。生产回读：62927061 已带上
   82 字符原文。自测 write_gate_blocked_selftest 11 项全过；任何异常
   一律不带字段（建议性字段，裁决路径仍是唯一权威）。
2. **裁决失败回结构化原因 `failure_reason`**：decide 回放失败时从上游
   output 的 `Failed:` 段解析本条原因，随 200 响应返回，不再只有
   泛化的 output 全文。
3. **失败留痕 `decide-attempts.jsonl`**（/opt/data/write-gate/，仅元数据）：
   每次失败的裁决尝试落一行（id/子系统/拟裁决/时间/原因）。decisions.jsonl
   保持「只记已决」语义不动（overview 已决呈现依赖它）。
4. **计数口径回读**：部署后 /status counts={memory:0, skills:1} 与部署前
   逐字一致——顶栏「待审批 1」就是这条死单本身，计数准确、未被误伤；
   部署前后内存 55%→54%，Hermes StartedAt 逐字不变
   （2026-11-10T14:21:47.024396739Z），只重建 companion 容器。
   全套自测：write-gate 三套（rules 22 / anchor 13 / blocked 11）全绿；
   p3 与 rendition 两套在本机 FAILED，但二者不引用 write-gate，rendition
   为本机出站 503 环境问题，与本次改动无关（部署前既存）。

## 待修项（不在伴生侧）

- **App 侧呈现**（留合并包）：①记录带 `blocked_reason` 时，审批卡应呈现
  「这条无法批准：<原因>」并只给驳回出路，不再给点了必败的批准钮；
  ②decide 响应 `success=false` 时把 `failure_reason` 呈现给用户，
  替代现行泛化红字「裁决未生效，请重新打开改动核对后再试。」。
- **Hermes 上游**（本体变更须另行请示，本次未动）：暂存路径不跑描述
  预算等落盘校验，是「能暂存、批准必败」死单的根源；理想修法在
  stage_write 时同口径预检。此外这条死单本身还等用户处置：内容原样
  批不了，只能驳回，或由智能体改短 description（≤60 字符）后重新提暂存
  再批——不要替用户裁决。

## 这条单子的现状（给用户的一句话版）

待审批还剩 1 条是真的：那条新建技能因一句话简介写超了 22 个字，
系统批一次退一次。已让服务器把「批不了的原因」明明白白标在这条上；
App 下一版把卡片改成显示原因。这条单子需要用户驳回、或让智能体
把简介改短后重新提交。
