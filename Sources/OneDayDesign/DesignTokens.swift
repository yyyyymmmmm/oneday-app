import SwiftUI

// MARK: - 设计令牌（自礼记 DesignTokens 移植，纪律原文沿用）
// 定版融合句：「纸墨为体，玻璃为用。」内容层（卡/列表/表单/消息）
// 永远纸墨平面、零玻璃；玻璃只活在功能层（发送键、行动条、次按钮、
// 指示器），且染色只许走主题强调令牌（Palette.primary /
// primaryFill），禁止写死 hex。
// 礼记的金额语义双色与衬线白名单不属于本 App，未移植。

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

// MARK: - Elevation 两档

/// 阴影规格令牌：全 App 阴影只许引用这两档。
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
    /// 卡档：贴面卡片的轻投影
    public static let card = ShadowSpec(opacity: 0.06, radius: 12, y: 4)
    /// 浮档：浮层与悬浮控件
    public static let floating = ShadowSpec(opacity: 0.18, radius: 14, y: 6)
}

public extension View {
    func odElevation(_ shadow: ShadowSpec) -> some View {
        self.shadow(color: .black.opacity(shadow.opacity), radius: shadow.radius, y: shadow.y)
    }
}

// MARK: - 圆角同心机制（子圆角由容器推导，禁止手算）

public enum CornerRadius {
    /// 同心圆角：内层元素圆角 = 容器圆角 − 内边距，下限 2pt。
    public static func concentric(container: CGFloat, padding: CGFloat) -> CGFloat {
        max(container - padding, 2)
    }
}

// MARK: - Motion 曲线与行为令牌（值沿礼记审计枚举）

public enum MotionTokens {
    /// 按压：一切点按反馈
    public static let press = Animation.snappy(duration: 0.22, extraBounce: 0.05)
    /// 液体弹簧：分段指示器滑移、Tab 形变等跟手位移
    public static let liquidSpring = Animation.interactiveSpring(response: 0.34, dampingFraction: 0.72)
    /// 页面交叉淡化：内容切换的默认过渡
    public static let pageCrossfade = Animation.easeInOut(duration: 0.25)

    /// Reduce Motion 降级口径：开启时返回 nil（调用方以
    /// withAnimation(resolved) 包裹，nil 即瞬时切换）；Reduce
    /// Transparency 的降级由系统玻璃自动回退实色，不在代码层处理。
    public static func resolved(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}
