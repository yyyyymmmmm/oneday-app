import Foundation

/// 对话内授权流（DESIGN §244，规格 permission-system-
/// redesign-20261113 §七）的纯逻辑层：桥侧结构化字段
/// 的分型、授权卡模型与状态机、resume 回执分型。呈现
/// 与副作用（系统请求/续办调用/持久化）在 App 层协调
/// 器（DevicePermissionCoordinator），本文件只做无副
/// 作用的解析与判定，全部可单测。
///
/// 状态机（规格 §7.3）：
///   primer ──允许──▶ asking ──回读可用──▶（桥侧同轮
///   放行/resume）──▶ done；asking 回读已拒绝 ──▶
///   blocked ──去设置──▶ 回前台回读可用 ──▶ resuming
///   ──▶ done；primer ──先不──▶ parked（卡留对话流，
///   点开续办）；parked ──继续──▶ primer（本地路）；
///   权限已开差开关 ──▶ switchOff ──打开并继续──▶
///   resuming；任一非终态超 24h ──▶ expired；算了
///   ──▶ declined；续办失败 ──▶ failed（可再试）。

// MARK: - 卡点层（与桥侧 blockerLayer 同字面单源）

public enum PermissionBlockerLayer: String, Codable, Equatable, Sendable {
    case permission
    case agentSwitch
    case sync
}

// MARK: - 授权卡

public enum PermissionCardPhase: String, Codable, Equatable, Sendable {
    /// 呈现中：等用户点「允许」或「先不」（系统窗未烧）
    case primer
    /// 已点允许：系统请求在途
    case asking
    /// 已拒绝/受限：只能去系统设置改，或算了
    case blocked
    /// 用户点了先不：卡留在对话流里，随时点开续办
    case parked
    /// 权限已开、只差智能体调用开关：点「打开并继续」
    case switchOff
    /// 续办调用在途
    case resuming
    /// 已办完（结果摘要在卡面）
    case done
    /// 用户点了算了（终态）
    case declined
    /// 挂起超 24 小时（终态，与桥侧 park TTL 同口径）
    case expired
    /// 续办失败（人话在卡面，可再试，不翻终态）
    case failed

    public var isTerminal: Bool {
        switch self {
        case .done, .declined, .expired: return true
        default: return false
        }
    }
}

public struct PermissionCard: Identifiable, Codable, Equatable, Sendable {
    /// 卡 id 即桥侧 resumeToken（挂起的唯一凭据）
    public var id: String
    public var source: DeviceSourceID
    /// 原调用的工具名（桥工具名，卡面文案据此与
    /// DeviceToolRegistry 对出中文动作名）
    public var tool: String
    public var layer: PermissionBlockerLayer
    /// true＝同步副本类查询的挂起：续办前先补一次同步
    public var isSyncQuery: Bool
    public var phase: PermissionCardPhase
    public var createdAt: TimeInterval
    public var expiresAt: TimeInterval
    /// done 时的结果摘要（优先取工具自带的 humanSummary）
    public var resultSummary: String?
    /// failed 时的人话失败说明
    public var failureNote: String?
    /// 桥侧 ask 等答超时、无人答复（§261 ③显性化）：
    /// 桥回执明确记了「未答」才置真，卡面据此与用户
    /// 主动「先不」区分呈现。旧持久化无此键、解码兜底 false
    public var askUnanswered: Bool

    /// 与桥侧 park TTL 同口径：24 小时
    public static let lifetime: TimeInterval = 24 * 3600

    public init(
        id: String,
        source: DeviceSourceID,
        tool: String,
        layer: PermissionBlockerLayer,
        isSyncQuery: Bool,
        phase: PermissionCardPhase,
        createdAt: TimeInterval,
        expiresAt: TimeInterval? = nil,
        resultSummary: String? = nil,
        failureNote: String? = nil,
        askUnanswered: Bool = false
    ) {
        self.id = id
        self.source = source
        self.tool = tool
        self.layer = layer
        self.isSyncQuery = isSyncQuery
        self.phase = phase
        self.createdAt = createdAt
        // §261 ②：桥给了 park 的 expiresAt 就用桥的
        //（起算点＝桥 park 时刻，全系统只此一份过期
        // 口径）；没给（旧桥）才本地按 createdAt＋24h 推
        self.expiresAt = expiresAt ?? createdAt + Self.lifetime
        self.resultSummary = resultSummary
        self.failureNote = failureNote
        self.askUnanswered = askUnanswered
    }

    private enum CodingKeys: String, CodingKey {
        case id, source, tool, layer, isSyncQuery, phase
        case createdAt, expiresAt, resultSummary, failureNote
        case askUnanswered
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )
        id = try container.decode(String.self, forKey: .id)
        source = try container.decode(
            DeviceSourceID.self, forKey: .source
        )
        tool = try container.decode(String.self, forKey: .tool)
        layer = try container.decode(
            PermissionBlockerLayer.self, forKey: .layer
        )
        isSyncQuery = try container.decode(
            Bool.self, forKey: .isSyncQuery
        )
        phase = try container.decode(
            PermissionCardPhase.self, forKey: .phase
        )
        createdAt = try container.decode(
            TimeInterval.self, forKey: .createdAt
        )
        // 旧持久化恒有 expiresAt；缺失时按 createdAt＋24h 补
        expiresAt = try container.decodeIfPresent(
            TimeInterval.self, forKey: .expiresAt
        ) ?? createdAt + Self.lifetime
        resultSummary = try container.decodeIfPresent(
            String.self, forKey: .resultSummary
        )
        failureNote = try container.decodeIfPresent(
            String.self, forKey: .failureNote
        )
        askUnanswered = try container.decodeIfPresent(
            Bool.self, forKey: .askUnanswered
        ) ?? false
    }

    /// 过期判定（纯函数）：非终态卡过了 expiresAt
    /// 即应翻 expired；终态卡不翻
    public func isExpired(at now: TimeInterval) -> Bool {
        !phase.isTerminal && now > expiresAt
    }
}

// MARK: - 桥载荷解析

/// 桥载荷里的时间字段取值（数型才认，余皆 nil）
private func bridgeTime(
    _ arguments: [String: JSONValue], _ key: String
) -> TimeInterval? {
    if case .number(let value)? = arguments[key] { return value }
    return nil
}

/// 落卡时间口径（§261 ②）：桥随载荷给了 park 的
/// createdAt/expiresAt 就以桥为准（起算点＝桥 park
/// 时刻，与桥侧 24h 自清同一份口径）；旧桥没给才
/// 用本地收信时刻兜底推算
public struct PermissionCardDates: Equatable, Sendable {
    public let createdAt: TimeInterval
    public let expiresAt: TimeInterval

    public static func resolve(
        parkedAt: TimeInterval?, bridgeExpiresAt: TimeInterval?,
        now: TimeInterval
    ) -> PermissionCardDates {
        let created = parkedAt ?? now
        return PermissionCardDates(
            createdAt: created,
            expiresAt: bridgeExpiresAt
                ?? created + PermissionCard.lifetime
        )
    }
}

/// permission_ask 伪调用的参数（桥 P-2 通道一）
public struct PermissionAskRequest: Equatable, Sendable {
    public let source: DeviceSourceID
    public let tool: String
    public let resumeToken: String
    /// 桥 park 的生成时刻与过期时刻（§261 ②；旧桥无）
    public let parkedAt: TimeInterval?
    public let parkExpiresAt: TimeInterval?

    public static func parse(
        arguments: [String: JSONValue]
    ) -> PermissionAskRequest? {
        guard case .string(let sourceKey)? = arguments["source"],
              let source = DeviceSourceID(rawValue: sourceKey),
              case .string(let tool)? = arguments["tool"],
              case .string(let token)? = arguments["resumeToken"],
              !token.isEmpty
        else { return nil }
        return PermissionAskRequest(
            source: source, tool: tool, resumeToken: token,
            parkedAt: bridgeTime(arguments, "parkedAt"),
            parkExpiresAt: bridgeTime(arguments, "expiresAt")
        )
    }

    public func cardDates(now: TimeInterval) -> PermissionCardDates {
        PermissionCardDates.resolve(
            parkedAt: parkedAt, bridgeExpiresAt: parkExpiresAt,
            now: now
        )
    }
}

/// permission_notice 的参数：已挂起的调用要 App 出卡
///（桥 P-3 通道二——已拒绝/开关层没有 ask 的机会，
/// 桥停好车后捎信过来）
public struct PermissionNotice: Equatable, Sendable {
    public let source: DeviceSourceID
    public let tool: String
    public let resumeToken: String
    public let layer: PermissionBlockerLayer
    public let state: DevicePermissionState?
    public let isSyncQuery: Bool
    /// 桥 park 的生成时刻与过期时刻（§261 ②；旧桥无）
    public let parkedAt: TimeInterval?
    public let parkExpiresAt: TimeInterval?

    public static func parse(
        arguments: [String: JSONValue]
    ) -> PermissionNotice? {
        guard case .string(let sourceKey)? = arguments["source"],
              let source = DeviceSourceID(rawValue: sourceKey),
              case .string(let tool)? = arguments["tool"],
              case .string(let token)? = arguments["resumeToken"],
              !token.isEmpty,
              case .string(let layerRaw)? = arguments["blockerLayer"],
              let layer = PermissionBlockerLayer(rawValue: layerRaw)
        else { return nil }
        var state: DevicePermissionState?
        if case .string(let stateRaw)? = arguments["state"] {
            state = DevicePermissionState(rawValue: stateRaw)
        }
        var isSync = false
        if case .string(let kind)? = arguments["parkKind"] {
            isSync = kind == "sync"
        }
        return PermissionNotice(
            source: source, tool: tool, resumeToken: token,
            layer: layer, state: state, isSyncQuery: isSync,
            parkedAt: bridgeTime(arguments, "parkedAt"),
            parkExpiresAt: bridgeTime(arguments, "expiresAt")
        )
    }

    public func cardDates(now: TimeInterval) -> PermissionCardDates {
        PermissionCardDates.resolve(
            parkedAt: parkedAt, bridgeExpiresAt: parkExpiresAt,
            now: now
        )
    }

    /// 通知落卡的初始相位：开关层直接 switchOff；权限
    /// 层（含同步类）一律 blocked（已拒绝是既成事实，
    /// 卡面给「去设置打开」与「算了」）
    public var initialPhase: PermissionCardPhase {
        layer == .agentSwitch ? .switchOff : .blocked
    }
}

// MARK: - 注册附加面（P-2）

/// 注册载荷的权限流附加面：agentCall 映射让桥侧能
/// 分层判「权限→开关」；capabilities 声明本 App 会
/// 应答 permission_ask（旧 App 不声明、桥保持旧行为）
public enum DeviceRegistrationExtras {
    public static let askCapability = "permission_ask_v1"

    public static func agentCallMap(
        agentCallEnabled: [DeviceSourceID: Bool]
    ) -> [String: Bool] {
        var map: [String: Bool] = [:]
        for id in DeviceSourceID.allCases {
            map[id.bridgeKey] = agentCallEnabled[id] ?? false
        }
        return map
    }

    public static var capabilities: [String] { [askCapability] }
}

// MARK: - resume 回执分型（P-4 客户端）

public enum PermissionResumeOutcome: Equatable, Sendable {
    /// 原调用已重发并拿到结果
    case succeeded(result: JSONValue?)
    /// 桥回业务错误（文案由桥侧中文单源，App 透传）
    case failed(code: String, message: String?)
    /// token 已过期/未知（HTTP 404）→ 卡翻 expired
    case tokenGone
    /// 设备会话不在线（HTTP 409）→ 可重试，不翻终态
    case offline

    public static func from(
        httpStatus: Int, body: JSONValue?
    ) -> PermissionResumeOutcome {
        if httpStatus == 404 { return .tokenGone }
        if httpStatus == 409 { return .offline }
        guard case .object(let dict)? = body else {
            return .failed(code: "bad_response", message: nil)
        }
        if case .bool(true)? = dict["ok"] {
            return .succeeded(result: dict["result"])
        }
        var code = "resume_failed"
        if case .string(let raw)? = dict["error"] { code = raw }
        var message: String?
        if case .string(let raw)? = dict["message"] { message = raw }
        return .failed(code: code, message: message)
    }
}

// MARK: - 桥侧卡状态读面与对账（§261 ①③）

/// ask 一轮的结局（桥侧记录、随 park 持有）：此前
/// 「用户点了先不」与「等答超时没人理」在桥侧同为
/// parked、无从分辨；§261 ③ 起桥显性记账，读面回给
/// App 对齐卡面
public enum PermissionAskOutcome: String, Codable, Equatable, Sendable {
    /// 等答超时，无人答复
    case unanswered
    /// 用户主动点了「先不」
    case deferred
    /// 会话中途断了，问没送达或答没回来
    case undeliverable
}

/// 桥侧 park 的状态快照（POST /device/park-state 回
/// 执体）：卡真相在桥侧——park 在不在、何时过期、
/// ask 结局如何，以桥这一份为准；本地卡账本降为
/// 展示缓存（呈现所需＋桥不可达时的兜底）
public struct PermissionParkState: Equatable, Sendable {
    public let exists: Bool
    public let source: DeviceSourceID?
    public let tool: String?
    public let layer: PermissionBlockerLayer?
    public let isSyncQuery: Bool
    public let createdAt: TimeInterval?
    public let expiresAt: TimeInterval?
    public let askOutcome: PermissionAskOutcome?

    /// 回执体解析：exists 缺失/非 bool 视为读面不可
    /// 信、回 nil（调用方据此走本地兜底，不当「卡没
    /// 了」处理）；exists=false 是桥的明确答复
    public static func parse(body: JSONValue?) -> PermissionParkState? {
        guard case .object(let dict)? = body,
              case .bool(let exists)? = dict["exists"]
        else { return nil }
        guard exists else {
            return PermissionParkState(
                exists: false, source: nil, tool: nil,
                layer: nil, isSyncQuery: false,
                createdAt: nil, expiresAt: nil, askOutcome: nil
            )
        }
        guard case .object(let park)? = dict["park"] else {
            return nil
        }
        var source: DeviceSourceID?
        if case .string(let raw)? = park["source"] {
            source = DeviceSourceID(rawValue: raw)
        }
        var tool: String?
        if case .string(let raw)? = park["tool"] { tool = raw }
        var layer: PermissionBlockerLayer?
        if case .string(let raw)? = park["blockerLayer"] {
            layer = PermissionBlockerLayer(rawValue: raw)
        }
        var isSync = false
        if case .string(let kind)? = park["kind"] {
            isSync = kind == "sync"
        }
        var outcome: PermissionAskOutcome?
        if case .string(let raw)? = park["askOutcome"] {
            outcome = PermissionAskOutcome(rawValue: raw)
        }
        return PermissionParkState(
            exists: true, source: source, tool: tool,
            layer: layer, isSyncQuery: isSync,
            createdAt: bridgeTime(park, "createdAt"),
            expiresAt: bridgeTime(park, "expiresAt"),
            askOutcome: outcome
        )
    }
}

/// 对账裁定（纯函数）：本地卡 × 桥侧 park 快照 →
/// 协调器该做什么。桥是真相，但两类本地相位不对账
/// ——终态卡是本地既成事实（办完/算了，桥 park 随
/// 24h 自清、不回头翻案）；asking/resuming 是本地
/// 操作在途（resume 本就会消费 park，此刻查到「没
/// 了」是时序不是真相）
public enum PermissionParkReconcile: Equatable, Sendable {
    case keep
    case expire
    case adopt(park: PermissionParkState)
}

public enum PermissionParkReconciler {
    public static func decision(
        card: PermissionCard, park: PermissionParkState,
        now: TimeInterval
    ) -> PermissionParkReconcile {
        if card.phase.isTerminal { return .keep }
        switch card.phase {
        case .asking, .resuming: return .keep
        default: break
        }
        // 桥明确说 park 没了（过期自清/已被消费/被
        // 丢弃）→ 本地卡同步翻过期，不再留着骗用户
        guard park.exists else { return .expire }
        if let expiresAt = park.expiresAt, now > expiresAt {
            return .expire
        }
        return .adopt(park: park)
    }
}

// MARK: - 结果摘要

/// 续办结果的一行摘要：优先工具自带的 humanSummary
///（多数设备工具都带），没有就给中性完成句——不编
/// 数字、不猜内容
public enum PermissionResultSummary {
    public static func line(for result: JSONValue?) -> String {
        if case .object(let dict)? = result,
           case .string(let summary)? = dict["humanSummary"],
           !summary.isEmpty {
            return summary
        }
        return "已办完。"
    }
}
