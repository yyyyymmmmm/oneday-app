import OneDayCore
import OneDayDesign
import SwiftUI

/// 运行中实时活动、审批、澄清与纠偏舱（对标 Claude Code / Manus / OpenAI Operator）：
/// - 只要当前对话有在飞任务，就在输入栏上方呈现紧凑浮卡；
/// - 实时展示 AI 当前动作（开分身 / 跑 CLI / 操作云电脑）与实时工具流数量，点击可展开观看实时原生卡片；
/// - 当服务端下发 `approval.request` 或 `clarify.request` 时，就地呈现原生审批/澄清交互区，无需弹窗打断；
/// - 内置「插话纠偏（Steer）」快捷输入栏与「停止」按钮，不中断整轮即可中途纠偏。
struct ChatLiveRunDockView: View {
    let activityPhrase: String
    let liveToolCards: [ToolCard]
    let canSteer: Bool
    let pendingApproval: RunApprovalPrompt?
    let pendingClarify: RunClarifyPrompt?
    let onSteer: (String) -> Void
    let onRespondApproval: (RunApprovalPrompt, String) -> Void
    let onRespondClarify: (RunClarifyPrompt, String) -> Void
    let onStop: () -> Void
    let onCloudTakeover: () -> Void

    @State private var showToolStream = false
    @State private var showSteerInput = false
    @State private var steerText = ""
    @State private var clarifyInput = ""
    @State private var pulse = false

    private var activeToolCount: Int {
        liveToolCards.filter { $0.result == nil }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
            // 顶行：状态脉动点 + 实时动作短语 + 工具数展开 + 纠偏 + 停止
            HStack(spacing: OneDayMetrics.spacingS) {
                Circle()
                    .fill(pendingApproval != nil || pendingClarify != nil ? Palette.warning : Palette.primary)
                    .frame(width: 8, height: 8)
                    .scaleEffect(pulse ? 1.25 : 0.85)
                    .opacity(pulse ? 1.0 : 0.45)
                    .animation(
                        .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                        value: pulse
                    )
                    .onAppear { pulse = true }

                Text(statusHeadline)
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

                if canSteer && pendingApproval == nil && pendingClarify == nil {
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

            // 运行中实时审批卡片（POST /v1/runs/{id}/approval）
            if let approval = pendingApproval {
                liveApprovalCard(approval)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // 运行中多选澄清卡片（POST /v1/runs/{id}/clarify）
            if let clarify = pendingClarify {
                liveClarifyCard(clarify)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // 中途插话纠偏输入栏
            if showSteerInput && canSteer && pendingApproval == nil && pendingClarify == nil {
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
                .strokeBorder(
                    (pendingApproval != nil || pendingClarify != nil)
                        ? Palette.warning.opacity(0.45)
                        : Palette.primary.opacity(0.22),
                    lineWidth: 1
                )
        )
        .shadow(color: Palette.shadowBase.opacity(0.06), radius: 10, y: 3)
        .padding(.horizontal, OneDayMetrics.spacingSM)
    }

    private var statusHeadline: String {
        if pendingApproval != nil { return "等待你确认高危操作" }
        if pendingClarify != nil { return "Hermes 需要你做个选择" }
        return activityPhrase
    }

    @ViewBuilder
    private func liveApprovalCard(_ approval: RunApprovalPrompt) -> some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
            Divider().overlay(Palette.hairline)
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "shield.lefthalf.filled.badge.checkmark")
                    .font(.subheadline)
                    .foregroundStyle(Palette.warning)
                Text(approval.description)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !approval.command.isEmpty {
                Text(approval.command)
                    .font(.caption.monospaced())
                    .foregroundStyle(Palette.ink)
                    .lineLimit(3)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.pageBG, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            HStack(spacing: OneDayMetrics.spacingS) {
                if approval.choices.contains("once") {
                    Button("仅本次允许") {
                        onRespondApproval(approval, "once")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(Palette.primary, in: Capsule())
                    .buttonStyle(.odPressable)
                }
                if approval.choices.contains("session") {
                    Button("本会话允许") {
                        onRespondApproval(approval, "session")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.tintSkyInk)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(Palette.tintSky, in: Capsule())
                    .buttonStyle(.odPressable)
                }
                Spacer(minLength: 0)
                Button("拒绝") {
                    onRespondApproval(approval, "deny")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.danger)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(Palette.danger.opacity(0.12), in: Capsule())
                .buttonStyle(.odPressable)
            }
        }
    }

    @ViewBuilder
    private func liveClarifyCard(_ clarify: RunClarifyPrompt) -> some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
            Divider().overlay(Palette.hairline)
            Text(clarify.question)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)

            if !clarify.options.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: OneDayMetrics.spacingS) {
                        ForEach(clarify.options, id: \.self) { option in
                            Button(option) {
                                onRespondClarify(clarify, option)
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Palette.primary)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .background(Palette.primaryTint, in: Capsule())
                            .buttonStyle(.odPressable)
                        }
                    }
                }
            }

            HStack(spacing: OneDayMetrics.spacingS) {
                TextField("或输入自定义答复…", text: $clarifyInput)
                    .font(.footnote)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Palette.pageBG, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Palette.hairline, lineWidth: 1)
                    )
                    .submitLabel(.send)
                    .onSubmit { submitClarify(clarify) }

                Button("回复") { submitClarify(clarify) }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        clarifyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? Palette.inkMuted : Palette.primary,
                        in: Capsule()
                    )
                    .disabled(clarifyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
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

    private func submitClarify(_ clarify: RunClarifyPrompt) {
        let trimmed = clarifyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        clarifyInput = ""
        onRespondClarify(clarify, trimmed)
    }
}
