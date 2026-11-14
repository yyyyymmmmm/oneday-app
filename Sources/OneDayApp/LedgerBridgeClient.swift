import Foundation
import OneDayCore

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
