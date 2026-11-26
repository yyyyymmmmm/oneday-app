import Foundation

// MARK: - GET /v1/capabilities（API Server 能力发现，Bearer）

/// 能力发现回文（官方源码 gateway/platforms/api_server.py
/// `_handle_capabilities` 形态，DESIGN §357）：features
/// 值异构（布尔／字符串型头名／幂等对象），走 JSONValue
/// 宽容解码；endpoints 只作内部完整性校验、不逐行上屏
/// （蓝图一期施工图 §1.5 口径：25 行端点表不是给人看的）
public struct CapabilitiesResponse: Decodable, Sendable {
    public let object: String?
    public let platform: String?
    public let model: String?
    public let authRequired: Bool?
    public let runtimeMode: String?
    public let features: [String: JSONValue]
    public let endpoints: [String: Endpoint]
    public let versionGate: VersionGateInfo?

    public struct Endpoint: Decodable, Sendable {
        public let method: String?
        public let path: String?
    }

    public struct VersionGateInfo: Decodable, Equatable, Sendable {
        public let minAppVersion: String?
        public let recommendedAppVersion: String?
        public let hermesVersion: String?

        enum CodingKeys: String, CodingKey {
            case minAppVersion = "min_app_version"
            case recommendedAppVersion = "recommended_app_version"
            case hermesVersion = "hermes_version"
        }
    }

    private struct AuthBody: Decodable {
        let type: String?
        let required: Bool?
    }

    private struct RuntimeBody: Decodable {
        let mode: String?
    }

    enum CodingKeys: String, CodingKey {
        case object, platform, model, auth, runtime, features, endpoints
        case versionGate = "version_gate"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        object = try container.decodeIfPresent(String.self, forKey: .object)
        platform = try container.decodeIfPresent(String.self, forKey: .platform)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        authRequired = try container.decodeIfPresent(
            AuthBody.self, forKey: .auth
        )?.required
        runtimeMode = try container.decodeIfPresent(
            RuntimeBody.self, forKey: .runtime
        )?.mode
        features = try container.decodeIfPresent(
            [String: JSONValue].self, forKey: .features
        ) ?? [:]
        endpoints = try container.decodeIfPresent(
            [String: Endpoint].self, forKey: .endpoints
        ) ?? [:]
        versionGate = try container.decodeIfPresent(
            VersionGateInfo.self, forKey: .versionGate
        )
    }

    /// 布尔旗标取值（字符串／对象型旗标回 nil）
    public func featureFlag(_ key: String) -> Bool? {
        if case .bool(let value)? = features[key] { return value }
        return nil
    }

    /// runs_idempotency 是对象型旗标
    /// （{supported, durable, retention_seconds}）
    public var runsIdempotencySupported: Bool? {
        if case .object(let body)? = features["runs_idempotency"],
           case .bool(let value)? = body["supported"] {
            return value
        }
        return nil
    }

    /// 消息级幂等子旗标（部署包 #14，总表 157）：runs_
    /// idempotency 对象内的 client_message_id；对象或子
    /// 旗标缺失回 nil（未广告），判定归 CapabilityNegotiation
    /// 选择框能力位（部署包 #22，总表 203）：features
    /// 布尔旗标 options_card；缺失回 nil（未广告），
    /// 判定归 CapabilityNegotiation
    public var optionsCardSupported: Bool? {
        featureFlag("options_card")
    }

    public var clientMessageIdSupported: Bool? {
        if case .object(let body)? = features["runs_idempotency"],
           case .bool(let value)? = body["client_message_id"] {
            return value
        }
        return nil
    }

    /// AI 自反应能力位（部署包 1.8.0，CAPABILITIES
    /// #19，DESIGN §432）：features.self_reactions
    /// 布尔旗标；缺失回 nil（未广告），判定归
    /// CapabilityNegotiation
    public var selfReactionsSupported: Bool? {
        featureFlag("self_reactions")
    }

    /// 短时票据能力位（#1 短时票据）：features.short_lived_tokens
    public var shortLivedTokensSupported: Bool? {
        featureFlag("short_lived_tokens")
    }

    /// 凭据库能力位（sj-07）：features.credential_vault
    public var credentialVaultSupported: Bool? {
        featureFlag("credential_vault")
    }

    /// 关键端点完整性（施工图 §1.5：缺失才上屏告警）
    public var missingKeyEndpoints: [String] {
        Self.keyEndpoints.filter { endpoints[$0] == nil }
    }

    public static let keyEndpoints = [
        "health", "models", "chat_completions", "runs", "sessions",
    ]
}

/// 能力旗标 → 人话行（Core 内写死一处，施工图 §1.5）：
/// 假旗标一律按「服务器未开放」呈现——是口径不开、
/// 不是故障（§1.4 全件⑥：admin_config_rw／jobs_admin／
/// memory_write_api／audio_api／realtime_voice 五项在
/// 本部署恒假）；runs_idempotency 走对象型取值
public struct CapabilityFeatureSpec: Sendable, Equatable {
    public let key: String
    public let title: String

    public init(key: String, title: String) {
        self.key = key
        self.title = title
    }
}

public enum CapabilityFeatureCatalog {
    public static let displayed: [CapabilityFeatureSpec] = [
        CapabilityFeatureSpec(key: "chat_completions", title: "对话接口"),
        CapabilityFeatureSpec(key: "chat_completions_streaming", title: "流式输出"),
        CapabilityFeatureSpec(key: "responses_api", title: "Responses 接口"),
        CapabilityFeatureSpec(key: "run_submission", title: "任务运行"),
        CapabilityFeatureSpec(key: "runs_idempotency", title: "任务幂等"),
        CapabilityFeatureSpec(key: "run_approval_response", title: "审批回执"),
        CapabilityFeatureSpec(key: "approval_events", title: "审批事件"),
        CapabilityFeatureSpec(key: "session_resources", title: "会话资源"),
        CapabilityFeatureSpec(key: "skills_api", title: "技能接口"),
        CapabilityFeatureSpec(key: "model_options", title: "模型选项"),
        CapabilityFeatureSpec(key: "run_unknown_resolution", title: "未知运行裁决"),
        CapabilityFeatureSpec(key: "audio_api", title: "语音接口"),
        CapabilityFeatureSpec(key: "realtime_voice", title: "实时语音"),
        CapabilityFeatureSpec(key: "memory_write_api", title: "记忆写入"),
        CapabilityFeatureSpec(key: "admin_config_rw", title: "配置读写"),
        CapabilityFeatureSpec(key: "jobs_admin", title: "任务管理"),
    ]
}

// MARK: - GET /health/detailed（API Server 深度健康，Bearer）

/// 深度健康回文（官方源码 `_handle_health_detailed`＋
/// gateway/readiness.py 形态）：readiness.checks 逐项
/// {status: ok|degraded|unavailable, detail?, …}，磁盘
/// 项带 used_percent／free_bytes、网关项带 state／
/// connected_platforms、队列项带三计数
public struct HealthDetailedResponse: Decodable, Sendable {
    public let status: String?
    public let version: String?
    public let gatewayState: String?
    public let readinessStatus: String?
    public let checks: [String: Check]
    public let apiServerState: String?
    public let metricsToday: MetricsToday?
    public let activeAgents: Int?
    public let gatewayBusy: Bool?

    public struct Check: Decodable, Sendable {
        public let status: String?
        public let detail: String?
        public let usedPercent: Double?
        public let freeBytes: Int64?
        public let state: String?
        public let connectedPlatforms: Int?
        public let activeAPIRuns: Int?
        public let processCompletions: Int?
        public let activeDelegations: Int?

        enum CodingKeys: String, CodingKey {
            case status, detail, state
            case usedPercent = "used_percent"
            case freeBytes = "free_bytes"
            case connectedPlatforms = "connected_platforms"
            case activeAPIRuns = "active_api_runs"
            case processCompletions = "process_completions"
            case activeDelegations = "active_delegations"
        }
    }

    public struct MetricsToday: Decodable, Sendable {
        public let requests: Int?
        public let messages: Int?
        public let tokens: Int?
        public let latencyP95Ms: Double?

        enum CodingKeys: String, CodingKey {
            case requests, messages, tokens
            case latencyP95Ms = "latency_p95_ms"
        }
    }

    private struct ReadinessBody: Decodable {
        let status: String?
        let checks: [String: Check]?
    }

    private struct PlatformBody: Decodable {
        let state: String?
    }

    enum CodingKeys: String, CodingKey {
        case status, version, readiness, platforms
        case gatewayState = "gateway_state"
        case metricsToday = "metrics_today"
        case activeAgents = "active_agents"
        case gatewayBusy = "gateway_busy"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        version = try container.decodeIfPresent(String.self, forKey: .version)
        gatewayState = try container.decodeIfPresent(
            String.self, forKey: .gatewayState
        )
        let readiness = try container.decodeIfPresent(
            ReadinessBody.self, forKey: .readiness
        )
        readinessStatus = readiness?.status
        checks = readiness?.checks ?? [:]
        let platforms = try container.decodeIfPresent(
            [String: PlatformBody].self, forKey: .platforms
        ) ?? [:]
        apiServerState = platforms["api_server"]?.state
        metricsToday = try container.decodeIfPresent(
            MetricsToday.self, forKey: .metricsToday
        )
        activeAgents = try container.decodeIfPresent(
            Int.self, forKey: .activeAgents
        )
        gatewayBusy = try container.decodeIfPresent(
            Bool.self, forKey: .gatewayBusy
        )
    }
}

// MARK: - GET /v1/approvals（待批聚合，Bearer；部署包批 2）

/// 待批聚合回文（部署包 patches/api_server.py
/// `_handle_list_approvals` 形态）：自检只取计数与降级
/// 旗，逐条记录不建模（正主在审批面）
public struct ApprovalsListResponse: Decodable, Sendable {
    public let object: String?
    public let pendingCount: Int
    public let ledgerDegraded: Bool

    enum CodingKeys: String, CodingKey {
        case object
        case pendingCount = "pending_count"
        case ledgerDegraded = "ledger_degraded"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        object = try container.decodeIfPresent(String.self, forKey: .object)
        pendingCount = try container.decodeIfPresent(
            Int.self, forKey: .pendingCount
        ) ?? 0
        ledgerDegraded = try container.decodeIfPresent(
            Bool.self, forKey: .ledgerDegraded
        ) ?? false
    }
}

// MARK: - 只读路由探针（补丁能力存在性，施工图 §1.1 探针表）

/// 路由探针结果：HTTP 状态码＋服务端错误码（无错误体
/// 时 nil）。判据按 CAPABILITIES 探针法：405＝POST 路
/// 由在位；404 须结合错误码分流（reactions 的
/// message_not_found 是路由在位、目标消息不存在）
public struct RouteProbeResult: Equatable, Sendable {
    public let status: Int
    public let errorCode: String?

    public init(status: Int, errorCode: String?) {
        self.status = status
        self.errorCode = errorCode
    }
}

// MARK: - 自检结论模型（连接自检面，DESIGN §357）

/// 单项探活的失败分型（呈现层把 HermesError 映射到
/// 此，人话原因在此单源生成、Core 钉测把守）
public enum SelfCheckFailure: Equatable, Sendable {
    /// 401/403：密钥被拒
    case unauthorized
    /// 其余非 200 状态码
    case httpStatus(Int)
    /// 服务端带错误码的失败（如投影不可用）
    case serverCode(String)
    /// 传输层失败（连不上/超时）
    case unreachable
    /// 200 但回文解不开
    case decoding
    /// 本机未配置密钥、带鉴权的探针无从发
    case missingCredentials

    /// 人话原因（行内呈现）
    public var reasonText: String {
        switch self {
        case .unauthorized:
            return "密钥被服务器拒绝"
        case .httpStatus(let status):
            return "服务器回码 \(status)"
        case .serverCode(let code):
            return "服务端错误（\(code)）"
        case .unreachable:
            return "连不上服务器"
        case .decoding:
            return "服务器回文读不懂"
        case .missingCredentials:
            return "未配置密钥"
        }
    }
}

/// 一次探活的结局：拿到真值／失败（带分型）／没发
/// （编排层主动跳过）。结论只许来自 success 的真值——
/// 失败与没发都不许推成「正常」（僵尸禁令）
public enum SelfCheckFetch<Value> {
    case success(Value)
    case failure(SelfCheckFailure)
    case notAttempted
}

extension SelfCheckFetch: Sendable where Value: Sendable {}

/// 自检行状态：正常／异常来自实测；未开放＝服务器口
/// 径不开（非故障）；未探＝没拿到证据、不下结论
public enum SelfCheckRowStatus: String, Equatable, Sendable {
    case ok
    case warn
    case off
    case unprobed

    /// 一词结论（文字与状态点并行呈现，不只靠颜色）
    public var word: String {
        switch self {
        case .ok: return "正常"
        case .warn: return "异常"
        case .off: return "未开放"
        case .unprobed: return "未探"
        }
    }
}

public struct SelfCheckRow: Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let status: SelfCheckRowStatus
    /// 实测值（如版本号、计数、百分比）；无值不占位
    public let value: String?
    /// 人话原因（异常给原因与下一步口径、未探给没探
    /// 的缘由）；正常行一般为空
    public let reason: String?

    public init(
        id: String, title: String, status: SelfCheckRowStatus,
        value: String? = nil, reason: String? = nil
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.value = value
        self.reason = reason
    }
}

public struct SelfCheckGroup: Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let rows: [SelfCheckRow]

    public init(id: String, title: String, rows: [SelfCheckRow]) {
        self.id = id
        self.title = title
        self.rows = rows
    }
}

public struct SelfCheckReport: Equatable, Sendable {
    public let groups: [SelfCheckGroup]
    public let checkedAt: Date

    public init(groups: [SelfCheckGroup], checkedAt: Date) {
        self.groups = groups
        self.checkedAt = checkedAt
    }

    public var rows: [SelfCheckRow] { groups.flatMap(\.rows) }

    public var warnCount: Int {
        rows.filter { $0.status == .warn }.count
    }

    /// 探到结论的行数（未探不算）
    public var probedCount: Int {
        rows.filter { $0.status != .unprobed }.count
    }

    /// 一词结论（设置行副题与页头共用）：有异常报数；
    /// 全探过且无异常报「正常」；一项都没探到报「未
    /// 检出」——不许把没探到说成正常
    public var overallWord: String {
        if warnCount > 0 { return "\(warnCount) 项异常" }
        if probedCount == 0 { return "未检出" }
        return "正常"
    }
}

/// 自检留痕（每台服务器最近一次）：只存时间＋一词结
/// 论＋异常数，原始回文不落盘（HealthSummaryStore 同式）
public struct SelfCheckSummary: Codable, Equatable, Sendable {
    public var date: Date
    public var serverBase: String
    public var word: String
    public var warnCount: Int

    public init(
        date: Date, serverBase: String, word: String, warnCount: Int
    ) {
        self.date = date
        self.serverBase = serverBase
        self.word = word
        self.warnCount = warnCount
    }
}

// MARK: - 自检结论合成（纯函数，逐项只认真值）

public enum SelfCheckReportBuilder {

    public static func build(
        health: SelfCheckFetch<HealthResponse>,
        capabilities: SelfCheckFetch<CapabilitiesResponse>,
        detailed: SelfCheckFetch<HealthDetailedResponse>,
        status: SelfCheckFetch<ServerStatus>,
        approvals: SelfCheckFetch<ApprovalsListResponse>,
        grants: SelfCheckFetch<GrantsListResponse>,
        enrollmentProbe: SelfCheckFetch<RouteProbeResult>,
        reactionsProbe: SelfCheckFetch<RouteProbeResult>?,
        checkedAt: Date
    ) -> SelfCheckReport {
        SelfCheckReport(
            groups: [
                connectionGroup(
                    health: health, capabilities: capabilities,
                    status: status, detailed: detailed
                ),
                serviceGroup(status: status, detailed: detailed),
                capabilityGroup(capabilities: capabilities),
                extensionGroup(
                    approvals: approvals, grants: grants,
                    enrollment: enrollmentProbe, reactions: reactionsProbe
                ),
            ],
            checkedAt: checkedAt
        )
    }

    // MARK: 连接组

    private static func connectionGroup(
        health: SelfCheckFetch<HealthResponse>,
        capabilities: SelfCheckFetch<CapabilitiesResponse>,
        status: SelfCheckFetch<ServerStatus>,
        detailed: SelfCheckFetch<HealthDetailedResponse>
    ) -> SelfCheckGroup {
        var rows: [SelfCheckRow] = []

        switch health {
        case .success(let response):
            rows.append(SelfCheckRow(
                id: "reachable", title: "服务器可达", status: .ok,
                value: response.version.map { "Hermes \($0)" }
                    ?? response.platform
            ))
        case .failure(let failure):
            rows.append(SelfCheckRow(
                id: "reachable", title: "服务器可达", status: .warn,
                reason: failure.reasonText
            ))
        case .notAttempted:
            rows.append(SelfCheckRow(
                id: "reachable", title: "服务器可达", status: .unprobed
            ))
        }

        switch capabilities {
        case .success:
            rows.append(SelfCheckRow(
                id: "credential", title: "密钥", status: .ok,
                value: "有效"
            ))
        case .failure(.missingCredentials):
            rows.append(SelfCheckRow(
                id: "credential", title: "密钥", status: .unprobed,
                reason: "未配置密钥，这一面没探"
            ))
        case .failure(let failure):
            rows.append(SelfCheckRow(
                id: "credential", title: "密钥", status: .warn,
                reason: failure.reasonText
            ))
        case .notAttempted:
            rows.append(SelfCheckRow(
                id: "credential", title: "密钥", status: .unprobed
            ))
        }

        rows.append(gatewayRow(status: status, detailed: detailed))
        return SelfCheckGroup(id: "connection", title: "连接", rows: rows)
    }

    /// 网关行：真源优先 /api/status 的运行面；缺位时退
    /// /health/detailed 的 gateway_state；两处都没拿到
    /// 才显未探
    private static func gatewayRow(
        status: SelfCheckFetch<ServerStatus>,
        detailed: SelfCheckFetch<HealthDetailedResponse>
    ) -> SelfCheckRow {
        if case .success(let serverStatus) = status {
            if serverStatus.gatewayRunning == true
                || serverStatus.gatewayState == "running" {
                return SelfCheckRow(
                    id: "gateway", title: "网关", status: .ok,
                    value: "运行中"
                )
            }
            if let state = serverStatus.gatewayState {
                return SelfCheckRow(
                    id: "gateway", title: "网关", status: .warn,
                    value: gatewayStateWord(state),
                    reason: "网关未在运行"
                )
            }
            if serverStatus.gatewayRunning == false {
                return SelfCheckRow(
                    id: "gateway", title: "网关", status: .warn,
                    value: "已停止", reason: "网关未在运行"
                )
            }
            return SelfCheckRow(
                id: "gateway", title: "网关", status: .unprobed,
                reason: "服务端未回报网关状态"
            )
        }
        if case .success(let detailed) = detailed,
           let state = detailed.gatewayState {
            return state == "running"
                ? SelfCheckRow(
                    id: "gateway", title: "网关", status: .ok,
                    value: "运行中"
                )
                : SelfCheckRow(
                    id: "gateway", title: "网关", status: .warn,
                    value: gatewayStateWord(state),
                    reason: "网关未在运行"
                )
        }
        return SelfCheckRow(
            id: "gateway", title: "网关", status: .unprobed,
            reason: failureReason(of: status)
        )
    }

    private static func gatewayStateWord(_ state: String) -> String {
        switch state {
        case "running": return "运行中"
        case "stopped": return "已停止"
        case "draining": return "排空中"
        case "starting": return "启动中"
        default: return state
        }
    }

    // MARK: 服务状态组

    private static func serviceGroup(
        status: SelfCheckFetch<ServerStatus>,
        detailed: SelfCheckFetch<HealthDetailedResponse>
    ) -> SelfCheckGroup {
        var rows: [SelfCheckRow] = []

        // 组件三行（/api/status components：面板/存储/平台）
        let componentTitles: [(String, String)] = [
            ("componentDashboard", "面板服务"),
            ("componentStorage", "存储"),
            ("componentPlatforms", "消息平台"),
        ]
        if case .success(let serverStatus) = status,
           let components = serverStatus.components {
            let dashboardErrors = components.dashboard?
                .recentUnhandledErrors ?? 0
            rows.append(componentRow(
                id: "componentDashboard", title: "面板服务",
                status: components.dashboard?.status,
                reason: dashboardErrors > 0
                    ? "近期有 \(dashboardErrors) 次未处理错误" : nil
            ))
            rows.append(componentRow(
                id: "componentStorage", title: "存储",
                status: components.storage?.status,
                reason: components.storage?.reason == "corrupt"
                    ? "存储损坏" : nil
            ))
            let platforms = components.platforms
            rows.append(componentRow(
                id: "componentPlatforms", title: "消息平台",
                status: platforms?.status,
                value: platforms.map {
                    "已连 \($0.connected ?? 0)/\($0.configured ?? 0)"
                }
            ))
        } else {
            let reason: String
            if case .success = status {
                reason = "服务端未提供组件状态"
            } else {
                reason = failureReason(of: status)
            }
            for (id, title) in componentTitles {
                rows.append(SelfCheckRow(
                    id: id, title: title,
                    status: .unprobed, reason: reason
                ))
            }
        }

        // 就绪六行（/health/detailed readiness.checks）
        let checkTitles: [(String, String)] = [
            ("state_db", "状态库"),
            ("session_store", "会话存储"),
            ("config", "配置"),
            ("model", "模型"),
            ("disk", "磁盘"),
            ("background_queues", "后台队列"),
        ]
        if case .success(let detailed) = detailed {
            for (key, title) in checkTitles {
                rows.append(readinessRow(
                    id: "check-\(key)", title: title,
                    check: detailed.checks[key]
                ))
            }
        } else {
            let reason = failureReason(of: detailed)
            for (key, title) in checkTitles {
                rows.append(SelfCheckRow(
                    id: "check-\(key)", title: title,
                    status: .unprobed, reason: reason
                ))
            }
        }

        return SelfCheckGroup(id: "service", title: "服务状态", rows: rows)
    }

    private static func componentRow(
        id: String, title: String, status: String?,
        value: String? = nil, reason: String? = nil
    ) -> SelfCheckRow {
        switch status {
        case "ok":
            return SelfCheckRow(
                id: id, title: title, status: .ok, value: value
            )
        case "degraded":
            return SelfCheckRow(
                id: id, title: title, status: .warn, value: value,
                reason: reason ?? "状态异常"
            )
        case nil:
            return SelfCheckRow(
                id: id, title: title, status: .unprobed,
                reason: "服务端未回报这一项"
            )
        default:
            return SelfCheckRow(
                id: id, title: title, status: .warn, value: value,
                reason: reason ?? "状态异常"
            )
        }
    }

    private static func readinessRow(
        id: String, title: String, check: HealthDetailedResponse.Check?
    ) -> SelfCheckRow {
        guard let check else {
            return SelfCheckRow(
                id: id, title: title, status: .unprobed,
                reason: "服务端未回报这一项"
            )
        }
        var value: String?
        if let usedPercent = check.usedPercent {
            value = "已用 \(percentText(usedPercent))"
        } else if let active = check.activeAPIRuns {
            let waiting = check.processCompletions ?? 0
            value = active > 0
                ? "\(active) 个任务运行中"
                : (waiting > 0 ? "待处理 \(waiting) 件" : "空闲")
        }
        switch check.status {
        case "ok":
            return SelfCheckRow(
                id: id, title: title, status: .ok, value: value
            )
        case "degraded":
            return SelfCheckRow(
                id: id, title: title, status: .warn, value: value,
                reason: check.detail ?? "状态降级"
            )
        case "unavailable":
            return SelfCheckRow(
                id: id, title: title, status: .warn, value: value,
                reason: check.detail ?? "不可用"
            )
        default:
            return SelfCheckRow(
                id: id, title: title, status: .unprobed, value: value,
                reason: "服务端回了没见过的状态"
            )
        }
    }

    private static func percentText(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(value))%"
            : String(format: "%.1f%%", value)
    }

    // MARK: 服务器能力组

    private static func capabilityGroup(
        capabilities: SelfCheckFetch<CapabilitiesResponse>
    ) -> SelfCheckGroup {
        var rows: [SelfCheckRow] = []
        switch capabilities {
        case .success(let response):
            for spec in CapabilityFeatureCatalog.displayed {
                let on: Bool? = spec.key == "runs_idempotency"
                    ? response.runsIdempotencySupported
                    : response.featureFlag(spec.key)
                switch on {
                case .some(true):
                    rows.append(SelfCheckRow(
                        id: "feature-\(spec.key)", title: spec.title,
                        status: .ok
                    ))
                case .some(false):
                    rows.append(SelfCheckRow(
                        id: "feature-\(spec.key)", title: spec.title,
                        status: .off, reason: "服务器未开放"
                    ))
                case .none:
                    rows.append(SelfCheckRow(
                        id: "feature-\(spec.key)", title: spec.title,
                        status: .off, reason: "服务器未广告此能力"
                    ))
                }
            }
            let missing = response.missingKeyEndpoints
            rows.append(missing.isEmpty
                ? SelfCheckRow(
                    id: "endpointIntegrity", title: "接口完整性",
                    status: .ok, value: "关键端点齐全"
                )
                : SelfCheckRow(
                    id: "endpointIntegrity", title: "接口完整性",
                    status: .warn,
                    reason: "缺失端点：\(missing.joined(separator: "、"))"
                ))
        case .failure(let failure):
            for spec in CapabilityFeatureCatalog.displayed {
                rows.append(SelfCheckRow(
                    id: "feature-\(spec.key)", title: spec.title,
                    status: .unprobed, reason: failure.reasonText
                ))
            }
            rows.append(SelfCheckRow(
                id: "endpointIntegrity", title: "接口完整性",
                status: .unprobed, reason: failure.reasonText
            ))
        case .notAttempted:
            for spec in CapabilityFeatureCatalog.displayed {
                rows.append(SelfCheckRow(
                    id: "feature-\(spec.key)", title: spec.title,
                    status: .unprobed
                ))
            }
            rows.append(SelfCheckRow(
                id: "endpointIntegrity", title: "接口完整性",
                status: .unprobed
            ))
        }
        return SelfCheckGroup(
            id: "capabilities", title: "服务器能力", rows: rows
        )
    }

    // MARK: 扩展能力组（部署包补丁，capabilities 不广告、逐项探针）

    private static func extensionGroup(
        approvals: SelfCheckFetch<ApprovalsListResponse>,
        grants: SelfCheckFetch<GrantsListResponse>,
        enrollment: SelfCheckFetch<RouteProbeResult>,
        reactions: SelfCheckFetch<RouteProbeResult>?
    ) -> SelfCheckGroup {
        var rows: [SelfCheckRow] = []

        switch approvals {
        case .success(let response):
            if response.ledgerDegraded {
                rows.append(SelfCheckRow(
                    id: "extApprovals", title: "待批查询", status: .warn,
                    value: "待批 \(response.pendingCount) 件",
                    reason: "待批账本降级，结论可能不全"
                ))
            } else {
                rows.append(SelfCheckRow(
                    id: "extApprovals", title: "待批查询", status: .ok,
                    value: response.pendingCount > 0
                        ? "待批 \(response.pendingCount) 件" : "无待批"
                ))
            }
        case .failure(.serverCode("approval_projection_unavailable")):
            rows.append(SelfCheckRow(
                id: "extApprovals", title: "待批查询", status: .warn,
                reason: "待批投影不可用"
            ))
        case .failure(.httpStatus(404)):
            rows.append(SelfCheckRow(
                id: "extApprovals", title: "待批查询", status: .off,
                reason: "服务器未开放"
            ))
        case .failure(.missingCredentials):
            rows.append(SelfCheckRow(
                id: "extApprovals", title: "待批查询", status: .unprobed,
                reason: "未配置密钥，这一面没探"
            ))
        case .failure(let failure):
            rows.append(SelfCheckRow(
                id: "extApprovals", title: "待批查询", status: .warn,
                reason: failure.reasonText
            ))
        case .notAttempted:
            rows.append(SelfCheckRow(
                id: "extApprovals", title: "待批查询", status: .unprobed
            ))
        }

        switch grants {
        case .success(let response):
            if response.partial {
                rows.append(SelfCheckRow(
                    id: "extGrants", title: "命令授权账本", status: .warn,
                    value: "读到 \(response.grants.count) 条",
                    reason: "只读到一半，清单可能不全"
                ))
            } else {
                rows.append(SelfCheckRow(
                    id: "extGrants", title: "命令授权账本", status: .ok,
                    value: "共 \(response.grants.count) 条授权"
                ))
            }
        case .failure(.serverCode("grant_projection_unavailable")):
            rows.append(SelfCheckRow(
                id: "extGrants", title: "命令授权账本", status: .warn,
                reason: "授权投影不可用"
            ))
        case .failure(.httpStatus(404)):
            rows.append(SelfCheckRow(
                id: "extGrants", title: "命令授权账本", status: .off,
                reason: "服务器未开放"
            ))
        case .failure(.missingCredentials):
            rows.append(SelfCheckRow(
                id: "extGrants", title: "命令授权账本", status: .unprobed,
                reason: "未配置密钥，这一面没探"
            ))
        case .failure(let failure):
            rows.append(SelfCheckRow(
                id: "extGrants", title: "命令授权账本", status: .warn,
                reason: failure.reasonText
            ))
        case .notAttempted:
            rows.append(SelfCheckRow(
                id: "extGrants", title: "命令授权账本", status: .unprobed
            ))
        }

        switch enrollment {
        case .success(let probe):
            // 判定单源在 CapabilityNegotiation（总表
            // 157，§394），本行呈现文案不动
            switch CapabilityNegotiation.enrollmentAvailability(probe) {
            case .available:
                rows.append(SelfCheckRow(
                    id: "extEnrollment", title: "设备认领", status: .ok
                ))
            case .unavailable:
                rows.append(SelfCheckRow(
                    id: "extEnrollment", title: "设备认领", status: .off,
                    reason: "服务器未开放"
                ))
            case .unknown:
                rows.append(SelfCheckRow(
                    id: "extEnrollment", title: "设备认领",
                    status: .unprobed,
                    reason: "回码 \(probe.status)，无法确认"
                ))
            }
        case .failure(let failure):
            rows.append(SelfCheckRow(
                id: "extEnrollment", title: "设备认领", status: .unprobed,
                reason: failure.reasonText
            ))
        case .notAttempted:
            rows.append(SelfCheckRow(
                id: "extEnrollment", title: "设备认领", status: .unprobed
            ))
        }

        if let reactions {
            switch reactions {
            case .success(let probe):
                // 判定单源在 CapabilityNegotiation（总
                // 表 157，§394）：405/200 与 404 带
                // message_not_found 错误码（路由在位、目
                // 标消息不存在的实证）同判在位
                switch CapabilityNegotiation.reactionsAvailability(probe) {
                case .available:
                    rows.append(SelfCheckRow(
                        id: "extReactions", title: "消息反应", status: .ok
                    ))
                case .unavailable:
                    rows.append(SelfCheckRow(
                        id: "extReactions", title: "消息反应", status: .off,
                        reason: "服务器未开放"
                    ))
                case .unknown:
                    rows.append(SelfCheckRow(
                        id: "extReactions", title: "消息反应",
                        status: .unprobed,
                        reason: "回码 \(probe.status)，无法确认"
                    ))
                }
            case .failure(let failure):
                rows.append(SelfCheckRow(
                    id: "extReactions", title: "消息反应",
                    status: .unprobed, reason: failure.reasonText
                ))
            case .notAttempted:
                rows.append(SelfCheckRow(
                    id: "extReactions", title: "消息反应", status: .unprobed
                ))
            }
        } else {
            rows.append(SelfCheckRow(
                id: "extReactions", title: "消息反应", status: .unprobed,
                reason: "暂无会话可探"
            ))
        }

        // rewind 无只读探针（GET 打该路由回 404 是本应用
        // 口径、CAPABILITIES 明载不作判据）：如实显未探，
        // 以 App 自身功能在位表达，不假探
        rows.append(SelfCheckRow(
            id: "extRewind", title: "编辑重发", status: .unprobed,
            reason: "服务端无只读探针，以聊天页入口在位为准"
        ))

        return SelfCheckGroup(
            id: "extensions", title: "扩展能力", rows: rows
        )
    }

    // MARK: 工具

    private static func failureReason<T>(
        of fetch: SelfCheckFetch<T>
    ) -> String {
        if case .failure(let failure) = fetch {
            return failure.reasonText
        }
        return "这一面没探"
    }
}
