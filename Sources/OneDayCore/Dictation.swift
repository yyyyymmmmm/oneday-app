import Foundation
import os

/// 语音输入纯逻辑层（0.36.6，DESIGN-V4 §71；规格
/// voice-input-spec-20261110.md §3）：状态机守卫、转写
/// 会话合并、电平平滑/波形、计时与静音判定全在此处
/// 纯函数化，App 层（DictationController）只做引擎与
/// 系统 API 的接线。红线：只走端上识别，录音不出手机；
/// 本文件不碰任何音频/网络 API。

/// 五相位＋失败相（规格 §3.5：待机/请求权限/准备中/
/// 录音中/收尾/失败；请求权限在本实现里由预备页承担
/// 呈现、相位仍单列以便守卫与测试）
public enum DictationPhase: String, Sendable, Equatable, CaseIterable {
    case idle
    case requestingPermission
    case preparing
    case recording
    case finishing
    case failed
}

/// 相位转移守卫：只许表内转移，迟到回调想把已落定的
/// 相位拽回录音中等一律拒绝（规格 §3.5「迟到回调作废」
/// 的相位面）
public enum DictationPhasePolicy {
    public static func canTransition(
        from: DictationPhase, to: DictationPhase
    ) -> Bool {
        if from == to { return true }
        switch (from, to) {
        case (.idle, .requestingPermission),
             (.idle, .preparing),
             (.idle, .recording),
             (.idle, .failed),
             (.failed, .requestingPermission),
             (.failed, .preparing),
             (.failed, .recording),
             (.failed, .idle),
             (.requestingPermission, .preparing),
             (.requestingPermission, .recording),
             (.requestingPermission, .idle),
             (.requestingPermission, .failed),
             (.preparing, .recording),
             (.preparing, .idle),
             (.preparing, .failed),
             (.recording, .finishing),
             (.recording, .failed),
             (.finishing, .idle),
             (.finishing, .failed):
            return true
        default:
            return false
        }
    }
}

/// 失败分类（App 层据此配三段式文案：发生了什么＋
/// 影响＋怎么办，续编 S10）
public enum DictationFailure: String, Sendable, Equatable, CaseIterable {
    /// 麦克风权限被拒/受限（0.36.8 起只此一道权限门：
    /// SpeechAnalyzer 路线官方口径不需要语音识别授权）
    case permissionDenied
    /// 停录时一个字都没识别到
    case nothingHeard
    /// 来电等系统中断打断录音（已定稿内容保留）
    case interrupted
    /// 引擎/语言不受本机支持且回退链走尽
    case engineUnavailable
    /// 语言模型资产下载失败（可重试）
    case assetDownloadFailed
    /// 引擎运行期抛错（已定稿保留、未定稿弃）
    case engineError
}

/// 识别语言（规格 §3.4：预备页同页选择，存本地偏好）。
/// 粤语首选 yue_CN（SpeechTranscriber 支持列表在列），
/// 规范化失败时回退 zh_HK
public enum DictationLanguage: String, Sendable, Equatable, CaseIterable {
    case mandarin
    case cantonese
    case english

    public var localeIdentifier: String {
        switch self {
        case .mandarin: return "zh_CN"
        case .cantonese: return "yue_CN"
        case .english: return "en_US"
        }
    }

    public var fallbackLocaleIdentifier: String? {
        switch self {
        case .cantonese: return "zh_HK"
        default: return nil
        }
    }

    public var displayName: String {
        switch self {
        case .mandarin: return "普通话"
        case .cantonese: return "粤语"
        case .english: return "英语"
        }
    }
}

/// 转写会话合并（规格 §3.1/§3.3 的数据面）：开录时
/// 记下既有草稿为 baseDraft；识别结果分两桶——final
/// 段只追加、volatile 段整段替换（禁逐字追加，防跳
/// 字）；停录落稿＝base＋final（＋可选带上 volatile）；
/// 取消＝只回 base，本次段整段丢弃
public struct DictationSession: Sendable, Equatable {
    public private(set) var baseDraft: String
    public private(set) var finalized: String = ""
    public private(set) var volatile: String = ""

    public init(baseDraft: String) {
        self.baseDraft = baseDraft
    }

    /// 一条识别结果：final 追加定稿并清 volatile；
    /// volatile 整段替换当前未定稿段
    public mutating func applyResult(text: String, isFinal: Bool) {
        if isFinal {
            finalized += text
            volatile = ""
        } else {
            volatile = text
        }
    }

    /// 本次口述已识别到的全部文字（定稿＋未定稿）
    public var recognizedText: String { finalized + volatile }

    public var hasRecognizedText: Bool { !recognizedText.isEmpty }

    /// 录音中文本视图应显示的全文（草稿＋定稿＋未定稿）
    public var displayText: String {
        Self.join(base: baseDraft, segment: recognizedText)
    }

    /// 未定稿段在 displayText 中的字数（渲染层据此
    /// 把尾段染灰；按 Character 计，与 SwiftUI/
    /// NSString 桥接时由 App 层换算）
    public var volatileLength: Int { volatile.count }

    /// 落稿文本：includeVolatile=false 时未定稿段丢弃
    /// （引擎抛错路径）；取消路径直接取 baseDraft
    public func committedText(includeVolatile: Bool) -> String {
        Self.join(
            base: baseDraft,
            segment: includeVolatile ? recognizedText : finalized
        )
    }

    /// 草稿与口述段的拼接：两段相邻字符同为 ASCII
    /// 字母/数字时补一个空格（英文草稿续说场景）；
    /// 中文相邻不加空格；任一段为空直接返回另一段
    static func join(base: String, segment: String) -> String {
        guard !base.isEmpty else { return segment }
        guard !segment.isEmpty else { return base }
        if let last = base.last, let first = segment.first,
           last.isASCII, first.isASCII,
           (last.isLetter || last.isNumber),
           (first.isLetter || first.isNumber) {
            return base + " " + segment
        }
        return base + segment
    }
}

/// 电平换算与平滑（规格 §3.2）：tap 逐 buffer 算 RMS
/// →dB→归一化；平滑用一阶低通，快攻慢放（起音要跟
/// 手、落音不许抖）
public enum DictationLevel {
    /// 静音下限（dBFS）：低于此值归 0
    public static let floorDB: Double = -50
    /// 满格点（dBFS）：高于此值归 1
    public static let ceilingDB: Double = -10

    public static func normalizedLevel(rms: Double) -> Double {
        guard rms > 0 else { return 0 }
        let db = 20 * log10(rms)
        let raw = (db - floorDB) / (ceilingDB - floorDB)
        return min(1, max(0, raw))
    }

    /// PCM Float 样本的 RMS（App 层从 tap buffer 取
    /// channel 0 样本喂进来；空数组回 0）
    public static func rms(samples: [Float]) -> Double {
        guard !samples.isEmpty else { return 0 }
        var sum: Double = 0
        for sample in samples {
            sum += Double(sample) * Double(sample)
        }
        return sqrt(sum / Double(samples.count))
    }
}

/// 一阶低通平滑器：目标高于现值走快攻时间常数、
/// 低于走慢放（规格 §3.2：快攻约 60ms、慢放约 180ms）
public struct DictationLevelSmoother: Sendable, Equatable {
    public static let attackTau: Double = 0.06
    public static let releaseTau: Double = 0.18

    public private(set) var level: Double = 0

    public init() {}

    @discardableResult
    public mutating func ingest(rms: Double, dt: Double) -> Double {
        let target = DictationLevel.normalizedLevel(rms: rms)
        let tau = target > level ? Self.attackTau : Self.releaseTau
        let alpha = dt > 0 ? 1 - exp(-dt / tau) : 0
        level += (target - level) * alpha
        return level
    }

    public mutating func reset() { level = 0 }
}

/// 波形采样环（规格 §3.2：9 根竖条，最新值从右端
/// 进入、整体左移——与真实电平一一对应，禁假动画）
public struct DictationWaveform: Sendable, Equatable {
    public static let barCount = 9

    public private(set) var bars: [Double] =
        Array(repeating: 0, count: DictationWaveform.barCount)

    public init() {}

    public mutating func push(_ level: Double) {
        bars.removeFirst()
        bars.append(min(1, max(0, level)))
    }

    public mutating func reset() {
        bars = Array(repeating: 0, count: Self.barCount)
    }
}

/// 计时与上限政策（规格 §3.1：单次 5 分钟上限、
/// 4:30 起警示、到限自动定稿）
public enum DictationTiming {
    public static let limitSeconds = 300
    public static let warningSeconds = 270

    public static func isWarning(elapsedSeconds: Int) -> Bool {
        elapsedSeconds >= warningSeconds
    }

    public static func reachedLimit(elapsedSeconds: Int) -> Bool {
        elapsedSeconds >= limitSeconds
    }

    /// m:ss 呈现（0:07 / 4:59 / 5:00），负数归 0
    public static func format(elapsedSeconds: Int) -> String {
        let clamped = max(0, elapsedSeconds)
        return String(format: "%d:%02d", clamped / 60, clamped % 60)
    }
}

/// 连续静音判定（规格 §3.1：连续 10 秒无声只出提
/// 示行、不停录；有声即清零）
public struct SilenceTracker: Sendable, Equatable {
    public static let promptAfterSeconds: Double = 10
    /// 归一化电平低于此值算「无声」
    public static let silenceLevelThreshold: Double = 0.05

    public private(set) var silentDuration: Double = 0

    public init() {}

    /// 喂入归一化电平与时间步长，返回当前是否应显
    /// 示「还没听到声音」提示
    @discardableResult
    public mutating func ingest(level: Double, dt: Double) -> Bool {
        if level < Self.silenceLevelThreshold {
            silentDuration += max(0, dt)
        } else {
            silentDuration = 0
        }
        return silentDuration >= Self.promptAfterSeconds
    }

    public mutating func reset() { silentDuration = 0 }
}

/// tap 格式有效性门（0.36.8 热修，诊断 voice-crash-
/// diagnosis-20261110.md §2/§5.2）：首次授权刚通过时
/// 输入硬件格式可合法地报出采样率 0，未经校验就递给
/// installTap/AVAudioConverter 会触发 AVFAudio 的
/// NSException（Swift catch 不住、进程当场死）。开录
/// 前读到的格式快照必须先过此门，无效宁可报不可用
public enum DictationAudioFormatPolicy {
    /// 格式可安全用于音频链的最低条件：采样率与声
    /// 道数都为正且采样率有限（NaN/∞ 不许过门）
    public static func isUsable(
        sampleRate: Double, channelCount: Int
    ) -> Bool {
        sampleRate.isFinite && sampleRate > 0 && channelCount > 0
    }

    /// 转码比值（输出采样率÷输入采样率）：任一端非
    /// 正/非有限则无可用比值，调用方整帧丢弃——不许
    /// 拿 inf/NaN 去做帧数换算（UInt32(∞) 是运行时
    /// trap，诊断 §1 候选 3）
    public static func conversionRatio(
        inputSampleRate: Double, outputSampleRate: Double
    ) -> Double? {
        guard isUsable(sampleRate: inputSampleRate, channelCount: 1),
              isUsable(sampleRate: outputSampleRate, channelCount: 1)
        else { return nil }
        let ratio = outputSampleRate / inputSampleRate
        guard ratio.isFinite, ratio > 0 else { return nil }
        return ratio
    }
}

/// 引擎故障信号的传播政策（0.36.8 热修，诊断 §6 附
/// 带发现）：analyzer.start/结果流抛错可能发生在相
/// 位进入 .recording 之前，旧实现按 phase==.recording
/// 守卫会把启动期错误静默吞掉、随后照常进录音态，
/// 出现「录音条在走、永不出字」的假录音。错误必达
/// 失败态：录音中→失败收尾；启动中→闩住作废（宣布
/// started 前由启动方检查并拆除管道）；已落定/收尾
/// 中→迟到信号作废
///
/// 0.36.12 残口收口（诊断 dictation-nolive §断点 2）：
/// 资产已装时 startEngine 全程停在 .idle 直到末尾才
/// 进 .recording——.idle 窗正是启动窗的一部分，此
/// 窗内抛错旧映射 .ignore 等于把 0.36.8 要根除的假
/// 录音模式留了个后门。.idle 并入 abortStartup：此
/// 时能产生故障信号的只有本代次的启动管道（结果/分
/// 析任务只在启动尝试内存在、收尾后代次递增使迟到
/// 信号先被代次守卫作废），并入无误伤面
public enum DictationFaultPolicy {
    public enum Action: String, Sendable, Equatable {
        /// 已在录音：走 .engineError 失败收尾
        case finishWithError
        /// 尚在启动（请求权限/准备中/启动窗的 .idle）：
        /// 置闩作废本次启动，绝不许进录音态
        case abortStartup
        /// 代次不符或相位已落定：迟到信号，不理
        case ignore
    }

    public static func action(
        generationMatches: Bool, phase: DictationPhase
    ) -> Action {
        guard generationMatches else { return .ignore }
        switch phase {
        case .recording:
            return .finishWithError
        case .requestingPermission, .preparing, .idle:
            return .abortStartup
        case .finishing, .failed:
            return .ignore
        }
    }
}

/// 麦克风权限状态（Core 口径）：App 层只做系统枚举
/// （AVAudioApplication.recordPermission）→本枚举的
/// 映射，判定全走 MicPermissionGate 单点，不散写
public enum MicPermissionStatus: String, Sendable, Equatable, CaseIterable {
    case granted
    case denied
    case undetermined
}

/// 麦克风权限同步门（0.36.9 热修二轮，与礼记
/// liqian-app 同案终局对齐）：礼记同症状猜错两轮
/// （权限文案、格式闸门都修了仍崩），最终靠崩溃日
/// 志破案——权限早已授过、处于「已决定」状态时，
/// 代码每次仍重走异步授权回调（requestRecord-
/// Permission 的 completion 续体）；iOS 26 上这类
/// 回调由系统在特殊线程投递、闭包线程隔离对不上
/// 就在回调入口崩，专挑已决定状态触发、不弹框点
/// 就崩。铁律：先同步读状态；已授权直接启动、永
/// 不重走异步回调；已拒绝走失败降级；只有真未决
/// 定才许发那唯一一次异步请求
public enum MicPermissionGate {
    public enum Action: String, Sendable, Equatable {
        /// 已授权：直接启动业务，绝不重走异步回调
        case start
        /// 已拒绝：失败降级，不弹系统窗、不发请求
        case failDenied
        /// 未决定：唯一允许发异步授权请求的情形
        /// （入口点按处＝先开预备页讲用途；预备页
        /// 确认后＝发那一次请求）
        case requestOnce
    }

    public static func action(for status: MicPermissionStatus) -> Action {
        switch status {
        case .granted:
            return .start
        case .denied:
            return .failDenied
        case .undetermined:
            return .requestOnce
        }
    }
}

/// 听写 tap 喂入盒（0.36.11，DESIGN-V4 §76）：实时
/// 音频线程侧喂入的纯逻辑核——nonisolated 终类、内部
/// 以 OSAllocatedUnfairLock 护状态，设计前提就是
/// 「从任意队列被调用」：tap 回调在 RealtimeMessenger
/// 实时线程投递，本盒若属任何 actor、或方法带隔离，
/// 回调入口的隔离断言即真机闪退的那一类（.ips 实锤：
/// _swift_task_checkIsolatedSwift →
/// dispatch_assert_queue_fail → EXC_BREAKPOINT，
/// 证据 voice-crash-ips-20261110-2117.ips）。App 侧
/// DictationAudioPipe 只做 AVFoundation 转码、把样本
/// 喂进来；电平由主线程 10Hz 轮询 latestRMS 取走，
/// 控制器状态从不经 tap 线程回写。
public final class DictationAudioFeedBox: @unchecked Sendable {
    private let state = OSAllocatedUnfairLock(
        initialState: (rms: 0.0, buffers: 0))

    public init() {}

    /// 喂入一帧样本：算 RMS 并记账。任意队列可调、
    /// 无隔离依赖（单测以并发队列＋detached 任务钉死）
    public func ingest(samples: [Float]) {
        let value = DictationLevel.rms(samples: samples)
        state.withLock { current in
            current.rms = value
            current.buffers += 1
        }
    }

    /// 最近一帧的 RMS（主线程轮询取电平用）
    public var latestRMS: Double {
        state.withLock { $0.rms }
    }

    /// 已喂入的 buffer 数（诊断/测试记账）
    public var ingestedBufferCount: Int {
        state.withLock { $0.buffers }
    }

    public func reset() {
        state.withLock { current in
            current.rms = 0
            current.buffers = 0
        }
    }
}

/// 起步时序点（0.36.15，语音延迟修复包）：首结果
/// 迟到型的量尺四点——点麦克风（零点）→音频引擎
/// 启动→分析器 start 调用→首条结果（vol/fin 不
/// 分型，第一条到达即记）。零点的口径：已授权直达
/// 时为点按本身；首用预备页路径为确认/授权通过的
/// 那一刻（读说明的时间不是管道延迟，不计入）
public enum DictationStartPoint: String, Sendable, Equatable, CaseIterable {
    case engineStarted
    case analyzerStarted
    case firstResult
}

/// 起步时序钟（纯逻辑）：uptime 由 App 层喂单调时
/// 钟（systemUptime），本结构只做相对毫秒换算与拼
/// 串——每点只认第一次到达（迟到的重复打点作废，
/// 与代次守卫同精神）；未 begin 时 mark 一律忽略
public struct DictationStartTiming: Sendable, Equatable {
    public private(set) var originUptime: TimeInterval?
    public private(set) var offsetsMs: [DictationStartPoint: Int] = [:]

    public init() {}

    /// 起点：开新一轮（旧轮各点清空）
    public mutating func begin(atUptime uptime: TimeInterval) {
        originUptime = uptime
        offsetsMs = [:]
    }

    /// 整轮作废（收尾/弃置时调用，防迟到打点污染
    /// 下一轮的诊断串）
    public mutating func reset() {
        originUptime = nil
        offsetsMs = [:]
    }

    /// 记一个点：相对零点的毫秒（时钟回拨等异常
    /// 钳到 0，不许出负数）；同点已有值则忽略
    public mutating func mark(
        _ point: DictationStartPoint, atUptime uptime: TimeInterval
    ) {
        guard let originUptime, offsetsMs[point] == nil else { return }
        offsetsMs[point] = max(0, Int((uptime - originUptime) * 1000))
    }

    public func offsetMs(_ point: DictationStartPoint) -> Int? {
        offsetsMs[point]
    }

    /// 首结果相对零点的毫秒（本案的 headline 数字）
    public var firstResultMs: Int? { offsetsMs[.firstResult] }

    /// 诊断串时序段：已到点按时序拼
    /// `eng+85ms ana+210ms 首结果+10234ms`；一
    /// 点未到返回空串（诊断行不留半截占位）
    public var diagnosticSegment: String {
        var parts: [String] = []
        if let value = offsetsMs[.engineStarted] {
            parts.append("eng+\(value)ms")
        }
        if let value = offsetsMs[.analyzerStarted] {
            parts.append("ana+\(value)ms")
        }
        if let value = offsetsMs[.firstResult] {
            parts.append("首结果+\(value)ms")
        }
        return parts.joined(separator: " ")
    }
}

/// 预热状态（0.36.15）：分析器在点麦克风之前备齐
/// 的四态——冷（无产物）／备中／已备（可消费）／
/// 备失败（不挡路，点按走冷路径兜底）
public enum DictationPreheatState: String, Sendable, Equatable, CaseIterable {
    case cold
    case warming
    case ready
    case failed
}

/// 预热事件（0.36.15）
public enum DictationPreheatEvent: String, Sendable, Equatable, CaseIterable {
    /// 发起一轮预热（冷/失败态才放行）
    case beginWarm
    case warmSucceeded
    case warmFailed
    /// 已备产物被一段录音消费（分析器单次使用制，
    /// 消费即回冷态，录后由控制器发起下一轮）
    case consume
    /// 弃置（语言变更/退后台/离开页面）：备中取消、
    /// 已备弃置，一律回冷态
    case invalidate
}

/// 预热状态机（纯政策）：转移全表在此单点，控制
/// 器只存状态与产物、不散写转移。表外组合一律保
/// 持原态（迟到事件不许把状态拽回头）
public enum DictationPreheatPolicy {
    public static func transition(
        from state: DictationPreheatState,
        event: DictationPreheatEvent
    ) -> DictationPreheatState {
        switch (state, event) {
        case (.cold, .beginWarm), (.failed, .beginWarm):
            return .warming
        case (.warming, .warmSucceeded):
            return .ready
        case (.warming, .warmFailed):
            return .failed
        case (.ready, .consume):
            return .cold
        case (.warming, .invalidate), (.ready, .invalidate),
             (.failed, .invalidate):
            return .cold
        default:
            return state
        }
    }

    /// 可否发起新一轮预热（已备/备中不起第二轮）
    public static func canBeginWarm(_ state: DictationPreheatState) -> Bool {
        state == .cold || state == .failed
    }
}
