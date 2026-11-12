# 症三·底坞浮空定因与修复报告（2026-11-12）

真机量测前账（oneday-design-review/shell-batch2-symptom3-
measurement-20261112.md）：自家浮空 ≈57±2pt；代码层显
式增距＝0pt，多出的距离在容器安全区传播里。本报告以
探针实证落锤并修复。旧记「原生标准带 34–36pt」属于
Platter/布局帧下缘口径，与真机录屏的玻璃视觉下缘不是
同一把尺，自本版起在报告中作废、不再引用，也不再据
此表述超标幅度；真机达标判据见文末双判据。

## 定因（落锤）

**DrawerContainer 经 UIViewControllerRepresentable 进
宿主时，被 SwiftUI 摆进安全区矩形**：容器视图帧被收编
为 (0,59 402×781)（顶 59＋底 34 都被帧偏移吃掉）、其自
身 safeAreaInsets 读数为零。从几何上看，底部 34pt 被
排除在容器帧外，而容器内部的坞盘相对宿主底边仍留
21pt——浮空＝34＋21＝55pt，与真机 57±2 同构（差在量
测误差带内）。这里只能观测到「底 34 在帧外、内部相对
底边仍留 21」这组几何事实；内部为何仍留 21pt、是否可
类比某种布局档位，属于基于几何结果的推断，不是直接
观测。多出的不是常量、不是视觉拉伸，是**底安全区被
帧偏移与内部几何双重消费**。

## 探针数据（同台对照，402×874、窗口安全区覆写 59/34）

探针代码即现行回归套件 Tests/OneDayAppTests/
TabBarFloatTests.swift；数据来源 CI run 43172232850
（探针二轮）＋43173935665（回归轮复测，一致）。

| 组 | 装配 | Platter 帧 | 浮空 | 容器帧 | 容器 viewSafe B | 页底预留 |
|---|---|---|---|---|---|---|
| A | UIHostingController 直装 TabView（对照） | (21,791 360×62) | **21.0** | — | — | 83 |
| B | DrawerContainerController 裸装为根 | (21,791 360×62) | **21.0** | 全屏 | 34 | 83 |
| C | B＋additionalSafeAreaInsets.bottom 34 | (21,757 360×62) | 55.0 | 全屏 | 68 | 83 |
| D | 生产桥链（桥＋TabView 替身） | (21,757 360×62) | **55.0** | (0,59 402×781) | **0** | 83 |
| F | D＋.ignoresSafeArea()（修复落法） | (21,791 360×62) | **21.0** | (0,0 402×874) | 34 | 83 |

读法：B 与 A 同值＝容器本体无罪；C 只证明人为注入
additionalSafeAreaInsets 也能产生同签名结果。C 机制
被排除并不只依赖 D 的帧与读数，还依赖生产源码核账：
生产代码全仓没有 additionalSafeAreaInsets 写入（检索
命中仅本报告、DESIGN 历史记账与测试注释），且
DrawerContainerView.swift:263–305 按容器 bounds 安放
drawerHost、foreground、clipView 与 contentHost，未另
行注入该 inset。D 在真实桥链原样复现 55 且链上读数自
证机制；F 与 A 同值＝修复成立。五组替身页的
pageBottomInset 均为 83，但这只证明探针替身页的局部
预留未随五组装配改变，不能外推为生产顶栏、输入舱或
真实页面落点不受影响；这些仍待生产装配/真机验证。

一轮探针教训（留痕）：裸 UIWindow 在测试宿主下底部
安全区恒 0、四组同值无从分辨；改照胶囊扫描线
StatusBarWindow 口径覆写窗口安全区（59/34）后才进真
机档位。探针文件两轮编译修正（PreferenceKey 并发安
全）无数据含义。

## 修复（最小）

`Sources/OneDayApp/ContentView.swift` 一处：Drawer-
Container 落位加 `.ignoresSafeArea()`（含定因注）。
容器改全屏安放、安全区改走系统传播回页面与底栏。
顶栏与真实输入区在新传播形态下是否保持原落点，目前
只是待验证预期：本探针没有装配生产顶栏或输入舱，五
组替身页 pageBottomInset 恒 83 不能为这两处背书，须
在壳体版真机验收中另看顶栏、键盘起落与输入区落点。
未动：页面背景与边缘效果、胶囊与呈现链、输入舱承载、
§124/§176、抽屉动画与命中、DrawerContainerView.swift
本体。

## 复测（验收）

CI run 43173935665（头 cb0f8af）：Build ✓／Unit
tests ✓（** TEST SUCCEEDED **、0 failures）／
Package ✓／Upload ✓。回归三条全过：
- testContainerDirectRoot_MatchesPlainHost（B＝A）
- testBridgeChain_LegacyPlacement_FloatsOneBottom-
  InsetHigher（缺陷签名：浮空恰高 34、帧 (0,59,·×
  781)、viewSafe B＝0）
- testBridgeChain_ProductionPlacement_MatchesPlain-
  Host（F＝A、帧全屏、viewSafe B＝34、页预留同值）
单测账：OneDayCore 未触碰；OneDayAppTests 净增 3 条
（TabBarFloatTests），未删任何既有测试。

## 复核必修补强（ext-20261112-021）

- 文档口径：本报告与 ContentView.swift 生产注释已按
  复核清单订正 DrawerView 挂法、顶栏/输入区证据边界、
  C 机制的源码核账依据，以及内部 21pt 的推断属性；
  修复本体 `.ignoresSafeArea()` 一行未动。
- 真机口径：已并入 Muse 同机型、同玻璃视觉口径锚点，
  验收改为「相对降幅 34±4pt＋复测落 20–27pt」双判
  据；旧 34–36pt 布局帧口径作废。
- 源码守护：TabBarFloatTests 在原三条之外新增
  `testContentViewDrawerContainerResultDirectlyIgnoresSafeArea`，
  限定 ContentView.body 生产装配点，去注释后核实
  DrawerContainer 结果直挂 `.ignoresSafeArea()`；
  本轮相对补强前单测净增 1、既有测试未删。

## 口径边界与残余风险（复核必读）

1. **真机验收双判据，两者同过才算达标**：
   录屏量的是玻璃视觉下缘、本台量的是 Platter 布局
   帧下缘，且本台是覆写安全区的测试窗，两者口径不
   同。真机复测须同机、同系统版本、聊天页键盘收起，
   并沿用原录屏的定边法（玻璃视觉下缘↔物理屏底）：
   ①修复后同口径浮空相对修前读数下降 **34±4pt**；
   ②同法复测落在 Muse 锚点邻域 **20–27pt**。任一
   不过，本线需重开核口径（可能还有第二层贡献未在
   本台出现）。
   **同条件对照锚点（2026-11-12 15:32 用户补图、主线
   同口径量测）**：Muse App 全屏截图为 1206×2622
   原生分辨率、402×874pt 画布，与症三录屏同机型；
   按玻璃色调消失、与页面底色不可分处定边，Muse
   底坞玻璃下缘 y≈2550±5px（3px/pt），浮空
   **≈23±2pt**，坞玻璃本体高约 69pt；屏幕边缘底色
   252，坞下的 Home Indicator 与极淡阴影带均已排除
   出定边。此前缺位的同条件对照样本就此补齐，修后
   预测 23±2 与该锚点吻合。量测原始图（主线留存）：
   `~/workspace/user/files/2309D4EE-05BD-482D-BB0A-FA80D2B6EE91-photo-1D30B64D-9891-441C-9DB0-F8BF1CFC7CC3.jpg`。
   原「34–36pt 标准带」系布局帧口径，与玻璃口径非
   同一把尺，作废、不再引用。
2. **回归绑定已补本体装配点守护**：除原三条桥链行
   为测试外，现新增一条限定生产装配点的源码守护：
   它只截取 ContentView body 的有限片段、去注释后解
   析 DrawerContainer 调用及其尾随闭包，并核实结果
   后紧接着 `.ignoresSafeArea()`；删除、移位或只在注
   释中保留均判红。它不托管真实 ContentView、不对全
   文件做无限定字符串搜。桥链 harness 本身仍是镜像
   装配，行为层面的同值结论仍由原三条承担。
3. **抽屉开态**：修复后抽屉宿主的安全区环境由「帧
   偏移」变「inset 传播」（顶 59／底 34 真值）。须纠
   正旧述：DrawerView.swift:235 的
   `.ignoresSafeArea(edges: [.top, .bottom])` 只挂在
   background 中的 drawerBackdrop（背景磨砂底）上；
   名单 ScrollView 本体尊重安全区，其底条由
   DrawerView.swift:201–203 的
   `.safeAreaBar(edge: .bottom)` 注册。因此不得以背
   景磨砂底的自理推断名单本体落点等价；壳体版真机
   验收时抽屉顶/底仍须各看一眼。
4. 与症一线（feat/shell-bg-unify）合并对账：本分
   支只动 ContentView.swift 一处修饰符；未动任何页
   面背景/边缘效果，两线在该文件若有交叉由主线串
   行处理。
