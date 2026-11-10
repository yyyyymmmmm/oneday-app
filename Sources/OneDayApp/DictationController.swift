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
/// 0.36.8 热修（DESIGN-V4 §73；诊断 voice-crash-
/// diagnosis-20261110.md）：删语音识别授权门（官方口
/// 径只需麦克风）、tap 格式有效性门＋installTap 传
/// nil 格式＋管线惰性建转换器、音频会话对齐 WWDC 样
/// 例、os.Logger 阶段面包屑、启动期引擎错误必达失败
/// 态（根除假录音）。
/// 0.36.11 热修三轮（DESIGN-V4 §76；.ips 实锤
/// voice-crash-ips-20261110-2117.ips）：前两轮修的都
/// 是 tap 的上游关口（授权门/格式门），真崩点在 tap
/// 回调入口本身——installTap 闭包字面量生在
/// @MainActor 上下文、继承主隔离，实时音频线程
/// （RealtimeMessenger）第一帧 buffer 触发
/// _swift_task_checkIsolatedSwift 断言
/// （EXC_BREAKPOINT/SIGTRAP），与权限、格式全无关。
/// 本轮：installTap 迁进 nonisolated 的
/// DictationAudioPipe 由盒本人安装（闭包只捕获盒）；
/// KVO 进度观察同形态收口（DictationProgress
/// Observer）；requestMicrophonePermission 标
/// nonisolated；喂入逻辑核下沉 Core 的
/// DictationAudioFeedBox 并以任意队列调用单测钉死。
/// 回调隔离铁律见 AGENTS.md（2026-11-10）。
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
    /// 结果分型计数（0.36.12 仪表，诊断 dictation-
    /// nolive 修法 1）：volatile（草稿）与 final（定
    /// 稿）分开累计——「实时不出字」的定案数据就在
    /// 这里：草稿到底有没有到达消费环
    private(set) var volatileResultCount = 0
    private(set) var finalResultCount = 0

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
    /// 阶段面包屑落盘键（0.36.8，诊断 §5.4）：闪退后
    /// 读末阶段即知死点，不再靠猜
    private static let lastStageKey = "dictation.lastStage"
    /// 诊断串落盘键（0.36.12；0.36.13 扩四格）：引
    /// 擎种类＋规范化 locale＋实际预设＋locale/资产
    /// 实查＋isAvailable 原值＋结果分型计数，与末阶
    /// 段同走诊断行上屏
    private static let diagKey = "dictation.lastDiag"
    private static let log = Logger(
        subsystem: "site.didichou.oneday", category: "dictation")

    /// 阶段打点：一行日志＋末阶段落盘（授权结果/资产
    /// 状态/会话激活/格式值/引擎启动/首结果各一处）
    private func markStage(_ stage: String) {
        Self.log.info("stage=\(stage, privacy: .public)")
        defaults.set(stage, forKey: Self.lastStageKey)
    }

    /// 规范化后的 locale 标识（选引擎时回填；回退引
    /// 擎无规范化环节，用语言标识原值）
    @ObservationIgnored
    private var diagLocaleID = ""

    /// 仪表四格（0.36.13，DESIGN-V4 §77.6 外部核查
    /// 增补）：①实际生效的预设名（回退＝所构造的
    /// DictationTranscriber 预设；主引擎＝其
    /// reportingOptions 构成）②supportedLocales 对
    /// 当前 locale 的实查布尔 ③installedLocales 实
    /// 查布尔 ④SpeechTranscriber.isAvailable 原值。
    /// 选引擎时落账、markDiag 随串上诊断行——四格齐
    /// 后 engine=main 且 vol=0 才许定案（1b「模块天
    /// 生节奏」说已作废，见 §77.6）。未落账（选引擎
    /// 前）为 nil、串中整段不出
    @ObservationIgnored
    private var diagPresetName = ""
    @ObservationIgnored
    private var diagSupportedLocale: Bool?
    @ObservationIgnored
    private var diagInstalledLocale: Bool?
    @ObservationIgnored
    private var diagTranscriberAvailable: Bool?

    /// 诊断串打点（0.36.12；0.36.13 扩四格）：把「实
    /// 际在跑哪个引擎、语言规范化成什么、预设与
    /// locale/资产实查如何、草稿/定稿各到几条」一
    /// 行落盘＋日志。调用点克制（选引擎、首条草稿、
    /// 首条定稿、收尾各一次），不在每条结果上写盘
    private func markDiag() {
        let engine = usedFallbackEngine ? "fallback" : "main"
        var text = "engine=\(engine)(\(diagLocaleID))"
        if !diagPresetName.isEmpty {
            text += " preset=\(diagPresetName)"
        }
        if let diagSupportedLocale {
            text += " sup=\(diagSupportedLocale)"
        }
        if let diagInstalledLocale {
            text += " inst=\(diagInstalledLocale)"
        }
        if let diagTranscriberAvailable {
            text += " avail=\(diagTranscriberAvailable)"
        }
        text += " vol=\(volatileResultCount)"
            + " fin=\(finalResultCount)"
        Self.log.info("diag=\(text, privacy: .public)")
        defaults.set(text, forKey: Self.diagKey)
    }

    /// 诊断串快照：预备页页脚与失败行上屏用（与
    /// lastStageSnapshot 同口径）
    static var lastDiagSnapshot: String? {
        UserDefaults.standard.string(forKey: diagKey)
    }

    /// 当前麦克风权限（同步读，0.36.9 同步门）：只
    /// 做系统枚举→Core 状态的映射，判定全走
    /// MicPermissionGate 单点——已决定状态绝不重走
    /// 异步回调是礼记同案实锤的铁律，见 Core 注释
    static var micPermissionStatus: MicPermissionStatus {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return .granted
        case .denied:
            return .denied
        default:
            return .undetermined
        }
    }

    /// 末阶段快照（0.36.9 诊断可见化，礼记同案后
    /// 手）：预备页页脚与失败行据此上屏，用户截图
    /// 即可定位死点
    static var lastStageSnapshot: String? {
        UserDefaults.standard.string(forKey: lastStageKey)
    }

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
    /// 启动期故障闩（0.36.8，诊断 §6）：analyzer.start
    /// 在相位进 .recording 前抛错时由 pipelineFault 置
    /// 位，startEngine 在宣布启动成功前检查并作废管道
    @ObservationIgnored
    private var startupFault = false

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
    private let progressObserver = DictationProgressObserver()
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
            // 只看麦克风一道门（0.36.8：SpeechAnalyzer
            // 路线官方口径不需要语音识别授权，原
            // SFSpeechRecognizer 授权门整道删除）＋同
            // 步门判定（0.36.9：先同步读状态，已决定
            // 绝不重走异步回调——礼记同案铁律）
            switch MicPermissionGate.action(for: Self.micPermissionStatus) {
            case .start:
                Task { await self.startPipeline(baseDraft: baseDraft) }
            case .failDenied:
                // 被拒不再弹系统窗：失败行给「去设置」
                // 与键盘听写两条降级路（续编 S4）
                fail(.permissionDenied)
                Haptics.error()
            case .requestOnce:
                pendingBaseDraft = baseDraft
                setPhase(.requestingPermission)
                showPrep = true
            }
        default:
            break
        }
    }

    // MARK: - 预备页动作

    /// 预备页「开始使用」：先同步门复读状态再决定要
    /// 不要发请求（0.36.9 热修二轮，本版主修）——旧
    /// 实现无条件 await 异步授权回调：权限已处于
    /// 「已决定」状态时（重签使 TCC 状态回落的只是
    /// 一端，另一端是授权其实已授过/期间已在别处授
    /// 过），iOS 26 上该回调在特殊线程投递、闭包隔
    /// 离对不上就在入口崩、不弹框点就崩（礼记同案
    /// 靠崩溃日志破的案，本仓 0.36.8 真机仍崩后对
    /// 齐）。已授权直达管道、已拒绝走失败、只有真
    /// 未决定才发那唯一一次请求
    func prepConfirmStart() {
        prepFlowActive = true
        showPrep = false
        switch MicPermissionGate.action(for: Self.micPermissionStatus) {
        case .start:
            markStage("micAlreadyGranted")
            Task { await self.startPipeline(baseDraft: pendingBaseDraft) }
        case .failDenied:
            fail(.permissionDenied)
            Haptics.error()
        case .requestOnce:
            Task {
                let micOK = await Self.requestMicrophonePermission()
                markStage(micOK ? "micGranted" : "micDenied")
                guard phase == .requestingPermission else { return }
                if micOK {
                    await startPipeline(baseDraft: pendingBaseDraft)
                } else {
                    fail(.permissionDenied)
                    Haptics.error()
                }
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
            progressObserver.invalidate()
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
        /// 引擎已起但分析器启动抛错被闩住作废（0.36.8）：
        /// 与「不可用」分开报——失败文案走 engineError
        case startFailed
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
        if first == .startFailed {
            fail(.engineError)
            Haptics.error()
            return
        }
        guard generation == gen else { return }
        // 主引擎不可用（不支持/无格式/起不来）→ 回退链
        let second = await startEngine(useFallback: true, generation: gen)
        if second == .started { return }
        if second == .assetFailed {
            fail(.assetDownloadFailed)
        } else if second == .startFailed {
            fail(.engineError)
        } else {
            fail(.engineUnavailable)
        }
        Haptics.error()
    }

    private func startEngine(
        useFallback: Bool, generation gen: Int
    ) async -> EngineAttempt {
        usedFallbackEngine = useFallback
        // 仪表归零（0.36.12）：计数归本尝试的引擎——
        // 结果只在启动成功后到达，归零无竞态；主引擎
        // 若中途失败转回退，计数随回退尝试重新起算
        volatileResultCount = 0
        finalResultCount = 0
        diagLocaleID = language.localeIdentifier
        // 仪表四格归零（0.36.13）：与计数同口径归本
        // 尝试，选引擎落账前串中整段不出
        diagPresetName = ""
        diagSupportedLocale = nil
        diagInstalledLocale = nil
        diagTranscriberAvailable = nil
        // 四格之④先行落账：isAvailable 原值必须在守
        // 卫消费前取值——先取原值存好，守卫用的是同
        // 一个值，诊断串读到的才是守卫真正看到的
        let transcriberAvailable = SpeechTranscriber.isAvailable
        diagTranscriberAvailable = transcriberAvailable
        // 1) 选模块并规范化语言（locale 必须经
        // supportedLocale 规范化——苹果工程师口径）
        var speechModule: (any SpeechModule)?
        var transcriber: SpeechTranscriber?
        var dictation: DictationTranscriber?
        if !useFallback {
            guard transcriberAvailable else { return .unavailable }
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
            // 规范化结果回填仪表（0.36.12）：诊断行要
            // 显示的是 supportedLocale 实际给了什么，
            // 不是请求了什么
            diagLocaleID = locale.identifier
            let module = SpeechTranscriber(
                locale: locale,
                transcriptionOptions: [],
                reportingOptions: [.volatileResults],
                attributeOptions: []
            )
            transcriber = module
            speechModule = module
            // 四格之①②③（主引擎）：预设记 reporting-
            // Options 构成（与上方构造逐字同值）；②③
            // 对规范化后的 locale 查 SpeechTranscriber
            // 的支持/已装清单原表——inst 是资产下载前
            // 的选引擎时刻快照，正是定案要的时点
            diagPresetName = "rep:volatileResults"
            diagSupportedLocale =
                await SpeechTranscriber.supportedLocales
                    .contains { $0.identifier == locale.identifier }
            diagInstalledLocale =
                await SpeechTranscriber.installedLocales
                    .contains { $0.identifier == locale.identifier }
        } else {
            let module = DictationTranscriber(
                locale: Locale(identifier: language.localeIdentifier),
                preset: .progressiveLongDictation
            )
            dictation = module
            speechModule = module
            // 四格之①②③（回退引擎）：预设记所构造的
            // 档位名；②③仍查 SpeechTranscriber 的清
            // 单（对请求的 locale）——回退为何发生，主
            // 引擎侧的支持/资产状态正是要留的账
            diagPresetName = "progressiveLongDictation"
            let requestedID = language.localeIdentifier
            diagSupportedLocale =
                await SpeechTranscriber.supportedLocales
                    .contains { $0.identifier == requestedID }
            diagInstalledLocale =
                await SpeechTranscriber.installedLocales
                    .contains { $0.identifier == requestedID }
        }
        guard let module = speechModule else { return .unavailable }
        let modules: [any SpeechModule] = [module]
        startupFault = false
        markStage("moduleBuilt")
        // 选引擎打点（0.36.12；0.36.13 扩四格）：引擎
        // 种类＋规范化 locale＋四格在此定格落盘——回
        // 退引擎静默在跑自此可见（旧实现 usedFallback-
        // Engine 只赋值、无任何消费点，用户与诊断都
        // 无从知道）
        markDiag()

        // 2) 语言资产：未装先下载（准备中相位带进度）
        let status = await AssetInventory.status(forModules: modules)
        if status != .installed {
            setPhase(.preparing)
            assetProgress = 0
            do {
                if let request = try await AssetInventory
                    .assetInstallationRequest(supporting: modules) {
                    // 观察闭包经 nonisolated 盒安装（0.36.11）：
                    // Progress 在自有队列投递变更，闭包若生在
                    // 本 @MainActor 上下文并继承隔离，与 tap
                    // 同病（入口断言）；盒内闭包只碰 @Sendable
                    // 回调，跳回主隔离由回调内部显式完成
                    progressObserver.observe(request.progress) {
                        [weak self] fraction in
                        Task { @MainActor in
                            self?.assetProgress = fraction
                        }
                    }
                    try await request.downloadAndInstall()
                }
            } catch {
                progressObserver.invalidate()
                guard generation == gen else { return .unavailable }
                return .assetFailed
            }
            progressObserver.invalidate()
            guard generation == gen else { return .unavailable }
        }
        markStage("assetReady")

        // 3) 分析器与音频格式（资产装好后才取得到）
        let analyzer = SpeechAnalyzer(modules: modules)
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: modules
        ) else { return .unavailable }

        // 4) 音频会话＋引擎＋tap 转码（一路音频分发
        // 识别与电平两用，规格施工坑注）。0.36.8 热修
        // 三点（诊断 §2/§5.2）：①会话对齐 WWDC25 样例
        // 的 .playAndRecord＋.spokenAudio；②tap 格式先
        // 过有效性门——首次授权后格式可为 0 Hz，未经
        // 校验递给 installTap 会抛 NSException 当场闪
        // 退，无效时 prepare 后复读一次、仍无效走不可
        // 用失败路；③installTap 传 nil 格式（用节点实
        // 时格式）、转换器改由管线按首个 buffer 的真实
        // 格式惰性建立，快照竞态整类消除；④installTap
        // 闭包的出生地（0.36.11）：必须由管线盒本人在
        // nonisolated 上下文安装——写在本方法里会继承
        // @MainActor 隔离，实时音频线程第一帧入口断言
        // 即死（.ips 实锤，与①②③的关口全无关）
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(
                .playAndRecord, mode: .spokenAudio)
            try audioSession.setActive(true)
        } catch {
            return .unavailable
        }
        markStage("sessionActive")
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        var tapFormat = inputNode.outputFormat(forBus: 0)
        if !DictationAudioFormatPolicy.isUsable(
            sampleRate: tapFormat.sampleRate,
            channelCount: Int(tapFormat.channelCount)) {
            engine.prepare()
            tapFormat = inputNode.outputFormat(forBus: 0)
        }
        guard DictationAudioFormatPolicy.isUsable(
            sampleRate: tapFormat.sampleRate,
            channelCount: Int(tapFormat.channelCount)) else {
            Self.log.error(
                "stage=formatInvalid rate=\(tapFormat.sampleRate) channels=\(tapFormat.channelCount)")
            markStage("formatInvalid")
            try? audioSession.setActive(
                false, options: .notifyOthersOnDeactivation)
            return .unavailable
        }
        markStage("formatReady")
        let (stream, continuation) =
            AsyncStream<AnalyzerInput>.makeStream()
        let pipe = DictationAudioPipe(
            targetFormat: format, continuation: continuation
        )
        // 由盒本人安装（0.36.11）：闭包只捕获盒、只做
        // 转码＋喂入；相位/面包屑等控制器状态在安装返
        // 回后由本方法在主隔离内处理，永不经 tap 线程
        pipe.installTap(on: inputNode)
        markStage("tapInstalled")
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
                    await self?.pipelineFault(generation: gen)
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
                    await self?.pipelineFault(generation: gen)
                }
            }
        }
        analyzeTask = Task { [weak self] in
            await self?.markStage("analyzerStarted")
            do {
                try await analyzer.start(inputSequence: stream)
            } catch {
                await self?.pipelineFault(generation: gen)
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
        // 启动期故障闩（0.36.8，诊断 §6）：分析器在进
        // 录音态前已抛错——拆管道、报 startFailed，绝
        // 不带着坏分析器进 .recording 假录音
        if startupFault {
            startupFault = false
            teardownAudio(deactivateSession: true)
            return .startFailed
        }
        markStage("engineStarted")

        registerInterruptionObservers()
        startedAt = Date()
        elapsedSeconds = 0
        smoother.reset()
        waveform.reset()
        silenceTracker.reset()
        showSilenceHint = false
        setPhase(.recording)
        markStage("recording")
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
        // 结果分型打点（0.36.12，诊断修法 1）：旧实现
        // 只在首条结果打 firstResult、不分型——草稿是
        // 否到达过无从分辨，1a/1b 两假设因此不可分。
        // 现行：首条草稿与首条定稿各打一格、两类逐条
        // 计数并同步进诊断串；定稿计数在首条定稿时连
        // 同当时的草稿计数落盘，「草稿先行还是全程为
        // 零」一录定案
        if isFinal {
            finalResultCount += 1
            if finalResultCount == 1 {
                markStage("firstFinal")
                markDiag()
            }
        } else {
            volatileResultCount += 1
            if volatileResultCount == 1 {
                markStage("firstVolatile")
                markDiag()
            }
        }
        session.applyResult(text: text, isFinal: isFinal)
        displayText = session.displayText
        volatileLength = session.volatileLength
        onTextChange?(displayText, volatileLength)
    }

    /// 引擎侧故障统一入口（0.36.8，诊断 §6）：处置由
    /// Core 的 DictationFaultPolicy 按相位定——录音中
    /// 失败收尾；启动中置闩作废（startEngine 宣布成功
    /// 前检查）；已落定则迟到信号作废。旧实现只认
    /// .recording，启动期抛错被静默吞＝假录音根源
    private func pipelineFault(generation gen: Int) {
        switch DictationFaultPolicy.action(
            generationMatches: generation == gen, phase: phase) {
        case .finishWithError:
            markStage("engineFault")
            Task { await self.finishRecording(outcome: .engineError) }
        case .abortStartup:
            markStage("startupFault")
            startupFault = true
        case .ignore:
            break
        }
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
        // 收尾把最终计数落盘（0.36.12 仪表）：会话结
        // 束后诊断行读到的是全程总数，不是首条时刻的
        markDiag()
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

    /// nonisolated（0.36.11）：授权回调闭包不许带隔
    /// 离——礼记同案即授权回调在系统特殊线程投递、隔
    /// 离对不上就在入口崩。本函数只碰 continuation
    /// （Sendable），标 nonisolated 把内部两个闭包
    /// （continuation 体与 requestRecordPermission
    /// 回调）的出生地一并钉死在无隔离上下文；调用点
    /// 仍只许 MicPermissionGate 判 requestOnce 时经
    /// prepConfirmStart 进来，全仓唯一（0.36.9 口径）
    nonisolated private static func requestMicrophonePermission()
        async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}

/// 音频管线（tap 线程侧）：硬件格式 buffer 在此转码
/// 到分析器格式并 yield，同时把原始电平写进无锁盒
/// 供主线程 10Hz 轮询——识别与电平共用一路 tap，
/// 不另开采集（规格施工坑注）。tap 回调在实时音频
/// 线程，只许做转码与写盒，不碰任何 UI/主线程状态。
/// 0.36.8：转换器不再由开录前格式快照预建——改为以
/// 首个实际 buffer 的格式惰性建立（格式变更时重建），
/// 转码比值先过 Core 有限性守卫，无效整帧丢弃
/// 0.36.11：本类即 tap 的音频处理盒——nonisolated
/// 终类，installTap 由盒本人安装（见 installTap(on:)），
/// 电平喂入核下沉 Core 的 DictationAudioFeedBox
final class DictationAudioPipe: @unchecked Sendable {
    private let targetFormat: AVAudioFormat
    private let continuation: AsyncStream<AnalyzerInput>.Continuation
    private let feedBox = DictationAudioFeedBox()
    private let consumedBox = OSAllocatedUnfairLock(initialState: false)
    private let converterBox = OSAllocatedUnfairLock<AVAudioConverter?>(
        initialState: nil)

    init(
        targetFormat: AVAudioFormat,
        continuation: AsyncStream<AnalyzerInput>.Continuation
    ) {
        self.targetFormat = targetFormat
        self.continuation = continuation
    }

    var latestRMS: Double { feedBox.latestRMS }

    /// 在输入节点上装 tap（0.36.11，本版主修）：闭包
    /// 必须生在本盒的 nonisolated 上下文里、只捕获盒
    /// 本人、只做「转码＋喂给分析器输入」。旧形态把
    /// 闭包字面量写在 @MainActor 的 startEngine 里——
    /// 闭包继承主隔离，AVFAudio 在实时音频线程
    /// （RealtimeMessenger.mServiceQueue）投递第一帧
    /// 时，运行时在闭包入口做隔离断言
    /// （_swift_task_checkIsolatedSwift →
    /// dispatch_assert_queue → _dispatch_assert_
    /// queue_fail），EXC_BREAKPOINT 当场掐断进程
    /// （.ips 实锤：closure #2 in startEngine，证据链
    /// 见 DESIGN-V4 §76）。控制器状态一律不经此闭
    /// 包：电平走 feedBox 锁盒由主线程轮询，相位与面
    /// 包屑在 installTap 返回后由控制器在主隔离内处理
    func installTap(on inputNode: AVAudioInputNode) {
        inputNode.installTap(
            onBus: 0, bufferSize: 1024, format: nil
        ) { buffer, _ in
            self.consume(buffer)
        }
    }

    /// 按输入格式取转换器：已有且输入格式一致直接用，
    /// 否则惰性新建（建不出回 nil，调用方丢帧）
    private func converter(
        for inputFormat: AVAudioFormat
    ) -> AVAudioConverter? {
        converterBox.withLock { current in
            if let current, current.inputFormat == inputFormat {
                return current
            }
            let created = AVAudioConverter(
                from: inputFormat, to: targetFormat)
            created?.primeMethod = .none
            current = created
            return created
        }
    }

    func consume(_ buffer: AVAudioPCMBuffer) {
        if let channel = buffer.floatChannelData?[0] {
            let samples = Array(UnsafeBufferPointer(
                start: channel, count: Int(buffer.frameLength)))
            feedBox.ingest(samples: samples)
        }
        guard buffer.frameLength > 0,
              let converter = converter(for: buffer.format),
              let ratio = DictationAudioFormatPolicy.conversionRatio(
                  inputSampleRate: buffer.format.sampleRate,
                  outputSampleRate: targetFormat.sampleRate)
        else { return }
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

/// 进度观察盒（0.36.11）：AssetInventory 下载进度的
/// KVO 观察必须经盒安装——Progress 在自有队列投递变
/// 更通知，观察闭包若在 @MainActor 上下文出生并继承
/// 隔离，与 tap 同病（入口隔离断言）。盒为 nonisolated
/// 终类，盒内闭包只捕获 @Sendable 回调；隔离跳回由
/// 回调内部显式完成（调用方 Task { @MainActor in … }）。
/// observation 只在主隔离侧写（observe/invalidate 均
/// 由控制器调用），KVO 闭包不碰它，@unchecked
/// Sendable 据此成立
final class DictationProgressObserver: @unchecked Sendable {
    private var observation: NSKeyValueObservation?

    func observe(
        _ progress: Progress,
        onChange: @escaping @Sendable (Double) -> Void
    ) {
        observation = progress.observe(
            \.fractionCompleted, options: [.new]
        ) { observed, _ in
            onChange(observed.fractionCompleted)
        }
    }

    func invalidate() {
        observation = nil
    }
}
