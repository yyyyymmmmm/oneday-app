import SwiftUI

/// 分区折叠头（§158 公用件）：抽屉分区与模型分组共
/// 用同一件——标题＋chevron（展开指下、折叠指右，
/// 随态旋转走系统动画曲线）、整行可点且命中高 ≥
/// 44pt、VoiceOver 以按钮 trait＋值报「已展开/已折
/// 叠」。标题字体由调用方经 titleFont 注入（抽屉走
/// 抽屉局部角色、模型面走系统分段头），本件不私定
/// 字阶。展开/折叠的高度过渡由调用方在内容容器上
/// 以动画事务承接（Grid 0fr→1fr 等价平滑，本件只
/// 管头不管身）。
public struct CollapsibleSectionHeader: View {
    public let title: String
    public let isCollapsed: Bool
    public let titleFont: Font
    public let onToggle: () -> Void

    public init(
        title: String,
        isCollapsed: Bool,
        titleFont: Font = .subheadline,
        onToggle: @escaping () -> Void
    ) {
        self.title = title
        self.isCollapsed = isCollapsed
        self.titleFont = titleFont
        self.onToggle = onToggle
    }

    public var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 6) {
                Text(title)
                    .font(titleFont)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                    .animation(.smooth(duration: 0.25), value: isCollapsed)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isCollapsed ? "已折叠" : "已展开")
    }
}
