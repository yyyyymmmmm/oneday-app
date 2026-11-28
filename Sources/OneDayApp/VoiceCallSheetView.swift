import OneDayCore
import OneDayDesign
import SwiftUI

/// 全双工语音电话通话面（对标旗舰级 AI 实时语音通话体验）：
/// - 端上实时语音识别（DictationController）+ 静默 1.4s 自动发送；
/// - 服务端 TTS 朗读回放（透传用户在「语音」页选择的引擎、音色与语速）；
/// - 真正支持全双工打断（Barge-In）：AI 说话时用户开口或点击打断立即停播并切回聆听。
struct VoiceCallSheetView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let agentName: String
    let agentAvatar: Image
    let isAssistantStreaming: Bool
    let activityPhrase: String?
    let latestAssistantReply: String
    let onSendMessage: (String) -> Void
    let onStopGeneration: () -> Void

    @State private var callDictation = DictationController()
    @State private var liveTranscript = ""
    @State private var isMuted = false
    @State private var callSeconds = 0
    @State private var orbPulse = false
    @State private var silenceSendTask: Task<Void, Never>?
    @State private var lastSpokenReply = ""
    @State private var statusHint: String?

    private var speechPlayer: SpeechPlayer { .shared }

    private enum CallPhase: Equatable {
        case muted
        case listening
        case thinking
        case speaking
    }

    private var phase: CallPhase {
        if isAssistantStreaming { return .thinking }
        switch speechPlayer.machine.state {
        case .playing, .requesting:
            return .speaking
        default:
            return isMuted ? .muted : .listening
        }
    }

    private var phaseTitle: String {
        switch phase {
        case .muted: return "麦克风已静音"
        case .listening: return liveTranscript.isEmpty ? "正在聆听，请直接说话…" : "识别中…"
        case .thinking: return activityPhrase ?? "正在思考…"
        case .speaking: return "正在语音回复（开口可随时打断）"
        }
    }

    private var orbColor: Color {
        switch phase {
        case .muted: return Palette.inkMuted
        case .listening: return Palette.primary
        case .thinking: return Palette.tintLavenderInk
        case .speaking: return Palette.tintGreenInk
        }
    }

    private var formattedDuration: String {
        let mins = callSeconds / 60
        let secs = callSeconds % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Palette.chatSurface,
                    orbColor.opacity(0.10),
                    Palette.settingsBG,
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 20)
                voiceOrbSection
                Spacer(minLength: 20)
                transcriptCard
                Spacer(minLength: 24)
                bottomControls
            }
            .padding(.horizontal, OneDayMetrics.pageGutter)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .onAppear {
            startVoiceCall()
        }
        .onDisappear {
            endVoiceCallCleanup()
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                callSeconds += 1
            }
        }
        .onChange(of: isAssistantStreaming) { wasStreaming, nowStreaming in
            if wasStreaming && !nowStreaming {
                speakLatestReplyIfNew()
            }
        }
        .onChange(of: speechPlayer.machine.state) { oldState, newState in
            if case .playing = oldState, case .idle = newState, !isMuted {
                // 播完后自动切回聆听
                startListeningIfAllowed()
            }
        }
        .sheet(isPresented: $callDictation.showPrep) {
            DictationPrepSheet(controller: callDictation)
        }
    }

    private var topBar: some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            agentAvatar
                .resizable()
                .scaledToFill()
                .frame(width: 36, height: 36)
                .clipShape(Circle())
                .overlay(Circle().stroke(Palette.hairline, lineWidth: 0.5))

            VStack(alignment: .leading, spacing: 2) {
                Text(agentName)
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                HStack(spacing: 6) {
                    Circle()
                        .fill(phase == .muted ? Palette.inkMuted : Palette.success)
                        .frame(width: 6, height: 6)
                    Text("全双工通话 · \(formattedDuration)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Palette.inkSecondary)
                }
            }

            Spacer()

            Button {
                Haptics.selection()
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 36, height: 36)
                    .glassEffect(.regular, in: Circle())
            }
            .buttonStyle(.odPressable)
            .accessibilityLabel("最小化并返回聊天")
        }
    }

    private var voiceOrbSection: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(orbColor.opacity(0.14))
                    .frame(width: orbPulse ? 210 : 176, height: orbPulse ? 210 : 176)
                Circle()
                    .fill(orbColor.opacity(0.24))
                    .frame(width: orbPulse ? 168 : 146, height: orbPulse ? 168 : 146)
                Circle()
                    .fill(orbColor.gradient)
                    .frame(width: 118, height: 118)
                    .shadow(color: orbColor.opacity(0.35), radius: 22, y: 8)
                Image(systemName: orbSymbol)
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
            }
            .animation(
                reduceMotion
                    ? .default
                    : .easeInOut(duration: 1.4).repeatForever(autoreverses: true),
                value: orbPulse
            )
            .onAppear { orbPulse = true }

            VStack(spacing: 6) {
                Text(phaseTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center)
                if let statusHint {
                    Text(statusHint)
                        .font(.caption)
                        .foregroundStyle(Palette.inkSecondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    private var orbSymbol: String {
        switch phase {
        case .muted: return "mic.slash.fill"
        case .listening: return "waveform"
        case .thinking: return "sparkles"
        case .speaking: return "speaker.wave.3.fill"
        }
    }

    private var transcriptCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !liveTranscript.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("你说")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Palette.primary)
                    Text(liveTranscript)
                        .font(.callout)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(3)
                }
            }

            if !latestAssistantReply.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text(agentName)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Palette.tintGreenInk)
                    Text(latestAssistantReply)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(4)
                }
            }

            if liveTranscript.isEmpty && latestAssistantReply.isEmpty {
                Text("直接开口说话即可对话，停顿约 1.4 秒自动发送；AI 回复时开口或点中间按钮可随时打断。")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Palette.surface,
            in: RoundedRectangle(cornerRadius: OneDayMetrics.radiusCard, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OneDayMetrics.radiusCard, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 1)
        )
    }

    private var bottomControls: some View {
        HStack(spacing: 28) {
            // 静音切换
            Button {
                Haptics.selection()
                toggleMute()
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: isMuted ? "mic.slash.fill" : "mic.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(isMuted ? Palette.ink : Palette.ink)
                        .frame(width: 60, height: 60)
                        .background(isMuted ? Palette.fillTertiary : Palette.surface, in: Circle())
                        .overlay(Circle().stroke(Palette.hairline, lineWidth: 1))
                    Text(isMuted ? "取消静音" : "静音")
                        .font(.caption)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            .buttonStyle(.odPressable)

            // 中间主操作：打断 / 立即发送
            Button {
                Haptics.impact(.medium)
                handlePrimaryAction()
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: primaryActionSymbol)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 68, height: 68)
                        .background(Palette.primary, in: Circle())
                        .shadow(color: Palette.primary.opacity(0.3), radius: 10, y: 4)
                    Text(primaryActionLabel)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Palette.ink)
                }
            }
            .buttonStyle(.odPressable)

            // 挂断
            Button {
                Haptics.impact(.heavy)
                endVoiceCallCleanup()
                dismiss()
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: "phone.down.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 60, height: 60)
                        .background(Palette.danger, in: Circle())
                    Text("挂断")
                        .font(.caption)
                        .foregroundStyle(Palette.danger)
                }
            }
            .buttonStyle(.odPressable)
        }
    }

    private var primaryActionSymbol: String {
        if phase == .speaking || phase == .thinking {
            return "hand.raised.fill"
        }
        return liveTranscript.isEmpty ? "waveform" : "arrow.up"
    }

    private var primaryActionLabel: String {
        if phase == .speaking || phase == .thinking {
            return "打断"
        }
        return liveTranscript.isEmpty ? "说话" : "发送"
    }

    // MARK: - 全双工状态流转

    private func startVoiceCall() {
        lastSpokenReply = latestAssistantReply
        callDictation.armPreheat()
        callDictation.onTextChange = { text, _ in
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            // 全双工 Barge-In：用户开口立即打断 AI 语音播报
            if case .playing = speechPlayer.machine.state {
                speechPlayer.stop()
            }
            liveTranscript = trimmed
            scheduleSilenceAutoSend()
        }
        callDictation.onSendRequest = {
            commitCurrentTranscript()
        }
        startListeningIfAllowed()
    }

    private func startListeningIfAllowed() {
        guard !isMuted else { return }
        if !callDictation.isRecording {
            callDictation.toggle(currentDraft: "")
        }
    }

    private func toggleMute() {
        isMuted.toggle()
        if isMuted {
            silenceSendTask?.cancel()
            if callDictation.isRecording {
                callDictation.cancel()
            }
        } else {
            startListeningIfAllowed()
        }
    }

    private func handlePrimaryAction() {
        if phase == .speaking {
            speechPlayer.stop()
            statusHint = "已打断，继续说吧"
            startListeningIfAllowed()
            return
        }
        if phase == .thinking {
            onStopGeneration()
            statusHint = "已停止生成，请重新说"
            startListeningIfAllowed()
            return
        }
        if !liveTranscript.isEmpty {
            commitCurrentTranscript()
        } else {
            isMuted = false
            startListeningIfAllowed()
        }
    }

    private func scheduleSilenceAutoSend() {
        silenceSendTask?.cancel()
        silenceSendTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1400))
            guard !Task.isCancelled else { return }
            commitCurrentTranscript()
        }
    }

    private func commitCurrentTranscript() {
        silenceSendTask?.cancel()
        let text = liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        liveTranscript = ""
        if callDictation.isRecording {
            callDictation.cancel()
        }
        statusHint = nil
        onSendMessage(text)
    }

    private func speakLatestReplyIfNew() {
        let trimmed = latestAssistantReply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != lastSpokenReply else { return }
        lastSpokenReply = trimmed
        speechPlayer.toggle(entryID: UUID(), content: trimmed, appState: appState)
    }

    private func endVoiceCallCleanup() {
        silenceSendTask?.cancel()
        if callDictation.isRecording {
            callDictation.cancel()
        }
        callDictation.disarmPreheat()
        speechPlayer.stop()
    }
}
