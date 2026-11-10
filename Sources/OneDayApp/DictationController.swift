import AVFoundation
import Observation
import OneDayCore
import os
import Speech
import UIKit

/// 语音输入控制器（0.36.6，DESIGN-V4 §71；规格
/// voice-input-spec-20261110.md）：端上路线唯一实现
/// ——iOS 26 SpeechAnalyzer＋SpeechTranscriber（回退
/// DictationTranscriber），录音只在本机处理、不出
/// 手机；服务端无转写端点，此路不通也不许走。
/// 纯逻辑（会话合并/电平/计时/相位守卫）在 OneDayCore
/// 的 Dictation.swift，本类只做引擎与系统 API 接线。
/// 交互定版：点按切换、流式上屏（未定稿灰字整段替
/// 换）、落框可改、不自动发送；单次上限 5 分钟。
@MainActor
@Observable
final class DictationController {

    // MARK: - 可观察状态（视图只读这些）

    private(set) var phase: DictationPhase = .idle
    /// 录音中文本视图应显示的全文（草稿＋识别段）
    private(set) var displayText: String = ""
    /// displayText 尾部未定稿段字数（渲染层染灰用）
    private(set) var volatileLength: Int = 0
    /// 9 根波形的当前采样（真实电平驱动，禁假动画）
    private(set) var waveformBars: [Double] =
        Array(repeating: 0, count: DictationWaveform.barCount)
    /// Reduce Motion 时的单条电平（0...1）
    private(set) var level: Double = 0
    private(set) var elapsedSeconds: Int = 0
    /// 计时进入 4:30 警示区
    var isTimingWarning: Bool {
        DictationTiming.isWarning(elapsedSeconds: elapsedSeconds)
    }
    /// 连续 10 秒无声提示（只提示、不停录）
    private(set) var showSilenceHint = false
    /// 语言模型资产下载进度（准备中相位，0...1）
    private(set) var assetProgress: Double = 0
    private(set) var failure: DictationFailure?
    /// 非失败类提示行（如到限自动落稿），数秒后自清
    private(set) var notice: String?
    /// 权限预备页（问前先讲用途，续编 S1–S4）
    var showPrep = false
    /// 识别语言（预备页选择，存本地偏好）
    var language: DictationLanguage {
        didSet {
            defaults.set(language.rawValue, forKey: Self.languageKey)
        }
    }
    /// 本次是否走了回退引擎（DictationTranscriber）
    private(set) var usedFallbackEngine = false

    /// 录音面是否应占住发送舱（准备中/录音中/收尾）
    var isActive: Bool {
        phase == .preparing || phase == .recording
            || phase == .finishing
    }

    // MARK: - 回调（ChatView 在 onAppear 挂）

    /// 文本落点：录音中逐结果回写、落稿时终值回写
    /// （text, volatileTailLength）
    @ObservationIgnored
    var onTextChange: ((String, Int) -> Void)?
    /// 预备页「用键盘听写」：交回 ChatView 聚焦输入框
    @ObservationIgnored
    var onUseKeyboardDictation: (() -> Void)?

    // MARK: - 内部状态

    @ObservationIgnored
    private let defaults: UserDefaults
    private static let languageKey = "dictation.language"

    @ObservationIgnored
    private var session = DictationSession(baseDraft: "")
    @ObservationIgnored
    private var pendingBaseDraft = ""
    /// 预备页已点「开始使用/用键盘听写」标记：sheet
    /// 关闭的 onDisappear 不许把进行中的权限流误判
    /// 为用户放弃（prepDismissed 据此分流）
    @ObservationIgnored
    private var prepFlowActive = false
    /// 代次守卫：每次开录/收尾递增，迟到回调比对后作废
    @ObservationIgnored
    private var generation = 0

    @ObservationIgnored
    private var analyzer: SpeechAnalyzer?
    @ObservationIgnored
    private var audioEngine: AVAudioEngine?
    @ObservationIgnored
    private var audioPipe: DictationAudioPipe?
    @ObservationIgnored
    private var resultsTask: Task<Void, Never>?
    @ObservationIgnored
    private var analyzeTask: Task<Void, Never>?
    @ObservationIgnored
    private var timerTask: Task<Void, Never>?
    @ObservationIgnored
    private var noticeTask: Task<Void, Never>?
    @ObservationIgnored
    private var startedAt: Date?
    @ObservationIgnored
    private var smoother = DictationLevelSmoother()
    @ObservationIgnored
    private var waveform = DictationWaveform()
    @ObservationIgnored
    private var silenceTracker = SilenceTracker()
    @ObservationIgnored
    private var progressObservation: NSKeyValueObservation?
    @ObservationIgnored
    private var interruptionTokens: [NSObjectProtocol] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let raw = defaults.string(forKey: Self.languageKey)
        self.language = raw.flatMap(DictationLanguage.init(rawValue:))
            ?? .mandarin
    }

    // MARK: - 入口（麦克风点按切换）

    /// 点按切换总入口：录音中＝停录落稿；待机/失败
    /// ＝走权限门后开录
    func handleMicTap(baseDraft: String) {
        switch phase {
        case .recording:
            stopAndCommit()
        case .idle, .failed:
            failure = nil
            notice = nil
            let mic = AVAudioApplication.shared.recordPermission
            let speech = SFSpeechRecognizer.authorizationStatus()
            if mic == .granted, speech == .authorized {
                Task { await self.startPipeline(baseDraft: baseDraft) }
            } else if mic == .denied || speech == .denied
                || speech == .restricted {
                // 被拒不再弹系统窗：失败行给「去设置」
                // 与键盘听写两条降级路（续编 S4）
                fail(.permissionDenied)
                Haptics.error()
            } else {
                pendingBaseDraft = baseDraft
                setPhase(.requestingPermission)
                showPrep = true
            }
        default:
            break
        }
    }

    // MARK: - 预备页动作

    /// 预备页「开始使用」：此刻才触发系统权限弹窗
    func prepConfirmStart() {
        prepFlowActive = true
        showPrep = false
        Task {
            let micOK = await Self.requestMicrophonePermission()
            let speechOK = await Self.requestSpeechPermission()
            guard phase == .requestingPermission else { return }
            if micOK && speechOK {
                await startPipeline(baseDraft: pendingBaseDraft)
            } else {
                fail(.permissionDenied)
                Haptics.error()
            }
        }
    }

    /// 预备页「用键盘听写」：关页、回输入框（键盘
    /// 自带听写即降级路，规格 §3.4）
    func prepUseKeyboard() {
        prepFlowActive = true
        showPrep = false
        if phase == .requestingPermission { setPhase(.idle) }
        onUseKeyboardDictation?()
    }

    func prepDismissed() {
        if prepFlowActive {
            prepFlowActive = false
            return
        }
        if phase == .requestingPermission { setPhase(.idle) }
    }

    // MARK: - 录音面动作

    /// ✓／点按停止：停录并落稿（不自动发送）
    func stopAndCommit() {
        guard phase == .recording else { return }
        Task { await self.finishRecording(outcome: .commit) }
    }

    /// ✕：丢弃本次口述段，既有草稿原样保留
    func cancel() {
        switch phase {
        case .recording:
            Haptics.impact(.light)
            Task { await self.finishRecording(outcome: .cancel) }
        case .preparing:
            // 资产还在下载：作废本次管道、回草稿原样
            generation += 1
            progressObservation = nil
            settle(text: session.baseDraft)
            setPhase(.idle)
        default:
            break
        }
    }

    /// 失败行关闭（用户已读）
    func clearFailure() {
        failure = nil
        if phase == .failed { setPhase(.idle) }
    }

    // MARK: - 管道启动

    private enum EngineAttempt {
        case started
        case assetFailed
        case unavailable
    }

    private func startPipeline(baseDraft: String) async {
        session = DictationSession(baseDraft: baseDraft)
        displayText = baseDraft
        volatileLength = 0
        generation += 1
        let gen = generation
        let first = await startEngine(useFallback: false, generation: gen)
        if first == .started { return }
        if first == .assetFailed {
            fail(.assetDownloadFailed)
            Haptics.error()
            return
        }
        guard generation == gen else { return }
        // 主引擎不可用（不支持/无格式/起不来）→ 回退链
        let second = await startEngine(useFallback: true, generation: gen)
        if second == .started { return }
        if second == .assetFailed {
            fail(.assetDownloadFailed)
        } else {
            fail(.engineUnavailable)
        }
        Haptics.error()
    }

    private func startEngine(
        useFallback: Bool, generation gen: Int
    ) async -> EngineAttempt {
        usedFallbackEngine = useFallback
        // 1) 选模块并规范化语言（locale 必须经
        // supportedLocale 规范化——苹果工程师口径）
        var speechModule: (any SpeechModule)?
        var transcriber: SpeechTranscriber?
        var dictation: DictationTranscriber?
        if !useFallback {
            guard SpeechTranscriber.isAvailable else { return .unavailable }
            var locale = await SpeechTranscriber.supportedLocale(
                equivalentTo: Locale(identifier: language.localeIdentifier)
            )
            if locale == nil, let fallbackID =
                language.fallbackLocaleIdentifier {
                locale = await SpeechTranscriber.supportedLocale(
                    equivalentTo: Locale(identifier: fallbackID)
                )
            }
            guard let locale else { return .unavailable }
            let module = SpeechTranscriber(
                locale: locale,
                transcriptionOptions: [],
                reportingOptions: [.volatileResults],
                attributeOptions: []
            )
            transcriber = module
            speechModule = module
        } else {
            let module = DictationTranscriber(
                locale: Locale(identifier: language.localeIdentifier),
                preset: .progressiveLongDictation
            )
            dictation = module
            speechModule = module
        }
        guard let module = speechModule else { return .unavailable }
        let modules: [any SpeechModule] = [module]

        // 2) 语言资产：未装先下载（准备中相位带进度）
        let status = await AssetInventory.status(forModules: modules)
        if status != .installed {
            setPhase(.preparing)
            assetProgress = 0
            do {
                if let request = await AssetInventory
                    .assetInstallationRequest(supporting: modules) {
                    progressObservation = request.progress.observe(
                        \.fractionCompleted, options: [.new]
                    ) { [weak self] progress, _ in
                        let fraction = progress.fractionCompleted
                        Task { @MainActor in
                            self?.assetProgress = fraction
                        }
                    }
                    try await request.downloadAndInstall()
                }
            } catch {
                progressObservation = nil
                guard generation == gen else { return .unavailable }
                return .assetFailed
            }
            progressObservation = nil
            guard generation == gen else { return .unavailable }
        }

        // 3) 分析器与音频格式（资产装好后才取得到）
        let analyzer = SpeechAnalyzer(modules: modules)
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: modules
        ) else { return .unavailable }

        // 4) 音频会话＋引擎＋tap 转码（一路音频分发
        // 识别与电平两用，规格施工坑注）
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .default)
            try audioSession.setActive(true)
        } catch {
            return .unavailable
        }
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let tapFormat = inputNode.outputFormat(forBus: 0)
        guard let converter = AVAudioConverter(
            from: tapFormat, to: format
        ) else {
            try? audioSession.setActive(
                false, options: .notifyOthersOnDeactivation)
            return .unavailable
        }
        converter.primeMethod = .none
        let (stream, continuation) =
            AsyncStream<AnalyzerInput>.makeStream()
        let pipe = DictationAudioPipe(
            converter: converter, continuation: continuation
        )
        inputNode.installTap(
            onBus: 0, bufferSize: 1024, format: tapFormat
        ) { buffer, _ in
            pipe.consume(buffer)
        }
        self.analyzer = analyzer
        self.audioEngine = engine
        self.audioPipe = pipe

        // 5) 结果消费任务必须先于 analyzer 启动
        // （DocC 官方口径）
        if let transcriber {
            resultsTask = Task { [weak self] in
                do {
                    for try await result in transcriber.results {
                        let text = String(result.text.characters)
                        let isFinal = result.isFinal
                        await self?.applyResult(
                            text: text, isFinal: isFinal, generation: gen)
                    }
                } catch {
                    await self?.engineFailed(generation: gen)
                }
            }
        } else if let dictation {
            resultsTask = Task { [weak self] in
                do {
                    for try await result in dictation.results {
                        let text = String(result.text.characters)
                        let isFinal = result.isFinal
                        await self?.applyResult(
                            text: text, isFinal: isFinal, generation: gen)
                    }
                } catch {
                    await self?.engineFailed(generation: gen)
                }
            }
        }
        analyzeTask = Task { [weak self] in
            do {
                try await analyzer.start(inputSequence: stream)
            } catch {
                await self?.engineFailed(generation: gen)
            }
        }

        do {
            engine.prepare()
            try engine.start()
        } catch {
            teardownAudio(deactivateSession: true)
            return .unavailable
        }
        guard generation == gen else {
            teardownAudio(deactivateSession: true)
            return .unavailable
        }

        registerInterruptionObservers()
        startedAt = Date()
        elapsedSeconds = 0
        smoother.reset()
        waveform.reset()
        silenceTracker.reset()
        showSilenceHint = false
        setPhase(.recording)
        Haptics.impact(.light)
        startTimer(generation: gen)
        return .started
    }

    // MARK: - 结果与失败回调

    private func applyResult(
        text: String, isFinal: Bool, generation gen: Int
    ) {
        guard generation == gen else { return }
        guard phase == .recording || phase == .finishing else { return }
        session.applyResult(text: text, isFinal: isFinal)
        displayText = session.displayText
        volatileLength = session.volatileLength
        onTextChange?(displayText, volatileLength)
    }

    private func engineFailed(generation gen: Int) {
        guard generation == gen, phase == .recording else { return }
        Task { await self.finishRecording(outcome: .engineError) }
    }

    // MARK: - 收尾

    private enum FinishOutcome {
        case commit
        case cancel
        case limit
        case interrupted
        case engineError
    }

    private func finishRecording(outcome: FinishOutcome) async {
        guard phase == .recording else { return }
        // 先落相位再 await：同帧重入（中断与引擎错
        // 同时到）在此被守卫挡下
        setPhase(.finishing)
        timerTask?.cancel()
        timerTask = nil
        unregisterInterruptionObservers()
        let currentAnalyzer = analyzer
        teardownAudio(deactivateSession: true)
        if let currentAnalyzer {
            await finalizeWithTimeout(currentAnalyzer)
            await drainResults()
        }
        resultsTask?.cancel()
        resultsTask = nil
        analyzeTask?.cancel()
        analyzeTask = nil
        analyzer = nil
        generation += 1

        switch outcome {
        case .commit:
            settle(text: session.committedText(includeVolatile: true))
            if session.hasRecognizedText {
                setPhase(.idle)
            } else {
                fail(.nothingHeard)
                Haptics.error()
            }
        case .limit:
            settle(text: session.committedText(includeVolatile: true))
            Haptics.warning()
            showNotice("已录满 5 分钟，识别到的内容已填入输入框")
            setPhase(.idle)
        case .cancel:
            settle(text: session.baseDraft)
            setPhase(.idle)
        case .interrupted:
            settle(text: session.committedText(includeVolatile: true))
            fail(.interrupted)
            Haptics.error()
        case .engineError:
            // 引擎抛错：已定稿保留、未定稿弃（规格 §3.7）
            settle(text: session.committedText(includeVolatile: false))
            fail(.engineError)
            Haptics.error()
        }
        volatileLength = 0
        waveform.reset()
        waveformBars = waveform.bars
        level = 0
        showSilenceHint = false
    }

    /// finalize 带 2 秒超时：超时走 cancelAndFinishNow，
    /// 不许收尾无限挂起（迟到结果由代次守卫作废）
    private func finalizeWithTimeout(_ analyzer: SpeechAnalyzer) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                try? await analyzer.finalizeAndFinishThroughEndOfInput()
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(2))
                await analyzer.cancelAndFinishNow()
            }
            await group.next()
            group.cancelAll()
        }
    }

    /// 等结果流自然收尾（上限 2 秒）：最后的 final
    /// 段在此窗口内落进会话，超时则按现有内容落稿
    private func drainResults() async {
        guard let resultsTask else { return }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await resultsTask.value }
            group.addTask { try? await Task.sleep(for: .seconds(2)) }
            await group.next()
            group.cancelAll()
        }
    }

    private func teardownAudio(deactivateSession: Bool) {
        if let audioEngine {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        audioPipe?.finish()
        audioPipe = nil
        audioEngine = nil
        if deactivateSession {
            try? AVAudioSession.sharedInstance().setActive(
                false, options: .notifyOthersOnDeactivation)
        }
    }

    // MARK: - 计时/电平轮

    private func startTimer(generation gen: Int) {
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self, generation == gen,
                      self.phase == .recording else { return }
                self.tick()
            }
        }
    }

    private func tick() {
        if let startedAt {
            elapsedSeconds = Int(Date().timeIntervalSince(startedAt))
        }
        let rms = audioPipe?.latestRMS ?? 0
        let smoothed = smoother.ingest(rms: rms, dt: 0.1)
        level = smoothed
        waveform.push(smoothed)
        waveformBars = waveform.bars
        showSilenceHint = silenceTracker.ingest(
            level: DictationLevel.normalizedLevel(rms: rms), dt: 0.1)
        if DictationTiming.reachedLimit(elapsedSeconds: elapsedSeconds) {
            Task { await self.finishRecording(outcome: .limit) }
        }
    }

    // MARK: - 系统中断（来电等）

    private func registerInterruptionObservers() {
        let center = NotificationCenter.default
        let names: [NSNotification.Name] = [
            AVAudioSession.interruptionNotification,
            AVAudioSession.mediaServicesWereResetNotification,
        ]
        for name in names {
            let token = center.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] notification in
                if name == AVAudioSession.interruptionNotification {
                    let raw = notification.userInfo?[
                        AVAudioSessionInterruptionTypeKey] as? UInt
                    guard raw == AVAudioSession.InterruptionType.began
                        .rawValue else { return }
                }
                Task { @MainActor in
                    guard let self, self.phase == .recording else {
                        return
                    }
                    await self.finishRecording(outcome: .interrupted)
                }
            }
            interruptionTokens.append(token)
        }
    }

    private func unregisterInterruptionObservers() {
        for token in interruptionTokens {
            NotificationCenter.default.removeObserver(token)
        }
        interruptionTokens = []
    }

    // MARK: - 小工具

    private func setPhase(_ next: DictationPhase) {
        guard DictationPhasePolicy.canTransition(from: phase, to: next)
        else { return }
        phase = next
    }

    private func fail(_ kind: DictationFailure) {
        failure = kind
        setPhase(.failed)
    }

    private func settle(text: String) {
        displayText = text
        onTextChange?(text, 0)
    }

    private func showNotice(_ text: String) {
        notice = text
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }

    private static func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private static func requestSpeechPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
}

/// 音频管线（tap 线程侧）：硬件格式 buffer 在此转码
/// 到分析器格式并 yield，同时把原始电平写进无锁盒
/// 供主线程 10Hz 轮询——识别与电平共用一路 tap，
/// 不另开采集（规格施工坑注）。tap 回调在实时音频
/// 线程，只许做转码与写盒，不碰任何 UI/主线程状态
final class DictationAudioPipe: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let continuation: AsyncStream<AnalyzerInput>.Continuation
    private let rmsBox = OSAllocatedUnfairLock(initialState: 0.0)
    private let consumedBox = OSAllocatedUnfairLock(initialState: false)

    init(
        converter: AVAudioConverter,
        continuation: AsyncStream<AnalyzerInput>.Continuation
    ) {
        self.converter = converter
        self.continuation = continuation
    }

    var latestRMS: Double { rmsBox.withLock { $0 } }

    func consume(_ buffer: AVAudioPCMBuffer) {
        if let channel = buffer.floatChannelData?[0] {
            let samples = Array(UnsafeBufferPointer(
                start: channel, count: Int(buffer.frameLength)))
            let rms = DictationLevel.rms(samples: samples)
            rmsBox.withLock { $0 = rms }
        }
        let ratio = converter.outputFormat.sampleRate
            / converter.inputFormat.sampleRate
        let capacity = AVAudioFrameCount(
            Double(buffer.frameLength) * ratio) + 16
        guard let converted = AVAudioPCMBuffer(
            pcmFormat: converter.outputFormat, frameCapacity: capacity
        ) else { return }
        consumedBox.withLock { $0 = false }
        var error: NSError?
        let status = converter.convert(to: converted, error: &error) {
            _, outStatus in
            let already = self.consumedBox.withLock { state -> Bool in
                let was = state
                state = true
                return was
            }
            if already {
                outStatus.pointee = .noDataNow
                return nil
            }
            outStatus.pointee = .haveData
            return buffer
        }
        if status != .error, error == nil, converted.frameLength > 0 {
            continuation.yield(AnalyzerInput(buffer: converted))
        }
    }

    func finish() {
        continuation.finish()
    }
}
