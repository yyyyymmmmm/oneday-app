import OneDayCore
import SwiftUI

// MARK: - 设计令牌（v2 定版，见 docs/DESIGN-V2.md）
// 定版融合句沿礼记：「纸墨为体，玻璃为用。」内容层（分组、列表、
// 表单、消息）永远纸墨平面、零玻璃零阴影零描边；玻璃只活在功能
// 层（发送键），且染色只许走主题强调令牌（Palette.primary /
// primaryFill），禁止写死 hex。

// MARK: - 字阶（定版 §3.1：一个家族、七档、三字重）

/// 字体角色令牌：页面只许引用这里，不许自选字号字重。
/// 家族只有一个（系统 SF Pro，中文落 PingFang SC）；等宽角色只
/// 给四类真实数据：版本号、计数、时间、代码块。
public enum TypeScale {
    /// 每屏唯一的排版时刻（总览状态头）
    public static let display = Font.title.weight(.semibold)
    /// 页内大标题（连接页字标）
    public static let title = Font.title2.weight(.semibold)
    /// 行标题、按钮文字
    public static let headline = Font.headline
    /// 正文与助手回答
    public static let body = Font.body
    /// 次级正文（字段值、步骤名）
    public static let callout = Font.callout
    /// 说明文字（空态、错误正文）
    public static let subhead = Font.subheadline
    /// 元信息
    public static let footnote = Font.footnote
    /// 分区标题：medium、句首大写、无字距（禁大写 eyebrow）
    public static let label = Font.footnote.weight(.medium)
    /// 最弱信息（时间戳）
    public static let caption = Font.caption
    /// 等宽正文（版本号、host 等读数）
    public static let monoBody = Font.system(.body, design: .monospaced)
    /// 等宽次级（模型名等标识符读数）
    public static let monoCallout = Font.system(.callout, design: .monospaced)
    /// 等宽元信息（计数）
    public static let monoFootnote = Font.system(.footnote, design: .monospaced)
    /// 等宽最弱信息（窄行内的标识符，如抽屉底行模型名）
    public static let monoCaption = Font.system(.caption, design: .monospaced)
    /// 等宽代码
    public static let monoCode = Font.system(.footnote, design: .monospaced)

    // —— 条 3 暗色降档变体（0.3.0，§14）：带权字体在暗色
    // 环境下经 VisualWeight 降一档；调用点以 colorScheme
    // 传入。未带权的字体（body/callout 等）由根环境
    // fontWeight 在暗色统一降档（ContentView 施加），两
    // 路合起来覆盖「所有文字」。
    public static func display(for scheme: ColorScheme) -> Font {
        Font.title.weight(.od(css: 600, scheme: scheme))
    }
    public static func title(for scheme: ColorScheme) -> Font {
        Font.title2.weight(.od(css: 600, scheme: scheme))
    }
    public static func label(for scheme: ColorScheme) -> Font {
        Font.footnote.weight(.od(css: 500, scheme: scheme))
    }
}

public extension Font.Weight {
    /// CSS 量纲字重（100–900）→ SwiftUI 字重；暗色环境
    /// 按 §14 条 3 降一档（映射表在 OneDayCore.VisualWeight，
    /// 单测把守）
    static func od(css: Int, scheme: ColorScheme) -> Font.Weight {
        let grade = scheme == .dark
            ? VisualWeight.steppedDown(css)
            : VisualWeight.nearestGrade(css)
        switch grade {
        case 100: return .ultraLight
        case 200: return .thin
        case 300: return .light
        case 500: return .medium
        case 600: return .semibold
        case 700: return .bold
        case 800: return .heavy
        case 900: return .black
        default: return .regular
        }
    }
}

// MARK: - Mat 材质三档（玻璃染色纪律）

/// 玻璃材质三档令牌：对应的系统 ButtonStyle / glassEffect 档位见下方扩展。
public enum Mat {
    /// 透明档：极轻浮层（系统 .glass 的 .clear 变体口径）
    case clear
    /// 常规档：行动条、次按钮（系统 .glass / .regular）
    case regular
    /// 染色档：唯一主操作（系统 .glassProminent ＋主题强调染色）
    case tinted
}

public extension View {
    /// 玻璃按钮令牌入口：regular → .glass；tinted → .glassProminent 并以
    /// 主题强调令牌染色（不写死色值）；clear 在按钮语境与 regular 同档
    /// （系统按钮玻璃只有两档，透明档只用于浮层表面）。
    @ViewBuilder
    func odGlassButton(_ mat: Mat) -> some View {
        switch mat {
        case .tinted:
            self.buttonStyle(.glassProminent).tint(Palette.primary)
        case .regular, .clear:
            self.buttonStyle(.glass)
        }
    }

    /// 玻璃表面令牌入口（非按钮浮层）：tinted 以主题浅染令牌轻染，
    /// 不用主色满染——表面染色面积受控，守单强调纪律。
    @ViewBuilder
    func odGlassSurface(_ mat: Mat, in shape: some Shape) -> some View {
        switch mat {
        case .clear:
            self.glassEffect(.clear, in: shape)
        case .regular:
            self.glassEffect(.regular, in: shape)
        case .tinted:
            self.glassEffect(.regular.tint(Palette.primaryTint), in: shape)
        }
    }
}

// MARK: - Elevation（定版 §3.4：只剩浮层一档，内容层零阴影）

/// 阴影规格令牌。
public struct ShadowSpec: Sendable {
    public let opacity: Double
    public let radius: CGFloat
    public let y: CGFloat

    public init(opacity: Double, radius: CGFloat, y: CGFloat) {
        self.opacity = opacity
        self.radius = radius
        self.y = y
    }
}

public enum Elevation {
    /// 浮档：只给浮空输入区与浮空控件（中性黑、带 y 偏移的软影）
    public static let floating = ShadowSpec(opacity: 0.14, radius: 16, y: 6)
}

public extension View {
    func odElevation(_ shadow: ShadowSpec) -> some View {
        // 阴影色不用纯黑（§14 条 1）：近黑墨色同效
        self.shadow(
            color: Color(hex: 0x0A0A0C).opacity(shadow.opacity),
            radius: shadow.radius, y: shadow.y
        )
    }
}

// MARK: - 圆角同心机制（子圆角由容器推导，禁止手算）

public enum CornerRadius {
    /// 同心圆角：内层元素圆角 = 容器圆角 − 内边距，下限 2pt。
    public static func concentric(container: CGFloat, padding: CGFloat) -> CGFloat {
        max(container - padding, 2)
    }
}

// MARK: - Motion 白名单（定版 §3.6：四条，只动 opacity/transform）

public enum MotionTokens {
    /// press：一切点按反馈（150ms 内出）
    public static let press = Animation.easeOut(duration: 0.15)
    /// swap：内容替换、错误出现、步骤状态变化
    public static let swap = Animation.easeInOut(duration: 0.2)
    /// indicator：指示器滑移（无额外弹跳的弹簧）
    public static let indicator = Animation.spring(response: 0.35, dampingFraction: 0.85)
    /// entrance：每屏至多一次入场
    public static let entrance = Animation.easeOut(duration: 0.45)
    /// 页面交叉淡化（滚动跟随等既有调用点沿用 swap 时长口径）
    public static let pageCrossfade = Animation.easeInOut(duration: 0.2)
    /// 条 9 定版弹簧·拖拽类（0.3.0，§14）：stiffness
    /// 1200 / damping 80，零回弹——抽屉拖动跟随与归位、
    /// 一切拖拽类交互走它
    public static let dragSpring = Animation.interpolatingSpring(
        stiffness: 1200, damping: 80
    )
    /// 条 9 定版弹簧·小动作（0.3.0，§14）：stiffness
    /// 380 / damping 18，微弹——点赞类点按反馈、徽标与
    /// 浮钮的出现/跳动走它
    public static let microSpring = Animation.interpolatingSpring(
        stiffness: 380, damping: 18
    )

    /// Reduce Motion 降级口径：开启时返回 nil（调用方以
    /// withAnimation(resolved) 包裹，nil 即瞬时切换）；Reduce
    /// Transparency 的降级由系统玻璃自动回退实色，不在代码层处理。
    public static func resolved(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}
