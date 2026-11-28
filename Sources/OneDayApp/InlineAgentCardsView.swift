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
                .font(.system(size: 13))
                .foregroundStyle(Palette.success)
        case .inProgress:
            Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                .font(.system(size: 13))
                .foregroundStyle(Palette.primary)
        case .cancelled:
            Image(systemName: "xmark.circle")
                .font(.system(size: 13))
                .foregroundStyle(Palette.inkMuted)
        case .pending:
            Image(systemName: "circle")
                .font(.system(size: 13))
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

// MARK: - 对话内「分身委派任务卡」（让用户亲眼看到 AI 开分身干活）

struct SubagentDelegationCardView: View {
    let card: SubagentDelegationCard
    @State private var isOutputExpanded = false

    private var headerTitle: String {
        card.tasks.count > 1 ? "已派出 \(card.tasks.count) 个并行分身" : "已派出专属分身"
    }

    private var statusBadge: (text: String, color: Color, bg: Color) {
        switch card.state {
        case .running:
            return ("执行中", Palette.tintSkyInk, Palette.tintSky)
        case .succeeded:
            return ("已完成", Palette.successText, Palette.tintGreen)
        case .failed:
            return ("未完成", Palette.danger, Palette.errorSurface)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
            HStack(spacing: OneDayMetrics.spacingS) {
                Image(systemName: "person.2.wave.2.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Palette.tintLavenderInk)
                    .frame(width: 28, height: 28)
                    .background(Palette.tintLavender, in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                Text(headerTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)

                Spacer()

                HStack(spacing: 4) {
                    if card.state == .running {
                        ProgressView().controlSize(.mini)
                    }
                    Text(statusBadge.text)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(statusBadge.color)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(statusBadge.bg, in: Capsule())
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(card.tasks) { task in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "sparkles")
                                .font(.caption2)
                                .foregroundStyle(Palette.tintLavenderInk)
                                .padding(.top, 3)
                            Text(task.goal)
                                .font(.footnote)
                                .foregroundStyle(Palette.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if !task.toolsets.isEmpty || task.profile != nil {
                            HStack(spacing: 6) {
                                if let profile = task.profile, !profile.isEmpty {
                                    Text("分身：\(profile)")
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(Palette.tintSkyInk)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Palette.tintSky, in: Capsule())
                                }
                                ForEach(task.toolsets.prefix(3), id: \.self) { ts in
                                    Text(ts)
                                        .font(.caption2)
                                        .foregroundStyle(Palette.inkSecondary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Palette.fillTertiary, in: Capsule())
                                }
                            }
                            .padding(.leading, 18)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.pageBG, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }

            if let output = card.output, !output.isEmpty {
                Button {
                    Haptics.selection()
                    isOutputExpanded = true
                } label: {
                    HStack(spacing: 4) {
                        Text("查看分身完整汇报")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Palette.primary)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Palette.primary)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
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
        .sheet(isPresented: $isOutputExpanded) {
            SubagentReportReaderSheet(
                title: headerTitle,
                subtitle: card.tasks.map(\.goal).joined(separator: " / "),
                markdownContent: card.output ?? ""
            )
        }
    }
}

// MARK: - 对话内「CLI 终端执行实时卡」（让用户亲眼看到 AI 跑命令与回显）

struct TerminalExecutionCardView: View {
    let card: TerminalExecutionCard
    @State private var isExpanded = false
    @State private var copied = false

    private var statusBadge: (text: String, color: Color, bg: Color) {
        switch card.state {
        case .running:
            return ("运行中", Palette.tintSkyInk, Palette.tintSky)
        case .succeeded:
            return ("完成", Palette.successText, Palette.tintGreen)
        case .failed:
            return ("异常退出", Palette.danger, Palette.errorSurface)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
            HStack(spacing: OneDayMetrics.spacingS) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.tintSkyInk)
                    .frame(width: 26, height: 26)
                    .background(Palette.tintSky, in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                Text(card.kindLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.inkSecondary)

                Spacer()

                HStack(spacing: 4) {
                    if card.state == .running {
                        ProgressView().controlSize(.mini)
                    }
                    Text(statusBadge.text)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(statusBadge.color)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(statusBadge.bg, in: Capsule())

                Button {
                    UIPasteboard.general.string = card.command
                    Haptics.impact(.light)
                    copied = true
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(1.5))
                        copied = false
                    }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(copied ? Palette.successText : Palette.inkSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("复制命令")
            }

            Text("$ \(card.command)")
                .font(.caption.monospaced().weight(.medium))
                .foregroundStyle(Palette.ink)
                .lineLimit(isExpanded ? nil : 2)
                .textSelection(.enabled)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.codeFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            if let output = card.output, !output.isEmpty {
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(isExpanded ? "收起终端输出" : "查看终端输出")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Palette.primary)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Palette.primary)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)

                if isExpanded {
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(output)
                            .font(.caption2.monospaced())
                            .foregroundStyle(card.state == .failed ? Palette.danger : Palette.ink)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.pageBG, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
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
                .strokeBorder(Palette.hairline, lineWidth: 0.75)
        }
    }
}

// MARK: - 对话内「云电脑操作实时卡」（带一键全屏接管入口）

struct CloudComputerActionCardView: View {
    let card: CloudComputerActionCard
    let onTakeover: () -> Void

    var body: some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            Image(systemName: "desktopcomputer")
                .font(.system(size: 16, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Palette.tintOrangeInk)
                .frame(width: 34, height: 34)
                .background(Palette.tintOrange, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(card.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                    if card.state == .running {
                        ProgressView().controlSize(.mini)
                    }
                }
                Text(card.detail)
                    .font(.caption)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Button(action: onTakeover) {
                HStack(spacing: 4) {
                    Image(systemName: "hand.tap.fill")
                        .font(.caption2.weight(.semibold))
                    Text("接管")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Palette.primary, in: Capsule())
            }
            .buttonStyle(.odPressable)
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
}
