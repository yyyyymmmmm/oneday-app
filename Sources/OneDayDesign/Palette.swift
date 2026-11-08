import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - 语义令牌（v2 定版，见 docs/DESIGN-V2.md §3.3）
// 组件只许引用这里的语义令牌，不写裸 hex。
//
// 0.3.2 令牌层礼记化（DESIGN-V4 §17）：全部令牌改由
// 「主题令牌表」查表生成——数据源是 AccentTheme.tokens
// （腾讯蓝为完整行、默认主题），本文件只剩工厂与别名，
// 不再逐令牌写死浅/深两套值。换主题＝换表行，组件零改。
//
// 色彩纪律不变：表面保持近中性（蓝味只在色温层），蓝色
// 只活在强调与每屏唯一的时刻里。文字三角色对 pageBG/
// bubbleFill 逐对验算 ≥4.5:1（0.3.2 出厂对比表见 §17.4：
// 浅色 ink 17.4/sec 8.8/muted 5.1（气泡底 15.8/8.0/4.6）、
// 暗色 ink 17.6/sec 8.9/muted 5.7（气泡底 15.9/8.0/5.2）、
// 白字对 primaryFill 浅 9.4/暗 6.5，全对达标）。

public extension Color {
    /// 0xRRGGBB
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

#if canImport(UIKit)
private extension UIColor {
    convenience init(hex: UInt32) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255.0
        let g = CGFloat((hex >> 8) & 0xFF) / 255.0
        let b = CGFloat(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
}
#endif

public enum Palette {
    /// 令牌工厂（0.3.2）：按当前主题令牌表的键生成动态色，
    /// 浅/深由系统外观在 provider 内解析。读取 AccentStore
    /// 当前主题即建立 @Observable 订阅——引用令牌的视图在
    /// 主题切换时自动重绘（与 0.2.x 强调色传播同机制），
    /// provider 捕获的是求值时点的令牌表行，重绘即换新行。
    private static func token(
        _ keyPath: KeyPath<ThemeTokens.Scheme, UInt32>
    ) -> Color {
        let tokens = AccentStore.shared.theme.tokens
        #if canImport(UIKit)
        return Color(uiColor: UIColor(dynamicProvider: { traits in
            let scheme = traits.userInterfaceStyle == .dark
                ? tokens.dark : tokens.light
            return UIColor(hex: scheme[keyPath: keyPath])
        }))
        #else
        return Color(hex: tokens.light[keyPath: keyPath])
        #endif
    }

    /// 基色＋alpha 成对令牌的工厂（scrim/hairline 用）：
    /// 基色与不透明度同在令牌表行内，provider 一并解析
    private static func tokenWithAlpha(
        _ base: KeyPath<ThemeTokens.Scheme, UInt32>,
        _ alpha: KeyPath<ThemeTokens.Scheme, Double>
    ) -> Color {
        let tokens = AccentStore.shared.theme.tokens
        #if canImport(UIKit)
        return Color(uiColor: UIColor(dynamicProvider: { traits in
            let scheme = traits.userInterfaceStyle == .dark
                ? tokens.dark : tokens.light
            return UIColor(hex: scheme[keyPath: base])
                .withAlphaComponent(scheme[keyPath: alpha])
        }))
        #else
        return Color(
            hex: tokens.light[keyPath: base],
            alpha: tokens.light[keyPath: alpha]
        )
        #endif
    }

    // —— 表面四层阶梯（§14 条 1：禁黑框与 #000，背景靠
    // 层间明度差 1–3% 的微差分层；数值在令牌表行内） ——
    /// 层 1 页面底：近中性纸色
    public static var pageBG: Color { token(\.pageBG) }
    /// 层 2 卡片/分组容器面
    public static var surface: Color { token(\.surface) }
    /// 层 3 浮层面（助手消息泡、浮起控件底）
    public static var bubbleFill: Color { token(\.bubbleFill) }
    /// 层 3.5 字段面：比浮层再降一级（输入字段、代码块）
    public static var fieldFill: Color { token(\.fieldFill) }
    /// 四层阶梯的语义别名（新代码按层引用，旧令牌同值）
    public static var layerPage: Color { pageBG }
    public static var layerCard: Color { surface }
    public static var layerOverlay: Color { bubbleFill }
    /// 层 4 遮罩：抽屉/弹层背后的压暗层（基色＋alpha 在表行内）
    public static var scrim: Color {
        tokenWithAlpha(\.scrimBase, \.scrimAlpha)
    }

    // —— 文字三角色 ——
    /// 主文字
    public static var ink: Color { token(\.ink) }
    /// 次文字
    public static var inkSecondary: Color { token(\.inkSecondary) }
    /// 弱文字：只用于元信息（计数、时间、占位性说明）。
    /// 暗色值 0.3.2 按审查 I-1 提亮至 0x8A8A90（气泡底
    /// 对比 4.3 → 5.2:1），数值在令牌表行内
    public static var inkMuted: Color { token(\.inkMuted) }

    /// 发丝线：基色低 alpha 推导，两套外观下都保持「看得见
    /// 的线、不是一道杠」（Pro Rules）
    public static var hairline: Color {
        tokenWithAlpha(\.hairlineBase, \.hairlineAlpha)
    }

    // —— 强调（主题三档，随令牌表行切换；每屏至多一个
    // 时刻＋关键动作的纪律不变） ——
    /// 品牌主色：文字/图标强调
    public static var primary: Color { token(\.primary) }
    /// 品牌填充：强调底＋白字（主按钮、发送键）
    public static var primaryFill: Color { token(\.primaryFill) }
    /// 品牌浅染：用户气泡、选中衬底
    public static var primaryTint: Color { token(\.primaryTint) }
    /// 填充上的文字色（主按钮/发送键的白字，页面不许写 .white）
    public static var onPrimary: Color { token(\.onPrimary) }

    /// 影基色：浮层软影的近黑墨色（§14 条 1 不用纯黑）；
    /// 与外观无关、不入令牌表，Elevation 与发送舱双环影共用
    public static let shadowBase = Color(hex: 0x0A0A0C)

    // —— 反馈语义 ——
    /// 成功 / 在线
    public static var success: Color { token(\.success) }
    /// 警告 / 降级
    public static var warning: Color { token(\.warning) }
    /// 危险 / 错误 / 离线
    public static var danger: Color { token(\.danger) }

    /// 平台/网关状态字符串 → 状态色：connected/running/ok 为绿，
    /// error/failed/disconnected 为红，其余（未知、未配置）为弱色。
    /// 状态色永不单独传意，调用方必须同时呈现状态词（定版 §3.5）。
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
    /// 侧边抽屉面板右侧圆角（0.3.6，§21）
    public static let drawerCorner: CGFloat = 24
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
    /// 抽屉宽占屏比（设备值，0.1.3 定版 82%）
    public static let drawerWidthFraction: CGFloat = 0.82
    /// 抽屉宽上限（设备值，大屏不无限拉宽）
    public static let drawerMaxWidth: CGFloat = 340
    /// 原生底栏在屏幕底部的占位（抽屉面板底部按它留位）
    public static let tabBarZone: CGFloat = 76

    /// 间距梯队：4/8/12/16/20/24/32/48，只许取梯队值
    public static let spacingXS: CGFloat = 4
    public static let spacingS: CGFloat = 8
    public static let spacingSM: CGFloat = 12
    public static let spacingM: CGFloat = 16
    public static let spacingL: CGFloat = 24
    public static let spacingXL: CGFloat = 32
    public static let spacingXXL: CGFloat = 48
}
