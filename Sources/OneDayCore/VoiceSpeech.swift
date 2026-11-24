import Foundation

// MARK: - Hermes 服务端语音 DTO（H2-a 朗读，台账 159）
//
// 契约据 2026-11-20 H2-0 探活＋开通复探冻结（pkg-
// hermes-voice-probe-20261120 §二／pkg-hermes-voice-
// enable-20261120 §三）：speak 出参为 JSON 内嵌 base64
// data_url（非二进制流、非裸 URL）；voice-config 不给
// Bool 式可用标志——mode 恒 relay、tts.reason 在开通
// 前后逐字不变（「provider 'edge' has no client wire」
// 是 relay 拓扑描述、不是缺口自报），可用性判定不许
// 只读 reason/mode，须组合字段并以 speak 实调为准
// （判定与精修口径见 VoiceAvailability）。

/// GET /api/audio/voice-config：语音配置读面（可用性
/// 总闸的数据源，但不是判定本身，见类头注）
public struct VoiceConfigResponse: Decodable, Sendable, Equatable {
    public struct Mode: Decodable, Sendable, Equatable {
        public let mode: String
        public let reason: String?
        /// 仅 stt 侧带（两 dict 字段不对称，探活 §1.1）
        public let streaming: Bool?

        public init(mode: String, reason: String?, streaming: Bool?) {
            self.mode = mode
            self.reason = reason
            self.streaming = streaming
        }
    }

    public let ok: Bool
    public let stt: Mode?
    public let tts: Mode?

    public init(ok: Bool, stt: Mode?, tts: Mode?) {
        self.ok = ok
        self.stt = stt
        self.tts = tts
    }
}

/// POST /api/audio/speak 成功回执（开通复探实测形态）：
/// `{ok, data_url: "data:audio/mpeg;base64,…",
/// mime_type: "audio/mpeg", provider: "edge"}`
public struct SpeakResponse: Decodable, Sendable, Equatable {
    public let ok: Bool
    public let dataURL: String
    public let mimeType: String?
    public let provider: String?

    enum CodingKeys: String, CodingKey {
        case ok
        case dataURL = "data_url"
        case mimeType = "mime_type"
        case provider
    }

    public init(
        ok: Bool, dataURL: String,
        mimeType: String?, provider: String?
    ) {
        self.ok = ok
        self.dataURL = dataURL
        self.mimeType = mimeType
        self.provider = provider
    }

    /// 播放器可直接消费的音频字节：data_url 的 base64
    /// 段解码；形态不对（无逗号/非 base64/解出空）返
    /// 回 nil——调用方按「这次朗读没成功」处理，不许
    /// 拿坏数据喂播放器
    public var audioData: Data? {
        SpeechAudioData.decode(dataURL: dataURL)
    }
}

/// data_url → 字节（纯函数，钉测把守）：只认
/// `data:<mime>;base64,<payload>` 形态
public enum SpeechAudioData {
    public static func decode(dataURL: String) -> Data? {
        guard let comma = dataURL.firstIndex(of: ",") else {
            return nil
        }
        let header = dataURL[..<comma]
        guard header.hasPrefix("data:"),
              header.hasSuffix(";base64") else { return nil }
        let payload = String(dataURL[dataURL.index(after: comma)...])
        guard !payload.isEmpty,
              let data = Data(base64Encoded: payload),
              !data.isEmpty else { return nil }
        return data
    }
}

/// GET /api/audio/elevenlabs/voices（只读展示数据源之
/// 一；现役实例未配 ElevenLabs、恒 available:false。
/// 注意：speak 的实际合成 provider 是 edge，与本端点
/// 不是同一家——音色展示以 voice-config／speak 回执
/// 的 provider 为准，不以本端点为准，探活 §2.4 定版）
public struct ElevenLabsVoicesResponse: Decodable, Sendable, Equatable {
    public struct Voice: Decodable, Sendable, Equatable {
        public let voiceID: String?
        public let name: String?

        enum CodingKeys: String, CodingKey {
            case voiceID = "voice_id"
            case name
        }

        public init(voiceID: String?, name: String?) {
            self.voiceID = voiceID
            self.name = name
        }
    }

    public let available: Bool
    public let voices: [Voice]
    /// key 被拒分支带 error:"unauthorized"（探活 §2.4）
    public let error: String?

    public init(available: Bool, voices: [Voice], error: String?) {
        self.available = available
        self.voices = voices
        self.error = error
    }
}

// MARK: - 可用性判定（组合字段＋speak 实调精修）

/// 朗读可用性三态：可用／未开通／未知。未知＝还没读
/// 到配置或读取失败——不造假成任何一端（设置行显
/// 「未知」、菜单项先按未确认处理，见 App 层口径）
public enum VoiceAvailability: String, Sendable, Equatable {
    case unknown
    case available
    case unavailable

    /// 一词呈现（设置行与服务器管理行副题共用）
    public var word: String {
        switch self {
        case .unknown: return "未知"
        case .available: return "可用"
        case .unavailable: return "未开通"
        }
    }

    /// 配置侧初判（纯函数）：voice-config 只能证伪与
    /// 给出「暂定可用」——ok 为假或 tts 段缺失＝配置
    /// 侧明确没开（未开通）；其余形态一律暂定可用
    /// （reason 不是可用标志：开通前后逐字不变，读
    /// 它判未开通会把已开通的实例误判死——开通复探
    /// §三钉死）。配置拉不到（nil）＝未知
    public static func assess(
        config: VoiceConfigResponse?
    ) -> VoiceAvailability {
        guard let config else { return .unknown }
        guard config.ok, config.tts != nil else { return .unavailable }
        return .available
    }

    /// 配置初判与现态合并：配置说未开通→未开通（配
    /// 置侧证伪优先）；配置说暂定可用只许把未知升为
    /// 可用——不许把 speak 实调已证伪的未开通翻回
    /// （配置证明不了可用，实调才算数）
    public static func mergingConfigAssessment(
        current: VoiceAvailability,
        assessed: VoiceAvailability
    ) -> VoiceAvailability {
        switch assessed {
        case .unavailable:
            return .unavailable
        case .available:
            return current == .unknown ? .available : current
        case .unknown:
            return current
        }
    }

    /// speak 实调结果精修（真值来源）：成功→可用；
    /// provider 不可用→未开通；其余失败（网络/超时/
    /// 解码）不携带可用性信息，现态不动
    public static func refined(
        current: VoiceAvailability,
        by outcome: SpeakOutcome
    ) -> VoiceAvailability {
        switch outcome {
        case .succeeded:
            return .available
        case .providerUnavailable:
            return .unavailable
        case .failedOther:
            return current
        }
    }
}

/// 一次 speak 实调的可用性相关分型
public enum SpeakOutcome: Sendable, Equatable {
    case succeeded
    case providerUnavailable
    case failedOther
}

/// speak 失败分型（纯函数）：服务端失败走 400
/// `{detail}`——detail 原文是唯一分型依据（探活
/// §1.2 失败原文冻结：「No TTS provider available」）
public enum SpeakFailureKind: Sendable, Equatable {
    /// provider 没开/没装（未开通，精修可用性）
    case providerUnavailable
    /// 文本为空被拒（客户端预检应先拦下，此为兜底）
    case emptyText
    /// 其余服务端失败（合成失败等）
    case server
    /// 非状态码失败（传输/解码层，不在本函数口径内
    /// ——调用方直接归 failedOther，本 case 只为分型
    /// 表完整）
    case other

    public static func classify(
        status: Int, detail: String?
    ) -> SpeakFailureKind {
        let text = detail ?? ""
        if text.contains("No TTS provider available") {
            return .providerUnavailable
        }
        if text.contains("Text is required") {
            return .emptyText
        }
        if (400...599).contains(status) {
            return .server
        }
        return .other
    }

    /// 对可用性精修的分型投影
    public var outcome: SpeakOutcome {
        switch self {
        case .providerUnavailable: return .providerUnavailable
        case .emptyText, .server, .other: return .failedOther
        }
    }
}

// MARK: - 朗读文本预处理

/// 朗读文本（纯函数）：落定回复全文 → 可朗读纯文本。
/// 剥 Markdown 沿既有管线口径（MessagePlainText，与
/// 长按「复制」同源）；其上只做朗读侧的空白归一：
/// 连续空行折成段落换行、行尾空白去掉——合成器对空
/// 白敏感，原文的排版空行不该读出长停顿。
/// 长文本策略：**整段单次提交、不截断不分段**——
/// 服务端内部自行分块合成（探活 §1.2 失败原文带
/// 「chunk 1」实证；开通复探 §五 2），回执恒为单个
/// data_url，客户端分段只会把一条回复拆成多次请
/// 求、段间续播无服务端依据，不许自创。剥完为空
/// （纯图片/纯标记回复）返回 nil，调用方不发请求
public enum SpeechText {
    public static func make(fromMarkdown markdown: String) -> String? {
        let plain = MessagePlainText.make(from: markdown)
        var lines: [String] = []
        var pendingBlank = false
        for rawLine in plain.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(
                in: .whitespaces
            )
            if line.isEmpty {
                pendingBlank = true
                continue
            }
            if pendingBlank, !lines.isEmpty {
                lines.append("")
            }
            pendingBlank = false
            lines.append(line)
        }
        let text = lines.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}

/// 合成 provider 的展示名（音色行数据源是 speak 回
/// 执的 provider，不是 elevenlabs/voices——探活
/// §2.4）；未知 provider 原样呈现、不编造
public enum SpeechProviderDisplay {
    public static func name(for provider: String?) -> String {
        switch provider {
        case "edge":
            return "Edge TTS"
        case nil:
            return "服务端决定"
        default:
            return provider!
        }
    }
}

// MARK: - 播放状态机（纯逻辑）

/// 朗读播放状态机（纯值类型，App 层 SpeechPlayer
/// 只做效果执行）：五态——静默／请求中／播放中／
/// 已暂停／失败（带人话原因）。事件→（新态＋效果
/// 列），效果由执行层落：tearDown＝停播＋取消在
/// 飞请求；startRequest＝发 speak；beginPlayback
/// ＝喂播放器；pausePlayback/resumePlayback＝引
/// 擎断点暂停/续播（不拆引擎、进度保留）。迟到回
/// 执（请求已切走/已停）按条目 id 对账丢弃，不许
/// 把上一条的音频播到当前态上
public struct SpeechPlaybackMachine: Sendable, Equatable {
    public enum State: Sendable, Equatable {
        case idle
        case requesting(entryID: UUID)
        case playing(entryID: UUID)
        case paused(entryID: UUID)
        case failed(entryID: UUID, message: String)
    }

    public enum Effect: Sendable, Equatable {
        case tearDown
        case startRequest(entryID: UUID)
        case beginPlayback(entryID: UUID)
        case pausePlayback
        case resumePlayback
    }

    public private(set) var state: State = .idle

    public init() {}

    /// 当前活动条目（请求中/播放中/已暂停/失败所在条）
    public var activeEntryID: UUID? {
        switch state {
        case .idle: return nil
        case .requesting(let id), .playing(let id),
             .paused(let id), .failed(let id, _): return id
        }
    }

    /// 播放条呈现派生（台账 183）：请求中/播放中/
    /// 已暂停为真——出声（含即将出声）必有当场可
    /// 见、可停的控制面（输入舱上瘦播放条，落点在
    /// App 层输入舱装配内）；暂停后条必须常驻，否
    /// 则没有当场继续的入口；静默为假；失败为假
    /// （失败走既有通知口给人话，不占舱面）。本派
    /// 生是播放条显隐的单一出处——视图层只读本
    /// 值，不许各自重判状态机
    public var showsPlaybackBar: Bool {
        switch state {
        case .requesting, .playing, .paused: return true
        case .idle, .failed: return false
        }
    }

    /// 播放条文案派生（与 showsPlaybackBar 同出
    /// 处）：请求中＝正在准备、播放中＝正在朗读、
    /// 已暂停＝已暂停（暂停态须与播放态可区分，
    /// 否则用户分不清是停了还是卡了）；不出条的
    /// 态为 nil
    public var playbackBarText: String? {
        switch state {
        case .requesting: return "正在准备朗读"
        case .playing: return "正在朗读"
        case .paused: return "已暂停"
        case .idle, .failed: return nil
        }
    }

    /// 是否占用着播放通道（菜单标题判读用）：请
    /// 求中/播放中/已暂停都算活动——暂停的条目菜
    /// 单仍显「停止朗读」（菜单 toggle 语义＝朗读/
    /// 停止二义，暂停/继续只住播放条，见 D1 对位
    /// 表分工裁定）
    public func isActive(entryID: UUID) -> Bool {
        switch state {
        case .requesting(let id), .playing(let id),
             .paused(let id):
            return id == entryID
        case .idle, .failed: return false
        }
    }

    /// 长按菜单项标题：活动中的条目显「停止朗读」，
    /// 其余显「朗读」（失败条目再点即重试）
    public func menuTitle(for entryID: UUID) -> String {
        isActive(entryID: entryID) ? "停止朗读" : "朗读"
    }

    /// 点按某条的朗读项：静默/失败→发起；活动中的
    /// 同一条→停；活动中的另一条→先拆后发（切换）。
    /// 已暂停与播放中同路（暂停中点同条＝停、点异
    /// 条＝切换），暂停不改变菜单 toggle 语义
    @discardableResult
    public mutating func tap(entryID: UUID) -> [Effect] {
        // 显式嵌套判定（不用多模式 case＋where 的组合
        // 形态：该形态在请求中切换一条上出过实测与推
        // 演不符的匹配结果，见 H2-a CI 第四轮记录）
        switch state {
        case .requesting(let id), .playing(let id),
             .paused(let id):
            if id == entryID {
                state = .idle
                return [.tearDown]
            }
            state = .requesting(entryID: entryID)
            return [.tearDown, .startRequest(entryID: entryID)]
        case .idle, .failed:
            state = .requesting(entryID: entryID)
            return [.startRequest(entryID: entryID)]
        }
    }

    /// 播放条「暂停」（D1）：只认播放中的条目——
    /// 引擎断点暂停、实例与进度保留，不拆不发请求；
    /// 其余态（含已暂停重复点）空转
    @discardableResult
    public mutating func pause() -> [Effect] {
        guard case .playing(let id) = state else { return [] }
        state = .paused(entryID: id)
        return [.pausePlayback]
    }

    /// 播放条「继续」（D1）：只认已暂停的条目——
    /// 从断点续播；其余态空转
    @discardableResult
    public mutating func resume() -> [Effect] {
        guard case .paused(let id) = state else { return [] }
        state = .playing(entryID: id)
        return [.resumePlayback]
    }

    /// speak 成功回执到达：只认仍在请求中的同一条
    @discardableResult
    public mutating func requestSucceeded(
        entryID: UUID
    ) -> [Effect] {
        guard case .requesting(let id) = state, id == entryID
        else { return [] }
        state = .playing(entryID: entryID)
        return [.beginPlayback(entryID: entryID)]
    }

    /// speak 失败：只认仍在请求中的同一条；失败态
    /// 留在条目上（菜单再点重试），人话由执行层给
    @discardableResult
    public mutating func requestFailed(
        entryID: UUID, message: String
    ) -> [Effect] {
        guard case .requesting(let id) = state, id == entryID
        else { return [] }
        state = .failed(entryID: entryID, message: message)
        return []
    }

    /// 播放自然结束：只认播放中的同一条（已暂停
    /// 不认——暂停时引擎不触发自然结束回调，与
    /// AVAudioPlayer 语义自洽）
    @discardableResult
    public mutating func playbackFinished(
        entryID: UUID
    ) -> [Effect] {
        guard case .playing(let id) = state, id == entryID
        else { return [] }
        state = .idle
        return []
    }

    /// 播放器自身失败（数据坏/解码失败）：只认播
    /// 放中（已暂停同 playbackFinished 口径不认）
    @discardableResult
    public mutating func playbackFailed(
        entryID: UUID, message: String
    ) -> [Effect] {
        guard case .playing(let id) = state, id == entryID
        else { return [] }
        state = .failed(entryID: entryID, message: message)
        return []
    }

    /// 外部停播（点另一条之外的全部停因：离开页面、
    /// 发送新消息、开始听写）：活动态才需要拆，
    /// 静默/失败态只清态不发效果。已暂停同样全拆
    /// ——暂停只豁免「条上暂停钮/来电打断」两个口，
    /// 其余停因不许留半截断点在场
    @discardableResult
    public mutating func stop() -> [Effect] {
        switch state {
        case .requesting, .playing, .paused:
            state = .idle
            return [.tearDown]
        case .idle, .failed:
            state = .idle
            return []
        }
    }
}
