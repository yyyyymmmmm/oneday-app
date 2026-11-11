import Foundation
import OneDayCore

/// write-gate 桥错误口径（桥方案 §3 错误契约）：段状态
/// 映射靠这组区分——404/501 在 /status、/pending 上是
/// 「桥不存在」信号（bridgeUnavailable），在 detail/
/// decision 上是「记录已被处理」（notFound）；409 是闸门
/// 模块不受支持或内容/状态已变化；401 不区分原因。
enum WriteGateError: Error, Sendable {
    /// 无桥钥匙（凭据通道未发放）：等同通道未接通
    case noKey
    /// 桥端点不存在（404/501 出现在 status/pending 上）
    case bridgeMissing
    /// 401：钥匙无效（桥不区分原因，客户端也不猜）
    case unauthorized
    /// detail/decision 的 404：记录已被别处处理或已失效
    case recordGone
    /// 409：自检失败或内容已变化，旧裁决不许硬打
    case conflict
    /// 其余网络/状态错误（人话简述，供行内提示）
    case failed(String)
}

/// write-gate 桥客户端协议：与 HermesClientProtocol 分开
/// ——桥是同机 sidecar、单独 Bearer 钥匙（WRITE_GATE_KEY，
/// 不复用聊天 API 钥匙、不走 Dashboard cookie 通道），
/// 接口形态见 OneDayCore/WriteApprovalModels.swift 文件头。
protocol WriteGateClientProtocol: Sendable {
    func gateStatus(config: ServerConfig) async throws -> WriteGateStatus
    func pendingList(config: ServerConfig) async throws -> WriteGatePendingList
    func detail(
        config: ServerConfig, subsystem: WriteGateSubsystem, id: String
    ) async throws -> WriteGateDetail
    func approve(
        config: ServerConfig, subsystem: WriteGateSubsystem, id: String
    ) async throws -> WriteGateDecisionResponse
    func reject(
        config: ServerConfig, subsystem: WriteGateSubsystem, id: String
    ) async throws -> WriteGateDecisionResponse
    /// GET /decisions?limit=（P10 已决历史；桥自上线起
    /// 就在的现成面，P7 已用它做落定判定）
    func decisions(
        config: ServerConfig, limit: Int
    ) async throws -> [WriteGateDecisionRecord]
    /// 锚点回溯专用（§165）：与 decisions 同端点、大
    /// limit 拉取——回溯窗 30 天的带锚记录可能在日常
    /// 50 条窗口之外，口径分开声明在协议层
    func decisionsForAnchor(
        config: ServerConfig, limit: Int
    ) async throws -> [WriteGateDecisionRecord]
    /// GET /rules（0.36.21「总是允许」规则面；规则只
    /// 存桥侧，App 不落本地）
    func rules(config: ServerConfig) async throws -> [WriteGateRule]
    /// POST /rules：按（子系统，来源原值）建规则，桥
    /// 侧幂等——同键已有规则时回既有规则
    func createRule(
        config: ServerConfig, subsystem: WriteGateSubsystem,
        origin: String
    ) async throws -> WriteGateRule
    /// DELETE /rules/{id}：撤销一条规则
    func deleteRule(config: ServerConfig, id: String) async throws
}

/// URLSession 实现：Base＝<服务器>/api/write-gate（nginx
/// 单前缀转发到桥的 127.0.0.1:8643）。钥匙从 Keychain
/// 读（BridgeCredential 统一读，0.33.1：聊天同一份
/// Hermes 登录密钥，入口在服务器内部换桥钥）——
/// 读不到钥匙一律以 noKey 落「通道未接通」诚实态，
/// 不发任何请求、不冒充已接通。
final class WriteGateClient: WriteGateClientProtocol, @unchecked Sendable {
    private let session: URLSession
    private let decoder = JSONDecoder()

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        session = URLSession(configuration: configuration)
    }

    private var bridgeKey: String? {
        BridgeCredential.read()
    }

    func gateStatus(config: ServerConfig) async throws -> WriteGateStatus {
        try await get(config: config, path: "/status", endpoint: L10n.string("审批状态"))
    }

    func pendingList(config: ServerConfig) async throws -> WriteGatePendingList {
        try await get(config: config, path: "/pending", endpoint: L10n.string("待批列表"))
    }

    func detail(
        config: ServerConfig, subsystem: WriteGateSubsystem, id: String
    ) async throws -> WriteGateDetail {
        guard let segment = subsystem.pathSegment else {
            throw WriteGateError.failed(L10n.string("这类审批 App 里还处理不了，请在 Hermes 网页端处理。"))
        }
        return try await get(
            config: config, path: "/pending/\(segment)/\(id)",
            endpoint: L10n.string("待批详情"), isDetail: true
        )
    }

    func approve(
        config: ServerConfig, subsystem: WriteGateSubsystem, id: String
    ) async throws -> WriteGateDecisionResponse {
        try await decide(config: config, subsystem: subsystem, id: id, action: "approve")
    }

    func reject(
        config: ServerConfig, subsystem: WriteGateSubsystem, id: String
    ) async throws -> WriteGateDecisionResponse {
        try await decide(config: config, subsystem: subsystem, id: id, action: "reject")
    }

    func decisions(
        config: ServerConfig, limit: Int
    ) async throws -> [WriteGateDecisionRecord] {
        let response: WriteGateDecisionsResponse = try await get(
            config: config, path: "/decisions?limit=\(limit)",
            endpoint: L10n.string("已决记录")
        )
        return response.decisions
    }

    /// 锚点回溯专用（§165）：decisions 桥侧按新近序返回
    /// 且 8646 读面只取最近一页——50 条窗口外的带锚已
    /// 决记录（回溯窗 30 天）会被日常历史刷新漏掉，故
    /// 锚点物化单独走大 limit 拉取，不动日常历史的 50
    /// 条口径（枢纽历史呈现与角标对账都不受影响）
    func decisionsForAnchor(
        config: ServerConfig, limit: Int
    ) async throws -> [WriteGateDecisionRecord] {
        let response: WriteGateDecisionsResponse = try await get(
            config: config, path: "/decisions?limit=\(limit)",
            endpoint: L10n.string("已决记录")
        )
        return response.decisions
    }

    func rules(config: ServerConfig) async throws -> [WriteGateRule] {
        let response: WriteGateRulesResponse = try await get(
            config: config, path: "/rules", endpoint: L10n.string("审批规则")
        )
        return response.rules
    }

    func createRule(
        config: ServerConfig, subsystem: WriteGateSubsystem,
        origin: String
    ) async throws -> WriteGateRule {
        guard let segment = subsystem.pathSegment else {
            throw WriteGateError.failed(L10n.string("这类审批 App 里还处理不了，请在 Hermes 网页端处理。"))
        }
        let body = try JSONSerialization.data(
            withJSONObject: ["subsystem": segment, "origin": origin]
        )
        var request = try makeRequest(
            config: config, path: "/rules", method: "POST"
        )
        request.httpBody = body
        request.setValue(
            "application/json", forHTTPHeaderField: "Content-Type"
        )
        let (data, http) = try await send(request, endpoint: L10n.string("建立规则"))
        switch http.statusCode {
        case 200...299:
            do {
                return try decoder.decode(
                    WriteGateRuleResponse.self, from: data
                ).rule
            } catch {
                throw WriteGateError.failed(L10n.string("建立规则回执格式无法识别"))
            }
        case 401:
            throw WriteGateError.unauthorized
        case 404, 501:
            throw WriteGateError.bridgeMissing
        case 409:
            throw WriteGateError.conflict
        default:
            throw WriteGateError.failed(L10n.format("建立规则返回 %@", String(http.statusCode)))
        }
    }

    func deleteRule(config: ServerConfig, id: String) async throws {
        let request = try makeRequest(
            config: config, path: "/rules/\(id)", method: "DELETE"
        )
        let (_, http) = try await send(request, endpoint: L10n.string("撤销规则"))
        switch http.statusCode {
        case 200...299:
            return
        case 401:
            throw WriteGateError.unauthorized
        case 404:
            // 规则已不在（可能已在别处撤销）：按「撤销
            // 未生效」如实上报，调用方保留列表并提示，
            // 不许假装撤成
            throw WriteGateError.failed(L10n.string("这条规则已不存在，可能已被撤销。"))
        case 501:
            throw WriteGateError.bridgeMissing
        default:
            throw WriteGateError.failed(L10n.format("撤销规则返回 %@", String(http.statusCode)))
        }
    }

    // MARK: - 请求底座

    private func makeRequest(
        config: ServerConfig, path: String, method: String
    ) throws -> URLRequest {
        guard let key = bridgeKey, !key.isEmpty else {
            throw WriteGateError.noKey
        }
        var request = URLRequest(url: config.endpoint("/api/write-gate" + path))
        request.httpMethod = method
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func get<T: Decodable>(
        config: ServerConfig, path: String, endpoint: String,
        isDetail: Bool = false
    ) async throws -> T {
        let request = try makeRequest(config: config, path: path, method: "GET")
        let (data, http) = try await send(request, endpoint: endpoint)
        switch http.statusCode {
        case 200:
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw WriteGateError.failed(L10n.format("%@返回格式无法识别", endpoint))
            }
        case 401:
            throw WriteGateError.unauthorized
        case 404, 501:
            // status/pending 上的 404＝桥不存在；detail 上
            // 的 404＝这条记录已不在了
            throw isDetail ? WriteGateError.recordGone : WriteGateError.bridgeMissing
        case 409:
            throw WriteGateError.conflict
        default:
            throw WriteGateError.failed(L10n.format("%@返回 %@", endpoint, String(http.statusCode)))
        }
    }

    private func decide(
        config: ServerConfig, subsystem: WriteGateSubsystem,
        id: String, action: String
    ) async throws -> WriteGateDecisionResponse {
        guard let segment = subsystem.pathSegment else {
            throw WriteGateError.failed(L10n.string("这类审批 App 里还处理不了，请在 Hermes 网页端处理。"))
        }
        let request = try makeRequest(
            config: config,
            path: "/pending/\(segment)/\(id)/\(action)",
            method: "POST"
        )
        let (data, http) = try await send(request, endpoint: L10n.string("审批裁决"))
        switch http.statusCode {
        case 200...299:
            do {
                return try decoder.decode(
                    WriteGateDecisionResponse.self, from: data
                )
            } catch {
                throw WriteGateError.failed(L10n.string("裁决回执格式无法识别"))
            }
        case 401:
            throw WriteGateError.unauthorized
        case 404:
            throw WriteGateError.recordGone
        case 409:
            throw WriteGateError.conflict
        default:
            throw WriteGateError.failed(L10n.format("裁决返回 %@", String(http.statusCode)))
        }
    }

    private func send(
        _ request: URLRequest, endpoint: String
    ) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw WriteGateError.failed(L10n.format("%@无响应", endpoint))
            }
            return (data, http)
        } catch let error as WriteGateError {
            throw error
        } catch {
            throw WriteGateError.failed(L10n.format("%@网络不可达", endpoint))
        }
    }
}

/// 演示模式的桥桩：闸门开启＋两条合成待批（内存里可批
/// 可驳，批完即消失）。只用合成文案，不放真实记忆/技能
/// 内容（数据设计 §5.7：pending 正文不进 Demo 真数据）。
final class DemoWriteGateClient: WriteGateClientProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var demoRules: [WriteGateRule] = []
    private var records: [WriteGateRecord]
    /// 演示已决历史（P10）：一条合成旧记录打底，演示中
    /// 的裁决实时追加到最前——与真实桥「裁决即落账」
    /// 同语义；内容全合成、不放真实记录
    private var decidedRecords: [WriteGateDecisionRecord]

    init() {
        decidedRecords = [
            WriteGateDecisionRecord(
                id: "demo-decided-1", subsystem: .memory, action: "append",
                summary: "把上周的服务器巡检结论写入长期记忆",
                origin: "background_review", decision: "approved",
                decidedAt: Date().addingTimeInterval(-2 * 3600)
            ),
        ]
        records = [
            WriteGateRecord(
                id: "demo-mem-1", subsystem: .memory, action: "append",
                summary: "把一条新的服务器巡检结论写入长期记忆",
                origin: "background_review",
                createdAt: Date().addingTimeInterval(-32 * 60)
            ),
            WriteGateRecord(
                id: "demo-skill-1", subsystem: .skills, action: "edit",
                summary: "修订技能《节点巡检》的异常判定口径",
                origin: "chat",
                createdAt: Date().addingTimeInterval(-5 * 60)
            ),
        ]
    }

    func gateStatus(config: ServerConfig) async throws -> WriteGateStatus {
        lock.withLock {
            WriteGateStatus(
                supported: true,
                memoryGateEnabled: true, skillsGateEnabled: true,
                memoryCount: records.filter { $0.subsystem == .memory }.count,
                skillsCount: records.filter { $0.subsystem == .skills }.count
            )
        }
    }

    func pendingList(config: ServerConfig) async throws -> WriteGatePendingList {
        lock.withLock {
            WriteGatePendingList(records: records, supported: true)
        }
    }

    func detail(
        config: ServerConfig, subsystem: WriteGateSubsystem, id: String
    ) async throws -> WriteGateDetail {
        let record = lock.withLock { records.first { $0.id == id } }
        guard let record else { throw WriteGateError.recordGone }
        let review = WriteGateReview(
            subsystem: record.subsystem,
            targetLabel: record.subsystem == .skills ? "SKILL.md" : "memory",
            language: record.subsystem == .skills ? "markdown" : "json",
            current: record.subsystem == .skills ? "# 节点巡检\n旧口径：延迟超过 2 秒即异常。" : "",
            proposed: record.subsystem == .skills
                ? "# 节点巡检\n新口径：延迟超过 2 秒先复测一次，两次都超时才记异常。"
                : "{\"target\": \"memory\", \"action\": \"append\"}",
            diff: record.subsystem == .skills
                ? "@@ 节点巡检 @@\n-旧口径：延迟超过 2 秒即异常。\n+新口径：延迟超过 2 秒先复测一次，两次都超时才记异常。"
                : "{\"target\": \"memory\", \"action\": \"append\"}",
            requestedOldString: nil,
            notes: []
        )
        return WriteGateDetail(record: record, review: review)
    }

    func approve(
        config: ServerConfig, subsystem: WriteGateSubsystem, id: String
    ) async throws -> WriteGateDecisionResponse {
        try decide(id: id, decision: "approved")
    }

    func reject(
        config: ServerConfig, subsystem: WriteGateSubsystem, id: String
    ) async throws -> WriteGateDecisionResponse {
        try decide(id: id, decision: "rejected")
    }

    func decisions(
        config: ServerConfig, limit: Int
    ) async throws -> [WriteGateDecisionRecord] {
        lock.withLock { Array(decidedRecords.prefix(limit)) }
    }

    /// 演示锚点回溯（§165）：与演示 decisions 同源同
    /// 语义，演示数据无 anchor 字段——回溯恒空锚，行
    /// 为与未升级桥一致
    func decisionsForAnchor(
        config: ServerConfig, limit: Int
    ) async throws -> [WriteGateDecisionRecord] {
        try await decisions(config: config, limit: limit)
    }

    // 演示规则面（0.36.21）：内存规则表，与真实桥同
    // 语义（同键幂等、撤销即消失）；内容全合成
    func rules(config: ServerConfig) async throws -> [WriteGateRule] {
        lock.withLock { demoRules }
    }

    func createRule(
        config: ServerConfig, subsystem: WriteGateSubsystem,
        origin: String
    ) async throws -> WriteGateRule {
        lock.withLock {
            if let existing = demoRules.first(where: {
                $0.subsystem == subsystem && $0.origin == origin
            }) {
                return existing
            }
            let rule = WriteGateRule(
                id: "demo-rule-\(demoRules.count + 1)",
                subsystem: subsystem, origin: origin,
                createdAt: Date()
            )
            demoRules.append(rule)
            return rule
        }
    }

    func deleteRule(config: ServerConfig, id: String) async throws {
        try lock.withLock {
            guard demoRules.contains(where: { $0.id == id }) else {
                throw WriteGateError.failed("这条规则已不存在，可能已被撤销。")
            }
            demoRules.removeAll { $0.id == id }
        }
    }

    private func decide(
        id: String, decision: String
    ) throws -> WriteGateDecisionResponse {
        try lock.withLock {
            guard let record = records.first(where: { $0.id == id }) else {
                throw WriteGateError.recordGone
            }
            records.removeAll { $0.id == id }
            decidedRecords.insert(
                WriteGateDecisionRecord(
                    id: record.id, subsystem: record.subsystem,
                    action: record.action, summary: record.summary,
                    origin: record.origin, decision: decision,
                    decidedAt: Date()
                ),
                at: 0
            )
            return WriteGateDecisionResponse(
                success: true, output: "", decision: decision
            )
        }
    }
}
