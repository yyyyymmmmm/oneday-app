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

DrawerContainer 容器根色未改（DrawerContainerView.swift:231 保留 Palette.pageBG，作抽屉 thinMaterial 向下采样底、与页面底同值；五页背景全出血后页面自己是最后一层画者、容器色不再参与页面静止视觉）。

### 第二步：内容真的流到栏下

| 页面 | 顶部能否流到栏下 | 底部能否流到栏下 | 原因/结构 |
|------|----------------|----------------|----------|
| ChatView | ✓ 能 | ✓ 能 | 顶栏用 `.safeAreaBar(edge: .top)`，底部用 `.safeAreaBar(edge: .bottom)`，滚动内容从栏下穿过 |
| FeedView | ✓ 能 | ✓ 能 | List 结构，系统自动处理安全区，内容可滚到导航栏下和底栏下 |
| IdeasView | ✓ 能 | ✓ 能 | List 结构，系统自动处理安全区，内容可滚到导航栏下和底栏下 |
| GoalsView | ✓ 能 | ✓ 能 | ScrollView 结构，系统自动处理安全区，内容可滚到导航栏下和底栏下 |
| DeliverablesView | ✓ 能 | ? 存疑 | 根为 VStack（头部＋分段＋滚动面），滚动面帧可能止于安全区、内容未必能流到坞下——结构探针验证中（ShellBgStructureProbeTests） |

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

| 页面 | 顶缘 | 底缘 | 落点行号 | 修订说明 |
|------|------|------|---------|---------|
| ChatView | `.soft` (已有) | `.hidden` (§170) | 1888, 1918 | 顶缘已是 `.soft`，底缘已是 `.hidden`（§170 输入舱布局流定版、不属于流动边缘），本包不动 |
| FeedView | (无单独设置) | `.soft` (§185) | 250 | 底缘改 `.soft`（内容可流到坞下、.hard 本身制造色带，见裁决第四节） |
| IdeasView | (无单独设置) | `.soft` (§185) | 175 | 底缘改 `.soft`（同上） |
| GoalsView | (无单独设置) | `.soft` (§185) | 160, 197 | 两个 ScrollView 底缘均改 `.soft`（同上） |
| DeliverablesView | (无单独设置) | `.soft` (§185) | 606, 753, 961, 1000 | 四个滚动面底缘均改 `.soft`（同上） |

**边缘口径修订说明**：

- ChatView 顶缘 `.soft` 与底缘 `.hidden` 均为 §170 用户亲定的定版口径，本包不修改
- 其他四页底缘按 solidband 裁决第四节改为 `.soft`：流动边缘用 `.soft`，`.hard` 官方定义为近乎不透明、本身制造色带感
- 每处代码已同步追加 §185 注释：保留 §170 历史一句，补一句裁决依据

## 禁区遵守检查

✓ IdentityCapsuleView 与胶囊呈现链：未触碰  
✓ DrawerContainer 全部：未触碰  
✓ 输入舱承载、§124 回底钮承载、§176 间距数值：未触碰  
✓ 版本号五处、本地化词条文件结构：未触碰

## 交付物状态

- [x] 代码修改：8 处底缘 .hard → .soft，同步注释
- [x] 结构探针测试：ShellBgStructureProbeTests.swift 已建，待 CI 日志裁决
- [ ] 自查表订正：已更新第一、二、四步实况
- [ ] DESIGN-V4.md 追加 §185.1 补记
- [ ] git commit
- [ ] 最终回报

## 验收终判（接管监工，2026-11-12，CI 实证）

- CI：run 43169634904（b8a362b 基线）success；run 43170888445（484d291）红——探针 measure 收参形态编译错、与生产改动无关；run 43171924228（7812328）**全步 success**（Build／Unit tests／Package／Upload 逐项），两套件 passed、0 失败。
- 结构探针实测（窗高 852，宿主 additionalSafeAreaInsets top=59/bottom=83）：
  - A（ScrollView 根）：frame 0→852、adjInset 113/83——全幅延伸、内容可流到两栏下。
  - C（List 根）：frame 0→852、adjInset 113/83——同上。
  - B（VStack＋ScrollView，文件页形态）：内层 ScrollView frameTop=217（头部 60＋分段 44＋顶 inset 113）、**frameBottom=852、adjInsetBottom=83**——帧直达窗底、坞 inset 以内容 inset 形式到达，内容可滚到坞下。原「VStack 阻断」存疑**证伪**。
- 步骤二终判：五页底缘结构成立（动态/点子＝C 式、目标＝A 式、文件＝B 式）；聊天页顶走 §28 safeAreaBar 机制（滚动内容从条下穿过被边缘效果化开）＋步骤一背景全出血，合判落实。探针留仓作回归取证件。
- 步骤四终判：四页底缘 8 处 .hard→.soft 已落码（484d291）并验计数 1/1/2/4、.hard 底缘全仓 0；ChatView 顶 .soft 原已达标、底 hidden 为 §170 输入舱布局流定版，不在流动边缘之列，不动。
- 过程留痕：Claude 两轮施工未实落代码（二轮误入主 worktree 在旧基线提交 720606d，已回滚主 worktree 至 8ac6193 并弃用该提交），代码由接管监工落码（484d291）、探针由监工按 XCTest 宿主形态重写。
