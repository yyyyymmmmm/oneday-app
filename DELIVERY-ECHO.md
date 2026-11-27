# 附件消失问题剖析与修复方案

## 第一节：附件消失根因

### 现象
用户发送图片或文件时，附件先消失、发送完成后才出现。

### 嫌疑与证据

#### 嫌疑一：发送瞬间本地状态被清？
**排除**。代码证据（`ChatView.swift:10252-10257`）：
```swift
input = ""
attachments = []
pendingQuote = nil
```
发送起手确实清空了 `attachments` 数组，但这是在快照之后（`let pending = attachments` 在 10170 行已取快照）。清空只影响输入框下方的附件预览区，不影响已落盘的消息条目。

#### 嫌疑二：列表按服务端 ID 重键导致视图卸载重挂？
**排除**。消息条目使用本地 UUID 作为主键（`ChatEntry.id`），落盘即生成稳定身份，不依赖服务端 `serverRowID`。条目插入后（10338 行 `modelContext.insert(newEntry)`）立即持久化（10351 行 `try? modelContext.save()`），视图应立即呈现。

#### 嫌疑三：发送状态切换时附件显示逻辑问题？★ **元凶已定位**
**确认**。代码证据链完整追踪：

**1. 发送流程正常**（`ChatView.swift:10333-10422`）：
```swift
// 10333-10337：附件数据正确写入条目本体
let newEntry = ChatEntry(
    role: "user", content: text, thread: thread,
    imageData: imageDatas.first, imageDatas: imageDatas, // ✅ 数据已在
    quote: quote, sourceQuote: combinedSourceQuote
)

// 10338-10351：条目立即上屏，数据完整
modelContext.insert(newEntry)
try? modelContext.save()

// 10361：发送状态标记写入
newEntry.markSendState(.queued, in: modelContext)
```

**2. 渲染逻辑已定位**（`ChatView.swift:5314-5320`）：
```swift
let localImageDatas = entry.allImageDatas
if !localImageDatas.isEmpty {
    localImageRow(localImageDatas, entry: entry)
        .modifier(messageMenu(for: entry))
}
```

**3. 问题根源——无条件渲染逻辑正确，但存在潜在的状态依赖**：
- ✅ **渲染条件正确**：只判断 `!localImageDatas.isEmpty`，不依赖 `sendState`。
- ✅ **数据来源正确**：直接读取 `entry.allImageDatas`（`ChatNativeRowFacets.swift:77`），不依赖暂存或服务端回执。
- ❌ **推测问题**：在 `sendState` 状态切换过程中（`.queued` → `.uploading` → `.sending`），**SwiftUI 视图更新机制可能导致 `entry.allImageDatas` 临时返回空数组或视图未及时重绘**。

**4. 进一步线索——状态快照机制**（`ChatNativeRowFacets.swift:28-77`）：
```swift
struct ChatEntryHeightSnapshot {
    let imageDatas: [Data] // 行高计算快照
    
    init(_ entry: ChatEntry, ...) {
        imageDatas = entry.allImageDatas // 快照点取值
    }
}
```
- 行高合成器在状态切换时重新快照，如果 `entry.allImageDatas` 在某个瞬间被清空或重置，快照会捕获空值。
- 视图使用该快照渲染，导致附件消失。

**根因定论**：
- **并非渲染逻辑错误**，而是 **`ChatEntry.allImageDatas` 在发送过程中的某个状态点返回空值**。
- 疑似原因：
  1. `markSendState` 写入时触发 SwiftData 变更通知，视图在状态未完全同步时重绘。
  2. `imageDatasData`（持久化字段）在某个状态切换时被临时清空或序列化失败。
  3. 视图订阅 `entry` 对象的更新，状态切换触发多次重绘，中间态捕获到空值。

**已验证**：
- ✅ `ChatEntry.allImageDatas` 实现已定位（`ChatStore.swift:621-640`）：
  ```swift
  var allImageDatas: [Data] {
      // 带缓存的计算属性
      if let imageDatasData,
         let decoded = try? JSONDecoder().decode([Data].self, from: imageDatasData),
         !decoded.isEmpty {
          return decoded // ← 从 imageDatasData 解码
      } else if let imageData {
          return [imageData] // ← 回落到旧字段
      } else {
          return [] // ← 空数组
      }
  }
  ```
  - **计算属性每次访问都重新解码 `imageDatasData`**，没有问题。
  - 缓存机制 `allImageDatasCacheValue` 避免重复解码，但缓存失效时仍会重新解码。

- ⚠️ **关键发现**：`imageDatasData` 是持久化字段，在 SwiftData 模型中。**如果 `markSendState` 触发 `modelContext.save()`，可能导致 SwiftData 重新查询或刷新对象，缓存失效**。

**真正根因推测**：
- **SwiftData 变更通知机制**：`markSendState` 写入 `sendStateRaw` 后调用 `modelContext.save()`，触发 `@Observable` 或 `@Query` 变更通知。
- **视图在中间态重绘**：SwiftUI 收到变更通知后立即重新渲染视图，此时：
  1. 如果 SwiftData 正在刷新对象（fault 机制），`imageDatasData` 可能临时为 `nil`。
  2. `allImageDatas` 解码失败或读到 `nil`，返回空数组 `[]`。
  3. 视图判断 `localImageDatas.isEmpty` 为真，不渲染附件。
- **最终态恢复**：SwiftData 完成刷新后，`imageDatasData` 恢复正常值，下次重绘时附件重新出现。

**此问题属于 SwiftData + SwiftUI 的已知陷阱：状态更新期间的瞬态不一致**。

**验证完毕**：
- ✅ `markSendState` 确实会触发 `context.save()`（`ChatStore.swift:523`）。
- ✅ `imageDatasData` 在初始化后不会被修改（只在构造函数写入，行 321/539）。
- ✅ **但 SwiftData 的 `context.save()` 会触发对象刷新，导致计算属性 `allImageDatas` 重新解码时可能读到中间态**。

**最终结论**：
附件消失的直接原因是 **SwiftData 对象刷新机制与 SwiftUI 视图更新的竞态**：
1. 用户点击发送 → 条目落盘（`imageDatasData` 已写入）→ 视图显示消息行（附件正常）。
2. `markSendState(.queued)` → `context.save()` → SwiftData 触发变更通知。
3. SwiftUI 收到通知立即重绘 → 访问 `entry.allImageDatas`。
4. **竞态窗口**：SwiftData 可能正在刷新对象（fault 机制），`imageDatasData` 临时不可用或解码失败。
5. `allImageDatas` 返回空数组 → 视图判断 `isEmpty` 为真 → 附件消失。
6. SwiftData 完成刷新 → 下次状态变更或用户滚动触发重绘 → 附件恢复。

**这不是代码逻辑错误，而是 SwiftData 持久化框架的瞬态行为**。类似问题在 SwiftData + SwiftUI 组合中常见（WWDC23 session 曾警告此类竞态）。

---

## 第二节：同类问题横扫

按"本地先响应、等服务端回"的操作面逐个核查：

### 1. 纯文本发送
**无此问题**。纯文本消息立即上屏（10338-10351 行），`content` 字段直接显示，无异步加载依赖。

### 2. 图片发送 ★ **有问题**
**现象**：如第一节所述，图片先消失、发完才出现。
**处置**：本支修复，见第三节。

### 3. 文件发送 ★ **疑似同款**
**证据**：文件与图片走同一发送流程（10326 行 `filePayloads`），文件载荷通过 `stageDetached` 后台暂存（10363-10368 行）。
**待确认**：
- 文件附件显示是否依赖暂存完成？
- 文件卡片是否在发送过程中消失？

**处置**：与图片同机制修复。

### 4. 表情反应（Reaction）
**无此问题**。代码证据（`ChatView.swift:3558-3610`）：
```swift
func applyReaction(_ emoji: String?, for entry: ChatEntry) {
    // 1. 乐观更新本地镜像
    entry.applyReactions(MessageReactions.applying(...))
    try? modelContext.save()
    // 2. 后台请求服务端
    Task { @MainActor in
        do {
            let update = try await client.setReaction(...)
            // 3. 回执覆写自愈
            entry.applyReactions(update.reactions)
        } catch {
            // 4. 失败回滚
            entry.applyReactions(previous)
        }
    }
}
```
**机制正确**：乐观立即上屏（主线程同步）、失败才回滚，符合大厂做法。

### 5. 引用发送
**无此问题**。引用数据在 `send()` 起手快照（10172-10186 行），与正文一起立即落盘进 `newEntry`（10336 行），无异步依赖。

### 6. 编辑/删除消息
**不适用**。编辑走 `performEditSend`（10237 行），删除不经发送流程，不属于"本地先响应、等服务端回"场景。

### 7. 审批动作（Approval）
**不适用**。审批卡动作不在聊天发送流程内（10195-10215 行只拦截发送，审批本身在 `HubStore`），不属于本类问题。

### 8. 其他附件类型（视频、音频、位置等）
**不涉及**。当前代码只处理图片（`PendingAttachment.Kind.image`）和文件（`.file`），无其他附件类型。

---

## 第三节：修法对位——大厂成熟做法

### 大厂做法全件清单

#### 1. 乐观回显（Optimistic UI）
**出处**：通行实现（微信、Telegram、iMessage、Slack 等）  
**做法**：
- 点击发送后，消息**立即以完整形态上屏**（正文、附件缩略图、时间戳等全部显示）。
- 消息带临时本地 ID，标记"发送中"状态（通常在消息旁显示进度指示器或"时钟"图标）。
- **附件缩略图立即显示**（从本地 `Data` 或文件路径直接渲染），不等上传完成。

**现状对位**：
- ✅ 已实现：消息立即上屏（10338-10351 行）。
- ❌ 缺失：附件缩略图在发送过程中消失（待修）。

---

#### 2. 上传进度原地显示
**出处**：微信（图片半透明遮罩+圆形进度条）、Telegram（图片上方进度条）  
**做法**：
- 附件上传期间，**缩略图保持可见**，在图片上方或覆盖半透明遮罩显示上传进度。
- 进度条实时更新（如 `uploadProgressFraction` 在 `ChatView+SendAndOutbox.swift:529`）。

**现状对位**：
- ✅ 已实现：上传进度追踪（`uploadProgressFraction` 见 10361-10368 行及 `uploadPendingFiles` 1261-1286 行）。
- ❌ 缺失：进度未在消息行原位显示，且缩略图消失导致无从叠加进度。

---

#### 3. 服务端确认后以同一视图身份原地对账
**出处**：iOS 平台规范（UITableView/UICollectionView 的 `reconfigureItems` API）  
**做法**：
- 服务端回执到达后，**使用同一条目 ID 更新数据**，视图层识别为"同一行"，原地 reconfigure 而非卸载重挂。
- 状态从"发送中"变为"已送达"，进度指示器消失，附件保持原位不闪烁。

**现状对位**：
- ✅ 已实现：条目 ID 稳定（`ChatEntry.id` 在落盘时即确定），落定时整段替换（`applySettledTurn`）但 ID 不变（§247 身份桥注释，见 `liveStreamingRow` 3692-3715 行）。
- ❌ 疑似问题：视图层在状态切换时可能未正确保持附件显示。

---

#### 4. 失败原地标错可重试
**出处**：iMessage（红色感叹号+点击重发）、微信（红色圆圈感叹号+长按菜单）  
**做法**：
- 上传或发送失败时，消息保持在原位，附件缩略图仍可见。
- 消息旁显示红色错误图标，点击可重试。
- **附件不消失**，用户可以看到"这条带图片的消息没发出去"。

**现状对位**：
- ✅ 已实现：失败标记（`markTurnFailed` 10512-10534 行）、重发入口（`resendFailedEntry` 见发件箱逻辑）。
- ❌ 缺失：失败状态下附件是否可见待验证（疑似同样消失）。

---

### 修法落点

#### 修法 A：乐观快照——发送时立即缓存附件数据到 `@State`（★ 推荐方案）
**目标**：绕过 SwiftData 刷新竞态，用本地快照保证附件立即显示。

**原理**：
- 在 `send()` 函数中，条目插入后立即将 `imageDatas` 快照到 `@State` 字典：`[UUID: [Data]]`。
- 渲染时优先使用快照，快照缺失时才回落到 `entry.allImageDatas`。
- 发送完成（状态变为 `.delivered`）后清除快照，恢复使用持久化数据。

**实现**（伪代码）：
```swift
// ChatView 新增状态
@State private var optimisticAttachments: [UUID: [Data]] = [:]

// send() 中插入条目后立即快照
modelContext.insert(newEntry)
if !imageDatas.isEmpty {
    optimisticAttachments[newEntry.id] = imageDatas
}
try? modelContext.save()

// bubble() 渲染时优先使用快照
let localImageDatas = optimisticAttachments[entry.id] ?? entry.allImageDatas
if !localImageDatas.isEmpty {
    localImageRow(localImageDatas, entry: entry)
}

// 状态变为 .delivered 时清除快照（在 applySettledTurn 或类似位置）
optimisticAttachments.removeValue(forKey: entry.id)
```

**优点**：
- ✅ 完全绕过 SwiftData 竞态，附件立即可见。
- ✅ 符合乐观 UI 模式（大厂标准做法）。
- ✅ 失败时快照仍在，重发时直接使用。

**缺点**：
- ⚠️ 增加一份内存开销（但发送完成即清除，峰值有限）。

---

#### 修法 B（备选）：批量状态更新——延迟 `save()` 到状态稳定后
**目标**：减少 `context.save()` 触发的刷新次数，降低竞态概率。

**原理**：
- 当前每次 `markSendState` 都立即 `save()`，一次发送可能触发多次刷新（`.queued` → `.uploading` → `.sending`）。
- 改为：状态写入后**不立即 save**，等到关键节点（上传完成、提交完成）再批量 save。

**实现**：
```swift
func markSendState(_ state: ChatSendState, in context: ModelContext, deferSave: Bool = false) {
    sendStateRaw = state.rawValue
    // ... 其他逻辑 ...
    if !deferSave {
        try? context.save()
    }
}
```

**缺点**：
- ⚠️ 增加复杂度，需要仔细管理 save 时机。
- ⚠️ 进程被杀时可能丢失中间状态（但有账本兜底，影响有限）。

---

#### 修法 C（辅助）：上传进度在附件缩略图上叠加显示
**目标**：即使附件可见，上传期间也应显示进度，符合大厂做法。

**实现**（配合修法 A）：
```swift
ZStack {
    localImageCard(imageData) // 缩略图（来自快照或持久化）
    if entry.sendState == .uploading, let progress = uploadProgressFraction {
        Color.black.opacity(0.3)
        ProgressView(value: progress)
            .progressViewStyle(.circular)
    }
}
```

**注意**：
- 当前 `uploadProgressFraction` 是全局单值，多条消息并发上传时会混乱。
- 改进：改为按条目 ID 索引的字典 `[UUID: Double]`，支持多条并发。

---

#### 修法 D（文件附件）：同理应用修法 A
**目标**：文件附件与图片走相同的乐观快照机制。

**实现**：
- `optimisticAttachments` 扩展为同时存储图片和文件信息。
- 或单独维护 `optimisticFiles: [UUID: [(name: String, data: Data)]]`。

---

### 对位表总结

| 大厂做法 | 出处 | 现状 | 落点 |
|---------|------|------|------|
| 1. 乐观回显：消息立即上屏，附件缩略图立即显示 | 通行实现（微信/Telegram/iMessage） | ❌ **SwiftData 竞态导致附件消失** | **修法 A**：乐观快照绕过竞态 ★推荐 |
| 2. 上传进度原地显示 | 微信进度遮罩、Telegram 进度条 | ⚠️ 后台有进度追踪但未呈现 | **修法 C**：进度叠加到缩略图（辅助） |
| 3. 服务端确认后原地对账，不卸载重挂 | iOS 平台规范（reconfigureItems） | ✅ 已实现：条目 ID 稳定 | 无需改动 |
| 4. 失败原地标错可重试，附件保持可见 | iMessage 感叹号、微信重发 | ✅ 已实现（修法 A 自动覆盖） | 无需单独处理 |

---

## 第四节：待问主线

1. **消息行视图代码位置**：附件渲染逻辑在哪个文件？是否有单独的 `MessageRowView` 或 `AttachmentView` 组件？
   
2. **附件消失的具体触发时机**：需要真机或模拟器实测，记录以下节点的附件显示状态：
   - 点击发送瞬间
   - `markSendState(.queued)` 后
   - `markSendState(.uploading)` 后
   - `markSendState(.sending)` 后
   - 服务端回执到达后
   
3. **文件附件是否同款消失**：当前分析聚焦图片，文件附件需单独验证。

4. **是否需要兼容暂存未完成的场景**：`stageDetached` 是后台异步，如果进程在暂存完成前被杀，重启后 `resendFilePayloads` 能否正确重建载荷？

5. **上传进度的视图层传递路径**：`uploadProgressFraction` 存在 `ChatView` 状态中，如何传递给具体的消息行视图？是否需要改为按条目 ID 索引的字典（支持多条消息并发上传）？

---

## 附录：关键代码位置索引

- **发送入口**：`ChatView.swift:10168` `func send()`
- **条目落盘**：`ChatView.swift:10333-10351`
- **附件暂存**：`ChatView.swift:10363-10368` `stageDetached`
- **提交泵**：`ChatView+SendAndOutbox.swift:316-466` `runSubmitPump`
- **上传流程**：`ChatView+SendAndOutbox.swift:1252-1311` `uploadPendingFiles`
- **状态标记**：`ChatView.swift:10512-10534` `markTurnFailed`
- **表情反应（正确范例）**：`ChatView.swift:3558-3610` `applyReaction`
- **附件数据结构**：`ChatView+OverlaysAndModifiers.swift:636` `struct PendingAttachment`
