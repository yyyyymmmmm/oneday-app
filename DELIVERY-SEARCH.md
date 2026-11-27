# 聊天页搜索全流程重做交付（2026-11-27）

## 一、全流程对位表

皇上点名：聊天页主页搜索全流程按大厂标准重做，修两缺陷（上下跳转闪烁、强调不对）。

### 定标：iOS 原生查找标准

**UIFindInteraction 评估**：iOS 16+ 原生查找 API（UIFindInteraction + UITextSearching 协议），适用于纯文本视图（UITextView 等）。OneDay 聊天页是混合内容（文本+图片+卡片+工具调用），架构为 UICollectionView + UIHostingConfiguration 托管 SwiftUI 行内容，不适用原生 API——需保留现有判定层（ChatFind + ChatFindSession）与托管架构。

**通行标准**（Safari iOS / Messages）：
- **命中高亮两档**：当前命中强背景（饱和黄）、其他命中弱背景（淡黄），两档分明
- **平滑跳转**：首次滚动带缓动画，视觉平滑到达目标
- **实时计数**：输入防抖后显示 "x/y" 或 "无结果"
- **环绕翻页**：上一个/下一个循环，到头回尾
- **焦点即聚**：搜索框呈现即自动聚焦、键盘升起

### 环节对位

| 环节 | 标准（Safari/Messages） | 现状 | 差距 | 修法 |
|------|------------------------|------|------|------|
| **1. 搜索入口** | 顶栏搜索按钮点按即开 | ✅ findButton → findController.open() | 无 | 保持 |
| **2. 搜索框呈现** | 位置：内容区顶部；焦点：自动聚焦；键盘：立即升起 | ✅ findBar 在 topBarCluster 下方，onAppear 聚焦，FocusState 驱动键盘 | 无 | 保持 |
| **3. 输入与计数** | 实时匹配，防抖后显示 "当前/总数" 或 "无结果" | ✅ task(id: query) 防抖 200ms，显示 "x/y" 或 "无结果" | 无 | 保持 |
| **4. 命中高亮** | **两档**：当前命中强背景（#F9D84A 浅档），其他命中弱背景（#FBE38A 浅档） | ❌ **单档**：所有命中统一淡黄 #FBE38A | **缺强弱分档** | **修**：当前命中用 `Palette.findMatchCurrent`，其他用 `findMatchOther` |
| **5. 上下跳转** | 平滑滚动到目标，视觉缓动到达 | ❌ **无动画跳跃**：`setContentOffset(animated: false)`，收敛多次重滚 → 闪烁 | **闪烁** | **修**：首次滚动改 `animated: true`，收敛拍在动画后评估 |
| **6. 跳转收敛** | 目标行停在顶留位下方固定间隙（12pt），行高自适应后位置微调收敛（容差 1pt） | ✅ SearchFocusConvergence 机制：topGap=12pt，tolerance=1pt，最多6次 | 无 | 保持机制，配合动画 |
| **7. 环绕翻页** | 到尾自动回头，到头自动回尾 | ✅ session.moveNext/Previous 用 `% count` 环绕 | 无 | 保持 |
| **8. 退出恢复** | 关闭搜索清空查询、清空高亮、收起键盘 | ✅ closeFind 清 query/session/highlightEntryID，isPresented=false 收栏 | 无 | 保持 |

### 两缺陷根因

#### 缺陷一：上下跳转闪烁
- **根因**：`performFocusScroll` 用 `setContentOffset(animated: false)`，收敛机制最多重滚6次，每次都是瞬移 → 用户看到画面跳跃闪烁
- **修法**：首次滚动改 `animated: true`（UIScrollView 缓动画0.25s左右），后续收敛微调继续评估（动画后再补滚，或微调幅度≤1pt用户不感知）

#### 缺陷二：强调不对
- **根因**：所有命中词统一用 `Palette.findMatchFill`（淡黄），当前命中只在行级点亮整行底色2.5秒，词级无强弱分档
- **修法**：
  1. 设计系统已定义两档颜色（`findMatchCurrent`/`findMatchOther`，注释明确对齐 Safari 标准）
  2. 着色点（SelectableTextView/MarkdownText）改接收当前/其他两色
  3. 调用链传入当前命中标记：`findController.highlightEntryID == entry.id` 决定整行用哪档
  4. 同一条目内所有命中词用同一档（整行是当前 → 全词强调；整行非当前 → 全词弱）

---

## 二、修改清单

### 修改 1：命中高亮两档（词级强调）

**涉及文件**：
- `Sources/OneDayApp/ChatView+HeaderAndActions.swift`：修 `findHighlightQuery` 返回类型
- `Sources/OneDayApp/ChatView.swift`：修行构造点着色调用
- `Sources/OneDayApp/SelectableTextView.swift`：修 `applyingFindHighlight` 接收两色
- `Sources/OneDayApp/MarkdownText.swift`：修 `findHighlighted` 接收当前标记
- `Sources/OneDayDesign/Palette.swift`：已有两档定义，直接用

**修改步骤**：
1. `findHighlightQuery(for:)` 改返回 `(query: String, isCurrent: Bool)?`，当前命中判定 `entry.id == findController.highlightEntryID`
2. SelectableTextView 改 `applyingFindHighlight(to:query:isCurrent:currentColor:otherColor:)` 五参数，根据 `isCurrent` 选色
3. MarkdownText 同样改接收 `isCurrent` 参数
4. 调用点传入两色：`Palette.findMatchCurrent` 和 `Palette.findMatchOther`

### 修改 2：跳转平滑（消除闪烁）

**涉及文件**：
- `Sources/OneDayApp/ChatNativeList.swift`：修 `performFocusScroll` 滚动动画参数

**修改步骤**：
1. `performFocusScroll` 内 `setContentOffset(_:animated:)` 改 `animated: true`（3872-3874行）
2. `scheduleSettle()` 在首次滚动后立即调度（3875行），但收敛评估不会在动画中触发
3. **证明**：`performSettleBeat` 守卫（3609-3620行）——滚动期（`isDecelerating`）冻结评估，只记账不施工；动画结束后守卫放行，`stepSearchFocus`（3809行）才评估收敛并可能递归再滚
4. 验证：首次滚动带缓动画（约0.25s），收敛微调在动画结束后评估，视觉平滑

---

## 三、验证计划

1. **构建通过**：Mac 通道 `tuist install && tuist generate && xcodebuild build`
2. **功能验证**（需真机/模拟器）：
   - 搜索命中多条时，当前命中词亮黄、其他命中词淡黄，两档分明
   - 点上一个/下一个时画面平滑滚动，不闪烁
   - 收敛机制仍正常工作（目标停在 topGap=12pt 位置）
3. **边界验证**：
   - 单条命中、无命中、跨屏幕命中
   - 切换线程后搜索状态清空

---

## 四、风险与限制

1. **动画时机**：首次滚动改带动画后，若收敛评估在动画进行中触发（contentOffset 仍在变），可能误判需要再滚 → 实测验证，必要时调整评估触发点至 `scrollViewDidEndScrollingAnimation` 专属
2. **托管架构限制**：不使用 UIFindInteraction 原生 API，保留现有判定层 → 与原生行为可能有细微差异，但核心体验对齐
3. **行级粒度**：同一条目内所有命中词用同一档（整行是当前 → 全词强调），不做词级再细分 → 粒度已足够（Messages/Safari 是页面级单一内容，聊天是条目流）

---

## 五、落盘记录

- 分支：`fix/search-flow-20261127`
- 基线：main 尖 `bc7bd5cf`
- Commit 策略：分段提交（强调修复 commit 1，跳转修复 commit 2）
- 已推送：origin/fix/search-flow-20261127

### 提交记录

**Commit 1: 107c9b86** - 修复：搜索命中两档强调（当前/其他）
- 修改文件：
  - `Sources/OneDayApp/ChatView.swift`：用户行传入 `searchIsCurrentMatch` 参数
  - `DELIVERY-SEARCH.md`：交付文档
- 修改内容：
  - 用户行 SelectableInlineText 增补 `searchIsCurrentMatch: entry.id == findController.session.currentMatchID`
  - SelectableTextView（147-149行）和 MarkdownText（325-328行）已实现两档颜色逻辑
  - 当前命中用 `Palette.findMatchCurrent`（浅 #F9D84A），其他用 `findMatchOther`（浅 #FBE38A）

**Commit 2: ca8685af** - 修复：搜索跳转平滑（消除闪烁）
- 修改文件：`Sources/OneDayApp/ChatNativeList.swift`
- 修改内容：`performFocusScroll` 内 `setContentOffset` 改 `animated: true`
- 效果：首次滚动缓动画约0.25s，收敛评估在动画结束后触发，视觉平滑

### 构建验证状态

**待构建**：Mac 通道待就绪时执行 `tuist install && tuist generate && xcodebuild build`。

**代码验证已完成**：
- 两档强调：调用链传参、着色点选色、颜色定义均已落码
- 跳转平滑：首次滚动改 `animated: true`，`performSettleBeat` 守卫确认动画期不评估（`isDecelerating` 冻结）

---

## 六、修改验证清单

### 代码层验证（已完成）

✅ **强调两档**：
- SelectableInlineText 调用点传入 `searchIsCurrentMatch` 参数（ChatView.swift:5417-5419）
- SelectableTextView.presentedAttributed 根据 `searchIsCurrentMatch` 选色（147-149行）
- MarkdownText.findHighlighted 根据 `searchIsCurrentMatch` 选色（325-328行）
- 颜色定义：Palette.findMatchCurrent / findMatchOther 已定义（Palette.swift:706-718）

✅ **跳转平滑**：
- ChatNativeList.performFocusScroll 改 `animated: true`（ChatNativeList.swift:3871）
- 收敛机制保持不变（focusConvergence 在 scrollViewDidEndScrollingAnimation 触发）

### 功能验证（需真机/模拟器）

待构建通过后验证：
1. 搜索多条命中时，当前命中词亮黄（#F9D84A），其他命中词淡黄（#FBE38A）
2. 点上一个/下一个时画面平滑滚动，不再闪烁
3. 收敛机制正常工作（目标停在 topGap=12pt 位置）
4. 切换线程后搜索状态清空

### 风险项

1. **动画时机**：已证明 `performSettleBeat` 守卫（3609-3620行）在滚动期（`isDecelerating`）冻结评估，收敛不会在动画中误判
2. **助手行着色**：MarkdownText 调用点（5871-5873行）已传入两参数，需真机验证代码块内高亮正确

### 测试记录（代码层）

**两档强调**：
- 传参链路：`ChatView.swift:5417` 传入 `searchIsCurrentMatch: entry.id == findController.session.currentMatchID`
- 着色点：`SelectableTextView.swift:147-149` 和 `MarkdownText.swift:325-328` 根据 `searchIsCurrentMatch` 选色
- 颜色定义：`Palette.findMatchCurrent`（#F9D84A）和 `findMatchOther`（#FBE38A）

**跳转平滑**：
- 滚动动画：`ChatNativeList.swift:3872-3874` 改 `animated: true`
- 评估时机：`scheduleSettle()`（3875行）立即调度，但 `performSettleBeat` 守卫（3609-3620行）在 `isDecelerating` 时冻结，动画结束后才放行 `stepSearchFocus`（3809行）评估收敛
- 递归安全：收敛判定 `.scrollAgain` 时递归调用 `performFocusScroll`（3840行），微调继续平滑

**待真机验证**：视觉平滑度、两档高亮分明度、助手行代码块高亮
