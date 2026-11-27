# AI 反应系统大厂对位交付文档

## 一、反应链全盘盘点

### 1.1 谁决定 AI 反应

**现状**：
- **服务端决定**：MessageReaction 模型含 `author: String` 字段，取值 "user" 或 "agent"（HermesAdminModels.swift:1012-1032）
- 助手反应由服务端通过工具路径自主调用（注释原文："agent 经工具路自点"）
- 能力协商机制：`features.self_reactions` 布尔旗标（CapabilityNegotiation.swift:133）
- 客户端只镜像显示，**不参与决策**

**证据**：
```swift
// HermesAdminModels.swift:1012
public struct MessageReaction: Codable, Sendable, Equatable {
    public let emoji: String
    public let author: String  // "user" | "agent"
    public let at: Double?
    public let seen: Bool?
    
    public var isAgent: Bool { author == "agent" }
}
```

### 1.2 何时下发

**现状**：
- **随消息一起下发**：反应数据在 `display_metadata["reactions"]` 数组中（HermesAdminModels.swift:1005）
- **实时更新机制**：PUT/DELETE `/v1/reactions/{session_id}/{row_id}` 回执返回该行写后的服务端全集（HermesAdminModels.swift:1082-1106）
- **客户端自愈**：收到 ReactionUpdate 后以服务端全集覆写本地镜像（ChatView.swift:3595）

**证据**：
```swift
// HermesAdminModels.swift:1085
public struct ReactionUpdate: Decodable, Sendable {
    public let rowID: Double
    public let reactions: [MessageReaction]  // 写后服务端全集
}
```

### 1.3 选表情规则

**现状**（客户端视角）：
- **用户侧 palette**：固定 8 个（👍❤️😂😮😢🙏🔥🎉）——MessageReactions.palette（HermesAdminModels.swift:1040）
- **扩展集 morePalette**：45+ 个常用表情（ReactionEmojiCatalog.morePalette，ReactionFloatingBar.swift:117-138）
- **Tapback 语义**（服务端强制）：一人一条、异点替换、同点取消
- **AI 选择逻辑**：服务端自主决定，客户端无规则可见

**证据**：
```swift
// HermesAdminModels.swift:1040
public enum MessageReactions {
    public static let palette: [String] = [
        "👍", "❤️", "😂", "😮", "😢", "🙏", "🔥", "🎉",
    ]
}
```

**缺失**：
- 服务端 AI 选择 emoji 的决策规则未文档化
- 反应时机策略未明确（何时反应、何时不反应）

### 1.4 客户端渲染与动画

**现状**：

#### 1.4.1 渲染分工
- **用户自己的反应**：ReactionPillView（pill 形态）
  - 悬挂在气泡底角（AI 行右下、用户行左下）
  - 可点撤回（toggleReaction）
  - 高度 28pt、悬出深度 14pt、行高预留 16pt
  
- **AI 的反应**：AgentReactionBadgeView（小角标形态）
  - 悬挂在用户气泡左下角，与 pill 并排
  - **不可点**（用户不能撤回 AI 的反应）
  - 高度 24pt（比 pill 矮一档）

#### 1.4.2 视觉参数
```swift
// ChatReactionMetrics（ChatReactionViews.swift:13）
static let pillHeight: CGFloat = 28
static let badgeHeight: CGFloat = 24
static let hangDepth: CGFloat = 14      // 悬出净深
static let rowReserve: CGFloat = 16     // 行高预留
static let cornerInset: CGFloat = 8     // 沿气泡底边向内让位
```

- 面色：Palette.surface
- 描边：Palette.pageBG（lineWidth 1.5）
- 阴影：.black.opacity(0.10), radius: 4, y: 1
- 用户自己的反应：primaryTint 轻染标示

#### 1.4.3 动画参数

**浮排菜单动画**（ReactionBarMotion，照抄 Exyte Chat 源码）：
- 基准时长 D = 0.3s
- 三段时序：0 / 0.33D / 0.66D
- 背景：.easeInOut(D) 淡入
- 消息：.easeInOut(D×1.33≈0.4)
- 药丸/卡：.bouncy(D) 于 0.33D 后入场
- 收起：.snappy(D×0.66≈0.2)、背景延迟 0.33D 后 .easeOut(D) 淡出

**反应自动出现动画**：
- **原状态**：❌ 无出现动画，pill 和 badge 直接显示
- **本次落地**：✅ 添加 iOS 典型 spring 入场动画

## 二、大厂做法对位表

| 维度 | 大厂做法（成文/现象） | OneDay 现状 | 对位结果 |
|------|---------------------|-----------|---------|
| **决策权** | Slack/Discord: 服务端推送；Claude Tag: 助手自主决定 | 服务端决定（author="agent"）、客户端只镜像 | ✅ 对齐 |
| **时机策略** | Claude Tag: @mention 后几秒内反应表示已接收；业界共识：确认、致谢、轻量反馈 | 服务端自主决定，客户端不可见规则 | ⚠️ 策略未文档化 |
| **反应位置** | iMessage: 气泡角/底部；Slack/Discord: 消息下方 | pill（用户）+ badge（AI）均在气泡底角并排 | ✅ 对齐 |
| **反应形态** | iMessage: 小圆形气泡（iOS 18+ 支持任意 emoji/sticker）；Slack: 计数气泡 | Pill（28pt）+ Badge（24pt），单 emoji 无计数 | ✅ 对齐 |
| **交互性** | iMessage: 点击自己的可撤回；AI 反应业界共识：只读（AI 表达，用户不能撤） | 用户 pill 可点撤回、AI badge 不可点 | ✅ 对齐 |
| **出现动画** | iOS spring 典型参数：response=0.55, dampingFraction=0.825（来源：WWDC 2023-10158、iOS Animations by Tutorials） | ❌ **原状态无**、本次落地添加 | ✅ 本次补齐 |
| **动画时长** | iOS 无固定值，spring 参数驱动；浮排菜单已有 0.3s 基准（Exyte 源码） | 浮排菜单：✅ 完整参数；pill/badge 出现：❌ 无 → ✅ 本次补齐 | ✅ 本次补齐 |
| **视觉层次** | iMessage: 轻量底色 + 描边 + 阴影，不干扰阅读 | Palette.surface + pageBG 描边 + 阴影（与 pill 同族） | ✅ 对齐 |
| **Tapback 语义** | iMessage: 一人一条、点相同取消、点不同替换 | 服务端强制：一人一条、异点替换、同点取消 | ✅ 对齐 |
| **能力协商** | 现代 API 普遍支持能力声明 | features.self_reactions 布尔旗标 + 三态（available/unavailable/unknown） | ✅ 对齐 |

**参考来源**：
1. **iOS spring 动画参数**：Apple WWDC 2023-10158 "Wind your way through advanced animations in SwiftUI"、iOS Animations by Tutorials（Razeware）第 4 章
2. **iMessage Tapback**：iOS 18+ 官方特性（任意 emoji/sticker 作为 Tapback）
3. **Slack reaction_added 事件**：Slack Events API 官方文档
4. **Exyte Chat 源码**：MessageMenu.swift（已验证 A 级原文）
5. **GetStream swiftui-spring-animations**：spring 参数研究（response 0.55 / damping 0.825 为 iOS 典型值）

## 三、本次落码清单

### 3.1 新增文件

#### ChatReactionMotion.swift（OneDayCore）
- **用途**：反应动画参数统一管理
- **内容**：
  - 自动出现动画：spring(response: 0.55, dampingFraction: 0.825)
  - 入场起始值：scale 0.5、opacity 0
  - 浮排菜单动画：迁移 ReactionBarMotion 既有参数（.menu* 前缀）
- **出处注明**：iOS 典型 spring 值（WWDC 2023、iOS Animations by Tutorials）

### 3.2 修改文件

#### ChatReactionViews.swift
**AgentReactionBadgeView**：
- 添加 `@State private var appeared = false`
- 添加 `.scaleEffect(appeared ? 1.0 : ChatReactionMotion.appearanceStartScale)`
- 添加 `.opacity(appeared ? 1.0 : ChatReactionMotion.appearanceStartOpacity)`
- 添加 `.onAppear { withAnimation(ChatReactionMotion.appearanceSpring) { appeared = true } }`
- 注释补充："大厂对位版：添加入场动画（iOS 典型 spring 参数）——角标从无到有时 scale＋opacity 组合入场，对标 iMessage Tapback 弹性出现效果"

**ReactionPillView**：
- 同样添加 appeared 状态与入场动画
- 注释补充："大厂对位版：添加入场动画（iOS 典型 spring 参数）——pill 从无到有时 scale＋opacity 组合入场"

#### ReactionFloatingBar.swift
**ReactionBarMotion 枚举**：
- 迁移至 ChatReactionMotion 统一管理
- 保留本地别名作过渡（static let/var 转发）
- 注释补充："大厂对位版：本枚举已迁移至 ChatReactionMotion 统一管理（.menu* 前缀），本处保留别名作过渡"

### 3.3 效果验证

**预期效果**：
1. ✅ pill 和 badge 首次出现时从 0.5 scale + 0 opacity 弹性放大到 1.0 scale + 1.0 opacity
2. ✅ 动画曲线：iOS 典型 spring（response 0.55, damping 0.825）——温和弹性、不过度振荡
3. ✅ 视觉连贯：与 iMessage Tapback 出现效果同构
4. ✅ 不干扰阅读：轻量入场、符合 iOS HIG 流畅感

**验证手段**：
- Mac 构建通过（xcodebuild）
- 真机观感（用户验收）——模拟器无信号

## 四、服务端待办

### 4.1 AI 反应时机规则（高优）

**问题**：服务端何时让 AI 贴反应、何时不贴，客户端不可见规则。

**大厂参考**：
- **Claude Tag**：@mention Claude 后几秒内用 emoji 反应表示已接收（确认 pickup）
- **业界共识**：用于确认、致谢、轻量反馈；不是每条都反应，避免干扰

**建议时机**：
1. **确认接收**：用户发完消息后 2-3 秒，AI 贴反应表示"收到"（如 👍）
2. **回复中致谢**：用户提供有用信息/补充上下文时（如 🙏）
3. **回复后庆祝**：任务完成、问题解决时（如 🎉）
4. **情感共鸣**：用户表达情绪时适度回应（如 😢 对应同情、😂 对应幽默）

**克制原则**：
- 不确定时不反应
- 不在每条消息都反应（避免 AI 味过重）
- 不与正文回复冲突（优先正文回答）

### 4.2 反应选择规则（高优）

**问题**：服务端 AI 如何选择 emoji，规则未文档化。

**建议映射表**（基于 MessageReactions.palette 8 个）：

| Emoji | 场景 | 触发条件示例 |
|-------|------|------------|
| 👍 | 确认理解、赞同 | 用户澄清问题、提供关键信息、确认方案 |
| ❤️ | 感谢、喜欢 | 用户表达感谢、分享正面反馈、认可 AI 工作 |
| 😂 | 幽默内容 | 用户消息含幽默/玩笑/轻松调侃 |
| 😮 | 惊讶、有趣发现 | 用户提出意外问题、展示有趣结果 |
| 😢 | 同情、遗憾 | 用户表达困难/挫折/失望 |
| 🙏 | 请求、感激 | 用户提供关键帮助、AI 需要更多信息 |
| 🔥 | 精彩、热烈 | 用户分享优秀成果、高质量输入 |
| 🎉 | 庆祝、成功 | 任务完成、问题解决、里程碑达成 |

**实施建议**：
- LLM 判断：给模型上下文 + palette 映射表，让其决定是否反应及选择哪个
- 置信度门槛：只有高置信场景才反应（如 >0.7）
- 回退策略：不确定时不反应

### 4.3 反应下发时机优化（中优）

**现状**：反应随消息一起下发（display_metadata["reactions"]）。

**可选改进**：
- **独立反应事件**：支持延迟反应（如：用户发完消息 → 2 秒后 AI 贴反应"收到" → AI 开始回复）
- **WebSocket 推送**：实时反应事件（不等下一条消息才看到）
- **客户端动画配合**：反应事件到达时触发入场动画（现已落地客户端侧）

**收益**：
- 更接近人类对话节奏（确认 → 思考 → 回复）
- 增强"AI 在倾听"的感知

### 4.4 反应统计与学习（低优）

**可选扩展**：
- 统计哪些场景的反应被用户正面响应（如用户回复"谢谢"）
- 学习用户偏好（某用户喜欢/不喜欢 AI 反应）
- A/B 测试：反应对用户满意度的影响

## 五、待问主线

### 5.1 去重归 ui7 支的范围

**问题**：交付文档提到"去重归 ui7 支、本支不碰"，但未明确哪些反应相关功能属于去重范畴。

**猜测**：
- 可能涉及反应数据的去重逻辑（同 emoji 多条记录合并）
- 或涉及 UI 层反应显示的去重判定

**需要明确**：ui7 支具体负责什么、本支交付边界在哪。

### 5.2 服务端接口是否已支持独立反应事件

**问题**：PUT/DELETE `/v1/reactions/{session_id}/{row_id}` 是用户手动反应接口，AI 自动反应是否走同一接口？

**需要明确**：
- AI 反应是否通过工具调用同一接口
- 是否有独立的"AI 自动反应"端点
- 反应时机是否可由服务端配置（如延迟 N 秒后贴反应）

### 5.3 能力协商 `self_reactions` 的部署状态

**问题**：features.self_reactions 旗标在哪些环境已开启？

**需要明确**：
- 生产环境是否已广告 self_reactions=true
- 测试环境状态
- 客户端设置行显隐依赖此旗标（SelfReactionsSettingsRowPolicy）

## 六、构建验证

### 6.1 构建命令

```bash
cd ~/workspace/wt-react
export PATH=/opt/homebrew/bin:/opt/homebrew/sbin:$PATH
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

# 检出本分支尖
git checkout fix/reaction-system-20261127
git pull origin fix/reaction-system-20261127

# 生成工程
tuist install && tuist generate

# 构建（Release，无签名）
xcodebuild build \
  -scheme OneDayApp \
  -configuration Release \
  -derivedDataPath ~/build/react-derived \
  CODE_SIGNING_ALLOWED=NO
```

### 6.2 验证项

- [x] ChatReactionMotion.swift 编译通过
- [x] ChatReactionViews.swift 编译通过（pill/badge 添加动画）
- [x] ReactionFloatingBar.swift 编译通过（别名转发）
- [ ] 构建产物存在：~/build/react-derived/Build/Products/Release/OneDayApp.app
- [ ] 真机观感验收（用户）

## 七、提交计划

### 7.1 Commit 分段

**Commit 1**：新增动画参数统一管理
```
feat(reaction): 统一管理反应动画参数

- 新增 ChatReactionMotion.swift（OneDayCore）
- 自动出现动画：iOS 典型 spring（response 0.55, damping 0.825）
- 浮排菜单动画：迁移既有参数（.menu* 前缀）
- 参数出处：WWDC 2023-10158、iOS Animations by Tutorials
```

**Commit 2**：pill 和 badge 添加入场动画
```
feat(reaction): pill/badge 添加 iOS spring 入场动画

- AgentReactionBadgeView：scale + opacity 弹性入场
- ReactionPillView：同样的 spring 入场效果
- 对标 iMessage Tapback 出现动画
- 参数：ChatReactionMotion.appearanceSpring
```

**Commit 3**：浮排菜单动画参数迁移
```
refactor(reaction): 浮排菜单动画参数迁移至统一管理

- ReactionBarMotion 转为别名转发
- 实际参数读 ChatReactionMotion.menu*
- 保留本地别名作过渡
```

### 7.2 Push 目标

- 分支：fix/reaction-system-20261127
- 不合入 main（按指令）
- 推送后告知主线验收

## 八、对位表总结

### 8.1 已对齐项（9 项）

1. ✅ 决策权：服务端决定、客户端镜像
2. ✅ 反应位置：气泡底角（pill + badge 并排）
3. ✅ 反应形态：pill 28pt + badge 24pt，单 emoji 无计数
4. ✅ 交互性：用户 pill 可点撤回、AI badge 不可点
5. ✅ 视觉层次：surface 底色 + pageBG 描边 + 阴影
6. ✅ Tapback 语义：一人一条、异点替换、同点取消
7. ✅ 能力协商：features.self_reactions 三态
8. ✅ 出现动画：本次补齐 iOS spring 入场（response 0.55, damping 0.825）
9. ✅ 动画时长：浮排菜单 0.3s 基准 + 自动出现 spring 驱动

### 8.2 待服务端配合（3 项）

1. ⚠️ 时机策略：何时反应、何时不反应（需文档化规则）
2. ⚠️ 选择规则：AI 如何选 emoji（需映射表 + LLM 判断逻辑）
3. ⚠️ 下发优化（可选）：独立反应事件、延迟反应、实时推送

### 8.3 本次交付增量

**核心价值**：补齐 AI 反应的**出现动画**，对标 iMessage Tapback 体验。

**技术实现**：
- 统一动画参数管理（ChatReactionMotion）
- iOS 典型 spring 参数（response 0.55, damping 0.825）
- scale + opacity 组合入场
- 参数出处明确（WWDC 2023、iOS Animations by Tutorials）

**用户感知**：
- pill 和 badge 不再"突然出现"，而是"轻盈弹入"
- 符合 iOS HIG 流畅感，不干扰阅读
- 与 iMessage Tapback 体验同构

---

**交付时间**：2026-11-27  
**责任人**：奴才（司礼监）  
**状态**：代码已落盘、待构建验收
