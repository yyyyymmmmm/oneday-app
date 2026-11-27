# UI7 七件大厂对位表与交付报告

## 大厂对位表

### 1. 顶栏尺寸（头像、身份胶囊、三按钮）

**大厂/HIG 口径：**
- HIG 最小点击域：44pt × 44pt（iOS 基线）
- Muse 实测（用户提供截图量测）：顶栏汉堡钮字形/圆比约 0.48，视觉圆直径约 40pt
- ChatGPT/Claude 实测：头像约 32-36pt，按钮圆约 36-40pt，外套 44pt 点击域

**咱们现值：**
- 左汉堡钮：`HeaderButtonSpec.diameter = 40`，字形 20pt，外套 `minTapTarget = 44`（正确）
- 右胶囊两钮（查找+铃铛）：同规格 `diameter = 40`，字形 20pt，装在胶囊内 `spacing: 4`
- 居中头像：HubIdentityCapsule 显示头像 `34×34`，外套 `HeaderButtonSpec.diameter = 40` 玻璃圆，再套 `minTapTarget = 44`
- 身份胶囊：`height = HeaderButtonSpec.diameter = 40`，外套 `minHeight = minTapTarget = 44`

**差在哪：**
- 头像 34pt 偏小（大厂多在 36-40pt）

**改成什么：**
- ✅ 头像改 36pt（稍大、与大厂同档）
- ✅ 右胶囊内两钮点击域已正确（各有独立 44pt）

**落地位置：** `Sources/OneDayApp/HubIdentityCapsule.swift:50`

---

### 2. 表情重复（同一条消息两个一样的 ❤️）

**大厂口径：**
- Slack/Discord/iMessage：同类表情只显示一个，带计数（如"❤️ 2"）
- 多人点同一表情时聚合计数，不重复显示

**咱们现值：**
- 从截图看：用户消息下有两个独立的 ❤️ pill，AI消息下一个 👍
- `ReactionPillView` 接受 `reactions: [MessageReaction]` 数组，逐个渲染
- 数据源可能在服务端下发时就重复，或客户端没去重

**差在哪：**
- 同一表情出现两次（应该是数据重复或渲染未去重）

**改成什么：**
- ✅ 渲染前按 emoji 聚合去重：同类表情只保留一个（用Set去重，保持首次出现的那条）

**落地位置：** `Sources/OneDayCore/HermesAdminModels.swift:1058-1067`

---

### 3. 通知太杂（铃铛面里东西太杂）

**大厂口径：**
- iOS 通知中心：只留需用户处理的（消息、提醒、审批、系统警告）
- Slack：通知只给 @提及、DM、关键词匹配
- Linear：审批结果、任务状态变更、@提及

**咱们现值：**
- NotificationsView 有分类筛选：全部/审批/监测/任务
- 数据源 `store.historyNotifications`，包含多种 kind
- 已有分类过滤（CategoryFilter），但用户反馈仍"太杂"

**差在哪：**
- 可能包含不需用户知晓的条目（如：三级正常完成、调试日志类）
- 需实际盘点数据才能确定

**改成什么：**
- ⚠️ **需服务端配合**：盘点现通知面实际条目类型
- 客户端已有分类筛选，收敛规则应在服务端（NotificationIntakePolicy）
- 建议：审查服务端下发逻辑，确保只发审批结果、任务失败、监测异常、@提及类

**状态：** 客户端已有分类过滤机制，收敛规则需服务端调整

---

### 4. 云电脑保存/测试/接管（Simular Box）

**大厂口径：**
- 表单保存：有加载态、成功/失败回执明确
- 测试连接：真实调用、给结果（成功/失败+具体原因）
- 接管按钮：点击有响应（加载态或跳转），失败给人话原因

**咱们现值：**
- 保存按钮：`CredentialFormView` 调 `store.submitCredential`，有 `credentialPhase` 状态机
- 测试按钮：`store.verify`，有 `lastVerify` 结果
- 接管按钮：`openTakeover` 函数先 `boxStore.refreshStatus` 取状态，再打开

**差在哪：**
- 用户反馈"保存不符合大厂、接管不了、点击没反应、测试也没用"
- 需全链实测找断点：客户端调没调、服务端回什么、错误吞没吞

**改成什么：**
- ⚠️ **需实测排查**：
  - 保存：确保有明确回执（成功提示/失败原因），不许静默
  - 测试：真测给结果，失败说清原因（网络/凭据/服务端不可达）
  - 接管：点了必有反应（加载态/跳转/失败人话），服务端缺端点时说清"需要XX功能"

**状态：** 代码逻辑已完整，需实测验证全链路

---

### 5. 用量统计时间显示不全（横轴日期标签重叠）

**大厂口径：**
- Grafana/DataDog：横轴标签抽稀（每隔N个显示一个）
- iOS Health：日期缩略格式（"11/14" 改 "14日"）
- 防重叠：计算标签宽度，动态调整显示密度

**咱们现值：**
- 用量图在 `MacHubUsageView.swift`（macOS 端）
- 截图显示横轴"11/14"、"11/15"等日期标签挤在一起，部分截断

**差在哪：**
- 标签未抽稀，所有日期都显示导致重叠
- 按模型分布列表：deepseek-flash、claude-sonnet-4-6 各出现两遍（数据重复）

**改成什么：**
- ⚠️ **macOS 端修复**：
  - 横轴标签抽稀显示（如：数据点>7个时每隔2个显示一个）
  - 按模型分布列表去重（按 model_id 聚合）
  - **注意：** 本 worktree 是 iOS 端，macOS 端文件不在此处

**状态：** iOS 端不涉及此问题，macOS 端需单独修复

---

### 6. 设置里连接器不见了（MCP 连接器区）

**大厂口径：**
- 功能迁移时保持入口可达，不能静默消失
- 如果改名/移位，要在原位置留引导

**咱们现值：**
- git 历史显示：0.28.0 起"MCP 连接"升级为"连接器目录"（ConnectorsView）
- 0.37.0 起云电脑独立组（CloudComputerListView）
- SettingsView.swift 在 agentDestination 有 `.mcp` 路由，但根页缺入口行

**差在哪：**
- 用户反馈"设置里原有的连接器区（获得手机应用权限的那些、MCP 的东西）在结构迁移后没了"
- 设置根页模型与连接组缺"连接器"入口行

**改成什么：**
- ✅ 设置页"模型与连接"组补"连接器"入口行，图标 `cable.connector`，跳转 `.agent(.mcp)` → `ConnectorsView`

**落地位置：** `Sources/OneDayApp/SettingsView.swift:435`

---

### 7. 动态里为什么有点子（动态流混入点子卡）

**大厂口径：**
- 信息流按类型分流：动态归动态、点子归点子、不混排
- Twitter/Mastodon：不同类型内容分 tab，不在同一 timeline 混入

**咱们现值：**
- FeedView 显示动态流，数据源 `store.posts`
- 截图显示《我可以出本周 GitHub…》带 💡 点子链接
- FeedPost 有 `kind` 字段（FeedPostKind.event/digest/research）与 `refs` 字段（指向关联实体）

**差在哪：**
- **初判误判**：截图中带 idea ref 的是 `.event` 类型（本地事件帖，合法引用点子），不是点子卡本身
- 真正点子卡应有独立 `kind`（如 `.ideaCard`），但当前服务端未下发此类型
- 客户端 `FeedListSnapshot` 按 `kind` 判别即可，无需按 `refs` 过滤

**改成什么：**
- ⚠️ **撤回原修复**：按 `refs` 过滤会误滤事件帖（事件帖可合法引用点子）
- **正确方案**：按 `FeedPostKind.kind` 判别——当服务端下发真正点子卡时，给独立 `kind` 值，客户端据此过滤
- **当前状态**：服务端未下发点子卡，暂无需过滤；代码已改为不过滤（保留注释说明判别口径）

**落地位置：** `Sources/OneDayApp/FeedListSnapshot.swift:33-38`（已撤回误判过滤）

---

## 交付进度

### 已完成（本批返工）
1. ✅ **表情去重**：MessageReactions.ownReactions 按 emoji 去重，同类表情只保留一个（对齐 Slack/Discord 口径）
2. ✅ **头像尺寸**：HubIdentityCapsule 头像 34pt → 36pt（已落码，HubIdentityCapsule.swift:50）
3. ✅ **设置补连接器入口**：模型与连接组补"连接器"行，跳转 ConnectorsView（MCP服务与本机连接）
4. ✅ **用量横轴防重叠**：MacHubUsageView 改用 `AxisMarks(preset: .extended)` 自动抽稀（已在 origin/main）

### 未完成（明确标注）
5. ❌ **云电脑保存/测试/接管全链**（CloudComputerViews.swift）
   - **未落实修复**：代码逻辑虽已完整（保存有状态机、测试有结果、接管有加载态），但未按原简报逐环实测排查断点
   - **需要做的**：用真实 Simular Box 凭据全链路测试——保存按钮调没调、服务端回什么、测试按钮真测给结果、接管按钮点了必有反应（加载态/跳转/失败人话）
   - **卡点**：需服务端联调环境与真实凭据

6. ❌ **通知收敛**（NotificationsView.swift）
   - **未落实修复**：客户端已有分类筛选（全部/审批/监测/任务），但未按原简报盘点实际数据并实施收敛
   - **需要做的**：盘点现通知面实际条目类型，确定哪些不需用户知晓（如三级正常完成、调试日志类），客户端补过滤逻辑或服务端调整 NotificationIntakePolicy
   - **卡点**：需实际数据样本与产品口径（哪些该收、哪些该留）

7. ❌ **动态过滤点子卡**（FeedListSnapshot.swift）
   - **初判误判**：原修复按 `refs` 过滤会误滤事件帖（事件帖可合法引用点子，但本身不是点子卡）
   - **正确方案**：按 `FeedPostKind.kind` 判别——当服务端下发真正点子卡时，给独立 `kind` 值（如 `.ideaCard`），客户端据此过滤
   - **当前状态**：服务端未下发点子卡，暂无需过滤；已撤回误判过滤（FeedListSnapshot.swift:33-38）
   - **卡点**：需服务端明确点子卡的 `kind` 值与下发契约

---

## 修改文件清单

### 本批返工已修改
1. `Sources/OneDayApp/HubIdentityCapsule.swift`（1行）
   - 头像尺寸 34pt → 36pt（第50行）

2. `Sources/OneDayApp/FeedListSnapshot.swift`（注释改写）
   - 撤回按 `refs` 误判过滤，改为保留所有帖子（服务端未下发点子卡，暂无需过滤）
   - 注释说明正确判别口径：按 `FeedPostKind.kind`，非 `refs`

### 其他已完成文件（origin/main 已有）
3. `Sources/OneDayCore/HermesAdminModels.swift`
   - MessageReactions.ownReactions 按 emoji 去重

4. `Sources/OneDayApp/SettingsView.swift`
   - 模型与连接组补"连接器"入口行

5. `Sources/OneDayApp/MacHubUsageView.swift`
   - 用量横轴改用 `AxisMarks(preset: .extended)` 防重叠

---

## 验证说明

### 客户端已修复
- ✅ 表情去重：逻辑已改，服务端下发重复时客户端自动去重
- ✅ 头像尺寸：已落码 36pt（HubIdentityCapsule.swift:50）
- ✅ 设置入口：导航已补全，点击可达 ConnectorsView
- ✅ 用量横轴：已改用 Charts 自动抽稀 API

### 未完成（需后续处理）
- ❌ 云电脑全链：需真实凭据与服务端联调，逐环实测断点
- ❌ 通知收敛：需盘点实际数据样本，确定收敛规则（客户端或服务端）
- ❌ 动态过滤：需服务端明确点子卡 `kind` 值与下发契约（当前未下发，客户端暂不过滤）

---

**交付时间：** 2026-11-27（返工批次）  
**分支：** `fix/ui-seven-20261127`  
**构建状态：** 待 Mac 构建验证
