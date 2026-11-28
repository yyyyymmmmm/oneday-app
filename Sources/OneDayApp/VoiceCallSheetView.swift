import AVFAudio
import OneDayCore
import OneDayDesign
import SwiftUI

// MARK: - 按句流式切分器（边生成边播报，对标豆包 / GPT 语音电话首音体验）

private enum VoiceSentenceSplitter {
    private static let terminators: Set<Character> = ["。", "！", "？", "!", "?", "\n", "；", ";"]

    /// 从累计流式文本的 `cursor` 位置起，提取所有已闭合的完整句子并推进游标
    static func extractCompleteSentences(from fullText: String, cursor: inout Int) -> [String] {
        guard fullText.count > cursor else { return [] }
        let startIdx = fullText.index(fullText.startIndex, offsetBy: cursor)
        let slice = fullText[startIdx...]
        var results: [String] = []
        var buffer = ""
        var consumed = 0

        for ch in slice {
            buffer.append(ch)
            consumed += 1
            if terminators.contains(ch) {
                let cleaned = cleanForSpeech(buffer)
                if cleaned.count >= 2 {
                    results.append(cleaned)
                }
                cursor += consumed
                consumed = 0
                buffer = ""
            }
        }
        return results
    }

    /// 流结束时刷出剩余尾句
    static func flushRemainder(from fullText: String, cursor: inout Int) -> String? {
        guard fullText.count > cursor else { return nil }
        let startIdx = fullText.index(fullText.startIndex, offsetBy: cursor)
        let rem = String(fullText[startIdx...])
        cursor = fullText.count
        let cleaned = cleanForSpeech(rem)
        return cleaned.isEmpty ? nil : cleaned
    }

    static func cleanForSpeech(_ raw: String) -> String {
        var text = raw
        // 去掉常见 Markdown 标记与代码块围栏，避免朗读出“井号/星号”
        text = text.replacingOccurrences(of: "```[\\s\\S]*?```", with: "代码片段已略过", options: .regularExpression)
        text = text.replacingOccurrences(of: "`([^`]+)`", with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\[([^\\]]+)\\]\\([^\\)]+\\)", with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: "[#*~>_]", with: "", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - 100% 有声保底：iOS 系统中文神经语音串行播报队列

@MainActor
private final class VoiceCallSpeechQueue: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var isSpeaking = false
    @Published private(set) var currentSpokenSentence = ""
    @Published private(set) var usingSystemVoiceFallback = false

    private let synthesizer = AVSpeechSynthesizer()
    private var pendingSentences: [String] = []
    private var isProcessing = false
    private var serverTTSFailedCount = 0
    private var activeServerPlayTask: Task<Void, Never>?
    private var activeAudioPlayer: AVAudioPlayer?
    private var audioPlayerDelegate: LocalAVPlayerDelegate?

    var onAllFinished: (() -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func enqueue(_ sentence: String, appState: AppState) {
        let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        pendingSentences.append(trimmed)
        if !isProcessing {
            playNext(appState: appState)
        }
    }

    func stopAll() {
        pendingSentences.removeAll()
        activeServerPlayTask?.cancel()
        activeServerPlayTask = nil
        activeAudioPlayer?.stop()
        activeAudioPlayer = nil
        audioPlayerDelegate = nil
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isProcessing = false
        isSpeaking = false
        currentSpokenSentence = ""
        VoiceCallAudioSessionManager.shared.clearAISpeechContext()
    }

    private func playNext(appState: AppState) {
        guard !pendingSentences.isEmpty else {
            isProcessing = false
            isSpeaking = false
            currentSpokenSentence = ""
            VoiceCallAudioSessionManager.shared.clearAISpeechContext()
            onAllFinished?()
            return
        }

        isProcessing = true
        isSpeaking = true
        let next = pendingSentences.removeFirst()
        currentSpokenSentence = next
        VoiceCallAudioSessionManager.shared.markAISpeechStarted(text: next)

        // 若服务端 TTS 连续失败超过 1 次，本通电话直接走 iOS 高品质神经语音保底（零等待、绝不静音）
        if serverTTSFailedCount >= 1 || appState.config == nil {
            usingSystemVoiceFallback = true
            speakLocally(next, appState: appState)
            return
        }

        activeServerPlayTask?.cancel()
        activeServerPlayTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let response = try await appState.performAdmin { client, config in
                    try await client.speak(config: config, text: next)
                }
                guard !Task.isCancelled else { return }
                // speak 出参是 SpeakResponse（data_url 内嵌
                // base64），播放字节走 Core 既有 audioData
                // 解码（与 SpeechPlayer 同源）；解不出按失
                // 败抛入 catch 的系统语音兜底链
                guard let data = response.audioData else {
                    throw NSError(domain: "VoiceCall", code: -2)
                }
                let player = try AVAudioPlayer(data: data)
                let delegate = LocalAVPlayerDelegate { [weak self] in
                    Task { @MainActor in
                        self?.activeAudioPlayer = nil
                        self?.audioPlayerDelegate = nil
                        self?.playNext(appState: appState)
                    }
                }
                player.delegate = delegate
                self.activeAudioPlayer = player
                self.audioPlayerDelegate = delegate
                self.usingSystemVoiceFallback = false
                if !player.play() {
                    throw NSError(domain: "VoiceCall", code: -1)
                }
            } catch {
                guard !Task.isCancelled else { return }
                self.serverTTSFailedCount += 1
                self.usingSystemVoiceFallback = true
                self.speakLocally(next, appState: appState)
            }
        }
    }

    private func speakLocally(_ text: String, appState: AppState) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
            ?? AVSpeechSynthesisVoice(language: Locale.current.identifier)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.06
        utterance.pitchMultiplier = 1.0
        utterance.postUtteranceDelay = 0.08
        self.pendingAppStateForSystemDelegate = appState
        synthesizer.speak(utterance)
    }

    private weak var pendingAppStateForSystemDelegate: AppState?

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard self.isProcessing else { return }
            if let appState = self.pendingAppStateForSystemDelegate {
                self.playNext(appState: appState)
            } else {
                self.isProcessing = false
                self.isSpeaking = false
                self.onAllFinished?()
            }
        }
    }
}

private final class LocalAVPlayerDelegate: NSObject, AVAudioPlayerDelegate {
    private let onFinish: () -> Void
    init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { onFinish() }
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) { onFinish() }
}

// MARK: - 豆包 / ChatGPT 级极简实时语音电话

struct VoiceCallSheetView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let agentName: String
    let agentAvatar: Image
    let isAssistantStreaming: Bool
    let activityPhrase: String?
    let streamingAssistantText: String
    let latestAssistantReply: String
    let onSendMessage: (String) -> Void
    let onStopGeneration: () -> Void

    @State private var callDictation = DictationController()
    @StateObject private var audioManager = VoiceCallAudioSessionManager.shared
    @StateObject private var speechQueue = VoiceCallSpeechQueue()

    @State private var liveTranscript = ""
    @State private var isMuted = false
    @State private var callSeconds = 0
    @State private var orbPulse = false
    @State private var silenceSendTask: Task<Void, Never>?
    @State private var spokenCursor = 0
    @State private var lastSettledReply = ""
    @State private var micPermissionDenied = false

    private enum CallPhase: Equatable {
        case muted
        case listening
        case thinking
        case speaking
    }

    private var phase: CallPhase {
        if speechQueue.isSpeaking { return .speaking }
        if isAssistantStreaming { return .thinking }
        return isMuted ? .muted : .listening
    }

    private var humanStatusText: String {
        if micPermissionDenied { return "需要开启麦克风权限才能通话" }
        switch phase {
        case .muted: return "已静音"
        case .listening: return liveTranscript.isEmpty ? "我在听，请直接说…" : "正在听你说…"
        case .thinking: return "正在想…"
        case .speaking: return "正在说 · 随时可以插话打断"
        }
    }

    private var orbGradientColors: [Color] {
        switch phase {
        case .muted:
            return [Color.gray.opacity(0.65), Color.gray.opacity(0.45)]
        case .listening:
            return [Color(red: 0.22, green: 0.52, blue: 0.98), Color(red: 0.42, green: 0.36, blue: 0.96)]
        case .thinking:
            return [Color(red: 0.56, green: 0.36, blue: 0.96), Color(red: 0.85, green: 0.40, blue: 0.72)]
        case .speaking:
            return [Color(red: 0.14, green: 0.76, blue: 0.56), Color(red: 0.16, green: 0.58, blue: 0.94)]
        }
    }

    private var formattedDuration: String {
        String(format: "%02d:%02d", callSeconds / 60, callSeconds % 60)
    }

    var body: some View {
        ZStack {
            // 沉浸式深色渐变背景（对标豆包 / GPT 语音通话）
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.07, blue: 0.11),
                    orbGradientColors[0].opacity(0.24),
                    Color(red: 0.04, green: 0.05, blue: 0.08),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 24)
                voiceOrb
                Spacer(minLength: 24)
                subtitleArea
                if micPermissionDenied {
                    permissionFixButton
                        .padding(.top, 12)
                }
                Spacer(minLength: 28)
                bottomControls
            }
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .padding(.bottom, 34)
        }
        .preferredColorScheme(.dark)
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
        // 流式每吐出完整一句，立即进入播报队列（边想边说！）
        .onChange(of: streamingAssistantText) { _, newText in
            guard isAssistantStreaming, !newText.isEmpty else { return }
            let sentences = VoiceSentenceSplitter.extractCompleteSentences(from: newText, cursor: &spokenCursor)
            for s in sentences {
                speechQueue.enqueue(s, appState: appState)
            }
        }
        // 生成结束时刷出最后半句；若整段未走流式（直接落盘），兜底整段按句切分播报
        .onChange(of: isAssistantStreaming) { wasStreaming, nowStreaming in
            if !wasStreaming && nowStreaming {
                spokenCursor = 0
            } else if wasStreaming && !nowStreaming {
                let source = !streamingAssistantText.isEmpty ? streamingAssistantText : latestAssistantReply
                if spokenCursor == 0 && !source.isEmpty && source != lastSettledReply {
                    var c = 0
                    let parts = VoiceSentenceSplitter.extractCompleteSentences(from: source, cursor: &c)
                    for s in parts { speechQueue.enqueue(s, appState: appState) }
                    if let tail = VoiceSentenceSplitter.flushRemainder(from: source, cursor: &c) {
                        speechQueue.enqueue(tail, appState: appState)
                    }
                    lastSettledReply = source
                } else if let rem = VoiceSentenceSplitter.flushRemainder(from: source, cursor: &spokenCursor) {
                    speechQueue.enqueue(rem, appState: appState)
                    lastSettledReply = source
                }
            }
        }
        .sheet(isPresented: $callDictation.showPrep) {
            DictationPrepSheet(controller: callDictation)
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            agentAvatar
                .resizable()
                .scaledToFill()
                .frame(width: 38, height: 38)
                .clipShape(Circle())
                .overlay(Circle().stroke(.white.opacity(0.22), lineWidth: 1))

            VStack(alignment: .leading, spacing: 2) {
                Text(agentName)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(formattedDuration)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.65))
            }

            Spacer()

            // 系统蓝牙/AirPods 路由图标（零文字干扰）
            VoiceCallRoutePickerButton(tintColor: .white, activeTintColor: .systemTeal)
                .frame(width: 36, height: 36)
                .background(.white.opacity(0.12), in: Circle())

            Button {
                Haptics.selection()
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.white.opacity(0.12), in: Circle())
            }
            .buttonStyle(.odPressable)
            .accessibilityLabel("返回聊天")
        }
    }

    private var voiceOrb: some View {
        VStack(spacing: 26) {
            Button {
                Haptics.impact(.light)
                handleOrbTap()
            } label: {
                ZStack {
                    Circle()
                        .fill(orbGradientColors[0].opacity(0.18))
                        .frame(width: orbPulse ? 236 : 194, height: orbPulse ? 236 : 194)
                        .blur(radius: 6)
                    Circle()
                        .fill(orbGradientColors[1].opacity(0.26))
                        .frame(width: orbPulse ? 186 : 158, height: orbPulse ? 186 : 158)
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: orbGradientColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 132, height: 132)
                        .shadow(color: orbGradientColors[0].opacity(0.55), radius: 28, y: 8)

                    Image(systemName: orbSymbol)
                        .font(.system(size: 40, weight: .medium))
                        .foregroundStyle(.white)
                        .contentTransition(.symbolEffect(.replace))
                }
                .animation(
                    reduceMotion
                        ? .default
                        : .easeInOut(duration: phase == .speaking ? 0.85 : 1.5).repeatForever(autoreverses: true),
                    value: orbPulse
                )
            }
            .buttonStyle(.plain)
            .onAppear { orbPulse = true }

            Text(humanStatusText)
                .font(.body.weight(.medium))
                .foregroundStyle(.white.opacity(0.92))
                .multilineTextAlignment(.center)
        }
    }

    private var orbSymbol: String {
        switch phase {
        case .muted: return "mic.slash.fill"
        case .listening: return "waveform"
        case .thinking: return "sparkles"
        case .speaking: return "waveform.circle.fill"
        }
    }

    private var subtitleArea: some View {
        VStack(spacing: 8) {
            if !liveTranscript.isEmpty {
                Text(liveTranscript)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            } else if !speechQueue.currentSpokenSentence.isEmpty {
                Text(speechQueue.currentSpokenSentence)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            } else if isAssistantStreaming && !streamingAssistantText.isEmpty {
                Text(String(streamingAssistantText.suffix(80)))
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.72))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            } else {
                Text("说话停顿约 1.2 秒自动发送，轻点光球随时打断")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.48))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(minHeight: 56)
        .padding(.horizontal, 8)
    }

    private var permissionFixButton: some View {
        Button {
            #if canImport(UIKit)
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
            #endif
        } label: {
            Text("去系统设置开启麦克风与语音识别")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(Color.blue, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var bottomControls: some View {
        HStack(spacing: 34) {
            // 1. 扬声器 / 听筒
            Button {
                Haptics.selection()
                audioManager.toggleSpeakerReceiver()
            } label: {
                VStack(spacing: 8) {
                    Image(systemName: audioManager.currentRoute.symbolName)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(audioManager.prefersSpeaker ? .black : .white)
                        .frame(width: 62, height: 62)
                        .background(audioManager.prefersSpeaker ? Color.white : Color.white.opacity(0.16), in: Circle())
                    Text(audioManager.currentRoute.displayName)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.78))
                }
            }
            .buttonStyle(.odPressable)

            // 2. 静音
            Button {
                Haptics.selection()
                toggleMute()
            } label: {
                VStack(spacing: 8) {
                    Image(systemName: isMuted ? "mic.slash.fill" : "mic.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(isMuted ? .black : .white)
                        .frame(width: 62, height: 62)
                        .background(isMuted ? Color.white : Color.white.opacity(0.16), in: Circle())
                    Text(isMuted ? "已静音" : "静音")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.78))
                }
            }
            .buttonStyle(.odPressable)

            // 3. 挂断
            Button {
                Haptics.impact(.heavy)
                endVoiceCallCleanup()
                dismiss()
            } label: {
                VStack(spacing: 8) {
                    Image(systemName: "phone.down.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 62, height: 62)
                        .background(Color.red, in: Circle())
                    Text("挂断")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.78))
                }
            }
            .buttonStyle(.odPressable)
        }
    }

    // MARK: - 通话控制逻辑

    private func startVoiceCall() {
        lastSettledReply = latestAssistantReply
        spokenCursor = 0
        audioManager.activateForVoiceCall(preferSpeaker: true)

        speechQueue.onAllFinished = { [self] in
            if !isMuted && !isAssistantStreaming {
                startListeningIfAllowed()
            }
        }

        callDictation.armPreheat()
        callDictation.onTextChange = { text, _ in
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            if speechQueue.isSpeaking {
                guard audioManager.shouldAcceptBargeIn(forTranscript: trimmed) else {
                    return
                }
                speechQueue.stopAll()
            }
            liveTranscript = trimmed
            scheduleSilenceAutoSend()
        }
        callDictation.onSendRequest = {
            commitCurrentTranscript()
        }

        // 先检查麦克风权限，避免静默失败
        AVAudioApplication.requestRecordPermission { granted in
            Task { @MainActor in
                micPermissionDenied = !granted
                if granted {
                    startListeningIfAllowed()
                }
            }
        }
    }

    private func startListeningIfAllowed() {
        guard !isMuted, !micPermissionDenied else { return }
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

    private func handleOrbTap() {
        if speechQueue.isSpeaking {
            speechQueue.stopAll()
            startListeningIfAllowed()
            return
        }
        if isAssistantStreaming {
            onStopGeneration()
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
            try? await Task.sleep(for: .milliseconds(1200))
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
        spokenCursor = 0
        onSendMessage(text)
    }

    private func endVoiceCallCleanup() {
        silenceSendTask?.cancel()
        if callDictation.isRecording {
            callDictation.cancel()
        }
        callDictation.disarmPreheat()
        speechQueue.stopAll()
        audioManager.deactivateAfterVoiceCall()
    }
}
