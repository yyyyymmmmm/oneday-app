import SwiftUI
import OneDayCore
import OneDayDesign

/// 聊天内嵌选择框（mac-09，对位 #21 / DESIGN §441）：
/// 复用 Core OptionsCardState / OptionsCardLogic 与
/// Design 令牌；桌面端形态与 iOS OptionsCardView 同构：
/// - live：可点选行（高 36pt、圆角 12pt、悬停轻染）
/// - selected：单行静态回执「已选：…」
/// - expired：置灰单行紧凑摘要
/// - hidden：不渲染
struct MacOptionsCardView: View {
    let state: OptionsCardState
    let options: [MessageOption]
    let onSelect: (MessageOption) -> Void

    @State private var hoveredIndex: Int?

    var body: some View {
        switch state {
        case .live:
            VStack(alignment: .leading, spacing: 6) {
                ForEach(
                    Array(options.enumerated()), id: \.offset
                ) { index, option in
                    Button {
                        onSelect(option)
                    } label: {
                        HStack(spacing: OneDayMetrics.spacingS) {
                            Text(option.label)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Palette.ink)
                                .lineLimit(1)
                                .frame(
                                    maxWidth: .infinity,
                                    alignment: .leading
                                )
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(
                                    Palette.primary.opacity(
                                        hoveredIndex == index ? 1.0 : 0.78
                                    )
                                )
                        }
                        .frame(minHeight: 36)
                        .padding(.horizontal, 12)
                        .background(
                            RoundedRectangle(
                                cornerRadius: OneDayMetrics.radiusCard,
                                style: .continuous
                            )
                            .fill(
                                hoveredIndex == index
                                    ? Palette.primaryTint
                                    : Palette.surface
                            )
                        )
                        .overlay {
                            RoundedRectangle(
                                cornerRadius: OneDayMetrics.radiusCard,
                                style: .continuous
                            )
                            .strokeBorder(
                                hoveredIndex == index
                                    ? Palette.primary.opacity(0.45)
                                    : Palette.separator.opacity(0.6),
                                lineWidth: 0.75
                            )
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { isHovering in
                        hoveredIndex = isHovering ? index : (
                            hoveredIndex == index ? nil : hoveredIndex
                        )
                    }
                }
            }
            .frame(maxWidth: 420, alignment: .leading)
        case .selected(let label):
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.primary)
                Text("已选：\(label)")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
            }
            .padding(.top, 2)
        case .expired:
            Text(options.map(\.label).joined(separator: " · "))
                .font(.system(size: 12))
                .foregroundStyle(Palette.inkSecondary)
                .opacity(0.55)
                .lineLimit(1)
                .padding(.top, 2)
        case .hidden:
            EmptyView()
        }
    }
}
