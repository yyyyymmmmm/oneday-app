import OneDayCore
import OneDayDesign
import SwiftUI

/// 运行中实时活动与纠偏舱（对标 Claude Code / Manus / OpenAI Operator）：
/// - 只要当前对话有在飞任务，就在输入栏上方呈现紧凑浮卡；
/// - 实时展示 AI 当前动作（开分身 / 跑 CLI / 操作云电脑）与实时工具流数量，点击可展开观看实时原生卡片；
/// - 内置「插话纠偏（Steer）」快捷输入栏与「停止」按钮，不中断整轮即可中途纠偏。
struct ChatLiveRunDockView: View {
    let activityPhrase: String
    let liveToolCards: [ToolCard]
    let canSteer: Bool
    let onSteer: (String) -> Void
    let onStop: () -> Void
    let onCloudTakeover: () -> Void

    @State private var showToolStream = false
    @State private var showSteerInput = false
    @State private var steerText = ""
    @State private var pulse = false

    private var activeToolCount: Int {
        liveToolCards.filter { $0.result == nil }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
            // 顶行：状态脉动点 + 实时动作短语 + 工具数展开 + 纠偏 + 停止
            HStack(spacing: OneDayMetrics.spacingS) {
                Circle()
                    .fill(Palette.primary)
                    .frame(width: 8, height: 8)
                    .scaleEffect(pulse ? 1.25 : 0.85)
                    .opacity(pulse ? 1.0 : 0.45)
                    .animation(
                        .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                        value: pulse
                    )
                    .onAppear { pulse = true }

                Text(activityPhrase)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)

                if !liveToolCards.isEmpty {
                    Button {
                        withAnimation(.snappy(duration: 0.22)) {
                            showToolStream.toggle()
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Text(activeToolCount > 0
                                 ? "进行中 \(activeToolCount)/\(liveToolCards.count)"
                                 : "已执行 \(liveToolCards.count)")
                                .font(.caption2.monospacedDigit().weight(.semibold))
                            Image(systemName: showToolStream ? "chevron.up" : "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .foregroundStyle(Palette.tintSkyInk)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Palette.tintSky, in: Capsule())
                    }
                    .buttonStyle(.odPressable)
                }

                Spacer(minLength: 4)

                if canSteer {
                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            showSteerInput.toggle()
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                                .font(.caption2)
                            Text("纠偏")
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(showSteerInput ? .white : Palette.primary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(
                            showSteerInput ? Palette.primary : Palette.primaryTint,
                            in: Capsule()
                        )
                    }
                    .buttonStyle(.odPressable)
                }

                Button(action: onStop) {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Palette.danger)
                }
                .buttonStyle(.odPressable)
                .accessibilityLabel("停止当前任务")
            }

            // 中途插话纠偏输入栏
            if showSteerInput && canSteer {
                HStack(spacing: OneDayMetrics.spacingS) {
                    TextField("中途纠偏，例如：先只看最近 3 天日志…", text: $steerText)
                        .font(.footnote)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Palette.pageBG, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Palette.hairline, lineWidth: 1)
                        )
                        .submitLabel(.send)
                        .onSubmit { submitSteer() }

                    Button("插入") { submitSteer() }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            steerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? Palette.inkMuted : Palette.primary,
                            in: Capsule()
                        )
                        .disabled(steerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // 展开的实时工具流（分身 / CLI / 云电脑原生卡片）
            if showToolStream && !liveToolCards.isEmpty {
                Divider().overlay(Palette.hairline)
                ScrollView {
                    VStack(spacing: OneDayMetrics.spacingS) {
                        ForEach(liveToolCards) { card in
                            liveCardRow(card)
                        }
                    }
                }
                .frame(maxHeight: 220)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            Palette.surface,
            in: RoundedRectangle(cornerRadius: OneDayMetrics.radiusCard, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OneDayMetrics.radiusCard, style: .continuous)
                .strokeBorder(Palette.primary.opacity(0.22), lineWidth: 1)
        )
        .shadow(color: Palette.shadowBase.opacity(0.06), radius: 10, y: 3)
        .padding(.horizontal, OneDayMetrics.spacingSM)
    }

    @ViewBuilder
    private func liveCardRow(_ card: ToolCard) -> some View {
        if let subagent = SubagentDelegationParser.parse(from: card) {
            SubagentDelegationCardView(card: subagent)
        } else if let terminal = TerminalExecutionParser.parse(from: card) {
            TerminalExecutionCardView(card: terminal)
        } else if let cloud = CloudComputerActionParser.parse(from: card) {
            CloudComputerActionCardView(card: cloud, onTakeover: onCloudTakeover)
        } else {
            HStack(spacing: OneDayMetrics.spacingS) {
                if card.result == nil {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: card.resultFailed ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(card.resultFailed ? Palette.danger : Palette.success)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                    if !card.summary.isEmpty {
                        Text(card.summary)
                            .font(.caption2)
                            .foregroundStyle(Palette.inkSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Palette.pageBG, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
    }

    private func submitSteer() {
        let trimmed = steerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        steerText = ""
        showSteerInput = false
        onSteer(trimmed)
    }
}
