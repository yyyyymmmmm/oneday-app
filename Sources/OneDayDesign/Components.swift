import SwiftUI

// MARK: - v2 组件层（定版 §3.5：每个组件全 App 只有一种实现）
// 内容层分离只靠留白、发丝线、一级表面差——零描边、零阴影、
// 零万能卡。玻璃与阴影各只有一个合法住所：发送键与浮空输入区。

public extension View {
    /// 分组容器：surface 底＋容器圆角，零描边零阴影（定版 §3.4）。
    /// 行与分隔线由内容自行排入（行走 ContentRow/FieldRow，
    /// 分隔走 GroupDivider），容器本身不加内边距。
    func odGroup() -> some View {
        self
            .background(
                Palette.surface,
                in: RoundedRectangle(cornerRadius: OneDayMetrics.containerCorner)
            )
            .clipShape(RoundedRectangle(cornerRadius: OneDayMetrics.containerCorner))
    }
}

/// 分组内发丝线：内缩至全页同一条对齐线（定版 §3.2）。
public struct GroupDivider: View {
    private let inset: CGFloat

    public init(inset: CGFloat = OneDayMetrics.dividerInset) {
        self.inset = inset
    }

    public var body: some View {
        Rectangle()
            .fill(Palette.hairline)
            .frame(height: 1)
            .padding(.leading, inset)
    }
}

/// 分区标题：13 medium、次色、句首大写、无字距。
/// 禁止大写 eyebrow（Hallmark Floor 9 / Impeccable 禁令）。
public struct SectionLabel: View {
    private let title: String

    public init(_ title: String) {
        self.title = title
    }

    public var body: some View {
        Text(title)
            .font(TypeScale.label)
            .foregroundStyle(Palette.inkSecondary)
    }
}

/// 状态点：只许出现在状态位（总览状态头、平台行），永远与状态
/// 文字成对，本身不单独传意（定版 §3.5）。
public struct StatusDot: View {
    private let color: Color

    public init(color: Color) {
        self.color = color
    }

    public var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .accessibilityHidden(true)
    }
}

/// 内容行：图标槽 28 等宽一列、标题＋副题、右侧安静的等宽元信息。
public struct ContentRow: View {
    private let icon: String?
    private let title: String
    private let subtitle: String?
    private let trailing: String?

    public init(
        icon: String? = nil,
        title: String,
        subtitle: String? = nil,
        trailing: String? = nil
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    public var body: some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            if let icon {
                Image(systemName: icon)
                    .font(TypeScale.body)
                    .foregroundStyle(Palette.inkSecondary)
                    .frame(width: OneDayMetrics.iconSlot, alignment: .leading)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(TypeScale.body)
                    .foregroundStyle(Palette.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(TypeScale.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            Spacer(minLength: OneDayMetrics.spacingS)
            if let trailing {
                Text(trailing)
                    .font(TypeScale.monoFootnote)
                    .foregroundStyle(Palette.inkMuted)
            }
        }
        .padding(.horizontal, OneDayMetrics.spacingM)
        .frame(minHeight: OneDayMetrics.rowHeight)
        .contentShape(Rectangle())
    }
}

/// 字段行（分组容器内）：标签在上、本体在下，行底无框，
/// 靠容器与发丝线成界（定版 §3.5）。
public struct FieldRow<Content: View>: View {
    private let label: String
    private let isActive: Bool
    private let content: Content

    public init(
        label: String,
        isActive: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.label = label
        self.isActive = isActive
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(TypeScale.label)
                .foregroundStyle(isActive ? Palette.ink : Palette.inkSecondary)
            content
                .font(TypeScale.body)
                .foregroundStyle(Palette.ink)
        }
        .padding(.horizontal, OneDayMetrics.spacingM)
        .padding(.vertical, OneDayMetrics.spacingSM)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// 主按钮：填充深档＋白字，每屏至多一个（定版 §3.5）。
/// 禁用态＝填充降至 35%，不整钮降透明。
public struct PrimaryButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        PrimaryButtonBody(configuration: configuration)
    }

    private struct PrimaryButtonBody: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(TypeScale.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(minHeight: OneDayMetrics.primaryButtonHeight)
                .background(
                    isEnabled
                        ? Palette.primaryFill
                        : Palette.primaryFill.opacity(0.35),
                    in: RoundedRectangle(cornerRadius: OneDayMetrics.buttonCorner)
                )
                .opacity(configuration.isPressed ? 0.85 : 1)
        }
    }
}

public extension ButtonStyle where Self == PrimaryButtonStyle {
    static var odPrimary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

/// 次按钮：surface 面＋墨字，靠一级表面差成面（定版 §3.5）。
public struct SecondaryButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TypeScale.body)
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, OneDayMetrics.spacingM)
            .frame(minHeight: OneDayMetrics.minTapTarget)
            .background(
                Palette.surface,
                in: RoundedRectangle(cornerRadius: OneDayMetrics.buttonCorner)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

public extension ButtonStyle where Self == SecondaryButtonStyle {
    static var odSecondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

/// 行/钮按压态（0.2.2 动效专项）：.plain 行默认无任何按压反馈，
/// 本样式补齐——按下时轻降透明＋微缩，松手弹簧回位。只服务
/// 状态感知（让用户看清点中了），参数登记于 DESIGN-V3-NOTES §7。
public struct PressableButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.55 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(MotionTokens.press, value: configuration.isPressed)
    }
}

public extension ButtonStyle where Self == PressableButtonStyle {
    static var odPressable: PressableButtonStyle { PressableButtonStyle() }
}

/// 空态：图标弱色 light、标题 semibold、说明次色，整页至多一个。
public struct EmptyState: View {
    private let icon: String
    private let title: String
    private let message: String

    public init(icon: String, title: String, message: String) {
        self.icon = icon
        self.title = title
        self.message = message
    }

    public var body: some View {
        VStack(spacing: OneDayMetrics.spacingS) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Palette.inkMuted)
                .accessibilityHidden(true)
            Text(title)
                .font(TypeScale.headline)
                .foregroundStyle(Palette.ink)
            Text(message)
                .font(TypeScale.subhead)
                .foregroundStyle(Palette.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

/// 行内错误：语义色图标＋墨色正文说清问题，恢复动作由调用方
/// 紧随其后放文字按钮（定版 §3.5）。
public struct InlineError: View {
    private let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var body: some View {
        HStack(alignment: .top, spacing: OneDayMetrics.spacingS) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 15))
                .foregroundStyle(Palette.danger)
                .accessibilityHidden(true)
            Text(message)
                .font(TypeScale.subhead)
                .foregroundStyle(Palette.ink)
        }
    }
}
