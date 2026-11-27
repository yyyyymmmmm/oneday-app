# 动态页视觉结构对标交付报告

**基线**：fix/feed-design-20261127，叠在 ui7 支（067f03e3）  
**对照**：参考截图（人家的）vs 现状截图（咱们的）  
**范围**：本支只管视觉结构（卡片结构、字阶、行距段距、留白、图片呈现、元信息行），串面数据问题归 ui7 支

---

## 一、不舒服清单与大厂对位表

### 1. 卡片结构：左侧图标块 + 右侧内容栏

**现状问题**：
- 左侧 kicker 图标块 36×36，占据横向空间但视觉权重不足
- 右侧内容栏起点被图标块推挤，标题起手晚

**参考标杆**（Twitter/Mastodon/Bluesky 等成熟社交动态页）：
- 左侧头像或图标通常 40–48pt，配合圆形或圆角方块
- 内容栏与图标间距 12–16pt（HIG 标准间距梯队）

**文献依据**：
- HIG Lists - Row Layout：图标与内容间距建议 12–16pt
- HIG Layouts - Spacing：标准间距梯队 {4, 8, 12, 16, 20, 24, 32, 48}
- standards-audit-type-layout-20261115.md §3：OneDayMetrics 间距梯队

**对位判断**：
- 当前 spacingM (12pt) 合规，kicker 尺寸 36×36 偏小
- 建议保持当前间距，kicker 视觉已定版不改（§462 映射表）

---

### 2. 标题字阶：视觉层次不足

**现状问题**：
- 标题使用 `.contentListTitle`（Title3 20pt semibold），在卡片内显得不够醒目
- 参考标杆的标题明显更大、更有冲击力

**参考标杆**：
- Twitter：标题约 22–24pt semibold
- Mastodon：标题约 20–22pt bold
- Bluesky：标题约 22pt semibold

**文献依据**：
- HIG Typography - Text Styles：
  - Title3 = 20pt（当前值）
  - Title2 = 22pt
  - Title1 = 28pt
- FontRoles.swift:60：`.contentListTitle` 定义为 Title3 20 semibold，§364 局部角色
- FontRoles.swift:46：`.detailTitle` 为 Title2 semibold（详情页题）

**对位判断**：
- 当前 Title3 20pt 偏小，建议升至 Title2 22pt semibold
- 或使用 `.title2.weight(.semibold)`，与参考标杆 22–24pt 区间对齐

---

### 3. 行距段距：内部拥挤，缺少呼吸感

**现状问题**：
- VStack spacing 使用 `OneDayMetrics.spacingS`（8pt），元素间距过紧
- 标题、category chip、正文、图片之间缺少足够的视觉间隔

**参考标杆**：
- Twitter/Mastodon：标题与正文间距约 12–16pt
- 图片上下留白约 12–16pt
- category chip 与正文间距约 8–12pt

**文献依据**：
- HIG Layouts - Spacing：推荐内容区块间距 12–16pt
- standards-audit-type-layout-20261115.md §3：OneDayMetrics 间距梯队
  - spacingS = 8pt
  - spacingM = 12pt
  - spacingL = 16pt
- OneDayMetrics 定义（推断）：spacingSM 应在 10pt 左右

**对位判断**：
- 当前 spacingS (8pt) 用于所有垂直间距，过于统一且偏紧
- 建议分层：
  - 标题与 category chip：spacingS (8pt) ✓
  - category chip 与正文：spacingM (12pt)
  - 正文与图片：spacingM (12pt)
  - 图片与 refs/动作行：spacingM (12pt)

---

### 4. 卡片留白：垂直方向紧凑

**现状问题**：
- 卡片垂直 padding 使用 `OneDayMetrics.spacingS`（8pt），上下留白不足
- 整体卡片显得紧绷，缺少轻松感

**参考标杆**：
- Twitter：卡片垂直 padding 约 12–16pt
- Mastodon：卡片垂直 padding 约 16pt
- 参考截图：明显有更充裕的上下留白

**文献依据**：
- HIG Layouts - Spacing：内容容器建议 padding 12–20pt
- standards-audit-type-layout-20261115.md §3：页面横边距 20pt（pageGutter）

**对位判断**：
- 当前垂直 padding spacingS (8pt) 偏小
- 建议升至 spacingM (12pt)

---

### 5. 图片呈现：尺寸与圆角

**现状问题**：
- 图片使用 16:9 固定比例 + `radiusPreview` 圆角
- 图片视觉占比相对较小（实际尺寸受限于父容器）

**参考标杆**：
- Twitter：图片通常占卡片宽度 90%+，圆角约 12–16pt
- Mastodon：图片圆角约 8–12pt
- 参考截图：图片占据较大比例，圆角适中

**文献依据**：
- HIG Components - Images：建议使用标准圆角（8–16pt）
- FeedView.swift:654：当前使用 `OneDayMetrics.radiusPreview`
- standards-audit-type-layout-20261115.md：圆角字面残量待收编（P3-02）

**对位判断**：
- 16:9 比例合规
- radiusPreview 圆角值需确认（推断约 12–16pt），应该合规
- 图片占比主要受内容栏宽度影响，本支不改布局宽度

---

### 6. 元信息行：字阶与视觉权重

**现状问题**：
- 动作行使用 `.subheadline`（15pt）和 `.footnote`（13pt）混用
- 爱心/讨论图标 `.subheadline`，时间文字 `.footnote`
- 视觉权重分布合理，但与参考标杆对比略显大

**参考标杆**：
- Twitter/Mastodon：元信息行统一约 13–14pt
- 参考截图：元信息行字号明显小于正文

**文献依据**：
- HIG Typography - Text Styles：
  - Footnote = 13pt（元信息标准档）
  - Caption1 = 12pt
  - Caption2 = 11pt
- FontRoles.swift:78：`.meta` 定义为 Footnote 13 regular

**对位判断**：
- 当前混用 subheadline (15pt) 与 footnote (13pt)
- 建议统一为 `.footnote`（13pt），与 HIG 元信息档对齐

---

### 7. category chip：视觉形态

**现状问题**：
- 当前使用 `.subheadline`（15pt）+ 浅灰填充 + radiusTile 圆角
- §486.3 注明「照审计量测：标题下、正文上、单片」

**参考标杆**：
- Twitter：话题标签约 13–15pt，浅灰底，圆角约 4–8pt
- Mastodon：标签约 13–14pt

**文献依据**：
- HIG Components - Tags：建议使用 Caption1 (12pt) 或 Footnote (13pt)
- FeedView.swift:613：当前 `.subheadline`

**对位判断**：
- 当前 subheadline (15pt) 偏大
- 建议降至 `.footnote`（13pt）

---

### 8. 大标题尺度：页面标题

**现状问题**：
- 页面标题"动态"使用 `.pageTitle`（LargeTitle 34pt bold）
- 在滚动时与内容的对比度很高

**参考标杆**：
- Twitter/Mastodon：页面标题约 28–34pt bold
- 参考截图：标题醒目但不过分

**文献依据**：
- HIG Typography - Large Title：34pt bold 是标准大标题档
- FontRoles.swift:28：`.pageTitle` 定义为 LargeTitle 34 bold，§486 定版

**对位判断**：
- 当前 34pt bold 符合 HIG 大标题规格
- 与参考标杆对齐，不改

---

## 二、落码计划（视觉结构收编）

### 改动项（按优先级）

1. **标题字阶提升**：`.contentListTitle` (Title3 20pt) → `.title2.weight(.semibold)` (22pt)
2. **内部间距分层**：VStack spacing 由统一 spacingS (8pt) 改为分层使用 spacingS/spacingM
3. **卡片垂直留白**：`.padding(.vertical, spacingS)` → `.padding(.vertical, spacingM)`
4. **元信息行统一**：动作行图标与文字统一为 `.footnote` (13pt)
5. **category chip 降档**：`.subheadline` (15pt) → `.footnote` (13pt)

### 不改项（已定版或超出本支范围）

- kicker 图标块尺寸（§462 映射表已定版）
- 图片圆角（radiusPreview 值合规）
- 页面大标题（34pt bold 符合 HIG）
- 卡片结构（左图标+右内容栏，不动布局）

---

## 三、待问主线

1. **OneDayMetrics 间距梯队实际值**：需确认 spacingS/spacingM/spacingL/spacingSM 的确切 pt 值
2. **radiusPreview 圆角值**：需确认当前值是否在 12–16pt 区间
3. **contentListTitle 角色变更影响面**：本角色为§364局部角色，动态/点子/目标三面共用，改动是否需要同步其他两面
4. **字阶提升是否需要用户裁决**：标题从 20pt 升至 22pt 属视觉显著变化

---

## 四、文献出处汇总

- **HIG Typography**：https://developer.apple.com/design/human-interface-guidelines/typography
- **HIG Layouts**：https://developer.apple.com/design/human-interface-guidelines/layout
- **HIG Lists**：https://developer.apple.com/design/human-interface-guidelines/lists
- **standards-audit-type-layout-20261115.md**：本仓排版与布局标尺全域审计
- **apple-design-overall-report-20261124.md**：OneDay 苹果设计规范审计总汇报
- **FontRoles.swift**：本仓字阶角色定义文件
- **FeedView.swift**：动态页当前实现

---

**交卷状态**：第一节不舒服清单与对位表已完成，待主线裁决后落码
