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
1. `performFocusScroll` 内 `setContentOffset(_:animated:)` 改 `animated: true`
2. 收敛评估时机已在 `scrollViewDidEndScrollingAnimation` 和 `attemptSettleIfNeeded`，机制无需改
3. 验证：动画进行中 contentOffset 在变，evaluate 仍在动画结束后触发，收敛判定不受影响

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
- 构建验证：Mac worktree `~/workspace/.nas/mac-via-tunnel`
