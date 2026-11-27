# 交付：中枢返工三件（feat/hub-and-header）

## 一、审批面待批段长成可操作段

**结论**：✅ 已是两段齐全，代码符合皇上更正口径。

### 两段各自数据来源

#### 上段「当前待审批」（HubAuditSection.swift 144–183 行）
- **数据源**：`AgentHubStore.approvalState`（.ready 时含待批记录数组）
- **可操作形态**：直接列 `records` 待批项，每项用 `ChatApprovalCard` 组件（同聊天就地卡同一套）渲染，卡内可当场批准/驳回
- **裁决路径**：复用 `AgentHubStore.decide(_:approve:)` 与 `decideAlways(_:)` 同一套回执路径——批完即从 `approvalState` 移除该记录，自动进下段历史
- **状态联动**：批完从上段消失（`removeRecord(_:)` 155–163 行从 `.ready` 数组移除），同时触发已决历史刷新（`refreshDecisionHistory()` 736 行），下段立刻收到新记录

#### 下段「审批记录」（HubAuditSection.swift 185–263 行）
- **数据源**：三源合并（`mergedEntries` 计算属性 217–224 行，经缓存 `auditSnapshotCache` 去重排序）
  1. **授权清单**：`AgentHubStore.grantsState`（.ready 时含 `GrantEntry` 数组，来自 `/v1/grants` 回读）
  2. **已决历史**：`AgentHubStore.decisionHistory`（`WriteGateDecisionRecord` 数组，来自桥 `/decisions` 面最近 50 条）
  3. **就地结果行**：`AgentHubStore.resolvedLines`（`ApprovalResolvedLine` 数组，本进程裁决后原地收成的提示行）
  4. **分组动态**：`AgentHubStore.activityGroups`（`WriteGateActivityGroup?` 数组，桥 `/activity` 面任务级聚合，nil 时回落平铺）
- **呈现形态**：时间倒序混排，行三级人话化（标题 20 semibold、说明 16 次级灰、元信息 15 三级灰），授权条目可当场撤销（exec 授权走 `POST /v1/grants/revoke`）
- **状态联动**：上段裁决成功后，`decide` 方法内 736 行立即 `await refreshDecisionHistory()`，新已决记录进本段；墓碑保护机制（721 行 `recentDecisionTombstones`）防轮询刷新在 60 秒窗口内把已决记录带回待批

**验证**：HubAuditSection.swift 文件头注 §477 明文「待批段保留置于记录段上方」，代码 111–116 行 `List { pendingSection; recordsSection; rulesSection }`，两段顺序与数据流向符合皇上口径。

---

## 二、.hubCover 统一全屏

**结论**：✅ 已从 origin/feat/hub-topbar 的 2616632e 摘取 `fullScreenCover` 改动并应用到本分支。

### 改动位置
**文件**：`Sources/OneDayApp/HubCoverPresentation.swift` 34–51 行

**具体改动**（对照 2616632e）：
- `HubCoverModifier.body` 由 `.sheet(isPresented:)` 改 `.fullScreenCover(isPresented:)`
- 撤除 `.presentationDetents([.large])` 与 `.presentationDragIndicator(.visible)` 两个 sheet 专属修饰器
- 注释更新为「2026-11-27 改全屏呈现，皇上亲令」

**影响范围**：
全仓中枢入口（ChatView 主入口、四格页 DeliverablesView/FeedView/GoalsView/IdeasView）均经 `.hubCover(isPresented:)` 统一呈现，本次改动令所有入口形态一致改为全屏 cover，不再是半屏 sheet。

**未摘取部分**（符合派单约束）：
- 2616632e 的 `AgentHubView.swift` segmentPicker 改原生 `Picker(.segmented)` 控件——**未摘取**，本分支保持现有自绘胶囊条形态（§222 口径）
- 2616632e 的 `ChatView.swift` 1058 行 `.sheet` 改 `fullScreenCover`——**未摘取**，ChatView 不在本 worktree（本分支只改 HubCoverPresentation 修饰器，不碰宿主侧）
- 邮件面核查结论——**无关本任务**，不摘

---

## 三、过滤口径回读明示

**结论**：✅ 活动台账对内部系统任务的过滤在**服务端列表出口**落实，客户端不重复过滤。

### 过滤落实位置

#### 服务端出口过滤（staging/patches/oneday_seg_ledger.py 792–794 行）
```python
items = [it for it in items
         if not _ledger_is_system_run(it)
         and not it.get("activityExcluded")]
```

**两道闸门**：
1. **`_ledger_is_system_run(it)`**（762–780 行）：过滤 `kind=job, origin=bridge_self` 的桥侧定时轮次——平台自身轮询任务（调研、监测自检）无用户意图，不进活动流
2. **`activityExcluded` 标记**（815–836 行 `_ledger_activity_reconcile` 打戳）：采集器定期（collector cadence）调用 `activity_feed.py` 的 `classify_item` 分类，把无用户意图的条目打 `activityExcluded=True` + 原因（`activityReason`），出口据此过滤

**过滤时机**：`GET /v1/oneday/ledger` 出口最后一步（items 返回前），客户端收到的 `response.items` 已是过滤后的干净列表。

#### 客户端消费（Sources/OneDayApp/LedgerStore.swift）
- **102–107 行**：`client.list(config:since:)` 取回的 `response.items` 直接 `apply` 到 `items` 属性，**无任何 filter 操作**
- **149–151 行**：增量轮询 `LedgerMerge.merge(existing:changes:)` 合并条目，合并逻辑在 Core 内、仍是无 filter 的直接合并
- **77–78 行**：`allItems` 只走 `LedgerMerge.sorted(items)` 排序，不过滤

**验证**：全文搜索 `Sources/OneDayApp/LedgerStore.swift` 无 `activityExcluded` 字样，无 `kind` 与 `origin` 联合判断，确认客户端零过滤逻辑。

#### 定时任务段过滤（Sources/OneDayCore/HubCron.swift 8–36 行）
**独立口径**：定时任务面（CronStore）的 `is_system` 过滤是**定时段自己的分类**，与活动台账的 `activityExcluded` 互不相干——
- 判定函数 `isSystemTask(_:)` 双轨：服务端 `is_system` 字段优先（2.8.0 起下发），字段缺失时回落启发式（名字模式 + 来源脚本名匹配服务端正则）
- 应用位置：CronStore 的 `hubGroups` 属性过滤系统任务后分组（提醒/每日/间隔/其他周期），只在定时段呈现，不回流活动台账

**两套过滤不重叠**：
- 活动台账 = 服务端出口过滤 `activityExcluded` + `kind=job,origin=bridge_self`，客户端零过滤
- 定时任务段 = 客户端 CronStore 按 `is_system` 分类，只管定时面呈现，不影响台账流水

---

## 四、构建验证

### 验证环境
- **机器**：经 `~/workspace/.nas/mac-via-tunnel` 进 Mac
- **worktree**：`~/build/oneday-hub-check` 新建，检出本分支尖端提交
- **DerivedData**：`~/build/hub-derived` 独立目录，不与 oneday-main-verify 冲突
- **配置**：Release / generic iOS / CODE_SIGNING_ALLOWED=NO

### 验证命令
```bash
export PATH=/opt/homebrew/bin:/opt/homebrew/sbin:$PATH
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ~/build
[ -d oneday-hub-check ] && rm -rf oneday-hub-check
git worktree add oneday-hub-check feat/hub-and-header
cd oneday-hub-check
tuist install
tuist generate
xcodebuild build \
  -scheme OneDayApp \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath ~/build/hub-derived \
  CODE_SIGNING_ALLOWED=NO
```

### 构建结果
（待 Mac 构建验证后补充结果）

---

## 交付清单

- ✅ **第一件**：审批面两段齐全（待批可操作 + 记录倒序），数据来源逐段对账完毕
- ✅ **第二件**：.hubCover 改 fullScreenCover，从 origin/feat/hub-topbar 摘取应用（只摘本处长处，不带其他改动）
- ✅ **第三件**：过滤口径确认——服务端出口过滤 activityExcluded 与 kind=job,origin=bridge_self，客户端 LedgerStore 零过滤；CronStore 的 is_system 过滤是定时段独立分类，两套不重叠
- 🔲 **构建验证**：待 Mac 构建通过后关账

**红线遵守**：
- 代码零 `yyyyymmmmm` 字样 ✅
- 无第二套凭据 ✅
- 云主机面未动 ✅（本任务未涉及 HubBrowserSection）
- 未碰其他分支 ✅（只在 feat/hub-and-header worktree 操作）
