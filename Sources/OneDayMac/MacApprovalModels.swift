import Foundation

/// 执行批准记录（棒 2，对位 #18）：GET /v1/approvals
/// 的逐条记录——服务端 approval_projection._public
/// 的字段口径逐字对齐（网关把内存批准队列投影到账
/// 本，pending 在读时对活队列复核）。Core 的
/// ApprovalsListResponse 只建模计数面，逐条记录在
/// Mac 端按服务端原形建模，不另发明字段。
struct MacExecApproval: Decodable, Sendable, Identifiable, Equatable {
    let requestID: String
    let sessionKey: String?
    let runID: String?
    let sessionID: String?
    let source: String?
    /// 有活等待者才可裁决（无等待者的投影记录只看不批）
    let answerable: Bool
    let command: String
    let description: String
    let patternKeys: [String]
    /// 服务端按记录实情给出的可选裁决（once/session/
    /// always/deny 的子集），钮面只许渲染这份清单
    let choices: [String]
    let status: String
    let choice: String?
    let createdAt: Double?
    let expiresAt: Double?
    let decidedAt: Double?
    let statusCause: String?

    var id: String { requestID }

    var isPending: Bool { status == "pending" }

    var createdDate: Date? {
        createdAt.map { Date(timeIntervalSince1970: $0) }
    }

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case sessionKey = "session_key"
        case runID = "run_id"
        case sessionID = "session_id"
        case source, answerable, command, description, choices, status
        case patternKeys = "pattern_keys"
        case choice
        case createdAt = "created_at"
        case expiresAt = "expires_at"
        case decidedAt = "decided_at"
        case statusCause = "status_cause"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        requestID = try container.decode(String.self, forKey: .requestID)
        sessionKey = try container.decodeIfPresent(
            String.self, forKey: .sessionKey
        )
        runID = try container.decodeIfPresent(String.self, forKey: .runID)
        sessionID = try container.decodeIfPresent(
            String.self, forKey: .sessionID
        )
        source = try container.decodeIfPresent(String.self, forKey: .source)
        answerable = try container.decodeIfPresent(
            Bool.self, forKey: .answerable
        ) ?? false
        command = try container.decodeIfPresent(
            String.self, forKey: .command
        ) ?? ""
        description = try container.decodeIfPresent(
            String.self, forKey: .description
        ) ?? ""
        patternKeys = try container.decodeIfPresent(
            [String].self, forKey: .patternKeys
        ) ?? []
        choices = try container.decodeIfPresent(
            [String].self, forKey: .choices
        ) ?? []
        status = try container.decodeIfPresent(
            String.self, forKey: .status
        ) ?? ""
        choice = try container.decodeIfPresent(String.self, forKey: .choice)
        createdAt = try container.decodeIfPresent(
            Double.self, forKey: .createdAt
        )
        expiresAt = try container.decodeIfPresent(
            Double.self, forKey: .expiresAt
        )
        decidedAt = try container.decodeIfPresent(
            Double.self, forKey: .decidedAt
        )
        statusCause = try container.decodeIfPresent(
            String.self, forKey: .statusCause
        )
    }
}

/// GET /v1/approvals 回包（object=hermes.approvals）
struct MacApprovalsResponse: Decodable, Sendable {
    let approvals: [MacExecApproval]
    let pendingCount: Int
    let ledgerDegraded: Bool

    enum CodingKeys: String, CodingKey {
        case approvals
        case pendingCount = "pending_count"
        case ledgerDegraded = "ledger_degraded"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        approvals = try container.decodeIfPresent(
            [MacExecApproval].self, forKey: .approvals
        ) ?? []
        pendingCount = try container.decodeIfPresent(
            Int.self, forKey: .pendingCount
        ) ?? approvals.filter { $0.isPending }.count
        ledgerDegraded = try container.decodeIfPresent(
            Bool.self, forKey: .ledgerDegraded
        ) ?? false
    }
}

/// 执行批准裁决钮文案：choice 值是服务端契约，钮面
/// 中文与 App 批准语义同口径（批准／本次会话内总是
/// 允许／总是允许／拒绝）；未知 choice 不渲染钮
enum MacApprovalChoiceCopy {
    static func title(for choice: String) -> String? {
        switch choice {
        case "once": return "批准"
        case "session": return "本次会话内总是允许"
        case "always": return "总是允许"
        case "deny": return "拒绝"
        default: return nil
        }
    }

    /// 已决记录的裁决回显
    static func decidedLabel(for record: MacExecApproval) -> String {
        switch record.status {
        case "approved", "resolved":
            switch record.choice {
            case "session": return "已批准 · 本次会话内总是允许"
            case "always": return "已批准 · 总是允许"
            default: return "已批准"
            }
        case "denied":
            return "已拒绝"
        case "expired":
            return "已过期"
        default:
            return record.status
        }
    }
}

/// write-gate 网关面错误（与 iOS 桥客户端
/// WriteGateError 同分型：网关化后路径换 /v1/write-
/// gate，状态口径不变——404 记录已不在、409 状态已
/// 变化、401/403 钥被拒）
enum MacWriteGateError: Error, Sendable, Equatable {
    case unauthorized
    case recordGone
    case conflict
    case failed(String)

    var userMessage: String {
        switch self {
        case .unauthorized:
            return "登录密钥被服务器拒绝"
        case .recordGone:
            return "这条待批已被处理或已失效"
        case .conflict:
            return "内容或状态已变化，请刷新后重试"
        case .failed(let message):
            return message
        }
    }
}
