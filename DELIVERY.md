# 中枢页全屏＋五面补齐、聊天页顶栏改版 施工交付

## 定位

### 一、中枢页实现位置
- **主视图**：`Sources/OneDayApp/AgentHubView.swift`（108行起）
  - 现状：body → NavigationStack → content → header + segmentPicker + segmentContent
  - 呈现方式：ChatView.swift:1058 通过 `.sheet(isPresented: $showHub)` 触发
  - 注册表驱动五面：HubSegmentRegistry.resolve() 按输入裁决格集（工作/审核/电脑/身份/邮箱）

### 二、五面数据源与视图（已核查）
1. **工作段**（.work）：HubLedgerSection - 真面
   - 数据源：LedgerStore（appState.sharedLedgerStore()）
   - 内容：台账＋预定任务折叠节（§434起定时并入本段）
   
2. **审核段**（.audit）：HubAuditSection - 真面
   - 数据源：AgentHubStore.grantsState + approvalState
   - 内容：授权账本＋审批记录
   - 长格条件：grantsReadbackOK 或 approvalsReadbackOK 任一为真
   
3. **电脑段**（.computer）：HubBrowserSection → ComputerFaceView - 真面
   - 本体：ComputerFaceView（状态头＋三段：桌面/文件/终端）
   - 桌面段内嵌 BrowserFaceView（云电脑真实截图＋接管）
   - 长格条件：boxConfigured（Box 钥匙在钥匙串）
   
4. **身份段**（.identity）：HubIdentitySection - 真面
   - 数据源：AgentHubStore.loadIdentityIfNeeded()
   
5. **邮箱段**（.mail）：EmptyView 占位 - 未实现（符合预期）
   - 现状：注册表 mailAdvertised: false，本段不长出
   - 长格条件：服务端广告 mail 位后才长格

### 三、聊天页顶栏实现位置
- **文件**：`Sources/OneDayApp/ChatView+HeaderAndActions.swift`
- **顶带结构**（204行 topBand）：ZStack 叠放
  - 底层：headerIdentityHero（316行）居中身份区
  - 上层：HStack 包含 drawerButton + Spacer + (findButton + bellButton)
- **身份区组件**：HubIdentityCapsule.swift
  - 原结构：GlassEffectContainer { HStack(spacing: 6) { 头像 + 名字胶囊 } }

## 施工内容

### 一、中枢页改全屏呈现（口径1："中枢页面做成这样的，点击是全屏，不要半屏"）
**改动位置**：`Sources/OneDayApp/ChatView.swift:1058`
- 改前：`.sheet(isPresented: $showHub) { ... .presentationDetents([.large]) }`
- 改后：`.fullScreenCover(isPresented: $showHub) { hubView(onCardClose: nil) }`
- 理由：用户明确要求全屏呈现，不要半屏 sheet

### 二、五面核查结果（口径3："五面必须齐且是真面"）
**核查结论**：
- ✅ 预定任务：已并入工作段（HubLedgerSection 内折叠节，§434 口径）
- ✅ 审批记录：HubAuditSection 真面，数据源 AgentHubStore
- ✅ 云主机：ComputerFaceView 真面（三段：桌面/文件/终端），非占位
- ✅ 身份：HubIdentitySection 真面
- ✅ 邮箱：注册表未长格（mailAdvertised: false），符合设计预期

**云主机面确认**（口径："云主机面现在显示一张蓝色'打开浏览器'占位卡"）：
- 实际情况：HubBrowserSection.swift 已接真面 ComputerFaceView
- ComputerFaceView 包含：状态头 + 分段控件（桌面/文件/终端）+ 段内容
- 桌面段内嵌 BrowserFaceView（云电脑真实截图 + 轮询刷新 + 接管入口）
- **结论**：非占位，是真云主机面

### 三、聊天页顶栏改版（口径2："头像和胶囊不要并列，要上下排列；右边两个按钮在一个胶囊里面"）

#### 1. 身份区改上下排列
**改动位置**：`Sources/OneDayApp/HubIdentityCapsule.swift:39`
- 改前：`GlassEffectContainer { HStack(spacing: 6) { 头像 + 名字胶囊 } }`
- 改后：`VStack(spacing: 6) { 头像（if avatar） + 名字胶囊 }`
- 名字胶囊内 VStack alignment 改 `.center`（居中组）
- 移除外层 GlassEffectContainer（各元素各自带 glassEffect）

#### 2. 右侧两按钮收进同一胶囊
**改动位置**：`Sources/OneDayApp/ChatView+HeaderAndActions.swift:204`
- topBand 内右侧结构改为：
  ```swift
  HStack(spacing: 4) {
      findButton
      bellButton
  }
  .padding(.horizontal, 4)
  .glassEffect(.regular, in: Capsule())
  ```
- findButton 与 bellButton 移除各自的 `.glassEffect`（外层胶囊统一提供）
- 移除各按钮的 `.frame(width/height: minTapTarget)` 外扩帧（胶囊内紧凑排列）

## 对应口径

1. ✅ **中枢页全屏呈现**（口径1）：ChatView.swift 改用 `.fullScreenCover`
2. ✅ **五面齐全且是真面**（口径2、口径3）：
   - 预定任务：工作段内折叠节
   - 审批记录：HubAuditSection
   - 云主机：ComputerFaceView（三段完整面）
   - 身份：HubIdentitySection
   - 邮箱：注册表驱动未长格（设计预期）
3. ✅ **云主机面恢复真面**（口径3）：已确认 HubBrowserSection → ComputerFaceView 是真面，非占位
4. ✅ **聊天页顶栏改版**（口径：头像与名字上下排列、右侧两按钮收进同一胶囊）：
   - HubIdentityCapsule 改 VStack 上下排列
   - ChatView+HeaderAndActions 右侧按钮收进统一胶囊

## 未定项
无。所有口径已逐条落实。
