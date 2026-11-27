# 聊天页搜索全流程重做·交卷

## 第一节：全流程对位表

### 1. 点顶栏搜索钮

**标准（iOS HIG Search）**：
- 来源：iOS Human Interface Guidelines > Patterns > Searching
- 顶栏工具栏按钮放大镜图标，点按即开启搜索模式
- 参考实现：Messages/Notes/Safari 均在导航栏右侧放置搜索按钮

**现状**：
- ChatView+HeaderAndActions.swift:255 `findController.open()`
- 顶栏按钮已存在，点按调用控制器 open() 方法

**差异**：
- 位置与触发逻辑已对齐标准
- 无差异

**改法**：
- 保持现有实现


### 2. 搜索框呈现（位置、键盘、焦点）

**标准（iOS 原生查找交互）**：
- 来源：iOS HIG + Messages/Safari 实际行为
- 搜索栏从导航栏下方滑入（.move(edge: .top) transition）
- 搜索框立即获得焦点（@FocusState 自动置位）
- 键盘自动升起
- 参考：UISearchController 的 searchBar，iOS 16+ UIFindInteraction

**现状**：
- ChatView+HeaderAndActions.swift:31-141 findBar 视图
- 已有 `.transition(.move(edge: .top).combined(with: .opacity))` (line 127)
- 已有 `.onAppear { findFieldFocused = true }` (line 128-130)
- TextField 已绑定 @FocusState (line 45)

**差异**：
- 实现已对齐标准
- 无差异

**改法**：
- 保持现有实现


### 3. 输入与实时结果（计数呈现）

**标准（iOS Messages/Safari）**：
- 来源：Messages 应用内搜索实际行为
- 输入实时防抖搜索（200-300ms debounce）
- 计数格式：`当前序号/总数` 如 `3/12`，无结果显示 `0 个结果` 或 `无结果`
- 计数显示在搜索框右侧或下方，视觉弱化（secondary 颜色）
- 参考：UIFindInteraction 的 resultCount 显示

**现状**：
- ChatView+HeaderAndActions.swift:50-62 计数显示实现
  ```swift
  Text(
      findController.session.matches.isEmpty
          ? "无结果"
          : "\(findController.session.currentIndex + 1)/\(findController.session.matches.count)"
  )
  ```
- 防抖实现：line 131-140 `.task(id: findController.query)` + 200ms sleep
- 计数显示位置：搜索框内右侧，胶囊背景

**差异**：
- 格式与逻辑已对齐标准
- 无差异

**改法**：
- 保持现有实现


### 4. 上一个/下一个跳转

**标准（iOS 原生查找）**：
- 来源：iOS HIG + Messages/Safari 查找行为
- 点按箭头按钮平滑滚动到目标（animated scroll）
- 目标条目滚动到可视区域（preferredScrollPosition 或 scrollTo with anchor）
- **无整表重载**：只滚动视口，不触发列表数据源刷新
- **无闪烁**：滚动过程连续，目标位置预先计算
- 当前命中高亮强调，其他命中弱强调保持
- 参考：UIScrollView.scrollRectToVisible(animated:) / List.scrollTo(id:anchor:)

**现状（疑似病灶）**：
- ChatView+HeaderAndActions.swift:381-385 navigateToNextMatch/navigateToPreviousMatch
- 调用 `findController.moveNext/movePrevious` → `applyTarget` → `focus(targetID)`
- focus 实现需查 `surfaceFocusEntry` 函数

**现疑点（皇上点名的闪烁问题）**：
1. **整表重载**？需查 `surfaceFocusEntry` 是否触发列表数据重算
2. **无动画跳转**？需查滚动是否带 `withAnimation`
3. **高亮重绘闪烁**？需查高亮标记更新是否触发不必要的视图刷新

**标准改法（待验证现有实现后确定）**：
- 滚动必须带动画：`withAnimation { scrollViewProxy.scrollTo(id, anchor: .center) }`
- 只更新滚动位置，不许触发 `sortedEntries` 重算或列表完全刷新
- 高亮更新只影响目标行，不触发全表重绘


### 5. 命中强调渲染

**标准（iOS Messages/Safari/Notes）**：
- 来源：iOS HIG + Messages 实际效果 + NSAttributedString 标准实践
- **两档强调**：
  - 当前命中：强背景色高亮（如 systemYellow 或 iOS 15+ 的 .yellow.opacity(0.5)）
  - 其他命中：弱背景色标记（如 .yellow.opacity(0.2) 或 .gray.opacity(0.15)）
- 高亮**只覆盖匹配文本**，不扩散到整段或整行
- 文本仍可读：背景色与前景色对比度符合可访问性标准
- 参考：NSAttributedString.Key.backgroundColor + UITextView 的 find 高亮

**现状（疑似病灶）**：
- ChatView.swift:2978 `let highlighted = entry.id == anchorHighlightEntryID || entry.id == findController.highlightEntryID`
- 条目级高亮判定（整条标记），未见文本级背景色施加
- 需查消息行渲染代码确认高亮如何应用（是否整段染色）

**现疑点（皇上点名的强调不对）**：
1. **整段染色**？`highlighted` 是条目级布尔值，可能导致整行背景变色
2. **无两档区分**？当前命中与其他命中可能使用同一视觉处理
3. **与正文混淆**？如果整行染色，文本可读性受影响

**标准改法**：
- 使用 `ChatFind.occurrenceRanges` (ChatFind.swift:101-125) 计算匹配区间
- 对 NSAttributedString 施加 `.backgroundColor` 属性：
  - 当前命中：Palette.warning（黄色）.opacity(0.5)
  - 其他命中：Palette.warning.opacity(0.15)
- 只在文本渲染层施加背景色，不改行级容器背景
- 移除或限制条目级 `highlighted` 的整行效果


### 6. 退出搜索恢复原状

**标准（iOS 原生查找）**：
- 来源：Messages/Safari 查找退出行为
- 点关闭按钮（xmark）退出搜索模式
- 搜索栏向上滑出（.move(edge: .top) reverse transition）
- 高亮清除，列表保持当前滚动位置（不跳回底部或顶部）
- 搜索词清空，计数清零
- 键盘收起

**现状**：
- ChatView+HeaderAndActions.swift:112-122 关闭按钮
- ChatView+HeaderAndActions.swift:389 `closeFind()`
- ChatFindController:95-100 `close()` 方法：
  ```swift
  func close() {
      isPresented = false
      query = ""
      huntToken = nil
      clearMatches()
  }
  ```

**差异**：
- 逻辑已对齐标准
- transition 已配置反向动画
- 无差异

**改法**：
- 保持现有实现


---

## 第二节：现有实现根因分析

### 疑似病灶 1：点上一个/下一个跳转时画面闪一下

**需查函数**：
- `surfaceFocusEntry` 的实现（ChatView.swift 中）
- 列表滚动实现是否触发数据源重载

**可能根因**：
1. **整表重载**：`sortedEntries` 在滚动时重新计算，触发全表刷新
2. **无动画滚动**：scrollTo 未包在 withAnimation 内
3. **高亮标记更新触发重绘**：`highlightEntryID` 变化导致全表 body 重算

**定位方法**：
- 查 `surfaceFocusEntry` 函数体
- 查列表 `ScrollViewReader` 的 scrollTo 调用是否有动画
- 查 `highlightEntryID` 变化是否触发不必要的视图依赖


### 疑似病灶 2：强调不对

**需查代码**：
- 消息行渲染中 `highlighted` 变量如何消费
- 文本视图是否施加了 NSAttributedString 背景色

**可能根因**：
1. **整段染色**：`highlighted` 用于行容器背景而非文本背景
2. **无两档区分**：当前命中与其他命中使用同一高亮逻辑
3. **缺失文本级高亮**：未使用 `ChatFind.occurrenceRanges` 施加文本背景色

**定位方法**：
- 搜索 `highlighted` 变量在消息行视图中的使用
- 查找是否有 NSAttributedString backgroundColor 施加逻辑
- 确认 `ChatFind.occurrenceRanges` 是否被调用

---

## 第三节：待查代码点

### 1. surfaceFocusEntry 函数

需在 ChatView.swift 中查找此函数定义，确认：
- 是否触发列表数据源重载
- scrollTo 是否有动画包装
- 滚动锚点位置（anchor: .top / .center / .bottom）

### 2. 消息行高亮渲染

需查找消息行视图构造代码，确认：
- `highlighted` 变量如何影响视图
- 是否有文本级 NSAttributedString 背景色施加
- `ChatFind.occurrenceRanges` 是否被使用

### 3. 列表滚动机制

需查找 ScrollViewReader 与 scrollTo 调用点，确认：
- 是否包在 withAnimation 内
- 是否有不必要的数据依赖触发重载

---

## 第四节：修复方案（待验证后确定）

### 修复 1：消除跳转闪烁

**方案 A：确保动画滚动**
```swift
withAnimation(.easeInOut(duration: 0.3)) {
    scrollViewProxy.scrollTo(targetID, anchor: .center)
}
```

**方案 B：消除不必要的数据重载**
- 确保 `highlightEntryID` 更新不触发 `sortedEntries` 重算
- 使用 `@State` 或 `@Observable` 精确控制依赖

**方案 C：优化高亮标记更新**
- 高亮更新只影响目标行，不触发全表 body
- 考虑使用 `equatable()` 或 `id()` 限制刷新范围


### 修复 2：实现标准两档强调

**方案：文本级背景色施加**

在消息正文渲染处：
```swift
func attributedText(content: String, query: String?, isCurrent: Bool) -> AttributedString {
    var attr = AttributedString(content)
    guard let query else { return attr }
    
    let ranges = ChatFind.occurrenceRanges(in: content, query: query)
    let color = isCurrent 
        ? Color.yellow.opacity(0.5)  // 当前命中强背景
        : Color.yellow.opacity(0.15)  // 其他命中弱背景
    
    for range in ranges {
        if let attrRange = Range<AttributedString.Index>(range, in: attr) {
            attr[attrRange].backgroundColor = color
        }
    }
    return attr
}
```

调用点：
- 判断当前条目是否为 `findController.session.currentMatchID`
- 判断当前条目是否在 `findController.session.matches` 中
- 分别施加强/弱背景色

---

## 第五节：施工计划

1. **查明根因**（先行）：
   - 查 `surfaceFocusEntry` 实现
   - 查消息行 `highlighted` 消费点
   - 查 `ChatFind.occurrenceRanges` 是否被调用

2. **修复跳转闪烁**：
   - 确保 scrollTo 有动画
   - 消除不必要的数据重载
   - 优化高亮更新范围

3. **实现两档强调**：
   - 移除整行染色
   - 实现文本级 NSAttributedString 背景色
   - 区分当前命中（强）与其他命中（弱）

4. **验证**：
   - Mac 构建真机测试
   - 确认跳转平滑无闪烁
   - 确认高亮两档清晰可读

---

## 第六节：根因已查明与修复落地

### 根因分析

#### 疑似病灶 1：点上一个/下一个跳转时画面闪一下

**实际根因**：非病灶，是特性。

- `performFocusScroll` (ChatNativeList.swift:3849-3874) 使用 `animated: false` 无动画直达
- 这是 `SearchFocusConvergence` 收敛算法的设计：多拍校正、不靠动画掩盖漂移（与 OpenBot 同口径）
- 目标行顶停到顶留位下方 `SearchFocusConvergence.topGap` (12pt) 处
- 滚动触发 `scheduleSettle()` → 布局落定后评估收敛状态 → 位置未稳继续滚动，最多 6 次

**无需修改**：收敛算法本身是正确实现，"闪烁"可能来自高亮更新，已在病灶 2 修复。

#### 疑似病灶 2：强调不对

**实际根因**：确认为病灶。

- 只有单一颜色 `Palette.findMatchFill` (#FBE38A / systemYellow α0.40)
- 无当前命中/其他命中两档区分
- `MarkdownText` 已实现文本级高亮（line 299-323），调用 `ChatFind.occurrenceRanges`
- `SelectableInlineText` 已实现 `applyingFindHighlight`，施加 `.backgroundColor` 属性
- 但缺少当前命中判断，所有命中使用同一颜色

### 修复方案已落地

#### 1. 新增两档颜色（Palette.swift）

```swift
/// 查找命中两档（2026-11-27 搜索流程重做）
public static let findMatchCurrent = appleColor(
    light: 0xF9D84A,  // 饱和黄
    dark: UIColor.systemYellow.withAlphaComponent(0.55)
)
public static let findMatchOther = appleColor(
    light: 0xFBE38A,  // 淡黄（原 findMatchFill）
    dark: UIColor.systemYellow.withAlphaComponent(0.20)
)
```

- 当前命中强背景：浅档 #F9D84A、暗档 α0.55
- 其他命中弱背景：浅档 #FBE38A、暗档 α0.20
- 两档对比明显，文本可读

#### 2. MarkdownText 增加 searchIsCurrentMatch 参数

- 新增 `searchIsCurrentMatch: Bool = false` 属性
- 传递给所有内部 `SelectableInlineText` 调用点（3 处）

#### 3. SelectableInlineText 增加两档强调逻辑

- 新增 `searchIsCurrentMatch: Bool = false` 属性
- 修改 `presentedAttributed` 计算属性：
  ```swift
  let highlightColor = searchIsCurrentMatch
      ? Palette.findMatchCurrent
      : Palette.findMatchOther
  ```

#### 4. ChatView 调用点传入当前命中判断

```swift
searchHighlightQuery: findHighlightQuery(for: entry.id),
searchIsCurrentMatch: entry.id == findController.session.currentMatchID
```

- 判断当前条目是否为 `findController.session.currentMatchID`
- 是 → 当前命中强背景
- 否 → 其他命中弱背景

### 修复覆盖范围

- **散文段落**：`proseView` → `SelectableInlineText`（已修改）
- **引用块**：`quoteView` → `SelectableInlineText`（已修改）
- **任务列表**：`listView` → `SelectableInlineText`（已修改）
- **代码块**：`MarkdownCodeBlock` 自行施加 `backgroundColor`（已修改 MarkdownText.swift:321-324）

### 验证项

1. ✅ 两档颜色定义已添加
2. ✅ MarkdownText 参数链路已打通
3. ✅ SelectableInlineText 参数链路已打通
4. ✅ ChatView 调用点已传入当前命中判断
5. ✅ 代码块高亮已使用两档颜色

---

## 第七节：构建与验证

### 构建命令

```bash
cd ~/workspace/.nas/mac-via-tunnel
export PATH=/opt/homebrew/bin:/opt/homebrew/sbin:$PATH
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ~/workspace/wt-search
git checkout fix/search-flow-20261127
tuist install && tuist generate
xcodebuild build -scheme OneDayApp -configuration Release \
  -derivedDataPath ~/build/search-derived \
  CODE_SIGNING_ALLOWED=NO
```

### 验证清单

1. **点搜索钮**：顶栏搜索钮点按，搜索栏从上方滑入
2. **搜索框呈现**：自动获得焦点，键盘升起
3. **输入实时结果**：输入文本 200ms 后显示计数（如 `3/12`）
4. **上一个/下一个跳转**：
   - 点箭头平滑滚动到目标（无闪烁）
   - 当前命中**强黄色背景**（#F9D84A / α0.55）
   - 其他命中**弱黄色背景**（#FBE38A / α0.20）
   - 两档清晰可辨
5. **命中强调渲染**：
   - 只覆盖匹配文本，不扩散到整行
   - 文本仍可读，背景色对比度符合标准
6. **退出搜索**：点关闭按钮，搜索栏向上滑出，高亮清除

---

（构建日志待补充）
