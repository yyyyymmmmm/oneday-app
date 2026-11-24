# DESIGN §462：kicker 改 SF 字形块

**设计日期**：2026-11-24  
**状态**：施工中  
**出处**：§453 内容三面包去卡通化口径

## 背景

动态卡与点子卡上的 kicker 目前使用 emoji（🌅📰🔍💡 等），视觉语言偏卡通化。按用户 2026-11-24 03:57 定的去卡通化口径，改为 **SF Symbol 字形块**：扁平、克制、专业，与全 App 图标语言一致。

## 设计规格

### 视觉形态
- **字形块结构**：SF Symbol 图标 ＋ 扁平底色小块
- **尺寸**：约 24-28pt 方形块，字形 14-16pt
- **圆角**：6pt（与卡片圆角语言一致）
- **配色**：字形用 ink（深色），底色用 Palette 既有令牌
- **原则**：扁平、单色、去渐变、去立体、去卡通

### 映射表

#### 动态卡（Feed，按 FeedPostKind）

| kind | 中文名 | SF Symbol | 底色令牌 | 色值参考（浅） |
|------|--------|-----------|----------|----------------|
| digest | 今日动态 | `doc.text` | `tintSky` | #EDF7FD |
| morning | 晨报 | `sunrise` | `tintOrange` | #FDF0DF |
| research | 调研 | `magnifyingglass` | `tintLavender` | #F0EEFA |
| seed | 上手指南 | `sparkles` | `tintGreen` | #E3F3E8 |
| unknown | 动态 | `doc.text` | `primaryPale` | 主题色浅档 |

#### 点子卡（Ideas，按 IdeaCategory）

| category | 中文名 | SF Symbol | 底色令牌 | 色值参考（浅） |
|----------|--------|-----------|----------|----------------|
| health | 健康 | `heart.fill` | `tintGreen` | #E3F3E8 |
| relationships | 人际关系 | `person.2.fill` | `tintLavender` | #F0EEFA |
| finance | 财务 | `dollarsign.circle.fill` | `tintOrange` | #FDF0DF |
| career | 事业 | `briefcase.fill` | `primary` | 主题色 |
| interest | 兴趣 | `star.fill` | `tintSky` | #EDF7FD |
| efficiency | 效率提升 | `bolt.fill` | `primaryPale` | 主题色浅档 |
| other | 其他 | `lightbulb.fill` | `fillSecondary` | 系统 fill 二档 |

**无分类兜底**：点子无 category 或 category 未知时，走 other 映射（灯泡＋fill 二档）。

### 色彩策略

- **复用克制**：12 类共用 Palette 现有 6 档色（4 tint ＋ primary 两档＋ fill 一档）
- **语义对位**：
  - 健康/成长类 → 绿（health, seed）
  - 人际/思考类 → 紫（relationships, research）
  - 财务/温暖类 → 橙（finance, morning）
  - 探索/信息类 → 蓝（interest, digest）
  - 专业/效率类 → 主题色（career, efficiency）
  - 通用/其他类 → 中性灰（unknown, other）

## 实现要点

### 数据层（不动）
- `BridgeFeedPost.emoji` 与 `BridgeIdea.emoji` 字段保留但不用
- `FeedPostKind` 与 `IdeaCategory` 枚举不变
- 新增计算属性返回 SF Symbol 名与底色

### 呈现层
1. **Feed kicker**：
   - `FeedModels.FeedPostKind` 新增 `symbolName` 与 `kickerColor` 计算属性
   - `FeedView` 的 kicker 渲染改为字形块组件
   
2. **Idea kicker**：
   - `IdeaPresentation` 或新建 `IdeaKicker` enum，提供 `symbol(for:)` 与 `color(for:)` 方法
   - `IdeasView` 的 kicker 渲染改为字形块组件

3. **字形块组件**（可选，或内联实现）：
   ```swift
   struct KickerBadge: View {
       let symbolName: String
       let backgroundColor: Color
       
       var body: some View {
           Image(systemName: symbolName)
               .font(.system(size: 15, weight: .semibold))
               .foregroundStyle(Palette.ink)
               .frame(width: 26, height: 26)
               .background(backgroundColor)
               .clipShape(RoundedRectangle(cornerRadius: 6))
       }
   }
   ```

## 验收标准

1. ✅ 构建通过，Feed/Ideas 相关测试套件全绿
2. ✅ 10 类字形块视觉自查：扁平、无渐变、无卡通感、像 SF 原生图标块
3. ✅ 深浅模式双验：底色在暗档使用对应 Palette 暗值（已定义）
4. ✅ 无分类卡走兜底字形，不显示 emoji
5. ✅ 数据层字段未动，改动只在呈现层

## 回滚方案

单文件回退以下文件至基线 9e29aca：
- `Sources/OneDayCore/FeedModels.swift`
- `Sources/OneDayCore/IdeaPresentation.swift`（或新建的 kicker 文件）
- `Sources/OneDayApp/FeedView.swift`
- `Sources/OneDayApp/IdeasView.swift`
