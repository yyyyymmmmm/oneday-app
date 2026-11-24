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
        public let gatewayVersion: String?
        public let hermesVersion: String?

        public init(
            appVersion: String,
            minAppVersion: String? = nil,
            gatewayVersion: String? = nil,
            hermesVersion: String? = nil
        ) {
            self.appVersion = appVersion
            self.minAppVersion = minAppVersion
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

    /// 评估当前 App 与服务端最低兼容线是否匹配
    public static func evaluate(_ handshake: Handshake) -> VersionCompatibilityStatus {
        guard let minApp = handshake.minAppVersion, !minApp.isEmpty else {
            return .compatible
        }
        if compare(handshake.appVersion, minApp) == .orderedAscending {
            return .incompatible(
                message: "当前客户端版本（\(handshake.appVersion)）过低，服务器要求至少升级到 \(minApp) 后才能正常使用。"
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
