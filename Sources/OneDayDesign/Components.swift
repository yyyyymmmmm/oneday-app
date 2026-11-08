import SwiftUI

// MARK: - 纸墨平面基础组件（内容层零玻璃；玻璃只走 DesignTokens 的 Mat）

public extension View {
    /// 卡面：容器底＋卡圆角＋描边＋卡档投影。内容层一律走它成面，
    /// 不许各页自拼 background/shadow。
    func odCard(padding: CGFloat = OneDayMetrics.cardPadding) -> some View {
        self
            .padding(padding)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: OneDayMetrics.cardCorner))
            .overlay(
                RoundedRectangle(cornerRadius: OneDayMetrics.cardCorner)
                    .strokeBorder(Palette.line, lineWidth: 1)
            )
            .odElevation(Elevation.card)
    }
}

/// 分区标题：次文字小字，页面内分区统一口径
public struct SectionHeader: View {
    private let title: String

    public init(_ title: String) {
        self.title = title
    }

    public var body: some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Palette.sub)
            .textCase(.uppercase)
    }
}

/// 状态丸：状态点＋文字，底走状态色浅染（12% 不透明）
public struct StatusPill: View {
    private let text: String
    private let color: Color

    public init(text: String, color: Color) {
        self.text = text
        self.color = color
    }

    public var body: some View {
        HStack(spacing: OneDayMetrics.spacingXS) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(text)
                .font(.caption.weight(.medium))
                .foregroundStyle(Palette.ink)
        }
        .padding(.horizontal, OneDayMetrics.spacingS)
        .padding(.vertical, OneDayMetrics.spacingXS)
        .background(color.opacity(0.12), in: Capsule())
    }
}

/// 主按钮样式：填充深档底＋白字（白字对 primaryFill 双底对比
/// 9.40:1 / 6.54:1，见 Palette 验算）。只给每屏唯一主操作。
public struct PrimaryButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(minHeight: OneDayMetrics.minTapTarget)
            .background(
                Palette.primaryFill,
                in: RoundedRectangle(cornerRadius: OneDayMetrics.controlCorner)
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

public extension ButtonStyle where Self == PrimaryButtonStyle {
    static var odPrimary: PrimaryButtonStyle { PrimaryButtonStyle() }
}
