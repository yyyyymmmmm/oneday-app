import Foundation

/// 平台用户配对模型（Hermes H5，台账 35；DESIGN §359）：
/// 网关「消息平台用户配对」白名单——陌生用户在
/// Telegram／WhatsApp 等平台私聊网关时收到一次性配对
/// 码（gateway/pairing.py 状态机，码 TTL 1 小时、失败
/// 锁定、按平台分 store），管理员批准后其 user_id 进
/// 该平台白名单。与「设备配对／新设备入驻」（enroll-
/// ment，手机扫码认领设备凭据）是两物：一个管「谁能
/// 跟网关说话」，一个管「哪台手机连进来」，文案与命
/// 名不许混。
/// 真源在 9119 Dashboard 面（hermes_cli/web_routers/
/// ops.py），会话 cookie 鉴权；字段口径以服务端回文
/// 形状为准（探活报告 blueprint-phase1-recon-20261122
/// §3.2 已证）：
/// - 待批条目永不回码本体，只回 request_id；旧版明文
///   条目 request_id 为空串——该类条目只能走码批准，
///   本面结构上批不了（canApprove=false、界面置灰）；
/// - approved_at 服务端原样字符串（可能缺失），客户
///   端不猜格式——呈现层能解析则格式化、不能就原样
///   显，都缺就显「未记录」。

/// 待批申请一条（平台＋申请编号＋申请者身份＋等待时长）
public struct PairingPendingEntry: Decodable, Equatable, Identifiable, Sendable {
    public let platform: String
    /// 申请编号（批准按它发，不经手配对码本体）；旧版
    /// 明文条目为空串——批不了
    public let requestID: String
    public let userID: String
    public let userName: String
    /// 等待时长（分钟，服务端按申请时刻现算）
    public let ageMinutes: Double

    /// 同一申请的稳定身份：有编号按编号、无编号退平台
    /// ＋用户（旧版条目在清单内仍须可区分）
    public var id: String {
        requestID.isEmpty
            ? "pending:\(platform):\(userID)"
            : "pending:\(platform):\(requestID)"
    }

    /// 能否在本面批准：必须有申请编号（批准走
    /// request_id 路径、不经手码本体，与服务端安全
    /// 口径一致）
    public var canApprove: Bool { !requestID.isEmpty }

    enum CodingKeys: String, CodingKey {
        case platform
        case requestID = "request_id"
        case userID = "user_id"
        case userName = "user_name"
        case ageMinutes = "age_minutes"
    }

    public init(
        platform: String, requestID: String, userID: String,
        userName: String, ageMinutes: Double
    ) {
        self.platform = platform
        self.requestID = requestID
        self.userID = userID
        self.userName = userName
        self.ageMinutes = ageMinutes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        platform = try container.decode(String.self, forKey: .platform)
        requestID = try container.decodeIfPresent(
            String.self, forKey: .requestID
        ) ?? ""
        userID = try container.decode(String.self, forKey: .userID)
        userName = try container.decodeIfPresent(
            String.self, forKey: .userName
        ) ?? ""
        ageMinutes = try container.decodeIfPresent(
            Double.self, forKey: .ageMinutes
        ) ?? 0
    }
}

/// 已批准用户一条（进入平台白名单、可撤销）
public struct PairingApprovedEntry: Decodable, Equatable, Identifiable, Sendable {
    public let platform: String
    public let userID: String
    public let userName: String
    /// 批准时刻（服务端原样字符串；缺失为 nil，界面
    /// 显「未记录」，不编造）
    public let approvedAt: String?

    public var id: String { "approved:\(platform):\(userID)" }

    enum CodingKeys: String, CodingKey {
        case platform
        case userID = "user_id"
        case userName = "user_name"
        case approvedAt = "approved_at"
    }

    public init(
        platform: String, userID: String, userName: String,
        approvedAt: String?
    ) {
        self.platform = platform
        self.userID = userID
        self.userName = userName
        self.approvedAt = approvedAt
    }
}

/// GET /api/pairing 回文：待批＋已批准两列
public struct PairingListResponse: Decodable, Equatable, Sendable {
    public let pending: [PairingPendingEntry]
    public let approved: [PairingApprovedEntry]

    public init(
        pending: [PairingPendingEntry],
        approved: [PairingApprovedEntry]
    ) {
        self.pending = pending
        self.approved = approved
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pending = try container.decodeIfPresent(
            [PairingPendingEntry].self, forKey: .pending
        ) ?? []
        approved = try container.decodeIfPresent(
            [PairingApprovedEntry].self, forKey: .approved
        ) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case pending, approved
    }
}

/// POST /api/pairing/approve 回执：{ok, user{user_id,
/// user_name}}——回执只作受理凭据，成败终局以回读
/// 清单为准（PairingReadback）
public struct PairingApproveReceipt: Decodable, Equatable, Sendable {
    public let ok: Bool
    public let userID: String?
    public let userName: String?

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decodeIfPresent(Bool.self, forKey: .ok) ?? false
        let user = try container.decodeIfPresent(
            UserBox.self, forKey: .user
        )
        userID = user?.userID
        userName = user?.userName
    }

    private struct UserBox: Decodable {
        let userID: String?
        let userName: String?

        enum CodingKeys: String, CodingKey {
            case userID = "user_id"
            case userName = "user_name"
        }
    }

    enum CodingKeys: String, CodingKey {
        case ok, user
    }
}

/// POST /api/pairing/clear-pending 回执：{ok, cleared}
/// ——cleared 是服务端实清条数，界面按它报回执
public struct PairingClearPendingReceipt: Decodable, Equatable, Sendable {
    public let ok: Bool
    public let cleared: Int

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decodeIfPresent(Bool.self, forKey: .ok) ?? false
        cleared = try container.decodeIfPresent(
            Int.self, forKey: .cleared
        ) ?? 0
    }

    enum CodingKeys: String, CodingKey {
        case ok, cleared
    }
}

/// 批准请求体（POST /api/pairing/approve）：本面只走
/// request_id 路径——不经手配对码本体；code 路径留
/// 给平台侧人工批准，不在本面出现
public struct PairingApproveRequest: Encodable, Equatable, Sendable {
    public let platform: String
    public let requestID: String

    public init(platform: String, requestID: String) {
        self.platform = platform
        self.requestID = requestID
    }

    enum CodingKeys: String, CodingKey {
        case platform
        case requestID = "request_id"
    }
}

/// 撤销请求体（POST /api/pairing/revoke）
public struct PairingRevokeRequest: Encodable, Equatable, Sendable {
    public let platform: String
    public let userID: String

    public init(platform: String, userID: String) {
        self.platform = platform
        self.userID = userID
    }

    enum CodingKeys: String, CodingKey {
        case platform
        case userID = "user_id"
    }
}

/// 写动作失败分类（DESIGN §359）：端点状态码 → 呈现
/// 指令的纯函数，钉测把守。成败终局仍以回读为准，
/// 本分类只决定「先给什么人话、要不要回读对齐」
public enum PairingActionDirective: Sendable, Equatable {
    /// 2xx：服务端已受理——进回读确认步
    case done
    /// 404：申请已过期（TTL 1h）或已被处理／用户不在
    /// 批准名单——良性，回读刷新对齐即可
    case gone
    /// 429：该平台尝试次数过多已被暂时锁定（仅码路
    /// 径触发；本面走编号路径，出现即如实呈现）
    case platformLocked
    /// 401：会话失效——走既有会话失效口径（重新登录）
    case sessionExpired
    /// 其余（服务器错等）：如实上抛
    case failed

    public static func directive(status: Int) -> PairingActionDirective {
        if (200...299).contains(status) { return .done }
        switch status {
        case 404: return .gone
        case 429: return .platformLocked
        case 401: return .sessionExpired
        default: return .failed
        }
    }
}

/// 写后回读判定（DESIGN §359）：批准／撤销／清待批的
/// 成败不认回执自报、只认事后重拉的清单——还在旧
/// 列里就是没生效，界面保留服务端清单原样＋给人话
/// 说明，不许本地假挪行
public enum PairingReadback {
    /// 批准确认：该用户已进已批准列、且已离开待批列
    public static func isApproveConfirmed(
        platform: String, userID: String, in refreshed: PairingListResponse
    ) -> Bool {
        let inApproved = refreshed.approved.contains {
            $0.platform == platform && $0.userID == userID
        }
        let stillPending = refreshed.pending.contains {
            $0.platform == platform && $0.userID == userID
        }
        return inApproved && !stillPending
    }

    /// 撤销确认：该用户已不在已批准列
    public static func isRevokeConfirmed(
        platform: String, userID: String, in refreshed: PairingListResponse
    ) -> Bool {
        !refreshed.approved.contains {
            $0.platform == platform && $0.userID == userID
        }
    }

    /// 清待批确认：待批列已空（过期条目随刷新收敛，
    /// 不留僵尸行）
    public static func isClearConfirmed(
        in refreshed: PairingListResponse
    ) -> Bool {
        refreshed.pending.isEmpty
    }
}
