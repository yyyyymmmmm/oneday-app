# 聊天页状态行交卷文档

## 一、状态口径表

### 状态源与触发条件

| 状态名称 | 触发条件 | 数据来源 | 显示文案 | 样板出处 |
|---------|---------|---------|---------|---------|
| **工具执行中** | `appState.liveActivityPhrase != nil` | `AppState.liveActivityPhrase`（由 `ToolCardClassifier.activityPhrase` 派生） | 直接显示工具短语（如"运行命令"、"浏览器操作"） | Muse 截图样板："Planning approach" |
| **等待审批** | `runMachine.phase == .generating` 且服务端 status == `.waitingForApproval` | `RunStatusKind.waitingForApproval`（需通过 OverviewStore 或实时查询获取） | "需要批准" | HubIdentityCapsule 现有口径 |
| **思考中** | `runMachine.phase == .generating` 且有 reasoning 增量 | `reasoningStartedAt != nil` | "思考中" | ChatGPT o1 reasoning 阶段 |
| **生成中** | `runMachine.phase == .generating(stopping: false)` | `RunTurnStateMachine.phase` | "正在回复" | 通用生成状态 |
| **停止中** | `runMachine.phase == .generating(stopping: true)` | `RunTurnStateMachine.phase` | "停止中" | 用户请求停止后 |
| **提交中** | `runMachine.phase == .submitting` | `RunTurnStateMachine.phase` | "发送中" | 请求提交阶段 |
| **对账中** | `runMachine.phase == .reconciling` | `RunTurnStateMachine.phase` | "同步中" | 断线恢复对账 |
| **空闲就绪** | `runMachine.phase == .finished` 或无活动 | 默认状态（无 run 在途） | "在线"或隐藏状态行 | Muse 空闲时无状态行 |
| **失败** | `runMachine.phase == .failed` | `RunTurnStateMachine.phase` | 不显示（由错误提示处理） | 失败由独立 UI 呈现 |
| **连接问题** | `connectionStatus` 不在线 | `AppState.connectionStatus` | 由现有 `overviewStatusWord` 处理 | 现有顶栏状态词 |

### 状态优先级

当多个状态同时满足时，按以下优先级显示（高到低）：
1. 工具执行中（liveActivityPhrase）
2. 等待审批（waitingForApproval）
3. 思考中（reasoning）
4. 停止中（stopping）
5. 生成中（generating）
6. 提交中（submitting）
7. 对账中（reconciling）
8. 空闲就绪（finished/idle）

### 数据来源实现说明

**问题**：当前架构中，`RunStatusKind.waitingForApproval` 状态未在 ChatView 层直接暴露。现有的 `overviewStore` 持有审批状态，但用于顶栏角标和总览。

**方案**：
- 利用现有 `appState.sharedHubStore().hasPendingApprovals` 判断是否有待审批
- 或扩展 ChatView 状态，从 runMachine 对应的 run 实时查询状态
- 优先使用现有 `needsApproval` 传入参数（已在 HubIdentityCapsule 使用）

## 二、样式规范（HIG 对位）

根据 Apple Human Interface Guidelines 和现有代码：

| 样式属性 | 规范值 | 出处 |
|---------|-------|------|
| 字体 | `.caption2.weight(.medium)` | HubIdentityCapsule:88 现有实现 |
| 颜色 | 常规状态：`Palette.inkSecondary`<br>需要审批：`Palette.primary` | HubIdentityCapsule:89-93 |
| 行间距 | `1 pt` | HubIdentityCapsule:81 VStack spacing |
| 对齐 | `.center` | HubIdentityCapsule:81 alignment |
| 行数限制 | `lineLimit(1)` | HubIdentityCapsule:94 |

## 三、实现方案

### 修改文件
1. `Sources/OneDayApp/HubIdentityCapsule.swift` - 改造状态文本计算逻辑
2. `Sources/OneDayApp/ChatView+HeaderAndActions.swift` - 传递实时状态参数
3. 可能需要扩展 `Sources/OneDayApp/ChatView.swift` - 添加状态计算属性

### 实现要点
1. 在 ChatView 添加计算属性 `var assistantActivityStatus: String?`，按优先级判定当前状态
2. 将该状态传递给 `HubIdentityCapsule` 的 `statusWord` 参数（替换现有的 `appState.liveActivityPhrase`）
3. 保持 `needsApproval` 参数继续工作，作为最高优先级状态

### 与顶栏支的重叠处理
- 顶栏支可能也在改 `ChatView+HeaderAndActions.swift` 中的 `topBand` 或相关布局
- 本包只修改 `headerIdentityHero` 的参数传递和状态计算逻辑
- 不改动顶栏按钮、间距等既有元素

## 四、实施

正在实施...
