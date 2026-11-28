import AVFoundation
import Foundation
import OneDayCore

/// 语音偏好键（设置「语音」段与播放器自动朗读共读
/// 同一键，不许两处各写一份字面量）
enum VoiceSpeechPreferences {
    /// §411 键进位 v2：用户拍板「自动朗读默认关」
    /// 须对存量设备生效——v1 键若曾被拨开过，存量
    /// true 不许带进新口径；v1 键就此弃置，想开的
    /// 人在设置面拨一次即写 v2
    static let autoReadKey = "voice.autoReadReplies.v2"

    /// 自动朗读开关现值（无存值＝关）：落定自动朗
    /// 读的唯一判读口（SpeechPlayer 的 autoReadIf-
    /// Enabled），设置面 Toggle 经 @AppStorage 同
    /// 键共写；现值现读、不缓存
    static var autoReadEnabled: Bool {
        UserDefaults.standard.bool(forKey: autoReadKey)
    }
}

/// 朗读音频引擎口（注入点）：生产实现包 AVAudio-
/// Player，测试注入假引擎——播放编排与状态机测试
/// 不碰真音频、不断言系统行为
protocol SpeechAudioEngine: AnyObject {
    /// 自然播完（成功放完）
    var onNaturalFinish: (@MainActor () -> Void)? { get set }
    /// 播放中失败（解码错误/未放完中断），带人话
    var onPlaybackFailure: (@MainActor (String) -> Void)? { get set }
    func start()
    func stop()
    /// 断点暂停（D1）：停声但保留播放实例与进度
    func pause()
    /// 从断点续播（D1）
    func resume()
}

/// AVAudioPlayer 引擎：音频会话在本层收口——播前
/// 切 .playback 并激活、停/完后释放（与听写的录音
/// 会话共用同一个 AVAudioSession 的分工：听写开始
/// 前 ChatView 先停朗读，后到者重设类别，互不抢）
final class AVSpeechAudioEngine: NSObject,
    AVAudioPlayerDelegate, @unchecked Sendable {
    private let player: AVAudioPlayer
    @MainActor var onNaturalFinish: (@MainActor () -> Void)?
    @MainActor var onPlaybackFailure: (@MainActor (String) -> Void)?

    init(data: Data) throws {
        player = try AVAudioPlayer(data: data)
        super.init()
        player.delegate = self
        player.prepareToPlay()
    }

    func start() {
        if !VoiceCallAudioSessionManager.shared.isVoiceCallActive {
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .default)
            try? session.setActive(true)
        }
        player.play()
    }

    func stop() {
        player.stop()
        releaseSession()
    }

    /// 断点暂停（D1）：只停声——不释放会话、不动
    /// delegate，player 的 currentTime 原地保留，
    /// resume 后 play() 即从断点续播（stop() 会连
    /// prepared 资源一并丢弃，两者不可混用）
    func pause() {
        player.pause()
    }

    /// 断点续播（D1）：暂停期间会话未释放、通常仍
    /// 激活；仍幂等重设一次类别并激活，防打断等外
    /// 部因素动过会话后静默无声
    func resume() {
        if !VoiceCallAudioSessionManager.shared.isVoiceCallActive {
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .default)
            try? session.setActive(true)
        }
        player.play()
    }

    private func releaseSession() {
        // 全双工语音通话进行中时，保留 `.playAndRecord` + `.voiceChat` 硬件 AEC 会话，
        // 避免播放完毕停用会话导致麦克风和蓝牙路由掉线
        guard !VoiceCallAudioSessionManager.shared.isVoiceCallActive else { return }
        try? AVAudioSession.sharedInstance().setActive(
            false, options: [.notifyOthersOnDeactivation]
        )
    }

    // AVAudioPlayerDelegate：回调隔离口径（2026-
    // 11-10 铁律）——本回调不碰任何 actor 隔离状态，
    // 只读本引擎的闭包并显式跳回主隔离执行
    func audioPlayerDidFinishPlaying(
        _ player: AVAudioPlayer, successfully flag: Bool
    ) {
        releaseSession()
        Task { @MainActor [weak self] in
            guard let self else { return }
            if flag {
                onNaturalFinish?()
            } else {
                onPlaybackFailure?("这次朗读没成功。")
            }
        }
    }

    func audioPlayerDecodeErrorDidOccur(
        _ player: AVAudioPlayer, error: Error?
    ) {
        releaseSession()
        Task { @MainActor [weak self] in
            self?.onPlaybackFailure?("这次朗读没成功。")
        }
    }
}

/// 协议一致性隔离在主 actor：两个回调闭包只在主隔离
/// 读写（消费方 SpeechPlayer 全程 @MainActor），系统
/// delegate 回调留在非隔离上下文、只跳回主隔离执行
/// （2026-11-10 回调隔离铁律），不把类整体标 @MainActor
extension AVSpeechAudioEngine: @MainActor SpeechAudioEngine {}

/// 朗读播放器（H2-a，台账 159）：状态机在 Core
/// （SpeechPlaybackMachine），本层只做效果执行——
/// 发 speak 请求、喂引擎、管可用性精修与会话打断。
/// 全 App 单例：一处出声，点另一条即切换（状态机
/// 语义），设置页与聊天页共读同一份可用性。
@MainActor
@Observable
final class SpeechPlayer {
    static let shared = SpeechPlayer()

    /// speak 执行口（注入点在「带 appState 跑一次合
    /// 成」这一层）：生产走 performAdmin＋client，
    /// 测试注入脚本
    typealias SpeakService =
        @MainActor (AppState, String) async throws -> SpeakResponse
    /// voice-config 执行口（注入点同上）
    typealias VoiceConfigService =
        @MainActor (AppState) async throws -> VoiceConfigResponse
    /// 引擎工厂（注入点）：数据坏在此抛错、归播放失败
    typealias EngineFactory =
        @MainActor (Data) throws -> SpeechAudioEngine

    private(set) var machine = SpeechPlaybackMachine()
    private(set) var availability: VoiceAvailability = .unknown
    /// 最近一次 speak 回执的 provider（音色展示的数
    /// 据源——voice-config 不给音色、elevenlabs 与
    /// 实际合成不是同一家，探活 §2.4）
    private(set) var lastProvider: String?

    private let speakService: SpeakService
    private let voiceConfigService: VoiceConfigService
    private let engineFactory: EngineFactory
    private var engine: SpeechAudioEngine?
    private var requestTask: Task<Void, Never>?
    private var lastConfigFetchAt: Date?
    private var configFetchInFlight = false
    /// 只在 init 写一次、deinit 读一次移除——deinit 是
    /// 非隔离上下文，故标 nonisolated(unsafe)（写入发生
    /// 在对象发布之前、无并发读者）
    private nonisolated(unsafe) var interruptionObserver:
        NSObjectProtocol?

    init(
        speakService: @escaping SpeakService = SpeechPlayer.liveSpeakService,
        voiceConfigService: @escaping VoiceConfigService =
            SpeechPlayer.liveVoiceConfigService,
        engineFactory: @escaping EngineFactory =
            SpeechPlayer.liveEngineFactory
    ) {
        self.speakService = speakService
        self.voiceConfigService = voiceConfigService
        self.engineFactory = engineFactory
        // 音频打断（来电等）：开始即暂停（D1 改判：
        // 通行做法是暂停而非全停——系统已自动哑掉
        // 输出，此处主职是同步状态机与播放条进暂停
        // 态；挂断后不自动续播，用户在条上点继续）；
        // 系统回调不继承隔离，闭包内只跳回主隔离
        interruptionObserver = NotificationCenter.default
            .addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: AVAudioSession.sharedInstance(),
                queue: .main
            ) { [weak self] notification in
                let raw = notification.userInfo?[
                    AVAudioSessionInterruptionTypeKey
                ] as? UInt
                guard raw == AVAudioSession.InterruptionType
                    .began.rawValue else { return }
                Task { @MainActor [weak self] in
                    self?.pause()
                }
            }
    }

    deinit {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(
                interruptionObserver
            )
        }
    }

    // MARK: - 生产执行口

    static func liveSpeakService(
        appState: AppState, text: String
    ) async throws -> SpeakResponse {
        try await appState.performAdmin { client, config in
            try await client.speak(config: config, text: text)
        }
    }

    static func liveVoiceConfigService(
        appState: AppState
    ) async throws -> VoiceConfigResponse {
        try await appState.performAdmin { client, config in
            try await client.voiceConfig(config: config)
        }
    }

    static func liveEngineFactory(
        data: Data
    ) throws -> SpeechAudioEngine {
        try AVSpeechAudioEngine(data: data)
    }

    // MARK: - 可用性

    /// 读 voice-config 刷新可用性（节流 300 秒，进对
    /// 话页/设置页时调）：合并口径在 Core——配置证
    /// 伪可定未开通、暂定可用不许翻 speak 已证伪的
    /// 态；拉失败不改现态（未知保持未知，不造假）
    func refreshAvailability(
        appState: AppState, force: Bool = false
    ) async {
        if !force, let last = lastConfigFetchAt,
           Date().timeIntervalSince(last) < 300 {
            return
        }
        guard !configFetchInFlight else { return }
        configFetchInFlight = true
        lastConfigFetchAt = Date()
        defer { configFetchInFlight = false }
        do {
            let config = try await voiceConfigService(appState)
            availability = VoiceAvailability
                .mergingConfigAssessment(
                    current: availability,
                    assessed: VoiceAvailability.assess(
                        config: config
                    )
                )
        } catch {
            // 拉不到不改现态
        }
    }

    /// 进页触发口（同步面只许起任务，不许 await）
    func refreshAvailabilityOnAppear(appState: AppState) {
        Task { await refreshAvailability(appState: appState) }
    }

    // MARK: - 播放控制

    /// 长按菜单「朗读/停止朗读」：状态机 tap 语义
    /// （同条停、异条切换、失败重试）
    func toggle(
        entryID: UUID, content: String, appState: AppState
    ) {
        let effects = machine.tap(entryID: entryID)
        run(effects, entryID: entryID, content: content,
            appState: appState)
    }

    /// 自动朗读新回复（设置开关开时由落定点调用）：
    /// 只在静默/失败态起播——用户正在听别条时不抢、
    /// 主动暂停时更不许抢（D1）；可用性已证伪（未
    /// 开通）时不出声、不报错
    func autoRead(
        entryID: UUID, content: String, appState: AppState
    ) {
        guard availability != .unavailable else { return }
        switch machine.state {
        case .idle, .failed:
            break
        case .requesting, .playing, .paused:
            return
        }
        let effects = machine.tap(entryID: entryID)
        run(effects, entryID: entryID, content: content,
            appState: appState)
    }

    /// 落定自动朗读的唯一入口（§411）：开关判读收
    /// 在播放器内——关（默认）＝静默返回，落定点不
    /// 再自己读偏好；开＝走 autoRead 既有口径（不
    /// 抢播、未开通不出声）
    func autoReadIfEnabled(
        entryID: UUID, content: String, appState: AppState
    ) {
        guard VoiceSpeechPreferences.autoReadEnabled
        else { return }
        autoRead(
            entryID: entryID, content: content,
            appState: appState
        )
    }

    /// 停播（离开页面/发送新消息/开始听写共用）：
    /// 活动态拆请求与引擎，静默态空转。已暂停同拆
    /// ——断点只在播放条暂停/继续之间活，其余停因
    /// 一律全停（状态机 stop 口径）
    func stop() {
        for effect in machine.stop() where effect == .tearDown {
            tearDown()
        }
    }

    /// 断点暂停（播放条主钮/音频打断共用）：只转发
    /// 当前引擎——不 tearDown、不取消请求（暂停只
    /// 发生在播放态，此时无请求在飞），引擎实例与
    /// 进度原地保留
    func pause() {
        runEngineEffects(machine.pause())
    }

    /// 断点续播（播放条主钮）：同 pause 口径，只转
    /// 发当前引擎从断点续播，不重发 speak 请求
    func resume() {
        runEngineEffects(machine.resume())
    }

    private func run(
        _ effects: [SpeechPlaybackMachine.Effect],
        entryID: UUID, content: String, appState: AppState
    ) {
        for effect in effects {
            switch effect {
            case .tearDown:
                tearDown()
            case .startRequest(let id):
                startRequest(
                    entryID: id, content: content,
                    appState: appState
                )
            case .beginPlayback:
                // tap 不产此效果（由请求成功点直产）
                break
            case .pausePlayback:
                engine?.pause()
            case .resumePlayback:
                engine?.resume()
            }
        }
    }

    /// 暂停/继续效果执行：这两件效果不需要条目/
    /// 正文/连接上下文，只转发当前引擎
    private func runEngineEffects(
        _ effects: [SpeechPlaybackMachine.Effect]
    ) {
        for effect in effects {
            switch effect {
            case .pausePlayback:
                engine?.pause()
            case .resumePlayback:
                engine?.resume()
            case .tearDown, .startRequest, .beginPlayback:
                // pause()/resume() 只产暂停/继续两件
                break
            }
        }
    }

    private func tearDown() {
        requestTask?.cancel()
        requestTask = nil
        engine?.stop()
        engine = nil
    }

    private func startRequest(
        entryID: UUID, content: String, appState: AppState
    ) {
        requestTask?.cancel()
        requestTask = Task { @MainActor [weak self] in
            guard let self else { return }
            // 文本预处理：剥完为空（纯图片/纯标记回
            // 复）不发请求，如实落失败态
            guard let text = SpeechText.make(
                fromMarkdown: content
            ) else {
                _ = machine.requestFailed(
                    entryID: entryID,
                    message: "这条回复没有可朗读的文字。"
                )
                return
            }
            // 首次点朗读且可用性未知：先读配置——配
            // 置证伪未开通就不发 speak（施工图口径）
            if availability == .unknown {
                await refreshAvailability(
                    appState: appState, force: true
                )
                if availability == .unavailable {
                    _ = machine.requestFailed(
                        entryID: entryID,
                        message: "这台服务器还没开通朗读。"
                    )
                    return
                }
            }
            do {
                let response = try await speakService(
                    appState, text
                )
                guard !Task.isCancelled else { return }
                availability = VoiceAvailability.refined(
                    current: availability, by: .succeeded
                )
                if let provider = response.provider {
                    lastProvider = provider
                }
                let effects = machine.requestSucceeded(
                    entryID: entryID
                )
                // 态已被切走（用户停了/切了条）：回执
                // 丢弃，不许把上一条的音频播出来
                guard effects.contains(
                    .beginPlayback(entryID: entryID)
                ) else { return }
                guard let data = response.audioData else {
                    _ = machine.playbackFailed(
                        entryID: entryID,
                        message: "这次朗读没成功。"
                    )
                    return
                }
                beginPlayback(entryID: entryID, data: data)
            } catch let error as HermesError {
                guard !Task.isCancelled else { return }
                if error.isSpeechProviderUnavailable {
                    availability = VoiceAvailability.refined(
                        current: availability,
                        by: .providerUnavailable
                    )
                    _ = machine.requestFailed(
                        entryID: entryID,
                        message: "这台服务器还没开通朗读。"
                    )
                } else if case .demoLimitReached = error {
                    _ = machine.requestFailed(
                        entryID: entryID,
                        message: error.userMessage
                    )
                } else {
                    _ = machine.requestFailed(
                        entryID: entryID,
                        message: "这次朗读没成功。"
                    )
                }
            } catch {
                guard !Task.isCancelled else { return }
                _ = machine.requestFailed(
                    entryID: entryID,
                    message: "这次朗读没成功。"
                )
            }
        }
    }

    private func beginPlayback(entryID: UUID, data: Data) {
        do {
            let newEngine = try engineFactory(data)
            newEngine.onNaturalFinish = { [weak self] in
                guard let self else { return }
                _ = machine.playbackFinished(entryID: entryID)
                // 只清自己这台：迟到回调不许把已切换
                // 的新引擎引用抹掉（状态机已按条目
                // id 对账，这里只管引用卫生）
                if engine === newEngine { engine = nil }
            }
            newEngine.onPlaybackFailure = { [weak self] message in
                guard let self else { return }
                _ = machine.playbackFailed(
                    entryID: entryID, message: message
                )
                if engine === newEngine { engine = nil }
            }
            engine = newEngine
            newEngine.start()
        } catch {
            _ = machine.playbackFailed(
                entryID: entryID, message: "这次朗读没成功。"
            )
        }
    }
}
