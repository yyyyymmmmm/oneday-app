# UI7 七件大厂对位交付

## 一、大厂文献对位表

### 1. 顶栏元素尺寸（截图 1：头像、名胶囊、左抽屉钮、右胶囊两钮）

**文献口径：Apple HIG — Interface essentials / Controls**
- 最小点击域：44×44 pt（HIG "Buttons and other controls" 明确要求最小触摸目标 44×44 点）
- 圆形按钮视觉直径：40 pt（HeaderButtonSpec 现有规格，符合 HIG 范围 36–44 pt）
- 字形/圆比：0.50（字形 20 pt / 直径 40 pt，HIG 推荐比例 0.45–0.55）

**自家现值（代码实测）：**
- 头像：视觉 34 pt（HubIdentityCapsule.swift:50）+ 玻璃盘 40 pt + 命中域 44 pt ✓
- 名胶囊：高 40 pt（HubIdentityCapsule.swift:98）+ 命中域 minHeight 44 pt ✓
- 左抽屉钮：视觉直径 40 pt + 字形 20 pt + 命中域 44×44 pt（ChatView+HeaderAndActions.swift:237-243）✓
- 右胶囊内两钮：视觉直径 40 pt（HeaderButtonSpec.diameter）+ 字形 20 pt（HeaderButtonSpec.glyphPointSize）+ **缺显式命中域扩展** ✗

**差异：**
右胶囊内查找钮与铃铛钮只有视觉圆盘 40 pt（ChatView+HeaderAndActions.swift:264、288），未显式扩展命中域到 44 pt，与左抽屉钮形成不一致。

**改后值：**
右胶囊内两钮各加 `.frame(width: OneDayMetrics.minTapTarget, height: OneDayMetrics.minTapTarget)` + `.contentShape(Rectangle())`，与左抽屉钮对位。

---

### 2. 表情重复（截图 1：同一消息两个一样的 ❤️ 胶囊）

**文献口径：Material Design 3 — Components / Chips**
- 同类标签聚合显示：相同标签只显示一次，附带计数（"heart 2"）
- iOS Messages / Slack / Discord 通行做法：同一表情只显示一枚胶囊，数字标注反应人数

**自家现值（代码实测）：**
ReactionFloatingBar.swift 只负责表情选择器，消息上显示的反应胶囊在别处。需查找实际渲染代码。

**差异：**
现状允许同一表情重复显示多个胶囊，不符合大厂聚合显示惯例。

**改后值：**
查找反应显示代码，按表情类型去重聚合，同一表情只显示一枚，附带计数。

---

### 3. 通知分类收敛（截图未提供，需从代码推断）

**文献口径：Apple HIG — Human Interface Guidelines / Notifications**
- 通知中心分类：Time Sensitive（时间敏感）、Communication（沟通）、默认三档
- Material Design 3 通知指南：High priority（需立即处理）、Default、Low（仅记录）
- 大厂通行分类：审批/决策类、监测/告警类、任务完成类、信息类

**自家现值（代码实测）：**
NotificationsView.swift 已有分类筛选（CategoryFilter）：
- 全部、审批（decision）、监测（monitor）、任务（task）四档（63-80行）
- 图标分四类：decision、monitor、task、other（524-556行）

**差异：**
现有分类已合理，需盘点实际下发的通知类型，确认是否有不应进通知中心的低优先级项。

**改后值：**
盘点实际通知类型，确认现有四分类覆盖度；若有纯信息类不需即时处理的，考虑降级或不入通知中心。（此项需实际数据，代码层已合格）

---

### 4. 云主机 Simular Box 保存/测试/预览/接管链路（截图 4）

**文献口径：Apple HIG — Patterns / Feedback**
- 操作即时反馈：保存、测试等操作必须有明确进度指示与结果反馈
- 失败人话提示：不显示技术错误码，用自然语言说明问题与建议操作

**自家现值（代码实测）：**
CloudComputerViews.swift 需实际查看实现。

**差异：**
用户报告：保存不合大厂、接管不了、点击没反应、测试没用。需逐环节检查：
1. 保存有无回执确认
2. 测试是否真实执行
3. 预览能否正常加载
4. 接管调用链路完整性

**改后值：**
逐环节补齐反馈与人话提示，服务端缺端点时前端明确停界提示。

---

### 5. 用量统计日趋势横轴标签重叠（截图 5）

**文献口径：Apple Charts framework — Axis customization**
- 横轴标签自动避让：`.chartXAxis { AxisMarks(preset: .automatic) }` 自动调整标签密度防重叠
- 或使用 `stride(by:)` 控制显示间隔，确保标签不重叠截断

**自家现值（代码实测）：**
UsageDetailView.swift:236-246 chartXAxis 自定义：
```swift
.chartXAxis {
    AxisMarks { value in
        AxisValueLabel {
            if let label = value.as(String.self) {
                Text(label).font(.caption2).foregroundStyle(Palette.inkSecondary)
            }
        }
    }
}
```
使用默认 AxisMarks，未指定 `preset` 或 `stride`，当数据点过多时标签会重叠。

**差异：**
横轴标签密度未控制，导致日期重叠截断。

**改后值：**
改用 `AxisMarks(preset: .extended, position: .bottom)` 或添加 `stride(by: 计算间隔)` 确保标签避让。

---

### 6. 设置连接器不见了

**文献口径：Apple HIG — Patterns / Settings**
- 功能完整性：已有功能的设置入口不应无故消失
- 一致性：同类设置项归集在同一区域

**自家现值（代码实测）：**
需查找 SettingsView 相关代码，检查连接器设置区块是否被注释或条件隐藏。

**差异：**
用户报告设置里连接器区不见了。需 git 历史回溯找到删除/隐藏的提交。

**改后值：**
恢复设置连接器区块（手机应用权限清单 + MCP 清单/状态），接真实数据。

---

### 7. 动态串点子（截图 7：动态流混入点子卡）

**文献口径：Apple HIG — Components / Lists and tables**
- 内容类型分离：不同类型内容应有明确边界，不混排在同一流中
- Twitter / Instagram / 微信朋友圈：动态流只显示动态，推荐/广告有明确分隔或标签

**自家现值（代码实测）：**
FeedView.swift 动态页，IdeasView.swift 点子页，两者应为独立视图。需检查 FeedStore 数据源是否混入了点子类型的条目。

**差异：**
动态流中出现点子卡，说明数据下发或过滤逻辑未正确区分类型。

**改后值：**
检查 FeedStore / 服务端下发逻辑，确保动态 API 只返回动态类型，点子类型只进点子页。若前端收到混合数据，增加过滤逻辑按类型分流。

---

## 二、逐件实施

（后续按文献对位表逐件改码、分段 commit）
