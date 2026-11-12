# 症三·底坞浮空定因与修复报告（2026-11-12）

真机量测前账（oneday-design-review/shell-batch2-symptom3-
measurement-20261112.md）：自家浮空 ≈57±2pt、原生标准带
34–36pt、真多出约 +20pt；代码层显式增距＝0pt，多出的距
离在容器安全区传播里。本报告以探针实证落锤并修复。

## 定因（落锤）

**DrawerContainer 经 UIViewControllerRepresentable 进
宿主时，被 SwiftUI 摆进安全区矩形**：容器视图帧被收编
为 (0,59 402×781)（顶 59＋底 34 都被帧偏移吃掉）、其自
身 safeAreaInsets 读数为零。内容宿主里的 TabView 因此
按「无 Home Indicator」档布局：坞盘停在宿主底边上方
21pt，而宿主底边本身距物理屏底还有 34pt——浮空＝34＋
21＝55pt，与真机 57±2 同构（差在量测误差带内）。多出
的不是常量、不是视觉拉伸，是**底安全区被帧偏移与坞布
局双重消费**。

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

读法：B 与 A 同值＝容器本体无罪；C 证明 additional
双计是另一条同签名机制（非生产链，D 的帧与读数已排
除它）；D 在真实桥链原样复现 55 且链上读数自证机制；
F 与 A 同值＝修复成立。五组页底预留恒 83（TabView 坞
区预留不随本修复变，§124 回底钮与输入舱的页面几何
不受影响）。

一轮探针教训（留痕）：裸 UIWindow 在测试宿主下底部
安全区恒 0、四组同值无从分辨；改照胶囊扫描线
StatusBarWindow 口径覆写窗口安全区（59/34）后才进真
机档位。探针文件两轮编译修正（PreferenceKey 并发安
全）无数据含义。

## 修复（最小）

`Sources/OneDayApp/ContentView.swift` 一处：Drawer-
Container 落位加 `.ignoresSafeArea()`（含定因注）。
容器改全屏安放、安全区改走系统传播回页面与底栏；
顶栏同理（帧偏移与 inset 传播对页面落点等价，探针
D→F 页面侧读数不变可佐证）。未动：页面背景与边缘效
果、胶囊与呈现链、输入舱承载、§124/§176、抽屉动画
与命中、DrawerContainerView.swift 本体。

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

## 口径边界与残余风险（复核必读）

1. **本台对照值 21 与会诊「标准带 34–36」对不上**：
   录屏量的是玻璃视觉下缘、本台量的是 Platter 布局
   帧下缘，且本台是覆写安全区的测试窗。修复判据是
   「消除被复现的 +34 双计、与同台对照同值」；真机
   复测是最终验收——预期录屏口径回落约 34pt（57→
   ≈23±2）。若真机读数与此预期明显不符，本线需重
   开核口径（可能还有第二层贡献未在本台出现）。
2. **回归绑定是镜像不是本体**：测试的 production-
   Placement 标志镜像 ContentView 的 .ignoresSafe-
   Area()；若有人删掉 ContentView 那一行，测试不会
   变红（装配 harness 与生产 ContentView 是两份装
   配）。本线按最小改动未加源码级守护，是否补由复
   核裁量。
3. **抽屉开态**：修复后抽屉宿主的安全区环境由「帧
   偏移」变「inset 传播」（顶 59／底 34 真值）。
   DrawerView 名单本体已 .ignoresSafeArea(.top/
   .bottom) 自理、底条走 safeAreaBar 注册，预期落
   点等价；壳体版真机验收时抽屉顶/底各看一眼。
4. 与症一线（feat/shell-bg-unify）合并对账：本分
   支只动 ContentView.swift 一处修饰符；未动任何页
   面背景/边缘效果，两线在该文件若有交叉由主线串
   行处理。
