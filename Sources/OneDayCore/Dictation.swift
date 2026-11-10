import Foundation

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
public enum DictationFaultPolicy {
    public enum Action: String, Sendable, Equatable {
        /// 已在录音：走 .engineError 失败收尾
        case finishWithError
        /// 尚在启动（请求权限/准备中）：置闩作废本次
        /// 启动，绝不许进录音态
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
        case .requestingPermission, .preparing:
            return .abortStartup
        case .idle, .finishing, .failed:
            return .ignore
        }
    }
}
