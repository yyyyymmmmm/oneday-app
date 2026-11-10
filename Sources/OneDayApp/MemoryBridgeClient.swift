import Foundation
import OneDayCore

/// 记忆条目桥客户端（0.13.0，P7 客户端先行）：契约
/// memory-bridge-contract-20261109.md——条目读与
/// propose 暂存是 write-gate 桥待扩展的 /memories
/// 路由组，与待批/裁决同基址（/api/write-gate）、
/// 同一 Bearer 钥匙（BridgeKeyStore 的 .writegate
/// 分项，0.32.1 分权 F03/R8；与 WriteGateClient 同
/// scope）。错误口径沿 WriteGateError：
/// 无钥 noKey、钥匙被拒 unauthorized、集合 404＝
/// 路由组未部署（bridgeMissing，面上露「记忆条目
/// 尚未开通」）、条目 404＝记录已不在、409＝闸门
/// 未开或条目已变化（透服务端人话）、其余人话。
/// 本客户端只有读与「发起待批」两类请求——没有任何
/// 直写记忆的路径（契约红线）。
final class MemoryBridgeClient: @unchecked Sendable {
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        session = URLSession(configuration: configuration)
    }

    private var bridgeKey: String? {
        BridgeKeyStore.read(.writegate)
    }

    // MARK: - 条目读（契约端点）

    /// 条目全量：集合 404＝条目面未开通
    func entries(config: ServerConfig) async throws -> [BridgeMemoryEntry] {
        let response: BridgeMemoryEntriesResponse = try await get(
            config: config, path: "/memories", endpoint: "记忆条目",
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
            endpoint: "记忆详情", collection: false
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
        var request = try makeRequest(
            config: config, path: "/memories/propose", method: "POST"
        )
        do {
            request.httpBody = try encoder.encode(body)
        } catch {
            throw WriteGateError.failed("提交内容组装失败")
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, http) = try await send(request, endpoint: "提交待批")
        switch http.statusCode {
        case 200...299:
            do {
                return try decoder.decode(
                    BridgeMemoryProposeResponse.self, from: data
                )
            } catch {
                throw WriteGateError.failed("提交回执格式无法识别")
            }
        case 401:
            throw WriteGateError.unauthorized
        case 404, 501:
            // 路由组未部署：与集合未开通同态
            throw WriteGateError.bridgeMissing
        case 409:
            // 闸门未开/条目已变：优先透服务端人话
            if let message = Self.serverMessage(data) {
                throw WriteGateError.failed(message)
            }
            throw WriteGateError.conflict
        default:
            if let message = Self.serverMessage(data) {
                throw WriteGateError.failed(message)
            }
            throw WriteGateError.failed("提交返回 \(http.statusCode)")
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
            endpoint: "已决记录", collection: false
        )
        return response.decisions
    }

    // MARK: - 请求底座

    private func makeRequest(
        config: ServerConfig, path: String, method: String
    ) throws -> URLRequest {
        guard let key = bridgeKey, !key.isEmpty else {
            throw WriteGateError.noKey
        }
        var request = URLRequest(
            url: config.endpoint("/api/write-gate" + path)
        )
        request.httpMethod = method
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func get<T: Decodable>(
        config: ServerConfig, path: String, endpoint: String,
        collection: Bool
    ) async throws -> T {
        let request = try makeRequest(config: config, path: path, method: "GET")
        let (data, http) = try await send(request, endpoint: endpoint)
        switch http.statusCode {
        case 200:
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw WriteGateError.failed("\(endpoint)返回格式无法识别")
            }
        case 401:
            throw WriteGateError.unauthorized
        case 404, 501:
            throw collection
                ? WriteGateError.bridgeMissing
                : WriteGateError.recordGone
        case 409:
            throw WriteGateError.conflict
        default:
            throw WriteGateError.failed("\(endpoint)返回 \(http.statusCode)")
        }
    }

    /// 桥错误体（契约口径）：失败响应统一 {"error": 人话}
    private struct BridgeErrorBody: Decodable {
        let error: String
    }

    private static func serverMessage(_ data: Data) -> String? {
        guard let body = try? JSONDecoder().decode(
            BridgeErrorBody.self, from: data
        ), !body.error.isEmpty else {
            return nil
        }
        return body.error
    }

    private func send(
        _ request: URLRequest, endpoint: String
    ) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw WriteGateError.failed("\(endpoint)无响应")
            }
            return (data, http)
        } catch let error as WriteGateError {
            throw error
        } catch {
            throw WriteGateError.failed("\(endpoint)网络不可达")
        }
    }
}
