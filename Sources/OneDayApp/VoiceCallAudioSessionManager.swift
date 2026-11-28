import AVFAudio
import AVKit
import OneDayDesign
import SwiftUI

// MARK: - 全双工语音通话音频输出路由模型

enum VoiceAudioOutputRoute: Equatable, Sendable {
    case speaker
    case receiver
    case bluetooth(name: String)
    case wiredHeadset(name: String)

    var displayName: String {
        switch self {
        case .speaker: return "扬声器"
        case .receiver: return "听筒"
        case .bluetooth(let name): return name.isEmpty ? "蓝牙耳机" : name
        case .wiredHeadset(let name): return name.isEmpty ? "有线耳机" : name
        }
    }

    var symbolName: String {
        switch self {
        case .speaker: return "speaker.wave.3.fill"
        case .receiver: return "ear.fill"
        case .bluetooth: return "airpodspro"
        case .wiredHeadset: return "headphones"
        }
    }

    var isExternalAccessory: Bool {
        switch self {
        case .bluetooth, .wiredHeadset: return true
        case .speaker, .receiver: return false
        }
    }
}

// MARK: - 全双工语音通话音频会话与硬件 AEC 管理器

/// 统一接管全双工语音电话期间的 `AVAudioSession`：
/// 1. 启用 `.playAndRecord` + `.voiceChat`（强制开启 iOS 硬件回声消除 AEC + 自动增益 AGC + 人声聚焦），
///    彻底解决扬声器播放 AI 声音被麦克风拾取自激打断的问题；
/// 2. 暴露 `isVoiceCallActive` 标志供 `SpeechPlayer` 协调，通话期间不覆写为 `.playback`、不提前停用会话；
/// 3. 实时监听 `AVAudioSession.routeChangeNotification`，热插拔 AirPods / 蓝牙 / 有线耳机自动同步 UI；
/// 4. 支持一键切换「扬声器 ↔ 听筒」以及系统原生 `AVRoutePickerView` 蓝牙/AirPlay 路由选择；
/// 5. 内置 `EchoBargeInGuard`（防回声自激门控）：结合硬件 AEC 收敛冷却窗口 + 播报正文子串比对，
///    过滤扬声器漏音，仅在真实人声打断时才停播 AI 回复。
@MainActor
final class VoiceCallAudioSessionManager: ObservableObject {
    static let shared = VoiceCallAudioSessionManager()

    @Published private(set) var isVoiceCallActive = false
    @Published private(set) var currentRoute: VoiceAudioOutputRoute = .speaker
    @Published private(set) var prefersSpeaker = true

    private var routeObserver: NSObjectProtocol?

    // MARK: - 防回声自激打断状态（EchoBargeInGuard）
    private var aiSpeechStartedAt: Date?
    private var activeSpokenNormalized: String = ""

    /// 硬件 AEC 起播收敛冷却时间（毫秒）：刚开播 650ms 内扬声器瞬间脉冲易漏进麦克风
    private let aecConvergenceGraceSeconds: TimeInterval = 0.65

    private init() {}

    /// 进入全双工语音通话时调用：启用硬件 AEC 与蓝牙/外放支持
    func activateForVoiceCall(preferSpeaker: Bool = true) {
        self.prefersSpeaker = preferSpeaker
        self.isVoiceCallActive = true
        applyAudioSession(preferSpeaker: preferSpeaker)
        startObservingRouteChanges()
        refreshCurrentRoute()
    }

    /// 退出全双工语音通话时调用：释放路由监听并优雅归还系统音频会话
    func deactivateAfterVoiceCall() {
        isVoiceCallActive = false
        clearAISpeechContext()
        if let observer = routeObserver {
            NotificationCenter.default.removeObserver(observer)
            routeObserver = nil
        }
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: [.notifyOthersOnDeactivation]
        )
    }

    /// 一键切换「扬声器（外放）」与「听筒」
    func toggleSpeakerReceiver() {
        guard isVoiceCallActive else { return }
        prefersSpeaker.toggle()
        applyAudioSession(preferSpeaker: prefersSpeaker)
        refreshCurrentRoute()
    }

    /// 在 AI 开始播报 TTS 时记录起播时间与归一化正文，供防回声自激判定使用
    func markAISpeechStarted(text: String) {
        aiSpeechStartedAt = Date()
        activeSpokenNormalized = Self.normalizeForEchoComparison(text)
    }

    /// 在 AI 停止或播完 TTS 时清空防回声窗口
    func clearAISpeechContext() {
        aiSpeechStartedAt = nil
        activeSpokenNormalized = ""
    }

    /// 防回声自激 Barge-In 门控：
    /// 返回 `true` 表示判定为真实用户开口打断；返回 `false` 表示疑似扬声器漏音/回声，应忽略。
    func shouldAcceptBargeIn(forTranscript rawTranscript: String) -> Bool {
        let normalized = Self.normalizeForEchoComparison(rawTranscript)
        guard normalized.count >= 2 else {
            // 单字或纯标点脉冲极大概率是回声爆音
            return false
        }

        // 若当前佩戴耳机/蓝牙，硬件物理隔离良好，直接放行真实人声打断
        if currentRoute.isExternalAccessory {
            return true
        }

        // 1. 起播前 650ms 为硬件 AEC 收敛期，抑制扬声器刚出声时的瞬时漏音
        if let startedAt = aiSpeechStartedAt,
           Date().timeIntervalSince(startedAt) < aecConvergenceGraceSeconds {
            return false
        }

        // 2. 若识别文本几乎完全命中当前 AI 正在朗读的正文子串（且长度较短），判定为扬声器回声
        if !activeSpokenNormalized.isEmpty,
           normalized.count <= 16,
           activeSpokenNormalized.contains(normalized) {
            return false
        }

        return true
    }

    /// 每次准备播报 AI 语音前显式加固扬声器/蓝牙路由：
    /// 使用 `.default` 模式避免 `.voiceChat` 把扬声器音量压到极小导致用户听不到声音。
    func ensurePlaybackRoute() {
        guard isVoiceCallActive else { return }
        let session = AVAudioSession.sharedInstance()
        var options: AVAudioSession.CategoryOptions = [
            .allowBluetoothHFP,
            .allowBluetoothA2DP,
        ]
        if prefersSpeaker {
            options.insert(.defaultToSpeaker)
        }
        try? session.setCategory(.playAndRecord, mode: .default, options: options)
        try? session.setActive(true)
        let currentOutputs = session.currentRoute.outputs
        let hasExternal = currentOutputs.contains { port in
            port.portType == .bluetoothHFP
                || port.portType == .bluetoothA2DP
                || port.portType == .bluetoothLE
                || port.portType == .headphones
                || port.portType == .usbAudio
        }
        if !hasExternal {
            try? session.overrideOutputAudioPort(prefersSpeaker ? .speaker : .none)
        }
        refreshCurrentRoute()
    }

    // MARK: - 内部 AVAudioSession 调度

    private func applyAudioSession(preferSpeaker: Bool) {
        let session = AVAudioSession.sharedInstance()
        var options: AVAudioSession.CategoryOptions = [
            .allowBluetoothHFP,
            .allowBluetoothA2DP,
        ]
        if preferSpeaker {
            options.insert(.defaultToSpeaker)
        }
        // 使用 `.default` 模式保证外放响度正常（避免 `.voiceChat` 导致系统语音音量过小听不见）
        try? session.setCategory(.playAndRecord, mode: .default, options: options)
        try? session.setActive(true)

        // 当未连接外部蓝牙/耳机时，显式覆盖扬声器/听筒输出端口
        let currentOutputs = session.currentRoute.outputs
        let hasExternal = currentOutputs.contains { port in
            port.portType == .bluetoothHFP
                || port.portType == .bluetoothA2DP
                || port.portType == .bluetoothLE
                || port.portType == .headphones
                || port.portType == .usbAudio
        }
        if !hasExternal {
            try? session.overrideOutputAudioPort(preferSpeaker ? .speaker : .none)
        }
    }

    private func startObservingRouteChanges() {
        if let observer = routeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshCurrentRoute()
            }
        }
    }

    func refreshCurrentRoute() {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        guard let port = outputs.first else {
            currentRoute = prefersSpeaker ? .speaker : .receiver
            return
        }
        switch port.portType {
        case .bluetoothHFP, .bluetoothA2DP, .bluetoothLE:
            currentRoute = .bluetooth(name: port.portName)
        case .headphones, .usbAudio:
            currentRoute = .wiredHeadset(name: port.portName)
        case .builtInSpeaker:
            currentRoute = .speaker
        case .builtInReceiver:
            currentRoute = .receiver
        default:
            currentRoute = prefersSpeaker ? .speaker : .receiver
        }
    }

    private static func normalizeForEchoComparison(_ text: String) -> String {
        let lowered = text.lowercased()
        let allowed = lowered.unicodeScalars.filter { scalar in
            CharacterSet.alphanumerics.contains(scalar)
                || (scalar.value >= 0x4E00 && scalar.value <= 0x9FFF)
        }
        return String(String.UnicodeScalarView(allowed))
    }
}

// MARK: - 系统原生蓝牙 / AirPlay 音频路由选择按钮（对标 FaceTime / 微信语音）

struct VoiceCallRoutePickerButton: UIViewRepresentable {
    var tintColor: UIColor = .label
    var activeTintColor: UIColor = .systemBlue

    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.tintColor = tintColor
        picker.activeTintColor = activeTintColor
        picker.prioritizesVideoDevices = false
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        uiView.tintColor = tintColor
        uiView.activeTintColor = activeTintColor
    }
}
