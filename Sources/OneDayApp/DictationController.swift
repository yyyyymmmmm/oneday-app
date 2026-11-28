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
/// 交互定版：点按切换、落框可改；单次上限 5 分钟。
/// （流式上屏与「不自动发送」两条已被 0.36.17 改判
/// 撤销，见文件下方 0.36.17 注与 DESIGN-V4 §82。）
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
/// 0.36.17 听写改判（DESIGN-V4 §82；用户 2026-11-10
/// 23:48 产品改判＋论坛核查 dictation-latency-forum-
/// check-20261110.md）：不再追实时出字——引擎交付
/// 段天生秒级节奏（外部多方实测），预热只治启动段。
/// 录音条改 Muse 形态：录时零文字（结果照常进会
/// 话攒稿、只是不呈现、不回写输入框）、停/发送两
/// 钮、停后整段落字。诊断行撤下录音条，移回预备页
/// 与失败行的阶段诊断行（沿现行载体）；
/// reportingOptions 开 .fastResults 作内部杠杆
/// （唯一未开的官方延迟开关），不作承诺。停后落
/// 字计时记账已退役（复杂度清理，审计第 8 项）。
/// 听写实现瘦身（DESIGN-V4 §299；横扫 A-07）：为已
/// 撤销的「实时出字」目标而建的实现机器整组退役——
/// 预热状态机＋round 令牌收成一个总闸 Bool＋单飞任
/// 务（产物在否即就绪、取消即作废）；起步时序钟、诊
/// 断四格、结果分型计数、末阶段/诊断串落盘与上屏诊
/// 断行全删（其使命——定位实时出字与 tap 崩溃——均
/// 已结案），阶段打点只留 os.Logger 系统日志。形态
/// 与外部行为逐项不变：录音条四态、停录整段落字、
/// 废弃不落字、权限同步门、tap/进度回调的 nonisolated
/// 隔离形态全数保留。
@MainActor
@Observable
final class DictationController {

    // MARK: - 可观察状态（视图只读这些）

    private(set) var phase: DictationPhase = .idle
    /// 会话当前全文（草稿＋识别段）：0.36.17 起只
    /// 作内部账（settle 时取 committedText 落稿），
    /// 录音中不向任何视图呈现
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
            // 语言变了（0.36.15 预热）：备好的分析器
            // 是旧语言的——弃置并按新语言重备
            dropPrepared()
            warmIfNeeded()
        }
    }
    /// 通话面入口别名（合并接缝修复：v23 通话面按
    /// toggle(currentDraft:) 调用；本体开关口径就是
    /// handleMicTap——闲置起录、录音中收尾落稿）
    func toggle(currentDraft: String) {
        handleMicTap(baseDraft: currentDraft)
    }

    /// 是否正在录音（通话面等消费方按此判麦克风实况；
    /// 合并接缝修复：v23 通话面引用此名，控制器只有
    /// phase——按 .recording 态派生，与 isActive 分工）
    var isRecording: Bool {
        phase == .recording
    }

    /// 录音面是否应占住发送舱（准备中/录音中/收尾）
    var isActive: Bool {
        phase == .preparing || phase == .recording
            || phase == .finishing
    }

    // MARK: - 回调（ChatView 在 onAppear 挂）

    /// 文本落点：只在落稿（settle）时回写终值——
    /// 0.36.17 改判后录音中不再逐结果回写输入框
    /// （录时零文字，见类头注）
    /// （text, volatileTailLength）
    @ObservationIgnored
    var onTextChange: ((String, Int) -> Void)?
    /// 发送钮落定回调（0.36.17）：↑ 发送路径在
    /// settle 回写完输入框之后由本控制器触发，
    /// ChatView 据此走它自己的 send()——顺序由本
    /// 类保证（先落稿、后发送），视图不许自拼
    @ObservationIgnored
    var onSendRequest: (() -> Void)?
    /// 预备页「用键盘听写」：交回 ChatView 聚焦输入框
    @ObservationIgnored
    var onUseKeyboardDictation: (() -> Void)?

    // MARK: - 内部状态

    @ObservationIgnored
    private let defaults: UserDefaults
    private static let languageKey = "dictation.language"
    private static let log = Logger(
        subsystem: "site.didichou.oneday", category: "dictation")

    /// 阶段打点：只走 os.Logger 系统日志（0.36.8 起
    /// 的阶段记号沿用）；原末阶段/诊断串落盘＋上屏
    /// 诊断行已随 §299 瘦身退役
    private func markStage(_ stage: String) {
        Self.log.info("stage=\(stage, privacy: .public)")
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

    /// 预热产物（0.36.15 立、§299 瘦身）：模块/分析
    /// 器/格式/语言在点麦克风之前备齐，点按只剩开音
    /// 频会话与喂入。分析器单次使用制（finish 后会话
    /// 终结、官方口径不再接受新输入），消费即弃、
    /// 录后重备下一份——「复用」的实体是这条常备
    /// 流水线，不是同一实例反复 start
    private struct PreparedDictation {
        let analyzer: SpeechAnalyzer
        let transcriber: SpeechTranscriber
        let format: AVAudioFormat
        let language: DictationLanguage
    }

    /// 预热总闸（§299：原 arm/disarm/suspend 三闸＋
    /// Core 状态机＋round 令牌收成此一个 Bool）：开
    /// ＝ChatView 在场许备；关＝离场。退后台只弃产
    /// 物不动闸（回前台由 ChatView 再 arm 触发重备）
    @ObservationIgnored
    private var preheatEnabled = false
    /// 在飞的备制任务（单飞：非 nil 即备中，不起第
    /// 二轮）；就绪与否看 preparedBundle 在否，不另
    /// 设状态。迟到回执由任务取消作废——弃置必先
    /// cancel 再清引用，旧任务回执见取消即弃
    @ObservationIgnored
    private var warmTask: Task<Void, Never>?
    @ObservationIgnored
    private var preparedBundle: PreparedDictation?
    /// 在备一轮是否卡在资产下载（点按时若在下，下
    /// 载窗要以 .preparing 相位示人，不许界面无反应）
    @ObservationIgnored
    private var warmAssetDownloading = false

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

    /// ■ 停／麦克风点按停止：停录并整段落稿进输
    /// 入框（不自动发送）
    func stopAndCommit() {
        guard phase == .recording else { return }
        Task { await self.finishRecording(outcome: .commit) }
    }

    /// ↑ 发送（0.36.17）：停录→整段落定后直接发
    /// 送（空稿只收条不发，路径由 Core 的
    /// DictationSettlePolicy 判定、本类执行）
    func stopAndSend() {
        guard phase == .recording else { return }
        Task { await self.finishRecording(outcome: .send) }
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
        // 全失败也重备一轮（0.36.15）：失败态可再备，
        // 用户重试时先看已备产物、备成则走快路
        warmIfNeeded()
    }

    // MARK: - 预热（0.36.15 立、§299 瘦身）

    /// 进聊天页（ChatView onAppear/scenePhase 回前
    /// 台驱动）：打开总闸并备下一段录音的分析器。
    /// 预热只构造模块/分析器、确保资产、调
    /// prepareToAnalyze——不碰音频会话、不开引擎、
    /// 不发任何权限请求（麦克风仍是点按时按同步状
    /// 态门走，授权铁律不因预热破例）；系统录音指
    /// 示（橙点）只随发射段激活音频会话出现，预热
    /// 不污染它的语义
    func armPreheat() {
        preheatEnabled = true
        warmIfNeeded()
    }

    /// 离开聊天页：关闸＋弃置产物，在备的取消。控
    /// 制器随 ChatView 销毁时产物自然释放，此处是
    /// 视图尚在但已离场的显式收束
    func disarmPreheat() {
        preheatEnabled = false
        dropPrepared()
    }

    /// 退后台：只弃产物、总闸保持——分析器不在后
    /// 台占着系统语音资源；回前台由 ChatView 的
    /// scenePhase 钩子再 arm 触发重备
    func suspendPreheat() {
        dropPrepared()
    }

    /// 发起一轮预热（总闸开＋相位允许＋单飞才动）：
    /// 已备/备中不起第二轮；录音/收尾/准备中不备
    /// （不与在飞的管道抢分析器资源）。备成只落产
    /// 物、备败什么都不落——点按时冷路径以原有形
    /// 态兜底（含它自己的失败呈现），下次触发点
    /// （录后/回前台/语言变更）自然重试
    private func warmIfNeeded() {
        guard preheatEnabled else { return }
        guard phase == .idle || phase == .failed else { return }
        guard warmTask == nil, preparedBundle == nil else { return }
        markStage("preheatStart")
        warmTask = Task { [weak self] in
            let bundle = await self?.buildPreparedBundle()
            // 弃置/离场已 cancel 本任务：迟到回执作
            // 废，不许踩其后新一轮的任务引用与产物
            guard let self, !Task.isCancelled else { return }
            self.warmTask = nil
            if let bundle, bundle.language == self.language {
                self.preparedBundle = bundle
                self.markStage("preheatReady")
            } else {
                self.markStage("preheatFailed")
            }
        }
    }

    /// 备一份产物：选主引擎模块→规范化 locale→
    /// 资产确保（未装走系统下载、无界面进度）→建
    /// 分析器→取最佳格式→prepareToAnalyze 把系统
    /// 侧资源（模型/locale 分配）先加载掉——官方
    /// 口径「may improve how quickly the modules
    /// return their first results」，正是本案 10 秒
    /// 首结果的对症面。任何一步不成回 nil：预热失
    /// 败不向用户报错，点按时冷路径以原有形态兜底
    /// （含它自己的失败呈现）。回退引擎不预热（无
    /// prepare 面、且它是主引擎不可用时的降级路，
    /// 冷启代价可接受）
    private func buildPreparedBundle() async -> PreparedDictation? {
        let forLanguage = language
        let available = SpeechTranscriber.isAvailable
        guard available else { return nil }
        var locale = await SpeechTranscriber.supportedLocale(
            equivalentTo: Locale(identifier: forLanguage.localeIdentifier)
        )
        if locale == nil, let fallbackID =
            forLanguage.fallbackLocaleIdentifier {
            locale = await SpeechTranscriber.supportedLocale(
                equivalentTo: Locale(identifier: fallbackID)
            )
        }
        guard let locale else { return nil }
        let module = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            // fastResults（0.36.17）：DocC 语义＝小
            // 上下文窗降结果延迟，官方预设 progressive-
            // Transcription 与手动形态的唯一差量即此
            // 项（论坛核查定案）——内部杠杆，不作 UI
            // 承诺（其落字计时记账已退役，见类头注）
            reportingOptions: [.volatileResults, .fastResults],
            attributeOptions: [.audioTimeRange]
        )
        let modules: [any SpeechModule] = [module]
        let status = await AssetInventory.status(forModules: modules)
        if status != .installed {
            warmAssetDownloading = true
            do {
                guard let request = try await AssetInventory
                    .assetInstallationRequest(supporting: modules)
                else {
                    warmAssetDownloading = false
                    return nil
                }
                try await request.downloadAndInstall()
            } catch {
                warmAssetDownloading = false
                return nil
            }
            warmAssetDownloading = false
        }
        let analyzer = SpeechAnalyzer(modules: modules)
        guard let format = await SpeechAnalyzer
            .bestAvailableAudioFormat(compatibleWith: modules)
        else { return nil }
        do {
            try await analyzer.prepareToAnalyze(in: format)
        } catch {
            return nil
        }
        return PreparedDictation(
            analyzer: analyzer, transcriber: module, format: format,
            language: forLanguage)
    }

    /// 取已备产物（startEngine 主引擎尝试专用）：
    /// 备中则等它落地再看——等的是已启程的预热，
    /// 仍快于从零冷启；等候期间若在下资产，以
    /// .preparing 相位示人（不许界面无反应）。语
    /// 言不符或备失败回 nil 走冷路径
    private func takePreparedBundle() async -> PreparedDictation? {
        if let warmTask {
            if warmAssetDownloading { setPhase(.preparing) }
            await warmTask.value
        }
        guard let bundle = preparedBundle,
              bundle.language == language else { return nil }
        preparedBundle = nil
        return bundle
    }

    /// 弃置产物（语言变更/退后台/离场共用）：在备
    /// 的先 cancel 再清引用——旧任务回执见取消即
    /// 作废，不许踩新一轮的任务引用与产物
    private func dropPrepared() {
        warmTask?.cancel()
        warmTask = nil
        preparedBundle = nil
        warmAssetDownloading = false
    }

    private func startEngine(
        useFallback: Bool, generation gen: Int
    ) async -> EngineAttempt {
        let transcriberAvailable = SpeechTranscriber.isAvailable
        // 预热消费（0.36.15）：主引擎尝试先看已备产
        // 物——命中则选模块/资产/建分析器整段跳过、
        // 直进发射；尚在备则等它落地再看（它比点按
        // 先启程，等也比冷启快）；语言不符/备失败回
        // nil、走下方冷路径
        if !useFallback, let bundle = await takePreparedBundle() {
            startupFault = false
            markStage("preheatConsumed")
            return await launchPipeline(
                analyzer: bundle.analyzer,
                transcriber: bundle.transcriber, dictation: nil,
                format: bundle.format, generation: gen)
        }
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
            let module = SpeechTranscriber(
                locale: locale,
                transcriptionOptions: [],
                // fastResults 与预热束同口径（0.36.17，
                // 见 buildPreparedBundle 注）
                reportingOptions: [.volatileResults, .fastResults],
                attributeOptions: [.audioTimeRange]
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
        startupFault = false
        markStage("moduleBuilt")

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
        return await launchPipeline(
            analyzer: analyzer,
            transcriber: transcriber, dictation: dictation,
            format: format, generation: gen)
    }

    /// 发射（0.36.15 拆分）：分析器/模块/格式备齐后
    /// 的共用尾段——预热消费与冷启构造两路在此汇
    /// 合，音频会话/tap/结果环/start 的次序与守卫
    /// 只此一份，不许两路各写一份日后漂移
    private func launchPipeline(
        analyzer: SpeechAnalyzer,
        transcriber: SpeechTranscriber?,
        dictation: DictationTranscriber?,
        format: AVAudioFormat,
        generation gen: Int
    ) async -> EngineAttempt {
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
        session.applyResult(text: text, isFinal: isFinal)
        displayText = session.displayText
        volatileLength = session.volatileLength
        // 0.36.17 改判：录音中不回写输入框——结果只
        // 进会话攒稿，呈现等停录落稿一次性给（录音
        // 条上零文字）。旧逐结果回写是「实时上屏」
        // 路线的呈现口，该路线已被产品改判撤销
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
        case send
        case cancel
        case limit
        case interrupted
        case engineError
    }

    private func finishRecording(outcome: FinishOutcome) async {
        guard phase == .recording else { return }
        // 先落相位再 await：同帧重入（中断与引擎错
        // 同时到）在此被守卫挡下。.finishing 即改判
        // 后的「整理中」态——录音条在此相位转「正
        // 在整理…」、三钮全禁（DictationBarPolicy）
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
            applyStopSettle(intent: .commitToComposer)
            setPhase(.idle)
        case .send:
            applyStopSettle(intent: .commitAndSend)
            setPhase(.idle)
        case .limit:
            // 到限与「停」同路（有字落稿＋提示、空
            // 稿静默——提示文案说「已填入」，空稿时
            // 不许撒谎），判定走同一张政策表
            if DictationSettlePolicy.route(
                intent: .commitToComposer,
                hasRecognizedText: session.hasRecognizedText
            ) == .fillComposer {
                settle(text: session.committedText(includeVolatile: true))
                Haptics.warning()
                showNotice(L10n.string("已录满 5 分钟，识别到的内容已填入输入框"))
            } else {
                settle(text: session.baseDraft)
            }
            markStage("settleApplied")
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
        // 录完即重备下一段（0.36.15）：本段分析器已
        // 随 finish 终结，下一份备在背景里——用户下
        // 次点麦克风时只剩开录与喂入
        warmIfNeeded()
        volatileLength = 0
        waveform.reset()
        waveformBars = waveform.bars
        level = 0
        showSilenceHint = false
    }

    /// 停/发送的落稿执行（0.36.17）：路径由 Core 的
    /// DictationSettlePolicy 判定（有字落稿／落稿并
    /// 发／空稿静默回待机），本类只执行——落稿先
    /// 行，发送触发垫在最后：ChatView 的 send()
    /// 读输入框时稿已落定
    private func applyStopSettle(intent: DictationStopIntent) {
        let route = DictationSettlePolicy.route(
            intent: intent,
            hasRecognizedText: session.hasRecognizedText)
        switch route {
        case .fillComposer, .fillAndSend:
            settle(text: session.committedText(includeVolatile: true))
        case .silentIdle:
            settle(text: session.baseDraft)
        }
        markStage("settleApplied")
        if route == .fillAndSend {
            onSendRequest?()
        }
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

// DictationAudioPipe、DictationProgressObserver 与 SpeechAnalyzerCapability 已抽离至 DictationController+Pipeline.swift（#32）
