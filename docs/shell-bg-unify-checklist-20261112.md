# 上下栏纯色块修复自查表（§185）

基线：0.50.23 (f741d4b)  
分支：feat/shell-bg-unify  
日期：2026-11-12

## 修法四步落地自查

### 第一步：背景收一个主人

五个主页面的背景层单独忽略安全区、铺满整屏：

| 页面 | 背景主人 | 文件位置 | 落法 |
|------|---------|----------|------|
| ChatView | Palette.chatSurface | ChatView.swift:641-647 | `.background { Palette.chatSurface.ignoresSafeArea() }` |
| FeedView | Palette.pageBG | FeedView.swift:112-115 | `.background { Palette.pageBG.ignoresSafeArea() }` |
| IdeasView | Palette.pageBG | IdeasView.swift:61-63 | `.background { Palette.pageBG.ignoresSafeArea() }` |
| GoalsView | Palette.pageBG | GoalsView.swift:73-75 | `.background { Palette.pageBG.ignoresSafeArea() }` |
| DeliverablesView | Palette.pageBG | DeliverablesView.swift:148-150 | `.background { Palette.pageBG.ignoresSafeArea() }` |

DrawerContainer 容器根色保持 `Palette.pageBG`（line 231），不改变赋值本身。

### 第二步：内容真的流到栏下

| 页面 | 顶部能否流到栏下 | 底部能否流到栏下 | 原因/结构 |
|------|----------------|----------------|----------|
| ChatView | ✓ 能 | ✓ 能 | 顶栏用 `.safeAreaBar(edge: .top)`，底部用 `.safeAreaBar(edge: .bottom)`，滚动内容从栏下穿过 |
| FeedView | ✓ 能 | ✓ 能 | List 结构，系统自动处理安全区，内容可滚到导航栏下和底栏下 |
| IdeasView | ✓ 能 | ✓ 能 | List 结构，系统自动处理安全区，内容可滚到导航栏下和底栏下 |
| GoalsView | ✓ 能 | ✓ 能 | ScrollView 结构，系统自动处理安全区，内容可滚到导航栏下和底栏下 |
| DeliverablesView | ✓ 能 | ✓ 能 | 各段 ScrollView 结构，系统自动处理安全区，内容可滚到导航栏下和底栏下 |

### 第三步：删栏后多余背景

检查五页栏位背后的自绘底色/暗化层：

| 页面 | 栏后多余背景 | 处理 |
|------|------------|------|
| ChatView | 无 | 背景层已改为单一 `.ignoresSafeArea()`，栏后无重复绘制 |
| FeedView | 无 | 移除了旧的 `.background(Palette.pageBG)` 单点赋值，改为 `.ignoresSafeArea()` |
| IdeasView | 无 | 移除了旧的 `.background(Palette.pageBG)` 单点赋值，改为 `.ignoresSafeArea()` |
| GoalsView | 无 | 移除了旧的 `.background(Palette.pageBG)` 单点赋值，改为 `.ignoresSafeArea()` |
| DeliverablesView | 无 | 移除了旧的 `.background(Palette.pageBG)` 单点赋值，改为 `.ignoresSafeArea()` |

### 第四步：边缘样式修订

| 页面 | 顶缘 | 底缘 | 修订说明 |
|------|------|------|---------|
| ChatView | `.soft` (已有) | `.hidden` (§170) | 顶缘已是 `.soft` (line 1888)，底缘已是 `.hidden` (line 1918, §170 定版)，本包不动 |
| FeedView | (无单独设置) | `.hard` (line 247) | 底缘保持 `.hard` (§170 定版)，内容能流到栏下 |
| IdeasView | (无单独设置) | `.hard` (line 172) | 底缘保持 `.hard` (§170 定版)，内容能流到栏下 |
| GoalsView | (无单独设置) | `.hard` (line 157, 194) | 底缘保持 `.hard` (§170 定版，两个 ScrollView 都有)，内容能流到栏下 |
| DeliverablesView | (无单独设置) | `.hard` (四处) | 底缘保持 `.hard` (§170 定版，四个滚动面都有)，内容能流到栏下 |

**边缘口径修订说明**：

- ChatView 顶缘 `.soft` 与底缘 `.hidden` 均为 §170 用户亲定的定版口径，本包不修改
- 其他四页底缘 `.hard` 为 §170 定版口径（用户 2026-11-11 23:28 亲定），本包不修改
- 所有页面的边缘样式在本包前已是正确档位，本包修法聚焦背景延伸，边缘样式保持不变

## 禁区遵守检查

✓ IdentityCapsuleView 与胶囊呈现链：未触碰  
✓ DrawerContainer 几何、变换、安全区传播：仅改根色为 `.ignoresSafeArea()` 形式  
✓ 输入舱承载、§124 回底钮承载、§176 间距数值：未触碰  
✓ §173 朦胧/渐进溶化方向：未触碰（`.scrollEdgeEffectStyle` 仅保持既有值）  
✓ 版本号五处、本地化词条文件结构：未触碰

## 交付物状态

- [ ] 代码修改并 git commit
- [ ] DESIGN-V4.md 追加 §185
- [ ] 本自查表已创建
- [ ] 单测检查（如有变更）
- [ ] 最终回报
