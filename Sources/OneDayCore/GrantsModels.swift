import Foundation

/// 授权账本投影模型（Hermes 批 5，部署包 1.3.0；DESIGN §355）：
/// GET /v1/grants 的统一清单——exec 命令授权（真源＝网关
/// config 的 command_allowlist）＋写闸规则（真源＝伴生桥
/// rules.json、本面只读投影）两源拼合。字段口径以服务端
/// grant_projection.py 为准，逐条钉死：
/// - granted_at／source_decision 查不到留 null（exec 侧自
///   批 2 决定账恢复、写闸侧恒 null）——界面显「未记录」，
///   不许编时间、不许编来源；
/// - expires_at 恒 null＝永久授权；
/// - 撤销只有 exec 走 POST /v1/grants/revoke（连别名键一
///   并删、端点内双自检）；写闸条目 revoke_via＝writegate-
///   bridge，本面不办、归审批规则区（桥 DELETE /rules）。
/// session 档授权不在清单内（无落盘真源、不可列表撤销，
/// 服务端刻意不投影）。

/// 授权来源（未知值原样保留在 .other，不猜不拼）
public enum GrantSource: Sendable, Equatable {
    case exec
    case writegate
    case other(String)

    public init(rawValue: String) {
        switch rawValue {
        case "exec": self = .exec
        case "writegate": self = .writegate
        default: self = .other(rawValue)
        }
    }
}

/// 统一清单里的一条常设授权
public struct GrantEntry: Decodable, Equatable, Identifiable, Sendable {
    /// 服务端稳定键（"exec:<pattern>"／"writegate:<rule_id>"），
    /// 兼作 Identifiable.id 与撤销后回读判定的比对键
    public let grantKey: String
    public let source: GrantSource
    /// exec 专有：命令模式键（撤销请求按它发）
    public let patternKey: String?
    /// 写闸专有：桥侧规则 id（字符串化；服务端原值可能是
    /// 数字，解码宽容收口为字符串）
    public let ruleID: String?
    /// 呈现标签：exec＝模式键本体；写闸＝「子系统 · 来源」
    public let scopeLabel: String
    /// 立授权时刻（epoch 秒转 Date）；查不到为 nil
    public let grantedAt: Date?
    /// 立授权的那次审批决定 id；查不到为 nil
    public let sourceDecision: String?
    public let status: String
    /// 恒 nil＝永久；非 nil 为到期时刻
    public let expiresAt: Date?
    /// 撤销通道：exec＝"gateway"、写闸＝"writegate-bridge"
    public let revokeVia: String

    public var id: String { grantKey }

    /// 本面（网关 grants 端点）可办撤销的只有 exec 且带
    /// 模式键的条目；写闸条目只读呈现（管理归桥侧规则面）
    public var canRevokeHere: Bool {
        source == .exec && patternKey != nil
    }

    enum CodingKeys: String, CodingKey {
        case grantKey = "grant_key"
        case source
        case patternKey = "pattern_key"
        case ruleID = "rule_id"
        case scopeLabel = "scope_label"
        case grantedAt = "granted_at"
        case sourceDecision = "source_decision"
        case status
        case expiresAt = "expires_at"
        case revokeVia = "revoke_via"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        grantKey = try container.decode(String.self, forKey: .grantKey)
        source = GrantSource(
            rawValue: try container.decodeIfPresent(
                String.self, forKey: .source
            ) ?? ""
        )
        patternKey = try container.decodeIfPresent(
            String.self, forKey: .patternKey
        )
        // rule_id 宽容解码：字符串原样、数字转字符串、缺席 nil
        if let text = try? container.decodeIfPresent(
            String.self, forKey: .ruleID
        ) ?? nil {
            ruleID = text
        } else if let number = try? container.decodeIfPresent(
            Double.self, forKey: .ruleID
        ) ?? nil {
            ruleID = Int(exactly: number).map(String.init)
                ?? String(number)
        } else {
            ruleID = nil
        }
        scopeLabel = try container.decodeIfPresent(
            String.self, forKey: .scopeLabel
        ) ?? ""
        grantedAt = (try container.decodeIfPresent(
            Double.self, forKey: .grantedAt
        )).map { Date(timeIntervalSince1970: $0) }
        sourceDecision = try container.decodeIfPresent(
            String.self, forKey: .sourceDecision
        )
        status = try container.decodeIfPresent(
            String.self, forKey: .status
        ) ?? ""
        expiresAt = (try container.decodeIfPresent(
            Double.self, forKey: .expiresAt
        )).map { Date(timeIntervalSince1970: $0) }
        revokeVia = try container.decodeIfPresent(
            String.self, forKey: .revokeVia
        ) ?? ""
    }

    public init(
        grantKey: String, source: GrantSource,
        patternKey: String? = nil, ruleID: String? = nil,
        scopeLabel: String, grantedAt: Date? = nil,
        sourceDecision: String? = nil, status: String = "active",
        expiresAt: Date? = nil, revokeVia: String
    ) {
        self.grantKey = grantKey
        self.source = source
        self.patternKey = patternKey
        self.ruleID = ruleID
        self.scopeLabel = scopeLabel
        self.grantedAt = grantedAt
        self.sourceDecision = sourceDecision
        self.status = status
        self.expiresAt = expiresAt
        self.revokeVia = revokeVia
    }
}

/// GET /v1/grants 回包：双源皆败服务端回 503（不进本模型）；
/// 单源败回 partial=true＋source_errors 点名失败半边，
/// 计数对失败半边为 null——界面须如实呈现「没读全」
public struct GrantsListResponse: Decodable, Equatable, Sendable {
    public let object: String?
    public let grants: [GrantEntry]
    public let execCount: Int?
    public let writegateCount: Int?
    public let partial: Bool
    public let sourceErrors: [String]
    public let projectionDegraded: Bool

    public var execEntries: [GrantEntry] {
        grants.filter { $0.source == .exec }
    }

    public var writegateEntries: [GrantEntry] {
        grants.filter { $0.source == .writegate }
    }

    enum CodingKeys: String, CodingKey {
        case object, grants
        case execCount = "exec_count"
        case writegateCount = "writegate_count"
        case partial
        case sourceErrors = "source_errors"
        case projectionDegraded = "projection_degraded"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        object = try container.decodeIfPresent(
            String.self, forKey: .object
        )
        grants = try container.decodeIfPresent(
            [GrantEntry].self, forKey: .grants
        ) ?? []
        execCount = try container.decodeIfPresent(
            Int.self, forKey: .execCount
        )
        writegateCount = try container.decodeIfPresent(
            Int.self, forKey: .writegateCount
        )
        partial = try container.decodeIfPresent(
            Bool.self, forKey: .partial
        ) ?? false
        sourceErrors = try container.decodeIfPresent(
            [String].self, forKey: .sourceErrors
        ) ?? []
        projectionDegraded = try container.decodeIfPresent(
            Bool.self, forKey: .projectionDegraded
        ) ?? false
    }

    public init(
        object: String? = nil, grants: [GrantEntry],
        execCount: Int? = nil, writegateCount: Int? = nil,
        partial: Bool = false, sourceErrors: [String] = [],
        projectionDegraded: Bool = false
    ) {
        self.object = object
        self.grants = grants
        self.execCount = execCount
        self.writegateCount = writegateCount
        self.partial = partial
        self.sourceErrors = sourceErrors
        self.projectionDegraded = projectionDegraded
    }
}

/// POST /v1/grants/revoke 请求体组装（批 5 契约：body
/// {"source": "exec", "pattern_key": ...}；source 恒
/// "exec"——写闸走本端点必被 400 wrong_channel 拒，客
/// 户端根本不发）
public struct GrantRevokeRequest: Encodable, Equatable, Sendable {
    public let source: String
    public let patternKey: String

    enum CodingKeys: String, CodingKey {
        case source
        case patternKey = "pattern_key"
    }

    public static func exec(patternKey: String) -> GrantRevokeRequest {
        GrantRevokeRequest(source: "exec", patternKey: patternKey)
    }
}

/// POST /v1/grants/revoke 200 回执：removed 是连别名一并
/// 删掉的键全集；verifiedAbsent 是端点内双自检（磁盘回
/// 读＋判定层 governing 集）结论——false 不会出现在
/// 200 里（自检不过回 409），客户端仍以事后清单回读
/// 为最终真源（本回执只作留痕/测试钉）
public struct GrantRevocationReceipt: Decodable, Equatable, Sendable {
    public let object: String?
    public let source: String?
    public let patternKey: String
    public let removed: [String]
    public let governingScope: String?
    public let verifiedAbsent: Bool

    enum CodingKeys: String, CodingKey {
        case object, source, removed
        case patternKey = "pattern_key"
        case governingScope = "governing_scope"
        case verifiedAbsent = "verified_absent"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        object = try container.decodeIfPresent(
            String.self, forKey: .object
        )
        source = try container.decodeIfPresent(
            String.self, forKey: .source
        )
        patternKey = try container.decodeIfPresent(
            String.self, forKey: .patternKey
        ) ?? ""
        removed = try container.decodeIfPresent(
            [String].self, forKey: .removed
        ) ?? []
        governingScope = try container.decodeIfPresent(
            String.self, forKey: .governingScope
        )
        verifiedAbsent = try container.decodeIfPresent(
            Bool.self, forKey: .verifiedAbsent
        ) ?? false
    }

    public init(
        object: String? = nil, source: String? = nil,
        patternKey: String, removed: [String],
        governingScope: String? = nil, verifiedAbsent: Bool
    ) {
        self.object = object
        self.source = source
        self.patternKey = patternKey
        self.removed = removed
        self.governingScope = governingScope
        self.verifiedAbsent = verifiedAbsent
    }
}

/// 撤销失败分类器（DESIGN §355，照 RewindDirective 同
/// 构）：输入 (HTTP 状态, 网关错误码本体)，码字面以批
/// 5 实测为准——写闸误走本端点 400 grant_revoke_wrong_
/// channel；键不存在 404 grant_not_found；自检不过
/// 409 grant_revoke_unverified；config 不可用/存盘失
/// 败 503 grant_revoke_failed。其余一律 .failed 如实
/// 上抛，不盲重试
public enum GrantRevokeDirective: Sendable, Equatable {
    /// 2xx：服务端已删且自检过——进回读确认步
    case done
    /// 404：这条授权已不在（多为别处刚撤过）——回读
    /// 刷新即可，不算失败
    case notFound
    /// 400 wrong_channel：写闸条目误发本端点（客户端
    /// 结构上不该发生，发生即呈现层 bug，如实报）
    case wrongChannel
    /// 409：服务端自检未过、授权可能仍在——不许报
    /// 撤销成功，回读清单以真源为准
    case unverified
    /// 其余（鉴权/服务器错/未知码）：如实上抛
    case failed

    public static func directive(
        status: Int, serverCode: String?
    ) -> GrantRevokeDirective {
        if (200...299).contains(status) {
            return .done
        }
        switch status {
        case 404:
            return .notFound
        case 400:
            return serverCode == "grant_revoke_wrong_channel"
                ? .wrongChannel : .failed
        case 409:
            return serverCode == "grant_revoke_unverified"
                ? .unverified : .failed
        default:
            return .failed
        }
    }
}

/// 撤销后回读判定（DESIGN §355）：撤销的成败不认回执
/// 自报、只认事后重拉的统一清单——被撤条目的 grant_key
/// 已不在清单里才算确认消失；还在即未确认（界面保留
/// 服务端清单原样＋给人话说明，不许本地假删行）
public enum GrantReadback {
    public static func isConfirmedAbsent(
        grantKey: String, in refreshed: GrantsListResponse
    ) -> Bool {
        !refreshed.grants.contains { $0.grantKey == grantKey }
    }
}
