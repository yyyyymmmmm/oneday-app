import Foundation

// MARK: - 三方版本兼容协商门（第五批 #9）

/// App ↔ 网关 ↔ Hermes 版本兼容协商结果
public enum VersionCompatibilityStatus: Equatable, Sendable {
    case compatible
    case upgradeRecommended(message: String)
    case incompatible(message: String)

    public var isBlocked: Bool {
        if case .incompatible = self { return true }
        return false
    }
}

/// 语义化版本比较与三方兼容门（纯函数，不依赖网络）
public enum VersionCompatibilityGate {

    public struct Handshake: Equatable, Sendable {
        public let appVersion: String
        public let minAppVersion: String?
        public let recommendedAppVersion: String?
        public let gatewayVersion: String?
        public let hermesVersion: String?

        public init(
            appVersion: String,
            minAppVersion: String? = nil,
            recommendedAppVersion: String? = nil,
            gatewayVersion: String? = nil,
            hermesVersion: String? = nil
        ) {
            self.appVersion = appVersion
            self.minAppVersion = minAppVersion
            self.recommendedAppVersion = recommendedAppVersion
            self.gatewayVersion = gatewayVersion
            self.hermesVersion = hermesVersion
        }
    }

    /// 按点分数字比较两个版本号（如 0.50.126 vs 0.50.125）
    public static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let a = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let b = rhs.split(separator: ".").map { Int($0) ?? 0 }
        let count = max(a.count, b.count)
        for i in 0..<count {
            let av = i < a.count ? a[i] : 0
            let bv = i < b.count ? b[i] : 0
            if av < bv { return .orderedAscending }
            if av > bv { return .orderedDescending }
        }
        return .orderedSame
    }

    /// 评估当前 App 与服务端最低/推荐兼容线是否匹配（三态门禁：正常 / 软提示 / 强阻断）
    public static func evaluate(_ handshake: Handshake) -> VersionCompatibilityStatus {
        if let minApp = handshake.minAppVersion,
           !minApp.isEmpty,
           compare(handshake.appVersion, minApp) == .orderedAscending {
            return .incompatible(
                message: "当前客户端版本（\(handshake.appVersion)）过低，服务器要求至少升级到 \(minApp) 后才能正常使用。"
            )
        }
        if let recommended = handshake.recommendedAppVersion,
           !recommended.isEmpty,
           compare(handshake.appVersion, recommended) == .orderedAscending {
            return .upgradeRecommended(
                message: "发现推荐更新（\(recommended)），当前版本（\(handshake.appVersion)）仍可继续使用，建议尽快升级。"
            )
        }
        return .compatible
    }
}

// MARK: - 产品健康度与运维面板指标模型（第五批 #10 / #11）

/// 对接主线 G1 服务端聚合字段的客户端消费模型；服务端未下发时可回落本地统计
public struct ProductHealthMetrics: Codable, Equatable, Sendable {
    public let runTotal24h: Int
    public let runSuccessRate: Double?
    public let runFailedCount: Int
    public let runCancelledCount: Int
    public let sessionLinkFailCount: Int
    public let pendingReconcileRuns: Int

    public init(
        runTotal24h: Int = 0,
        runSuccessRate: Double? = nil,
        runFailedCount: Int = 0,
        runCancelledCount: Int = 0,
        sessionLinkFailCount: Int = 0,
        pendingReconcileRuns: Int = 0
    ) {
        self.runTotal24h = runTotal24h
        self.runSuccessRate = runSuccessRate
        self.runFailedCount = runFailedCount
        self.runCancelledCount = runCancelledCount
        self.sessionLinkFailCount = sessionLinkFailCount
        self.pendingReconcileRuns = pendingReconcileRuns
    }

    enum CodingKeys: String, CodingKey {
        case runTotal24h = "run_total_24h"
        case runSuccessRate = "run_success_rate"
        case runFailedCount = "run_failed_count"
        case runCancelledCount = "run_cancelled_count"
        case sessionLinkFailCount = "session_link_fail_count"
        case pendingReconcileRuns = "pending_reconcile_runs"
    }

    public var formattedSuccessRate: String {
        guard let rate = runSuccessRate else { return "暂无数据" }
        return String(format: "%.1f%%", rate * 100)
    }
}

// MARK: - 短时票据与会话管理模型（#1 短时票据）

/// POST /v1/auth/token 与 /v1/auth/refresh 回执（与 server/patches/auth_tokens.py 字段严格对齐）
public struct ShortLivedTokenPair: Codable, Equatable, Sendable {
    public let sessionID: String
    public let accessToken: String
    public let refreshToken: String
    public let tokenType: String
    public let expiresIn: Int
    public let accessExpiresAt: Double
    public let refreshExpiresAt: Double

    public init(
        sessionID: String,
        accessToken: String,
        refreshToken: String,
        tokenType: String = "Bearer",
        expiresIn: Int,
        accessExpiresAt: Double,
        refreshExpiresAt: Double
    ) {
        self.sessionID = sessionID
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.tokenType = tokenType
        self.expiresIn = expiresIn
        self.accessExpiresAt = accessExpiresAt
        self.refreshExpiresAt = refreshExpiresAt
    }

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case accessExpiresAt = "access_expires_at"
        case refreshExpiresAt = "refresh_expires_at"
    }
}

/// GET /v1/auth/sessions 单条会话摘要
public struct AuthSessionSummary: Codable, Equatable, Sendable, Identifiable {
    public let sessionID: String
    public let deviceName: String
    public let appVersion: String?
    public let createdAt: Double
    public let lastUsedAt: Double
    public let refreshExpiresAt: Double
    public let revoked: Bool
    public let revokedReason: String?

    public var id: String { sessionID }

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case deviceName = "device_name"
        case appVersion = "app_version"
        case createdAt = "created_at"
        case lastUsedAt = "last_used_at"
        case refreshExpiresAt = "refresh_expires_at"
        case revoked
        case revokedReason = "revoked_reason"
    }
}

/// GET /v1/auth/sessions 响应包装
public struct AuthSessionsListResponse: Codable, Equatable, Sendable {
    public let object: String?
    public let data: [AuthSessionSummary]
}

/// DELETE /v1/auth/sessions/{session_id} 撤销回执
public struct AuthRevokeReceipt: Codable, Equatable, Sendable {
    public let revoked: Int
    public let sessionIDs: [String]

    enum CodingKeys: String, CodingKey {
        case revoked
        case sessionIDs = "session_ids"
    }
}

/// 短时票据生命周期纯函数判定（默认提前 2 小时触发无感刷新）
public enum ShortLivedTokenLifecycle {
    public static let defaultRefreshLeewaySeconds: TimeInterval = 2 * 3600

    public static func isExpired(
        expiresAt: TimeInterval,
        now: Date = Date()
    ) -> Bool {
        now.timeIntervalSince1970 >= expiresAt
    }

    public static func needsRefresh(
        expiresAt: TimeInterval,
        now: Date = Date(),
        leewaySeconds: TimeInterval = defaultRefreshLeewaySeconds
    ) -> Bool {
        now.timeIntervalSince1970 + leewaySeconds >= expiresAt
    }
}

