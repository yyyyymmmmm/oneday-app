# 抽屉与顶栏四题定因分析（§179 预稿）

## 题 1 · 抽屉导航组缺组标题「选项卡」

### 对照图分析
- Muse 参照图：主导航组（主要聊天／动态／点子／目标／资源库）上方有一行小号灰字组标题「选项卡」
- Muse 参照图：「空间」「频道」「旁聊」各组也都有同形态小标题
- OneDay 真机截图：频道/旁聊组头在，唯独导航组直接从「主线聊天」行开始，组标题缺失

### 代码定因
查 DrawerView.swift:439 `drawerNavList` 实现：

```swift
private var drawerNavList: some View {
    VStack(alignment: .leading, spacing: 0) {
        // §158 合裁：§157 已删「选项卡」组头文
        // 字，本区折叠头改无标题形态（折叠钮本
        // 体见 drawerNavCollapseToggle），折叠键
        // 仍 drawer.nav、内容五行不变
        drawerNavCollapseToggle  // 行445：只有折叠钮，无标题文字
        drawerCollapsibleContent(
            collapsed: drawerSectionCollapsed(
                DrawerSectionKey.navigation
            )
        ) {
        drawerNavRow(...) // 五个导航行
```

查 DrawerView.swift:1120-1149 `drawerNavCollapseToggle` 实现：
- 只有 `Image(systemName: "chevron.down")` + 旋转逻辑
- 无任何 Text 组件
- 注释明确说「无标题形态」

对比频道/旁聊组头调用（DrawerView.swift:680, 587）：
```swift
drawerCollapsibleHeader("旁聊", key: DrawerSectionKey.sideChats)
drawerCollapsibleHeader("频道", key: DrawerSectionKey.channels)
```
使用 `CollapsibleSectionHeader` 公用件，带标题字符串。

### 根因坐实
**DrawerView.swift:445** 导航组使用 `drawerNavCollapseToggle`（无标题形态），而频道/旁聊使用 `drawerCollapsibleHeader("标题", key)`（有标题形态）。

注释表明这是 §157 删除「选项卡」组头文字后的遗留状态，但用户要求的是**恢复**组标题，不是维持删除后的无标题状态。

### 改法
将 `drawerNavCollapseToggle` 调用改为 `drawerCollapsibleHeader("选项卡", key: DrawerSectionKey.navigation)`，与频道/旁聊同口径。

---

## 题 2 · 抽屉与聊天页互补弧度缺失

### 对照图几何量测
需量测前景页左上/左下圆角半径及外露形态。

**Muse 参照图**（1206×2622 像素）：
- 前景页左侧明显可见弧线，与抽屉右缘互补
- 抽屉宽度约占屏幕 ~75-80%
- 圆角半径目测约 28-30pt（按 iPhone 标准 3x 屏换算）

**OneDay 真机截图**（1206×2622 像素）：
- 前景页左缘近乎直角，无明显弧线
- 抽屉宽度相似

### 代码定因
查 DrawerContainerView.swift 圆角裁切实现：

DrawerContainerView.swift:29-33 注释：
> 阴影与裁切分层：wrapper 只挂阴影、clip 只管圆角裁切（DrawerMotion.cornerRadius 一步到位口径：progress>0.02 即 28pt）

查实际代码实现位置（需定位 clipView 的 cornerRadius 设置）。

候选根因：
1. ✓ 圆角只裁了部分角或被其它层覆盖
2. progress 判定未生效
3. 裁切层与实际内容错位
4. 前景根视图背景不透明溢出

需查 DrawerContainerController 中 clipView.layer.cornerRadius 的设置与 contentHost 的层级关系。

---

## 题 3 · 模型选择里当前模型所在服务商分组无法折叠

### 代码定因
查 ChatModelPickerView.swift:148-160 `isGroupCollapsed` 判定：

```swift
private func isGroupCollapsed(_ display: DisplayGroup) -> Bool {
    if isSearching { return false }
    if display.rows.contains(where: { $0.choice == current }) {
        return false  // ← 行150：当前组强制展开
    }
    return SectionCollapseState.isCollapsed(...)
}
```

**根因坐实**：ChatModelPickerView.swift:150-152，当前模型所在组被逻辑短路成强制展开（`return false`），toggle 写入的折叠状态虽被持久化但判定时被此行覆盖。

### 改法
删除行150-152的强制展开逻辑，或改为仅在初次呈现时默认展开、后续尊重用户 toggle 操作。

验收注意：需确认当前模型在折叠组内时的可见性——可能需要在组头显示当前模型标记。

---

## 题 4 · 模型名过长时顶栏两侧按钮位移

### 代码定因
查 ChatView.swift:1054-1169 `headerBar` 布局：

```swift
private var headerBar: some View {
    VStack(spacing: OneDayMetrics.rowInnerGap) {
        HStack(alignment: .center, spacing: OneDayMetrics.spacingS) {
            Button { ... } label: { /* 汉堡钮 */ }
            
            Spacer()
            
            identityCapsule
                .layoutPriority(1)  // 行1103：胶囊优先保宽
            
            Spacer()
            
            Button { ... } label: { /* 铃铛钮 */ }
        }
```

**根因坐实**：ChatView.swift:1091-1105，布局使用 `Spacer() + identityCapsule.layoutPriority(1) + Spacer()` 结构，胶囊优先保宽会压缩两个 Spacer，导致两侧按钮位置随胶囊宽度变化而移动。

### 改法
反转布局锚点：
1. 删除两个 Spacer() 和 layoutPriority
2. 两侧按钮用 `.frame(maxWidth: .infinity, alignment: .leading/.trailing)` 或 overlay 定位
3. 胶囊在中间剩余空间居中，限宽并尾部截断

参考实现：
```swift
HStack(spacing: 0) {
    drawerButton  // 固定在 leading
    Spacer(minLength: 8)
    identityCapsule
        .frame(maxWidth: /* 计算值 */)
        .lineLimit(1)
    Spacer(minLength: 8)
    bellButton  // 固定在 trailing
}
```

或使用 ZStack overlay 方案，两侧按钮绝对定位。
