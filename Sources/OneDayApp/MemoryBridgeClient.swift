import Foundation
import OneDayCore

/// 记忆条目桥客户端（0.13.0，P7 客户端先行）：契约
/// memory-bridge-contract-20261109.md——条目读与
/// propose 暂存是 write-gate 桥待扩展的 /memories
/// 路由组，与待批/裁决同基址（/api/write-gate）、
/// 同一 Bearer 钥匙（BridgeCredential 统一读，
/// 0.33.1：聊天同一份 Hermes 登录密钥；与 WriteGate-
/// Client 同口径）。错误口径沿 WriteGateError：
/// 无钥 noKey、钥匙被拒 unauthorized、集合 404＝
/// 路由组未部署（bridgeMissing，面上露「记忆条目
/// 尚未开通」）、条目 404＝记录已不在、409＝闸门
/// 未开或条目已变化（透服务端人话）、其余人话。
/// 本客户端只有读与「发起待批」两类请求——没有任何
/// 直写记忆的路径（契约红线）。
final class MemoryBridgeClient: @unchecked Sendable {
    /// C-10 收敛：与 WriteGateClient 同基座（同 /api/
    /// write-gate、同 WriteGateError 口径），本类只留
    /// 路径、DTO 与状态口径
    private let base = BridgeClientBase<WriteGateError>(
        pathPrefix: "/api/write-gate", timeout: 15,
        noKey: .noKey, failed: WriteGateError.failed
    )

    // MARK: - 条目读（契约端点）

    /// 条目全量：集合 404＝条目面未开通
    func entries(config: ServerConfig) async throws -> [BridgeMemoryEntry] {
        let response: BridgeMemoryEntriesResponse = try await get(
            config: config, path: "/memories", endpoint: L10n.string("记忆条目"),
            collection: true
        )
        return response.entries
    }

    /// 条目全文：条目 404＝这条已不在
    func entry(
        config: ServerConfig, id: String
    ) async throws -> BridgeMemoryEntryDetail {
        let response: BridgeMemoryDetailResponse = try await get(
            config: config, path: "/memories/\(id)",
            endpoint: L10n.string("记忆详情"), collection: false
        )
        return response.entry
    }

    // MARK: - 发起待批（唯一的写发起面）

    /// 暂存一条拟写进 write-gate：201 拿到 pendingId
    /// 才算发起成功；此后裁决走活动格审批面，本方法
    /// 不做任何落盘动作
    func propose(
        config: ServerConfig, request body: BridgeMemoryProposeRequest
    ) async throws -> BridgeMemoryProposeResponse {
        let bodyData: Data
        do {
            bodyData = try base.encoder.encode(body)
        } catch {
            throw WriteGateError.failed(L10n.string("提交内容组装失败"))
        }
        let (data, http) = try await base.perform(
            config: config, path: "/memories/propose", method: "POST",
            bodyData: bodyData, endpoint: L10n.string("提交待批")
        )
        switch http.statusCode {
        case 200...299:
            return try base.decode(
                data,
                orThrow: WriteGateError.failed(L10n.string("提交回执格式无法识别"))
            )
        case 401:
            throw WriteGateError.unauthorized
        case 404, 501:
            // 路由组未部署：与集合未开通同态
            throw WriteGateError.bridgeMissing
        case 409:
            // 闸门未开/条目已变：优先透服务端人话
            if let message = base.serverMessage(data) {
                throw WriteGateError.failed(message)
            }
            throw WriteGateError.conflict
        default:
            if let message = base.serverMessage(data) {
                throw WriteGateError.failed(message)
            }
            throw WriteGateError.failed(L10n.format("提交返回 %@", String(http.statusCode)))
        }
    }

    // MARK: - 已决记录（桥已上线现成面）

    /// 提案落定判定用：pending 消失后查裁决结果，
    /// 不从「消失」本身反推批准/驳回
    func decisions(
        config: ServerConfig, limit: Int = 100
    ) async throws -> [WriteGateDecisionRecord] {
        let response: WriteGateDecisionsResponse = try await get(
            config: config, path: "/decisions?limit=\(limit)",
            endpoint: L10n.string("已决记录"), collection: false
        )
        return response.decisions
    }

    // MARK: - 请求底座（基座代行，本类只给状态口径）

    private func get<T: Decodable>(
        config: ServerConfig, path: String, endpoint: String,
        collection: Bool
    ) async throws -> T {
        try await base.get(
            config: config, path: path, endpoint: endpoint
        ) { http, _ in
            switch http.statusCode {
            case 200:
                return
            case 401:
                throw WriteGateError.unauthorized
            case 404, 501:
                throw collection
                    ? WriteGateError.bridgeMissing
                    : WriteGateError.recordGone
            case 409:
                throw WriteGateError.conflict
            default:
                throw WriteGateError.failed(
                    L10n.format("%@返回 %@", endpoint, String(http.statusCode))
                )
            }
        }
    }
}
