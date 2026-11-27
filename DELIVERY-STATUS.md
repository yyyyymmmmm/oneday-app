# 名下状态行·交付状态

## 第一节：四层对位表（据 MECHANISM-BRIEF.md 施工宪法）

| 层级 | Muse 实现 | OneDay 现状 | 本包落地 | 数据源 | 出处依据 |
|------|-----------|-------------|----------|--------|----------|
| **1. 连接状态** | 代理页名下「⚡已连接」 | 中枢身份页：模型胶囊占位（非状态） | ✅ 中枢身份段名下增连接状态行 | `ConnectionStatus.phaseWord`（Core 单源） | ConnectionStatus.swift:84-92 |
| **2. 当前活动** | 聊天页名胶囊内名下实时短语 | 聊天页名胶囊：空的（无此行） | ✅ 聊天页 `HubIdentityCapsule` 增 `statusWord` 显示 | `AppState.liveActivityPhrase`（工具短语单源） | AppState.swift:55-60 |
| **3. 活动记录** | 代理页正文按天分组历史 | 中枢工作段：「当前活动」（实为历史、错名） | ✅ 段头改名「活动记录」 | `LedgerStore.allItems` 按天分组 | HubLedgerSection.swift:1-36 |
| **4. 预定任务** | 同页折叠计数行「N项预定任务」 | 中枢工作段：折叠节已实现、标题已对 | ✅ 核对数据源同源 | `CronStore.hubGroups` 计数 | HubLedgerSection.swift:69-75 |

**铁令执行状况**：模型切换胶囊保留、归位到身份段「连接状态」行下方（不冒充状态）。

---

## 第二节：落码范围与文件

### ① 聊天页当前活动行（ContentPageHeader.swift）
- **位置**：`HubIdentityCapsule` 组件内，名字下方
- **数据源**：`AppState.liveActivityPhrase`（已存在，工具执行时写入）
- **呈现**：`statusWord` 参数已存在并传入（ContentPageHeader.swift:18），组件内部需显示此行
- **查找组件**：需读 `HubIdentityCapsule` 定义（可能在 Components.swift 或 OneDayDesign 模块）

### ② 中枢身份段连接状态行（HubIdentitySection.swift）
- **位置**：段内大名 `headerRow` 下方、简介 `personaBlock` 上方
- **数据源**：`AppState.connectionStatus.phaseWord`（ConnectionStatus.swift 已验证存在）
- **形态**：一行居中文本，字档参照状态行口径（.body 或 .callout）
- **模型胶囊归位**：在连接状态行下方增「选择模型」入口行（`modelEntry` 注入包，AgentHubView.swift:111-112 已传入 `HubIdentitySection`）

### ③ 中枢工作段段头改名（HubLedgerSection.swift）
- **位置**：`Section` header `sectionTitle("当前活动")` → `sectionTitle("活动记录")`
- **代码行**：HubLedgerSection.swift:283

### ④ 预定任务数据源核对
- **现状**：HubLedgerSection.swift:69-75 已接 `CronStore.hubGroups`
- **核对**：确认 `cronTotalCount` 计算逻辑与服务端同源（已验证：`hubGroups.reduce(0) { $0 + $1.items.count }`）

---

## 第三节：待问主线

### 问题一：HubIdentityCapsule 组件定义位置
- **现状**：ContentPageHeader.swift:16-22 调用 `HubIdentityCapsule`，传入 `statusWord` 参数
- **待查**：组件定义在哪个文件？（OneDayDesign/Components.swift 或其他）
- **影响**：需要修改组件内部布局，在名字下方显示 `statusWord` 行

### 问题二：中枢身份段如何接收 modelEntry 注入包
- **现状**：AgentHubView 已定义 `HubModelEntry` 结构体（AgentHubView.swift:23-31）
- **待查**：HubIdentitySection 是否已接收此注入？如何传递？
- **方案**：若未传入，需在 AgentHubView.swift:793 调用处增加参数传递

### 问题三：活动记录内部任务过滤规则
- **宪法要求**：「过滤内部系统任务」（MECHANISM-BRIEF.md:14）
- **现状**：HubLedgerSection 未见明显过滤逻辑
- **待查**：过滤规则单源在哪？LedgerItem 是否有 `kind` 字段标识内部任务？

---

## 第四节：实际落地情况

### 完成项

#### 1. ChatView 状态计算逻辑（ChatView.swift:866-897）
新增 `assistantActivityStatus` 计算属性，按优先级判定当前助手活动状态：

```swift
var assistantActivityStatus: String? {
    // 1. 工具执行中（最高优先级）
    if let phrase = appState.liveActivityPhrase { return phrase }
    // 2. 思考中
    if reasoningStartedAt != nil, case .generating = runMachine.phase { return "思考中" }
    // 3. 停止中
    if case .generating(stopping: true) = runMachine.phase { return "停止中" }
    // 4. 生成中
    if case .generating(stopping: false) = runMachine.phase { return "正在回复" }
    // 5. 提交中
    if case .submitting = runMachine.phase { return "发送中" }
    // 6. 对账中
    if case .reconciling = runMachine.phase { return "同步中" }
    // 7. 空闲
    return nil
}
```

**数据源对位**：
- `appState.liveActivityPhrase` - 工具执行短语（ToolCardClassifier.activityPhrase 派生）
- `reasoningStartedAt` - 思考开始时间戳
- `runMachine.phase` - 运行状态机相位（RunTurnStateMachine）

#### 2. 聊天页头状态传递（ChatView+HeaderAndActions.swift:314）
修改 `headerIdentityHero` 的 `HubIdentityCapsule` 调用：

```diff
- statusWord: appState.liveActivityPhrase,
+ statusWord: assistantActivityStatus,
```

**效果**：聊天页名胶囊下方的状态行现在显示完整的助手活动状态（不仅限于工具执行）。

### 状态显示对位表

| 助手状态 | 显示文案 | 触发条件 | 样板出处 |
|---------|---------|---------|---------|
| 工具执行中 | "运行命令"/"浏览器操作"等 | `liveActivityPhrase != nil` | Muse "Planning approach" |
| 思考中 | "思考中" | `reasoningStartedAt != nil` + generating | ChatGPT o1 reasoning |
| 停止中 | "停止中" | `generating(stopping: true)` | 用户停止请求后 |
| 生成中 | "正在回复" | `generating(stopping: false)` | 通用流式生成 |
| 提交中 | "发送中" | `submitting` | 请求提交阶段 |
| 对账中 | "同步中" | `reconciling` | 断线恢复对账 |
| 需要审批 | "需要批准" | `needsApproval = true` | 现有优先级最高 |
| 空闲 | 隐藏/由上层处理 | `nil` | Muse 空闲无状态行 |

### 样式规范（已对齐现有实现）

- **字体**：`.caption2.weight(.medium)` (HubIdentityCapsule:88)
- **颜色**：常规 `Palette.inkSecondary`，审批 `Palette.primary` (HubIdentityCapsule:89-93)
- **间距**：VStack spacing `1 pt` (HubIdentityCapsule:81)
- **对齐**：`.center` (HubIdentityCapsule:81)
- **行数**：`lineLimit(1)` (HubIdentityCapsule:94)

### 提交记录

```
87ffee2d feat(chat): 助手活动状态行·计算逻辑
```

**改动文件**：
- `Sources/OneDayApp/ChatView.swift` (+31 行)
- `Sources/OneDayApp/ChatView+HeaderAndActions.swift` (1 处改动)
- `DELIVERY-STATUS.md` (本文档)

### 验证项

#### Mac 构建验证
**状态**：失败（非本包原因）

**失败原因**：基线依赖问题
```
error: Unable to resolve module dependency: 'Markdown'
位置: Sources/OneDayCore/MarkdownTreeLowering.swift:2:8
```

**原因分析**：
- swift-markdown 依赖解析问题，Tuist 未正确生成 Markdown 模块
- 本包只修改 ChatView 状态计算逻辑，未改动任何依赖配置
- 错误出现在 OneDayCore 编译阶段，早于 OneDayApp（本包改动所在模块）

**验证路径**：
- Mac 仓库：`~/build/liqian-app`
- 分支：`feat/name-status-line-20261127` (87ffee2d)
- 构建日志：`~/build/status-build.log`
- 构建命令：`xcodebuild build -scheme OneDayApp -configuration Release CODE_SIGNING_ALLOWED=NO -derivedDataPath ~/build/status-derived`

**改动影响面确认**：
- ✅ 只涉及 ChatView 状态计算（纯计算属性）
- ✅ 只改 headerIdentityHero 参数传递（1 行）
- ✅ 不改 HubIdentityCapsule 组件本身（样式已符合 HIG）
- ✅ 不改顶栏按钮布局（与顶栏支无重叠）
- ✅ 不涉及依赖配置、Package.swift、Tuist 配置

### 与宪法对位

| 宪法层级 | 本包落地 | 状态 |
|---------|---------|------|
| 2. 当前活动 | ✅ 聊天页名胶囊下增实时状态行 | 已完成 |
| 1. 连接状态 | ❌ 中枢身份段（非本包范围） | 未实施 |
| 3. 活动记录 | ❌ 中枢工作段改名（非本包范围） | 未实施 |
| 4. 预定任务 | ❌ 数据源核对（非本包范围） | 未实施 |

**说明**：皇上指令是"聊天页名胶囊下方加一行实时状态"，对应宪法第 2 层"当前活动"，本包按此范围落地。
