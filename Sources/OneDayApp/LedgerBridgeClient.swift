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
    /// C-10 收敛：与 OneDayBridgeClient 同基座同口径
    private let base = BridgeClientBase<OneDayBridgeError>(
        pathPrefix: "/api/oneday-bridge", timeout: 15,
        noKey: .noKey, failed: OneDayBridgeError.failed
    )

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
            config: config, path: path, endpoint: L10n.string("台账列表"),
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
            endpoint: L10n.string("台账计数"), collection: true
        )
    }

    /// GET /ledger/{id}：条目详情（带 history 全流水）；
    /// 条目端点 404＝记录已不在（recordGone）
    func detail(
        config: ServerConfig, id: String
    ) async throws -> LedgerItem {
        try await get(
            config: config, path: "/ledger/\(id)",
            endpoint: L10n.string("台账详情"), collection: false
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
            body: body, endpoint: L10n.string("台账上报"), collection: false
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
        let request: URLRequest
        do {
            var made = try base.makeRequest(
                config: config, fullPath: "/api/companion/info",
                method: "GET"
            )
            made.timeoutInterval = 10
            request = made
        } catch {
            return .unreachable
        }
        do {
            let (data, http) = try await base.performRaw(request)
            switch http.statusCode {
            case 200:
                if let info = try? base.decoder.decode(
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

    // MARK: - 请求底座（基座代行，本类只给状态口径）

    private func get<T: Decodable>(
        config: ServerConfig, path: String, endpoint: String,
        collection: Bool
    ) async throws -> T {
        try await base.get(
            config: config, path: path, endpoint: endpoint
        ) { http, data in
            try self.base.checkStatus(
                http, data: data, endpoint: endpoint,
                collection: collection
            )
        }
    }

    private func send<Body: Encodable, T: Decodable>(
        config: ServerConfig, path: String, method: String,
        body: Body, endpoint: String, collection: Bool
    ) async throws -> T {
        try await base.send(
            config: config, path: path, method: method,
            body: body, endpoint: endpoint
        ) { http, data in
            try self.base.checkStatus(
                http, data: data, endpoint: endpoint,
                collection: collection
            )
        }
    }
}
