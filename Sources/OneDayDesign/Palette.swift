import SwiftUI

// MARK: - 语义色角色层（0.4.0 降级，审计 §1.1）
// 沿革：0.3.2 礼记式「主题令牌表」→ 0.3.6 Muse 基线冻
// 值 → 0.4.0 **整表废止**：主题表（AccentTheme/ThemeTokens）
// 删除，Palette 从「按当前主题查表」降级为**系统语义色的
// 命名引用层**——每个角色直挂 UIKit 语义色/系统灰阶，浅
// 深与对比度由系统随环境解析（HIG：优先语义色、系统色，
// 自建动态色只在系统无对应时才用）。~380 处调用点零改动
// 是靠这层降级换来的，不代表回潮：新代码直接用系统色，
// 本层只作存量桥。
// 气泡两色口径（0.4.1 再改，用户 10:07 真机点名）：
// 0.4.0 曾按 §1.1 把冻值改挂 systemGray5/6——真机判
// 「两泡都发紫灰、深浅难分」（systemGray 的 #E5E5EA／
// #F2F2F7 带蓝紫倾向），本版按用户令回封存中性灰阶
// 直给：助手 #E9EAEC／用户 #F0F0F2（浅色值即 0.3.x
// 冻值）；暗色给纯中性深灰对（#2E2E2E／#242424、
// R=G=B 零色偏），深浅关系与浅色同向（助手深于用
// 户）。动态色写法与下方 scrim 同式。此二色自此为
// 用户点名的封存值，不再改挂系统灰阶。
// scrim：0.3.6 的「白纱」仍是抽屉例外 E5 的一部分（浅
// 色近白半透/暗色近黑半透），用动态色直给、不成表。
public enum Palette {
    public static let pageBG = Color(.systemGroupedBackground)
    public static let surface = Color(.secondarySystemGroupedBackground)
    public static let bubbleFill = Color(
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(
                    red: 0x2E / 255.0, green: 0x2E / 255.0,
                    blue: 0x2E / 255.0, alpha: 1
                )
                : UIColor(
                    red: 0xE9 / 255.0, green: 0xEA / 255.0,
                    blue: 0xEC / 255.0, alpha: 1
                )
        }
    )
    public static let fieldFill = Color(.secondarySystemBackground)
    public static let chatSurface = Color(.systemBackground)
    public static let selectionFill = Color(.systemGray5)
    public static let floatFill = Color(.secondarySystemBackground)
    public static let userBubbleFill = Color(
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(
                    red: 0x24 / 255.0, green: 0x24 / 255.0,
                    blue: 0x24 / 255.0, alpha: 1
                )
                : UIColor(
                    red: 0xF0 / 255.0, green: 0xF0 / 255.0,
                    blue: 0xF2 / 255.0, alpha: 1
                )
        }
    )

    public static let scrim = Color(
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.black.withAlphaComponent(0.50)
                : UIColor.white.withAlphaComponent(0.55)
        }
    )

    public static let ink = Color.primary
    public static let inkSecondary = Color.secondary
    public static let inkMuted = Color(.tertiaryLabel)
    public static let hairline = Color(.separator)

    public static let primary = Color.accentColor
    public static let primaryFill = Color.accentColor
    public static let primaryTint = Color.accentColor.opacity(0.12)
    public static let onPrimary = Color.white

    public static let success = Color.green
    public static let warning = Color.orange
    public static let danger = Color.red

    /// 阴影基色（0.3.8 起）：Elevation 规格的基色（原
    /// shadowBase 令牌）；0.4.0 Elevation 整表废止后仅
    /// 抽屉例外的一处内联阴影引用（ChatView drawer）
    public static let shadowBase = Color.black

    /// 语义分层别名（0.3.2 与礼记对齐的叫法）：底＝页面
    /// 底色、卡＝分组卡面、浮＝浮层/弹层级表面。0.4.0 起
    /// 三者随角色层一并挂系统语义色
    public static var layerPage: Color { pageBG }
    public static var layerCard: Color { surface }
    public static var layerOverlay: Color { bubbleFill }

    /// 平台/网关状态字符串 → 状态色：connected/running/ok 为绿，
    /// error/failed/disconnected 为红，其余（未知、未配置）为弱色。
    /// 状态色永不单独传意，调用方必须同时呈现状态词（定版 §3.5）。
    /// （0.4.0：实现沿旧口径，色值随角色层改系统反馈色）
    public static func stateColor(_ state: String?) -> Color {
        switch state?.lowercased() {
        case "connected", "running", "ok", "ready":
            return success
        case "error", "failed", "disconnected", "stopped":
            return danger
        case "degraded", "warning", "restarting":
            return warning
        default:
            return inkMuted
        }
    }
}

// MARK: - 度量（定版 §3.2/§3.4：4pt 网格、圆角梯队、行高与对齐线）
// 纪律（0.3.2 补，审查 T-4）：每个数有出处——梯队值之外
// 的光学/手势/设备驱动值一律在此具名，不许散落在页面里
// 写字面量（tokenFlowSpacing/drawerEdgeZone 等即此收编）。

public enum OneDayMetrics {
    /// 触摸目标下限 44pt
    public static let minTapTarget: CGFloat = 44

    // 圆角梯队（同心推导的锚点，内层走 CornerRadius.concentric）
    /// 分组容器
    public static let containerCorner: CGFloat = 18
    /// 侧边抽屉面板右侧圆角（0.3.6 立宪大圆角，§22）
    public static let drawerCorner: CGFloat = 28
    /// 抽屉内容左右边距（0.3.6：名字/组标签/行标题/
    /// 发丝线同一条 20 线）
    public static let drawerInset: CGFloat = 20
    /// 名单导航行高（0.3.6 实测约 47）
    public static let navRowHeight: CGFloat = 47
    /// 名单行图标字形（细线 20–22 带内）
    public static let navGlyph: CGFloat = 21
    /// 底栏字形（0.3.6 立宪 21–22）
    public static let tabGlyph: CGFloat = 22
    /// 抽屉底部浮动条圆钮边长（0.3.6 实测约 52；搜索
    /// 胶囊同高）
    public static let drawerBarButton: CGFloat = 52
    /// 输入字段 / 代码块
    public static let fieldCorner: CGFloat = 12
    /// 按钮
    public static let buttonCorner: CGFloat = 14
    /// 用户消息气泡
    public static let bubbleCorner: CGFloat = 22
    /// 助手消息气泡（0.2.5：浅灰软填充泡，圆角比用户泡略收）
    public static let assistantBubbleCorner: CGFloat = 18
    /// 输入区胶囊（多行态圆角矩形的圆角，单行态走 Capsule）
    public static let composerCorner: CGFloat = 24
    /// 代码块（正文区内的内容面）
    public static let codeCorner: CGFloat = 10

    /// 页面左右边距（内容页）
    public static let pageGutter: CGFloat = 20
    /// 列表行图标槽宽：全页同一条对齐线
    public static let iconSlot: CGFloat = 28
    /// 发丝线内缩：边距 20＋槽 28＋间距 12
    public static let dividerInset: CGFloat = 60
    /// 内容行最小高（0.3.3 按礼记行口径放大：礼记
    /// MeView.entryLabel minHeight 44＋List 行内边距的实
    /// 效行高约 56；OneDay 自 52 提到 56，行不再挤）
    public static let rowHeight: CGFloat = 56
    /// 列表行图标字形字号（0.3.3）：semibold 粗实字形才
    /// 有分量（礼记行图标为系统 body 字形＋24 槽；OneDay
    /// 取 20 semibold，槽宽仍 iconSlot 28 保对齐线与
    /// dividerInset 60 的推导不变）
    public static let rowIconGlyph: CGFloat = 20
    /// 主按钮高
    public static let primaryButtonHeight: CGFloat = 50

    // —— 气泡内边距（0.3.2 具名收编，原 ChatView 散数 14/10）——
    /// 气泡横向内边距（用户泡与助手泡共用）
    public static let bubblePaddingH: CGFloat = 14
    /// 气泡纵向内边距
    public static let bubblePaddingV: CGFloat = 10
    /// 气泡靠边让位：对侧 Spacer 的最小让宽（用户泡左让/
    /// 助手泡右让同值，0.2.5 对齐口径）
    public static let bubbleSideInset: CGFloat = 44

    // —— 梯外具名值（审查 T-4 收编：光学/手势/设备驱动）——
    /// 流式词元流布局的词间/行间距（光学值，TokenFlow 用）
    public static let tokenFlowSpacing: CGFloat = 5
    /// 抽屉左缘唤出热区宽（手势值：够拇指起滑、不挡正文滚动）
    public static let drawerEdgeZone: CGFloat = 24
    /// 抽屉宽占屏比（0.3.6 立宪 peek 口径约 79%；
    /// 0.1.3 的 82% 整幅盖法作废，§21.5）
    public static let drawerWidthFraction: CGFloat = 0.79
    /// 抽屉宽上限（设备值，大屏不无限拉宽）
    public static let drawerMaxWidth: CGFloat = 340
    /// （tabBarZone 已于 0.4.0 删除，审计 §3.2：底栏回
    /// 原生后底部避让由系统安全区自理，手算占位带退役）
    /// 两行制会话行最小高（0.3.8 第 19 条，与 Core 的
    /// ListRowSpec.sessionRowMinHeight 同值）
    public static let sessionRowHeight: CGFloat = 57

    /// 间距梯队：4/8/12/16/20/24/32/48，只许取梯队值
    public static let spacingXS: CGFloat = 4
    public static let spacingS: CGFloat = 8
    public static let spacingSM: CGFloat = 12
    public static let spacingM: CGFloat = 16
    public static let spacingL: CGFloat = 24
    public static let spacingXL: CGFloat = 32
    public static let spacingXXL: CGFloat = 48
}
