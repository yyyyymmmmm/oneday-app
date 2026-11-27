# 链接卡施工交卷

## 第一节：输入框上方渲染区盘点与对位

按现行代码，输入框上方会出现的东西（从上到下）：

### 1. 语音失败条（dictationFailureBarView）
- **位置**：ChatInputBarView 顶部，SmoothExpand 包裹
- **触发**：dictation.failure != nil
- **大厂做法**：iOS 原生消息 App、微信等——权限/错误提示在输入区上方独立一行，可关闭
- **咱们现状**：已有实现，SmoothExpand 折叠展开
- **结论**：✅ 符合通行做法，保留

### 2. 语音提示条（dictationNoticeBarView）
- **位置**：失败条下方，同为 SmoothExpand
- **触发**：dictation.notice != nil
- **大厂做法**：同上，状态提示独立一行
- **咱们现状**：已有实现
- **结论**：✅ 符合通行做法，保留

### 3. 审批区（approvalZoneView）
- **位置**：ChatBottomBarView 中，输入舱正上方（朗读条与输入舱之间）
- **触发**：approvalZoneVisible 为 true
- **咱们现状**：皇上旨意明确——固定槽位、输入栏上方、原地换内容，不许改
- **结论**：✅ 已定版机制，红线不动

### 4. 朗读播放条（speechPlaybackBarView）
- **位置**：ChatBottomBarView 中，输入舱正上方一行（台账 183）
- **触发**：speechBarVisible 为 true
- **大厂做法**：iOS 原生朗读、播客 App——播放控制条在输入区上方
- **咱们现状**：已实现，非 overlay 野挂
- **结论**：✅ 符合通行做法，保留

### 5. 编辑已发送横幅（EditSentBannerSlot）
- **位置**：ChatComposerCardView 顶部，卡根直接子级
- **触发**：editBannerArmed 为 true
- **大厂做法**：Telegram、微信等——编辑态在输入区上方显示"编辑消息"横幅
- **咱们现状**：已实现（§352 D3）
- **结论**：✅ 符合通行做法，保留

### 6. 引用块（quoteBarView/feedQuoteBarView/sourceQuoteBarView）
- **位置**：ChatComposerCardView 中，输入行正上方（卡内）
- **触发**：三个变体至多一个在场
- **大厂做法**：Muse、Telegram、Slack——回复/引用嵌在输入舱内，上方有分隔线
- **咱们现状**：已实现（0.36.19 入舱 §84），用户 2026-11-11 00:24 点名对齐 Muse
- **结论**：✅ 符合通行做法，保留

### 7. 待发附件条（attachmentsStripView）
- **位置**：ChatComposerCardView 中，引用块与输入行之间
- **触发**：attachmentsCount > 0
- **大厂做法**：微信、Telegram、Muse——附件预览在输入框内、输入行上方
- **咱们现状**：已实现（流式行 AttachmentFlowLayout）
- **结论**：✅ 符合通行做法，保留

### 8. **【缺失】链接预览卡**
- **大厂做法**：
  - **Muse（皇上样板）**：输入框内打出 URL，上方自动出链接卡（站点图标＋页面标题＋域名＋ ✕）
  - **iMessage/Messages**：iOS 原生用 LinkPresentation 框架（LPMetadataProvider 获取元数据，LPLinkView 渲染）
  - **Telegram**：链接预览在输入框上方，可移除
  - **Slack**：同样自动预览链接
- **咱们现状**：无此功能
- **结论**：❌ 需要实现（本次施工目标）

### 共存规则与堆叠顺序（从上到下）

按现行代码结构，输入框上方的完整堆叠顺序：

```
ChatBottomBarView (VStack spacing: spacingS)
  ├─ 1. importRetryBarView（导入重试条）
  ├─ 2. historySyncBarView（历史同步条）
  ├─ 3. errorBannerView（错误横幅）
  ├─ 4. noticeBarView（提示条）
  ├─ 5. 回底钮行（showsArrowRow）
  ├─ 6. speechPlaybackBarView（朗读播放条）
  ├─ 7. approvalZoneView（审批区）✅ 红线位置
  └─ 8. ChatInputBarView
       └─ ChatComposerCardView（玻璃卡）
            ├─ EditSentBannerSlot（编辑横幅）
            ├─ quoteBarView（引用块，三变体之一）
            ├─ 【链接预览卡】← 新增位置
            ├─ attachmentsStripView（附件条）
            └─ composerRowView（输入行本体）
```

**新增链接卡的位置判定**：
- 按大厂做法（Muse/iMessage），链接预览在输入舱内、输入行正上方
- 与引用块、附件条共存时：引用块 → 链接卡 → 附件条 → 输入行（从上到下）
- 理由：引用是对已有消息的回应（优先级最高），链接是即将发送的内容预览（次之），附件是明确的文件（最接近输入行）

---

## 第二节：链接卡实现

### 大厂成熟做法调研

#### 1. iOS 原生 LinkPresentation 框架
出处：[Apple LinkPresentation Documentation](https://developer.apple.com/documentation/linkpresentation)

**核心组件**：
- `LPMetadataProvider`：异步获取链接元数据（标题、图标、缩略图）
- `LPLinkMetadata`：元数据模型（title、iconProvider、imageProvider、URL）
- `LPLinkView`：UIKit 原生渲染视图（自动布局、适配明暗主题）

**通行做法**：
- 检测到 URL 后异步调用 `LPMetadataProvider.startFetchingMetadata(for:completionHandler:)`
- 获取成功后用 `LPLinkView(metadata:)` 渲染
- 失败兜底：显示纯文本 URL 或简化卡片（仅域名）

#### 2. Muse 实现特征（皇上样板）
- 输入框检出 URL 后立即在上方出卡片
- 卡片元素：左侧站点图标、中间标题＋域名、右上角 ✕ 按钮
- ✕ 的语义：**移除链接预览**（不删除文本中的 URL，只移除预览卡片）
  - 出处：iMessage 同行为——关闭预览后 URL 仍在文本中，只是不显示富媒体卡片
  - Telegram 同样：点 ✕ 后预览消失，消息文本保留 URL

#### 3. 元数据获取与缓存
**大厂做法**（iMessage/Telegram/Slack 通行）：
- **异步获取**：输入时不阻塞，后台请求元数据
- **缓存策略**：同一 URL 短时间内不重复请求（会话级缓存或磁盘缓存）
- **超时处理**：设置合理超时（通常 10-15 秒），超时显示兜底卡片
- **失败兜底**：网络失败或站点不支持时显示简化版（仅域名＋通用图标）

#### 4. 多链接处理
**大厂做法**：
- **iMessage**：只预览第一个链接
- **Telegram**：可预览多个链接（每个独立卡片）
- **Slack**：预览所有链接，折叠显示超过 3 个时

**本次实现选择**：只预览第一个检出的 URL（与 iMessage 对齐，简化实现）

#### 5. 发送后消息中的链接呈现
**大厂做法**：
- **iMessage**：发送后消息气泡内显示相同的链接预览（富媒体卡片）
- **Telegram**：消息中的链接预览与输入区预览一致
- **一致性原则**：输入区看到什么，发送后就应该是什么

**实现要求**：发送后消息中的链接渲染需与输入区卡片保持一致（后续可能需要扩展消息渲染逻辑，本次先确保输入区卡片正确）

---

### 实现方案

#### 步骤 A：URL 检测
- 在 `ChatView` 或输入处理逻辑中，对 `input` 文本用 `NSDataDetector` 检出 URL
- 只取第一个检出的 URL（与 iMessage 对齐）
- 检出后触发元数据获取

#### 步骤 B：元数据获取与缓存
- 用 `LPMetadataProvider` 异步获取元数据
- 实现简单的会话级缓存（字典：URL → LPLinkMetadata）
- 设置 15 秒超时
- 失败兜底：返回仅含 URL 的简化元数据

#### 步骤 C：链接卡渲染
- 在 `ChatComposerCardView` 中新增链接卡槽位（引用块与附件条之间）
- 用 `LPLinkView` 包装为 SwiftUI View（UIViewRepresentable）
- 右上角添加 ✕ 按钮（移除预览，不删文本）
- 添加分隔线（与引用块、附件条同口径）

#### 步骤 D：输入不阻塞与不闪烁
- 元数据获取在后台进行，不阻塞输入
- 卡片出现用 `.transition(.opacity)` 淡入（与引用块、附件条同口径）
- 输入文本变化时，debounce 300ms 再检出 URL（防止每个字符都触发检测）

---

### 待问主线

1. **发送后消息中的链接渲染**：当前消息气泡中是否已有链接富文本处理？如果没有，本次只做输入区卡片，消息中链接的富媒体呈现留待后续包？
2. **缓存持久化**：元数据缓存是否需要磁盘持久化，还是仅会话级内存缓存即可？
3. **多链接支持**：确认只预览第一个 URL 的决策是否可行？
4. **✕ 按钮语义确认**：点 ✕ 后是移除预览（URL 文本保留）还是连文本一起删？按大厂做法应该是前者。

---

## 第三节：施工计划

### 分段 commit 计划
1. **Commit 1**：URL 检测与元数据获取逻辑（LPMetadataProvider 包装＋缓存）
2. **Commit 2**：链接卡视图组件（LPLinkView 包装＋ ✕ 按钮）
3. **Commit 3**：集成到 ChatComposerCardView（槽位＋动画＋共存规则）
4. **Commit 4**：输入处理优化（debounce＋不阻塞）

### 验证计划
- Mac 构建通过（xcodebuild build Release）
- 手动测试输入 URL 后卡片出现、✕ 按钮移除预览、与引用/附件共存无冲突

---

**状态**：盘点完成，等待主线确认待问节后开始落码。
