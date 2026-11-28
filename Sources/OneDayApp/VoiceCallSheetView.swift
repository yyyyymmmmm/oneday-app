import AudioToolbox
import AVFAudio
import OneDayCore
import OneDayDesign
import Speech
import SwiftUI

// MARK: - 通话音效提示音（接通 / 发送 / 挂断 / 异常，对齐豆包 / 微信语音反馈）

private enum VoiceCallEarcon {
    static func playConnected() { AudioServicesPlaySystemSound(1113) }
    static func playMessageSent() { AudioServicesPlaySystemSound(1114) }
    static func playEnded() { AudioServicesPlaySystemSound(1117) }
    static func playError() { AudioServicesPlaySystemSound(1053) }
}

// MARK: - 按句流式切分器（边生成边播报，降低首音延迟）

private enum VoiceSentenceSplitter {
    private static let terminators: Set<Character> = ["。", "！", "？", "!", "?", "\n", "；", ";"]

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
        text = text.replacingOccurrences(of: "```[\\s\\S]*?```", with: "代码片段已略过", options: .regularExpression)
        text = text.replacingOccurrences(of: "`([^`]+)`", with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\[([^\\]]+)\\]\\([^\\)]+\\)", with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: "[#*~>_]", with: "", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - 实时通话字幕条目

private struct VoiceCallTranscriptLine: Identifiable, Equatable {
    let id = UUID()
    let isUser: Bool
    var text: String
}

// MARK: - 100% 有声保底：服务端 TTS + iOS 中文系统语音串行队列

@MainActor
private final class VoiceCallSpeechQueue: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var isSpeaking = false
    @Published private(set) var currentSpokenSentence = ""
    @Published private(set) var lastAudioNotice: String?

    private let synthesizer = AVSpeechSynthesizer()
    private var pendingSentences: [String] = []
    private var isProcessing = false
    private var serverTTSFailedCount = 0
    private var activeServerPlayTask: Task<Void, Never>?
    private var activeAudioPlayer: AVAudioPlayer?
    private var audioPlayerDelegate: LocalAVPlayerDelegate?
    private weak var pendingAppState: AppState?

    var onWillStartSpeaking: (() -> Void)?
    var onAllFinished: (() -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func enqueue(_ sentence: String, appState: AppState, forceLocal: Bool = false) {
        let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        pendingAppState = appState
        pendingSentences.append(trimmed)
        if !isProcessing {
            playNext(appState: appState, forceLocal: forceLocal)
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

    private func playNext(appState: AppState, forceLocal: Bool = false) {
        guard !pendingSentences.isEmpty else {
            isProcessing = false
            isSpeaking = false
            currentSpokenSentence = ""
            VoiceCallAudioSessionManager.shared.clearAISpeechContext()
            onAllFinished?()
            return
        }

        // 播报前先通知通话页暂停外放录音（防止 AVAudioEngine 抢占导致 AVSpeechSynthesizer 静音），
        // 再显式加固扬声器路由，确保 100% 有声
        onWillStartSpeaking?()
        VoiceCallAudioSessionManager.shared.ensurePlaybackRoute()

        isProcessing = true
        isSpeaking = true
        let next = pendingSentences.removeFirst()
        currentSpokenSentence = next
        VoiceCallAudioSessionManager.shared.markAISpeechStarted(text: next)

        if forceLocal || serverTTSFailedCount >= 1 || appState.config == nil {
            speakLocally(next, appState: appState)
            return
        }

        activeServerPlayTask?.cancel()
        activeServerPlayTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let data = try await appState.performAdmin { client, config in
                    try await client.speak(config: config, text: next)
                }
                guard !Task.isCancelled else { return }
                VoiceCallAudioSessionManager.shared.ensurePlaybackRoute()
                let player = try AVAudioPlayer(data: data)
                player.volume = 1.0
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
                self.lastAudioNotice = nil
                if !player.play() {
                    throw NSError(domain: "VoiceCall", code: -1)
                }
            } catch {
                guard !Task.isCancelled else { return }
                self.serverTTSFailedCount += 1
                self.lastAudioNotice = "已自动切换系统语音播报"
                self.speakLocally(next, appState: appState)
            }
        }
    }

    private func speakLocally(_ text: String, appState: AppState) {
        VoiceCallAudioSessionManager.shared.ensurePlaybackRoute()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
            ?? AVSpeechSynthesisVoice(language: Locale.current.identifier)
        utterance.volume = 1.0
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.04
        utterance.pitchMultiplier = 1.0
        utterance.postUtteranceDelay = 0.06
        pendingAppState = appState
        synthesizer.speak(utterance)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard self.isProcessing else { return }
            if let appState = self.pendingAppState {
                self.playNext(appState: appState)
            } else {
                self.isProcessing = false
                self.isSpeaking = false
                self.onAllFinished?()
            }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isProcessing = false
            self.isSpeaking = false
        }
    }
}

private final class LocalAVPlayerDelegate: NSObject, AVAudioPlayerDelegate {
    private let onFinish: () -> Void
    init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { onFinish() }
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) { onFinish() }
}

// MARK: - 豆包 / ChatGPT 级实时语音电话（带实时滚动文字 + 音效 + 权限明确诊断 + 100% 有声保底）

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
    @State private var callTranscriptLines: [VoiceCallTranscriptLine] = []
    @State private var showTranscriptPanel = true
    @State private var isMuted = false
    @State private var callSeconds = 0
    @State private var orbPulse = false
    @State private var silenceSendTask: Task<Void, Never>?
    @State private var spokenCursor = 0
    @State private var lastSettledReply = ""

    @State private var micPermissionIssue: String?
    @State private var speechPermissionIssue: String?

    private enum CallPhase: Equatable {
        case permissionBlocked
        case muted
        case listening
        case thinking
        case speaking
    }

    private var hasPermissionBlocker: Bool {
        micPermissionIssue != nil || speechPermissionIssue != nil
    }

    private var phase: CallPhase {
        if hasPermissionBlocker { return .permissionBlocked }
        if speechQueue.isSpeaking { return .speaking }
        if isAssistantStreaming { return .thinking }
        return isMuted ? .muted : .listening
    }

    private var humanStatusText: String {
        if let micErr = micPermissionIssue { return micErr }
        if let spErr = speechPermissionIssue { return spErr }
        switch phase {
        case .permissionBlocked: return "请先开启权限"
        case .muted: return "已静音"
        case .listening:
            if !liveTranscript.isEmpty { return "正在听你说…" }
            return callDictation.isRecording ? "我在听，请直接说…" : "准备收音中…"
        case .thinking: return "正在想…"
        case .speaking: return "正在说 · 轻点光球可打断"
        }
    }

    private var orbGradientColors: [Color] {
        switch phase {
        case .permissionBlocked:
            return [Color.orange, Color.red.opacity(0.85)]
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
                Spacer(minLength: 14)
                voiceOrb
                if hasPermissionBlocker {
                    permissionFixCard
                        .padding(.top, 14)
                }
                if showTranscriptPanel {
                    liveTranscriptFeed
                        .padding(.top, 16)
                } else {
                    Spacer(minLength: 24)
                }
                Spacer(minLength: 16)
                bottomControls
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 30)
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
        .onChange(of: streamingAssistantText) { _, newText in
            guard isAssistantStreaming, !newText.isEmpty else { return }
            let sentences = VoiceSentenceSplitter.extractCompleteSentences(from: newText, cursor: &spokenCursor)
            for s in sentences {
                speechQueue.enqueue(s, appState: appState)
            }
        }
        .onChange(of: isAssistantStreaming) { wasStreaming, nowStreaming in
            if !wasStreaming && nowStreaming {
                spokenCursor = 0
            } else if wasStreaming && !nowStreaming {
                let source = !streamingAssistantText.isEmpty ? streamingAssistantText : latestAssistantReply
                if !source.isEmpty && source != lastSettledReply {
                    callTranscriptLines.append(VoiceCallTranscriptLine(isUser: false, text: source))
                    if spokenCursor == 0 {
                        var c = 0
                        let parts = VoiceSentenceSplitter.extractCompleteSentences(from: source, cursor: &c)
                        for s in parts { speechQueue.enqueue(s, appState: appState) }
                        if let tail = VoiceSentenceSplitter.flushRemainder(from: source, cursor: &c) {
                            speechQueue.enqueue(tail, appState: appState)
                        }
                    } else if let rem = VoiceSentenceSplitter.flushRemainder(from: source, cursor: &spokenCursor) {
                        speechQueue.enqueue(rem, appState: appState)
                    }
                    lastSettledReply = source
                }
            }
        }
        .sheet(isPresented: $callDictation.showPrep) {
            DictationPrepSheet(controller: callDictation)
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            agentAvatar
                .resizable()
                .scaledToFill()
                .frame(width: 36, height: 36)
                .clipShape(Circle())
                .overlay(Circle().stroke(.white.opacity(0.22), lineWidth: 1))

            VStack(alignment: .leading, spacing: 2) {
                Text(agentName)
                    .font(.headline)
                    .foregroundStyle(.white)
                HStack(spacing: 6) {
                    Text(formattedDuration)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.65))
                    if let note = speechQueue.lastAudioNotice {
                        Text("· \(note)")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            Button {
                Haptics.selection()
                withAnimation(.snappy(duration: 0.2)) {
                    showTranscriptPanel.toggle()
                }
            } label: {
                Text(showTranscriptPanel ? "隐藏字幕" : "显示字幕")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.white.opacity(0.14), in: Capsule())
            }
            .buttonStyle(.plain)

            VoiceCallRoutePickerButton(tintColor: .white, activeTintColor: .systemTeal)
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.12), in: Circle())

            Button {
                Haptics.selection()
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(.white.opacity(0.12), in: Circle())
            }
            .buttonStyle(.odPressable)
            .accessibilityLabel("返回聊天")
        }
    }

    private var voiceOrb: some View {
        VStack(spacing: 16) {
            Button {
                Haptics.impact(.light)
                handleOrbTap()
            } label: {
                ZStack {
                    Circle()
                        .fill(orbGradientColors[0].opacity(0.18))
                        .frame(width: orbPulse ? 176 : 148, height: orbPulse ? 176 : 148)
                        .blur(radius: 5)
                    Circle()
                        .fill(orbGradientColors[1].opacity(0.28))
                        .frame(width: orbPulse ? 138 : 118, height: orbPulse ? 138 : 118)
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: orbGradientColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 102, height: 102)
                        .shadow(color: orbGradientColors[0].opacity(0.55), radius: 22, y: 6)

                    Image(systemName: orbSymbol)
                        .font(.system(size: 32, weight: .medium))
                        .foregroundStyle(.white)
                        .contentTransition(.symbolEffect(.replace))
                }
                .animation(
                    reduceMotion
                        ? .default
                        : .easeInOut(duration: phase == .speaking ? 0.8 : 1.4).repeatForever(autoreverses: true),
                    value: orbPulse
                )
            }
            .buttonStyle(.plain)
            .onAppear { orbPulse = true }

            Text(humanStatusText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.94))
                .multilineTextAlignment(.center)
        }
    }

    private var orbSymbol: String {
        switch phase {
        case .permissionBlocked: return "exclamationmark.triangle.fill"
        case .muted: return "mic.slash.fill"
        case .listening: return "waveform"
        case .thinking: return "sparkles"
        case .speaking: return "speaker.wave.3.fill"
        }
    }

    /// 实时滚动对话字幕面板（对齐豆包/GPT 实时文字字幕体验）
    private var liveTranscriptFeed: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if callTranscriptLines.isEmpty && liveTranscript.isEmpty && streamingAssistantText.isEmpty {
                        Text("已接通，直接开口说话即可看到实时文字；停顿约 1.2 秒自动发送，AI 回复会实时出字并朗读。")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.55))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .multilineTextAlignment(.center)
                            .padding(.vertical, 20)
                    }

                    ForEach(callTranscriptLines) { line in
                        transcriptRow(isUser: line.isUser, text: line.text, isLive: false)
                    }

                    if !liveTranscript.isEmpty {
                        transcriptRow(isUser: true, text: liveTranscript, isLive: true)
                            .id("live-user")
                    }

                    if isAssistantStreaming && !streamingAssistantText.isEmpty {
                        transcriptRow(isUser: false, text: streamingAssistantText, isLive: true)
                            .id("live-ai")
                    }

                    Color.clear.frame(height: 1).id("transcript-bottom")
                }
                .padding(14)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 160, maxHeight: 260)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 0.75)
            )
            .onChange(of: liveTranscript) { _, _ in
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo("transcript-bottom", anchor: .bottom)
                }
            }
            .onChange(of: streamingAssistantText) { _, _ in
                proxy.scrollTo("transcript-bottom", anchor: .bottom)
            }
            .onChange(of: callTranscriptLines.count) { _, _ in
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo("transcript-bottom", anchor: .bottom)
                }
            }
        }
    }

    private func transcriptRow(isUser: Bool, text: String, isLive: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(isUser ? "你" : agentName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isUser ? Color.cyan : Color.green)
                if isLive {
                    Text("实时")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.white.opacity(0.16), in: Capsule())
                }
            }
            Text(text)
                .font(.footnote)
                .foregroundStyle(.white.opacity(isLive ? 0.98 : 0.82))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var permissionFixCard: some View {
        VStack(spacing: 8) {
            Text("当前无法收音：请在 iPhone「设置 → OneDay」中同时打开「麦克风」和「语音识别」权限。")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
            Button {
                #if canImport(UIKit)
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
                #endif
            } label: {
                Text("去系统设置开启权限")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.blue, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color.red.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var bottomControls: some View {
        HStack(spacing: 34) {
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

            Button {
                Haptics.impact(.heavy)
                VoiceCallEarcon.playEnded()
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

    // MARK: - 通话控制与权限体检

    private func startVoiceCall() {
        lastSettledReply = latestAssistantReply
        spokenCursor = 0
        audioManager.activateForVoiceCall(preferSpeaker: true)

        // 播报期间暂停外放录音，彻底避免 AVAudioEngine 压制系统语音导致无声；播完自动恢复收音
        speechQueue.onWillStartSpeaking = { [self] in
            if !audioManager.currentRoute.isExternalAccessory, callDictation.isRecording {
                callDictation.cancel()
            }
        }
        speechQueue.onAllFinished = { [self] in
            if !isMuted && !isAssistantStreaming && !hasPermissionBlocker {
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

        // 同时核查麦克风权限 + 语音识别权限，任何一项缺失立即提示并响异常音
        AVAudioApplication.requestRecordPermission { micGranted in
            SFSpeechRecognizer.requestAuthorization { speechStatus in
                Task { @MainActor in
                    micPermissionIssue = micGranted ? nil : "麦克风权限未开启"
                    speechPermissionIssue = (speechStatus == .authorized) ? nil : "语音识别权限未开启"
                    if micGranted && speechStatus == .authorized {
                        VoiceCallEarcon.playConnected()
                        // 接通即播报一句简短问候，既像真人接起，又立即验证扬声器有声
                        speechQueue.enqueue("已接通，我在听。", appState: appState, forceLocal: true)
                    } else {
                        VoiceCallEarcon.playError()
                    }
                }
            }
        }
    }

    private func startListeningIfAllowed() {
        guard !isMuted, !hasPermissionBlocker, !speechQueue.isSpeaking else { return }
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
        callTranscriptLines.append(VoiceCallTranscriptLine(isUser: true, text: text))
        if callDictation.isRecording {
            callDictation.cancel()
        }
        spokenCursor = 0
        VoiceCallEarcon.playMessageSent()
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
