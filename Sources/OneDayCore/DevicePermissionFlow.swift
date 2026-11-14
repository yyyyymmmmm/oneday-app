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
        resultSummary: String? = nil,
        failureNote: String? = nil
    ) {
        self.id = id
        self.source = source
        self.tool = tool
        self.layer = layer
        self.isSyncQuery = isSyncQuery
        self.phase = phase
        self.createdAt = createdAt
        self.expiresAt = createdAt + Self.lifetime
        self.resultSummary = resultSummary
        self.failureNote = failureNote
    }

    /// 过期判定（纯函数）：非终态卡过了 expiresAt
    /// 即应翻 expired；终态卡不翻
    public func isExpired(at now: TimeInterval) -> Bool {
        !phase.isTerminal && now > expiresAt
    }
}

// MARK: - 桥载荷解析

/// permission_ask 伪调用的参数（桥 P-2 通道一）
public struct PermissionAskRequest: Equatable, Sendable {
    public let source: DeviceSourceID
    public let tool: String
    public let resumeToken: String

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
            source: source, tool: tool, resumeToken: token
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
            layer: layer, state: state, isSyncQuery: isSync
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
