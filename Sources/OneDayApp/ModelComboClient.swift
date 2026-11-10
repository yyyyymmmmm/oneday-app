import Foundation
import OneDayCore

/// 模型组合客户端（0.37.0）：组合定义存 oneday 桥
/// meta 区（GET/PUT /meta/model-combos，与 /meta/brief
/// 整体存取同构；设计 §5.3 定版落点——服务端为真源，
/// App 本地不留第二份）。桥面未上线时集合 GET 404 →
/// bridgeMissing，UI 如实露「还没开通」，不拿本地假
/// 数据顶（台账 App 半同纪律）。
final class ModelComboClient: @unchecked Sendable {
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        session = URLSession(configuration: configuration)
    }

    private var bridgeKey: String? { BridgeCredential.read() }

    func loadDocument(
        config: ServerConfig
    ) async throws -> ModelComboDocument {
        try await get(
            config: config, path: "/meta/model-combos",
            endpoint: L10n.string("组合清单")
        )
    }

    /// 整体写回（组合的增删改与激活标记都走这一口，
    /// 与 brief 的 PUT 整体存取一致）
    func saveDocument(
        config: ServerConfig, document: ModelComboDocument
    ) async throws {
        let _: ModelComboDocument = try await send(
            config: config, path: "/meta/model-combos",
            method: "PUT", body: document, endpoint: L10n.string("保存组合")
        )
    }

    // MARK: - 请求底座（/api/oneday-bridge 前缀，与
    // LedgerBridgeClient 同口径）

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
        config: ServerConfig, path: String, endpoint: String
    ) async throws -> T {
        let request = try makeRequest(config: config, path: path, method: "GET")
        let (data, http) = try await send(request, endpoint: endpoint)
        try checkStatus(http, data: data, endpoint: endpoint, collection: true)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw OneDayBridgeError.failed(L10n.format("%@返回格式无法识别", endpoint))
        }
    }

    private func send<Body: Encodable, T: Decodable>(
        config: ServerConfig, path: String, method: String,
        body: Body, endpoint: String
    ) async throws -> T {
        var request = try makeRequest(config: config, path: path, method: method)
        do {
            request.httpBody = try encoder.encode(body)
        } catch {
            throw OneDayBridgeError.failed(L10n.format("%@请求组装失败", endpoint))
        }
        request.setValue(
            "application/json", forHTTPHeaderField: "Content-Type"
        )
        let (data, http) = try await send(request, endpoint: endpoint)
        try checkStatus(http, data: data, endpoint: endpoint, collection: true)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw OneDayBridgeError.failed(L10n.format("%@回执格式无法识别", endpoint))
        }
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
            throw OneDayBridgeError.failed(
                L10n.format("%@返回 %@", endpoint, String(http.statusCode))
            )
        }
    }

    private func send(
        _ request: URLRequest, endpoint: String
    ) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw OneDayBridgeError.failed(L10n.format("%@无响应", endpoint))
            }
            return (data, http)
        } catch let error as OneDayBridgeError {
            throw error
        } catch {
            throw OneDayBridgeError.failed(L10n.format("%@网络不可达", endpoint))
        }
    }
}
