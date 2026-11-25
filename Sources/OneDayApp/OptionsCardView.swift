import SwiftUI
import OneDayCore
import OneDayDesign

/// 选择框视图（总表 203／DESIGN §441）：挂在
/// assistant 气泡下方随行滚动（与审批卡「输入栏
/// 上方固定」分工不同）。三态形态与行高合成器
/// optionsCardSlot 逐值同式：活卡＝每项一行
/// minTapTarget 高、行间 spacingXS；已选＝一行
/// 回执；过期＝一行紧凑摘要。状态由 ChatView 按
/// 覆盖层＋线程尾位纯派生后传入，本视图不持状态
struct OptionsCardView: View {
    let state: OptionsCardState
    let options: [MessageOption]
    let onSelect: (MessageOption) -> Void

    var body: some View {
        switch state {
        case .live:
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingXS) {
                ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                    Button {
                        Haptics.selection()
                        onSelect(option)
                    } label: {
                        HStack(spacing: OneDayMetrics.spacingS) {
                            Text(option.label)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Palette.ink)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Palette.primary.opacity(0.85))
                        }
                        .frame(minHeight: OneDayMetrics.minTapTarget)
                        .padding(.horizontal, OneDayMetrics.spacingM)
                        .background(
                            RoundedRectangle(
                                cornerRadius: OneDayMetrics.radiusCard,
                                style: .continuous
                            )
                            .fill(Palette.surface)
                        )
                        .overlay {
                            RoundedRectangle(
                                cornerRadius: OneDayMetrics.radiusCard,
                                style: .continuous
                            )
                            .strokeBorder(Palette.separator.opacity(0.6), lineWidth: 0.5)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        case .selected(let label):
            HStack(spacing: OneDayMetrics.spacingXS) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(Palette.primary)
                Text("已选：\(label)")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
            }
            .frame(minHeight: OneDayMetrics.minTapTarget, alignment: .leading)
        case .expired:
            Text(options.map(\.label).joined(separator: " · "))
                .font(.footnote)
                .foregroundStyle(Palette.inkSecondary)
                .opacity(0.55)
                .lineLimit(1)
                .frame(minHeight: OneDayMetrics.minTapTarget, alignment: .leading)
        case .hidden:
            EmptyView()
        }
    }
}
