import Foundation
import OneDayCore

/// 自检留痕（DESIGN §357）：每台服务器只存最近一次自
/// 检的结论摘要（一词结论＋异常数＋时间），原始回文
/// 永不落盘。归宿与 HealthSummaryStore 同式
/// （UserDefaults JSON）；设置根行副题与自检面共读
/// 同一份（shared）
@MainActor
@Observable
final class SelfCheckSummaryStore {
    static let shared = SelfCheckSummaryStore()

    private let defaults: UserDefaults
    private var summaries: [String: SelfCheckSummary] = [:]

    private static let defaultsKey = "selfcheck.lastSummary.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode(
               [String: SelfCheckSummary].self, from: data
           ) {
            summaries = decoded
        }
    }

    func summary(for serverBase: String?) -> SelfCheckSummary? {
        guard let serverBase else { return nil }
        return summaries[serverBase]
    }

    func save(_ summary: SelfCheckSummary) {
        summaries[summary.serverBase] = summary
        if let data = try? JSONEncoder().encode(summaries) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }
}

/// 连接自检编排（DESIGN §357）：一轮约 8 个只读 GET
/// 并发取数、逐项隔离——一项失败只落该项的失败分
/// 型，不拖整面；结论合成走 Core 纯函数
/// SelfCheckReportBuilder，本层只管取数与
/// HermesError → SelfCheckFailure 的映射。服务端零
/// 写请求；整轮结论落留痕供设置行副题读
@MainActor
@Observable
/// §416 新鲜度普查豁免：自检面——显式触发汇总，无读触发全量拉取（判定表见 DESIGN §416）
final class ConnectionSelfCheckStore {
    private(set) var report: SelfCheckReport?
    private(set) var isRunning = false

    private let summaryStore: SelfCheckSummaryStore

    init(summaryStore: SelfCheckSummaryStore = .shared) {
        self.summaryStore = summaryStore
    }

    /// 跑一轮自检（重入不双跑：首入/下拉/按钮三路同源）
    func run(
        client: HermesClientProtocol, config: ServerConfig,
        apiKey: String?
    ) async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        async let healthFetch = Self.fetch {
            try await client.health(config: config)
        }
        async let statusFetch = Self.fetch {
            try await client.status(config: config)
        }

        // 带鉴权四面（能力/深度健康/待批/授权账本）：
        // 无密钥时不发请求、直接记 missingCredentials，
        // 对应行显「未配置密钥」未探，不假装探过
        let capabilitiesFetch: SelfCheckFetch<CapabilitiesResponse>
        let detailedFetch: SelfCheckFetch<HealthDetailedResponse>
        let approvalsFetch: SelfCheckFetch<ApprovalsListResponse>
        let grantsFetch: SelfCheckFetch<GrantsListResponse>
        if let apiKey {
            async let capsFetch = Self.fetch {
                try await client.capabilities(
                    config: config, apiKey: apiKey
                )
            }
            async let detFetch = Self.fetch {
                try await client.healthDetailed(
                    config: config, apiKey: apiKey
                )
            }
            async let appFetch = Self.fetch {
                try await client.listApprovals(
                    config: config, apiKey: apiKey
                )
            }
            async let grFetch = Self.fetch {
                try await client.listGrants(
                    config: config, apiKey: apiKey
                )
            }
            capabilitiesFetch = await capsFetch
            detailedFetch = await detFetch
            approvalsFetch = await appFetch
            grantsFetch = await grFetch
        } else {
            capabilitiesFetch = .failure(.missingCredentials)
            detailedFetch = .failure(.missingCredentials)
            approvalsFetch = .failure(.missingCredentials)
            grantsFetch = .failure(.missingCredentials)
        }

        // 认领探针免鉴权、恒跑（405＝路由在位）
        let enrollmentProbe = await client.routeProbe(
            config: config, apiKey: apiKey,
            path: "/v1/enrollment/claim"
        )
        let enrollmentFetch: SelfCheckFetch<RouteProbeResult> =
            enrollmentProbe.map { .success($0) }
                ?? .failure(.unreachable)

        // 反应探针须先有一条会话作目标；无密钥不探
        var reactionsFetch: SelfCheckFetch<RouteProbeResult>?
        if let apiKey {
            reactionsFetch = await Self.probeReactions(
                client: client, config: config, apiKey: apiKey
            )
        }

        let built = SelfCheckReportBuilder.build(
            health: await healthFetch,
            capabilities: capabilitiesFetch,
            detailed: detailedFetch,
            status: await statusFetch,
            approvals: approvalsFetch,
            grants: grantsFetch,
            enrollmentProbe: enrollmentFetch,
            reactionsProbe: reactionsFetch,
            checkedAt: Date()
        )
        report = built
        summaryStore.save(SelfCheckSummary(
            date: built.checkedAt, serverBase: config.baseString,
            word: built.overallWord, warnCount: built.warnCount
        ))
    }

    /// 反应探针：取最近一条会话作探针目标（判据在
    /// Core：405/200/message_not_found 的 404 都是在
    /// 位实证）；没会话或取会话失败回 nil——该行显
    /// 「暂无会话可探」，不假探
    private nonisolated static func probeReactions(
        client: HermesClientProtocol, config: ServerConfig,
        apiKey: String
    ) async -> SelfCheckFetch<RouteProbeResult>? {
        guard let page = try? await client.serverSessions(
            config: config, limit: 1
        ), let session = page.sessions.first else { return nil }
        let probe = await client.routeProbe(
            config: config, apiKey: apiKey,
            path: "/v1/reactions/\(session.id)/1"
        )
        return probe.map { .success($0) } ?? .failure(.unreachable)
    }

    /// 取数一口：成败收成 SelfCheckFetch，失败按
    /// HermesError 分型（与呈现层共用同一口径）
    private nonisolated static func fetch<T>(
        _ body: () async throws -> T
    ) async -> SelfCheckFetch<T> {
        do {
            return .success(try await body())
        } catch {
            return .failure(classify(error))
        }
    }

    /// HermesError → 自检失败分型：密钥被拒单列（呈
    /// 现给「密钥」行）、带码错误连码（投影不可用等
    /// 专属分型在 Core 合成处认码）、其余归传输失败
    nonisolated static func classify(_ error: Error) -> SelfCheckFailure {
        guard let error = error as? HermesError else {
            return .unreachable
        }
        switch error {
        case .apiKeyRejected, .loginRejected:
            return .unauthorized
        case .healthCheckFailed(let status),
             .unexpectedStatus(_, let status),
             .loginFailed(let status):
            return .httpStatus(status)
        case .serverError(_, _, let code):
            return .serverCode(code)
        case .decodingFailed:
            return .decoding
        default:
            return .unreachable
        }
    }
}
