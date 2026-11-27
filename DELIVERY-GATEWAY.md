# 网关状态页设计审计报告

## 一、审计对位表

### 1. 信息架构与层级

| 审计项 | 截图现状 | 标准与出处 | 档位 | 说明 |
|--------|---------|-----------|------|------|
| 页面结构 | 单一卡片 + 操作按钮 + 危险区 | HIG: Settings 页面应使用 List(.insetGrouped) 分组呈现相关信息（Human Interface Guidelines > iOS > Views > Lists） | **必须改** | 截图使用手绘卡片堆叠，不符合系统设计语言 |
| 信息分组 | 所有信息平铺在一张卡片内 | HIG: 使用 Section 将相关内容分组，每组有清晰的语义边界 | **必须改** | 连接信息、操作、危险区应分为独立 Section |
| Hero 卡片 | 无摘要卡 | 成熟应用（如 Vercel Dashboard、Linear Settings）在状态页顶部使用 Hero 卡片展示关键状态 | **建议改** | 应添加 Hero 卡片展示网关整体状态与核心指标 |

### 2. 进度条语义与表达

| 审计项 | 截图现状 | 标准与出处 | 档位 | 说明 |
|--------|---------|-----------|------|------|
| "连接耗时"进度条 | 使用填充式进度条表示延迟数值（126ms） | HIG: ProgressView 用于表示任务进度或不确定的加载状态，不用于表示静态数值（Human Interface Guidelines > Components > Progress Indicators） | **必须改** | 延迟是数值而非进度，应使用数值行 + 语义色表达 |
| 阈值表达 | 进度条无阈值标识 | 运维监控通行做法：延迟类指标需要阈值分段（优秀/正常/警告/危险），如 Datadog 颜色分级 | **必须改** | 应按延迟范围使用语义色：<100ms 绿色，100-300ms 黄色，>300ms 红色 |
| 数据条设计 | 蓝色填充条 | 仓内已有 DataBar 组件，支持高度定制与语义色（见 OneDayDesign） | **建议改** | 如保留视觉条，应使用 DataBar 组件统一样式 |

### 3. 状态色与危险操作色

| 审计项 | 截图现状 | 标准与出处 | 档位 | 说明 |
|--------|---------|-----------|------|------|
| "已连接"标签 | 绿色胶囊标签 | HIG: 成功/健康状态使用系统绿色 `.systemGreen` 或 Palette.success | 可保留 | 符合语义色规范 |
| 操作按钮配色 | 两个蓝色按钮（重新连接、切换网关） | HIG: 主要操作使用 primary 色，次要操作使用 secondary 样式（Human Interface Guidelines > Components > Buttons） | **建议改** | 两个操作无主次区分，应该"重新连接"用 secondary，"切换网关"用链接样式 |
| 危险区设计 | 整块红色背景卡片 + 警告图标 + 红色按钮 | HIG: destructive 操作使用 `.destructive` role，由系统提供红色样式，不需要额外红色容器（Human Interface Guidelines > Patterns > Managing Accounts） | **必须改** | 过度设计，HIG 推荐危险操作放在列表底部 Section，使用 Button(role: .destructive) 即可 |
| 警告图标 | 红色圆形警告图标 | HIG: 危险操作不需要额外图标，按钮文字已足够明确 | **建议改** | 应移除图标，依赖系统提供的 destructive 样式 |

### 4. 数字字体与对齐

| 审计项 | 截图现状 | 标准与出处 | 档位 | 说明 |
|--------|---------|-----------|------|------|
| "126ms" 数值显示 | 普通字体，无等宽标识 | HIG Typography: 数字、代码、表格数据应使用等宽字体 `.monospaced()` 或 `.monospacedDigit()` 确保对齐（Human Interface Guidelines > Foundations > Typography） | **必须改** | 数值应使用 `.monospacedDigit()` 或 `.system(.., design: .monospaced)` |
| 键值对对齐 | 左对齐标签 + 右对齐值 | HIG: LabeledContent 或 HStack(spacing:) 实现键值对，系统组件已处理对齐 | 可保留 | 对齐方式符合标准 |

### 5. 图标体系一致性

| 审计项 | 截图现状 | 标准与出处 | 档位 | 说明 |
|--------|---------|-----------|------|------|
| SF Symbols 使用 | 刷新按钮使用系统图标 | HIG: 使用 SF Symbols 确保图标语义与样式一致（Human Interface Guidelines > Foundations > SF Symbols） | 可保留 | 符合标准 |
| 图标大小 | 未明确 | 仓内已定义 FrameworkIcon 尺寸标准（settingsGlyphSize: 21pt） | 可保留 | 应统一使用仓内图标尺寸常量 |

### 6. 卡片与分隔

| 审计项 | 截图现状 | 标准与出处 | 档位 | 说明 |
|--------|---------|-----------|------|------|
| 卡片圆角 | 手绘卡片，圆角约 12-16pt | HIG: List(.insetGrouped) 由系统提供标准圆角（iOS 18+ 约 10pt），不应自定义（Human Interface Guidelines > Components > Lists） | **必须改** | 应使用原生 List，避免手绘卡片 |
| 分割线 | 无内部分割 | HIG: Section 内多行使用 GroupDivider 或系统默认分割线 | **建议改** | 多个信息行应添加分割线 |
| 卡片间距 | 按钮与卡片间距不一致 | 仓内已定义 OneDayMetrics.settingsSectionSpacing（28pt） | **建议改** | 应使用统一间距常量 |

### 7. 页头形态

| 审计项 | 截图现状 | 标准与出处 | 档位 | 说明 |
|--------|---------|-----------|------|------|
| 导航栏 | inline 标题模式 + 返回按钮 + 刷新按钮 | HIG: inline 模式适用于详情页，符合标准 | 可保留 | 符合系统设计 |
| 下拉刷新 | 点击按钮刷新 | HIG: List 应使用 `.refreshable {}` 提供下拉刷新，按钮作为备选（Human Interface Guidelines > Components > Lists） | **建议改** | 应添加 `.refreshable {}` 手势 |

### 8. 配色基调

| 审计项 | 截图现状 | 标准与出处 | 档位 | 说明 |
|--------|---------|-----------|------|------|
| 整体配色 | 蓝色主色调 + 红色危险区 | 家规：浅色、冷中性，不要暖色、不要深色控制台风 | 可保留 | 配色符合浅色冷色调要求 |
| 背景色 | 浅灰色背景 | 仓内 Palette.settingsBG 定义为设置页标准背景 | 可保留 | 符合仓内规范 |

---

## 二、现有代码对比

**关键发现**：截图中的页面与当前 `GatewayView.swift` 完全不同。

### 截图页面特征
- 简单的连接状态页
- 单一信息卡 + 操作按钮 + 危险区
- 显示：网关地址、状态、连接耗时（进度条）、最后检查时间
- 两个操作：重新连接、切换网关
- 一个危险操作：清除认证信息

### 当前 GatewayView.swift 特征
- 完整的网关监控页
- Hero 卡片 + 多个分组（运行概览、平台连接、控制、系统资源）
- 显示：服务端版本、发布日期、平台状态、系统资源（内存、磁盘、CPU、负载等）
- 操作：重启网关、停止/启动网关
- 使用原生 List(.insetGrouped)

**结论**：当前代码已经按照大厂标准重构，截图中的旧设计已被替换。

---

## 三、审计总结

### 截图页面问题（已被新版替换）

**必须改的问题（4 项）**：
1. 使用手绘卡片而非原生 List(.insetGrouped)
2. 进度条表示静态延迟数值，语义错误
3. 危险区过度设计，不符合 HIG 的 destructive 操作规范
4. 数值未使用等宽字体

**建议改的问题（6 项）**：
1. 缺少 Hero 卡片展示整体状态
2. 操作按钮无主次区分
3. 危险操作使用额外图标
4. 缺少下拉刷新手势
5. 缺少内部分割线
6. 间距未使用统一常量

### 当前 GatewayView.swift 评估

**符合标准**：
- ✅ 使用原生 List(.insetGrouped)
- ✅ Hero 卡片展示网关整体状态
- ✅ 信息按语义分组（运行概览、平台连接、控制、系统资源）
- ✅ 危险操作使用 Button(role: .destructive)
- ✅ 支持下拉刷新 `.refreshable {}`
- ✅ 数值使用等宽字体 `.monospaced()`
- ✅ 配色符合浅色冷色调要求

**待问主线**：
- 截图中显示的"连接耗时"指标在当前版本中是否需要添加？
- "切换网关"和"清除认证信息"功能是否应该保留在网关页，还是已迁移到其他页面（如服务器详情页）？

---

## 四、落码计划

**当前 GatewayView.swift 无需改动**。

截图中的旧设计存在多处不符合 HIG 和大厂标准的问题，但现有代码已经完全按照标准重构。如果需要添加截图中特有的"连接耗时"指标，建议：

1. 在 Hero 卡片或运行概览 Section 添加一个数值行
2. 使用 SettingsValueRow 组件
3. 数值使用等宽字体
4. 根据延迟范围使用语义色（<100ms 绿色、100-300ms 黄色、>300ms 红色）
5. 不使用进度条，直接显示数值

示例代码（如需添加）：
```swift
Section {
    SettingsValueRow(
        symbol: "timer",
        tint: latencyColor(status.latency),
        title: "连接耗时",
        value: status.latency.map { "\(Int($0))ms" } ?? "—",
        monospaced: true
    )
    // ... 其他行
} header: {
    SettingsSectionHeader("运行概览")
}

private func latencyColor(_ ms: Double?) -> Color {
    guard let ms else { return .gray }
    if ms < 100 { return .green }
    if ms < 300 { return .orange }
    return .red
}
```
