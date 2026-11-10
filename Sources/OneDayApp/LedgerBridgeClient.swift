import Foundation
import OneDayCore

/// 伴生探测结果（/api/companion/info）：台账未上线
/// 时的旁证——探测只用来把「还没上线」说得更准，
/// 读不到不臆断版本。台账是否上线以 /ledger 读面
/// 本身为准（旧伴生无此面、集合 404），探测是补充
/// 不是判据
enum CompanionProbe: Sendable {
    /// 读到信息面：带版本与模块状态
    case detected(CompanionInfo)
    /// 404：信息面不存在（旧伴生或 front 未部署此面）
    case missing
    /// 面在但 App 的钥读不到（面板口要面板会话）：
    /// 只知「有伴生面」，版本不确认
    case unreadable(Int)
    /// 网络不可达／无钥匙：什么都确认不了
    case unreachable
}

/// 工作台账客户端：读面挂 oneday 模块（/api/oneday-
/// bridge/ledger*），与 OneDayBridgeClient 同构（同
/// 底座、同错误口径 OneDayBridgeError、同单钥来源
/// BridgeCredential）。集合端点 404＝台账未上线
/// （bridgeMissing），条目端点 404＝记录已不在
/// （recordGone），与既有桥面分法一致
final class LedgerBridgeClient: @unchecked Sendable {
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        session = URLSession(configuration: configuration)
    }

    private var bridgeKey: String? {
        BridgeCredential.read()
    }

    // MARK: - 台账读面

    /// GET /ledger：since 为 nil 拉全量、非 nil 只拉
    /// 该序之后的变更条目（回执同形，snapshotSeq 为
    /// 当前账序）
    func list(
        config: ServerConfig, since: Int?
    ) async throws -> LedgerListResponse {
        var path = "/ledger"
        if let since {
            path += "?since=\(since)"
        }
        return try await get(
            config: config, path: path, endpoint: "台账列表",
            collection: true
        )
    }

    /// GET /ledger/summary：计数＋降级位＋采集器心跳
    /// （列表回执的 counts 不带 degraded，降级露面靠
    /// 本面补）
    func summary(
        config: ServerConfig
    ) async throws -> LedgerSummary {
        try await get(
            config: config, path: "/ledger/summary",
            endpoint: "台账计数", collection: true
        )
    }

    /// GET /ledger/{id}：条目详情（带 history 全流水）；
    /// 条目端点 404＝记录已不在（recordGone）
    func detail(
        config: ServerConfig, id: String
    ) async throws -> LedgerItem {
        try await get(
            config: config, path: "/ledger/\(id)",
            endpoint: "台账详情", collection: false
        )
    }

    /// POST /ledger/report：App 主通道上报（开始／心
    /// 跳／终态，规格 §2.1）；回执取 seq。本包先落客
    /// 户端契约，聊天发送链的挂点接线由主线在合并时
    /// 决定（采集器兜底通道不依赖它先行成立）
    func report(
        config: ServerConfig, body: LedgerReportRequest
    ) async throws -> Int {
        let response: LedgerReportResponse = try await send(
            config: config, path: "/ledger/report", method: "POST",
            body: body, endpoint: "台账上报", collection: false
        )
        return response.seq
    }

    private struct LedgerReportResponse: Decodable {
        let seq: Int
    }

    // MARK: - 伴生探测

    /// GET /api/companion/info（服务器根下、front 面）：
    /// 不抛错——任何失败都是一种探测结果，调用方据此
    /// 组织「还没上线」的说明文案
    func probeCompanion(
        config: ServerConfig
    ) async -> CompanionProbe {
        guard let key = bridgeKey, !key.isEmpty else {
            return .unreachable
        }
        var request = URLRequest(
            url: config.endpoint("/api/companion/info")
        )
        request.httpMethod = "GET"
        request.setValue(
            "Bearer \(key)", forHTTPHeaderField: "Authorization"
        )
        request.timeoutInterval = 10
        do {
            let (data, response) = try await session.data(
                for: request
            )
            guard let http = response as? HTTPURLResponse else {
                return .unreachable
            }
            switch http.statusCode {
            case 200:
                if let info = try? decoder.decode(
                    CompanionInfo.self, from: data
                ) {
                    return .detected(info)
                }
                return .unreadable(200)
            case 404:
                return .missing
            default:
                return .unreadable(http.statusCode)
            }
        } catch {
            return .unreachable
        }
    }

    // MARK: - 请求底座（与 OneDayBridgeClient 同口径）

    private func makeRequest(
        config: ServerConfig, path: String, method: String
    ) throws -> URLRequest {
        guard let key = bridgeKey, !key.isEmpty else {
            throw OneDayBridgeError.noKey
        }
        var request = URLRequest(
            url: config.endpoint("/api/oneday-bridge" + path)
        )
        request.httpMethod = method
        request.setValue(
            "Bearer \(key)", forHTTPHeaderField: "Authorization"
        )
        return request
    }

    private func get<T: Decodable>(
        config: ServerConfig, path: String, endpoint: String,
        collection: Bool
    ) async throws -> T {
        let request = try makeRequest(
            config: config, path: path, method: "GET"
        )
        let (data, http) = try await send(request, endpoint: endpoint)
        try checkStatus(
            http, data: data, endpoint: endpoint,
            collection: collection
        )
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw OneDayBridgeError.failed("\(endpoint)返回格式无法识别")
        }
    }

    private func send<Body: Encodable, T: Decodable>(
        config: ServerConfig, path: String, method: String,
        body: Body, endpoint: String, collection: Bool
    ) async throws -> T {
        var request = try makeRequest(
            config: config, path: path, method: method
        )
        do {
            request.httpBody = try encoder.encode(body)
        } catch {
            throw OneDayBridgeError.failed("\(endpoint)请求组装失败")
        }
        request.setValue(
            "application/json", forHTTPHeaderField: "Content-Type"
        )
        let (data, http) = try await send(request, endpoint: endpoint)
        try checkStatus(
            http, data: data, endpoint: endpoint,
            collection: collection
        )
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw OneDayBridgeError.failed("\(endpoint)回执格式无法识别")
        }
    }

    private struct BridgeErrorBody: Decodable {
        let error: String
    }

    private func checkStatus(
        _ http: HTTPURLResponse, data: Data,
        endpoint: String, collection: Bool
    ) throws {
        switch http.statusCode {
        case 200...299:
            return
        case 401:
            throw OneDayBridgeError.unauthorized
        case 404:
            throw collection
                ? OneDayBridgeError.bridgeMissing
                : OneDayBridgeError.recordGone
        default:
            if let body = try? decoder.decode(
                BridgeErrorBody.self, from: data
            ), !body.error.isEmpty {
                throw OneDayBridgeError.failed(body.error)
            }
            throw OneDayBridgeError.failed(
                "\(endpoint)返回 \(http.statusCode)"
            )
        }
    }

    private func send(
        _ request: URLRequest, endpoint: String
    ) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw OneDayBridgeError.failed("\(endpoint)无响应")
            }
            return (data, http)
        } catch let error as OneDayBridgeError {
            throw error
        } catch {
            throw OneDayBridgeError.failed("\(endpoint)网络不可达")
        }
    }
}
