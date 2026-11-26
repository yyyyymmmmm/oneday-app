import OneDayCore
import OneDayDesign
import SwiftUI

/// 对话内任务进度清单卡（Hermes v0.23.0 `todo` 工具的原生呈现）
struct TodoChecklistCardView: View {
    let items: [TodoChecklistItem]
    @State private var isExpanded = true

    private var completedCount: Int {
        items.filter { $0.status == .completed }.count
    }

    private var progress: Double {
        guard !items.isEmpty else { return 0 }
        return Double(completedCount) / Double(items.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: OneDayMetrics.spacingS) {
                    Image(systemName: "checklist")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.primary)
                    Text("任务进度")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    Text("\(completedCount)/\(items.count)")
                        .font(.caption.monospacedDigit().weight(.medium))
                        .foregroundStyle(Palette.inkSecondary)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Palette.inkMuted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            ProgressView(value: progress)
                .tint(completedCount == items.count ? Palette.success : Palette.primary)

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(items) { item in
                        HStack(alignment: .top, spacing: OneDayMetrics.spacingS) {
                            statusIcon(for: item.status)
                                .frame(width: 16, height: 18, alignment: .center)
                            Text(item.content)
                                .font(.footnote)
                                .foregroundStyle(
                                    item.status == .completed || item.status == .cancelled
                                        ? Palette.inkSecondary
                                        : Palette.ink
                                )
                                .strikethrough(item.status == .completed || item.status == .cancelled)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(OneDayMetrics.spacingSM)
        .background(
            Palette.surface,
            in: RoundedRectangle(cornerRadius: OneDayMetrics.containerCorner, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: OneDayMetrics.containerCorner, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 0.75)
        }
    }

    @ViewBuilder
    private func statusIcon(for status: TodoChecklistItem.Status) -> some View {
        switch status {
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.captionText)
                .foregroundStyle(Palette.success)
        case .inProgress:
            Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                .font(.captionText)
                .foregroundStyle(Palette.primary)
        case .cancelled:
            Image(systemName: "xmark.circle")
                .font(.captionText)
                .foregroundStyle(Palette.inkMuted)
        case .pending:
            Image(systemName: "circle")
                .font(.captionText)
                .foregroundStyle(Palette.inkMuted)
        }
    }
}

/// 对话内结构化澄清提问卡（Hermes v0.23.0 `clarify` 工具的原生呈现）
struct ClarifyPromptCardView: View {
    let prompt: ClarifyPromptCard
    let onSelectChoice: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
            HStack(alignment: .top, spacing: OneDayMetrics.spacingS) {
                Image(systemName: "questionmark.bubble.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.primary)
                    .padding(.top, 1)
                Text(prompt.question)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !prompt.choices.isEmpty {
                VStack(spacing: 6) {
                    ForEach(prompt.choices, id: \.self) { choice in
                        Button {
                            Haptics.selection()
                            onSelectChoice(choice)
                        } label: {
                            HStack(spacing: OneDayMetrics.spacingS) {
                                Text(choice)
                                    .font(.subheadline)
                                    .foregroundStyle(Palette.ink)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Palette.primary)
                            }
                            .padding(.horizontal, OneDayMetrics.spacingSM)
                            .padding(.vertical, 9)
                            .background(
                                Palette.pageBG,
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Palette.hairline, lineWidth: 0.75)
                            }
                        }
                        .buttonStyle(.odPressable)
                    }
                }
            }
        }
        .padding(OneDayMetrics.spacingSM)
        .background(
            Palette.surface,
            in: RoundedRectangle(cornerRadius: OneDayMetrics.containerCorner, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: OneDayMetrics.containerCorner, style: .continuous)
                .strokeBorder(Palette.primary.opacity(0.25), lineWidth: 1)
        }
    }
}
