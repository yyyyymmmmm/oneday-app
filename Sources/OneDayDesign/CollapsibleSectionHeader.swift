import SwiftUI

/// 分区折叠头（§158 公用件）：抽屉分区与模型分组共
/// 用同一件——标题＋尾件（默认 chevron：展开指下、
/// 折叠指右，随态旋转走系统动画曲线；抽屉可改
/// stateText「显示」字样形态，见 TrailingStyle
/// 注）、整行可点且命中高默认 ≥44pt（抽屉传 36，
/// 见 minHeight 注）、VoiceOver 以按钮 trait＋值报
/// 「已展开/已折叠」。标题字体由调用方经 titleFont 注入（抽屉走
/// 抽屉局部角色、模型面走系统分段头），本件不私定
/// 字阶。展开/折叠的高度过渡由调用方在内容容器上
/// 以动画事务承接（Grid 0fr→1fr 等价平滑，本件只
/// 管头不管身）。
public struct CollapsibleSectionHeader: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 尾件形态：chevron（默认、既有消费面不变）／
    /// stateText（2026-11-21 抽屉样板对齐包增）：折
    /// 叠时尾端出「显示」字样（与标题同字阶、色随
    /// 消费点 foregroundStyle）、展开时尾端留空——
    /// Muse 现行版抽屉实机截图两态实测即此形态
    /// （展开态组头右侧无字、折叠态出「显示」）。
    /// 只许抽屉消费点传 stateText，模型分组等既有
    /// 面维持 chevron
    public enum TrailingStyle {
        case chevron
        case stateText
    }

    public let title: String
    public let isCollapsed: Bool
    public let titleFont: Font
    public let trailingStyle: TrailingStyle
    public let minHeight: CGFloat
    public let onToggle: () -> Void

    public init(
        title: String,
        isCollapsed: Bool,
        titleFont: Font = .subheadline,
        trailingStyle: TrailingStyle = .chevron,
        minHeight: CGFloat = 44,
        onToggle: @escaping () -> Void
    ) {
        self.title = title
        self.isCollapsed = isCollapsed
        self.titleFont = titleFont
        self.trailingStyle = trailingStyle
        self.minHeight = minHeight
        self.onToggle = onToggle
    }

    public var body: some View {
        Button(action: onToggle) {
            HStack(spacing: OneDayMetrics.rowInnerGap) {
                Text(title)
                    .font(titleFont)
                Spacer(minLength: 0)
                switch trailingStyle {
                case .chevron:
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                        .animation(
                            MotionTokens.resolved(
                                MotionTokens.sectionCollapse,
                                reduceMotion: reduceMotion
                            ),
                            value: isCollapsed
                        )
                case .stateText:
                    if isCollapsed {
                        Text("显示")
                            .font(titleFont)
                    }
                }
            }
            // 命中高默认 44（§158 定版）；抽屉消费点传
            // 36——样板组头块高实测约 32，44 时折叠块
            // 距 60 对样板 52 明显发散，取 36 兼顾节奏
            // 与命中域（仍高于样板本体），理由见交卷
            // 报告对位表
            .frame(minHeight: minHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isCollapsed ? "已折叠" : "已展开")
    }
}
