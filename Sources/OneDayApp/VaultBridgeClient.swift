import Foundation
import OneDayCore

/// Vault 桥错误（与其他桥同分法：无钥/钥被拒＝桥未连接，其余失败如实报）
enum VaultBridgeError: Error, Sendable, Equatable {
    case noKey
    case unauthorized
    case failed(String)
}

/// Vault 桥客户端：凭据库六个端点（list/get/create/replace/revoke/requestStatus/fulfill）
/// 路径：/v1/vault/*，Bearer 从 BridgeCredential 统一读（与全 App 桥客户端同口径）
/// C-10 收敛：连接/单钥/管线/文案走统一基座，本类只留路径、DTO 与状态口径
final class VaultBridgeClient: @unchecked Sendable {
    private let base = BridgeClientBase<VaultBridgeError>(
        pathPrefix: "/v1/vault",
        timeout: 30,
        waitsForConnectivity: true,
        noKey: .noKey,
        failed: VaultBridgeError.failed
    )

    // MARK: - Entry Management

    func listEntries(config: ServerConfig) async throws -> [VaultEntryMeta] {
        let response: VaultEntryListResponse = try await base.get(
            config: config,
            path: "/entries",
            endpoint: L10n.string("凭据库")
        ) { http, data in
            try checkStatus(http, data: data, endpoint: L10n.string("凭据库"), collection: true)
        }
        return response.data
    }

    func getEntry(config: ServerConfig, id: String) async throws -> VaultEntryMeta {
        try await base.get(
            config: config,
            path: "/entries/\(id)",
            endpoint: L10n.string("凭据条目")
        ) { http, data in
            try checkStatus(http, data: data, endpoint: L10n.string("凭据条目"), collection: false)
        }
    }

    func createEntry(
        config: ServerConfig,
        name: String,
        service: String,
        domains: [String],
        values: [String: String],
        username: String?
    ) async throws -> VaultEntryWriteResponse {
        let request = VaultEntryCreateRequest(
            name: name,
            service: service,
            domains: domains,
            values: values,
            username: username
        )
        return try await base.send(
            config: config,
            path: "/entries",
            method: "POST",
            body: request,
            endpoint: L10n.string("凭据库")
        ) { http, data in
            try checkStatus(http, data: data, endpoint: L10n.string("凭据库"), collection: true)
        }
    }

    func replaceEntry(
        config: ServerConfig,
        id: String,
        name: String,
        service: String,
        domains: [String],
        values: [String: String],
        username: String?
    ) async throws -> VaultEntryWriteResponse {
        let request = VaultEntryReplaceRequest(
            name: name,
            service: service,
            domains: domains,
            values: values,
            username: username
        )
        return try await base.send(
            config: config,
            path: "/entries/\(id)",
            method: "PUT",
            body: request,
            endpoint: L10n.string("凭据条目")
        ) { http, data in
            try checkStatus(http, data: data, endpoint: L10n.string("凭据条目"), collection: false)
        }
    }

    func revokeEntry(config: ServerConfig, id: String) async throws -> VaultEntryRevokeResponse {
        try await base.sendEmpty(
            config: config,
            path: "/entries/\(id)",
            method: "DELETE",
            endpoint: L10n.string("凭据条目")
        ) { http, data in
            try checkStatus(http, data: data, endpoint: L10n.string("凭据条目"), collection: false)
        }
    }

    // MARK: - Request Handling

    func getRequestStatus(config: ServerConfig, requestId: String) async throws -> VaultRequestStatus {
        try await base.get(
            config: config,
            path: "/requests/\(requestId)",
            endpoint: L10n.string("凭据请求")
        ) { http, data in
            try checkStatus(http, data: data, endpoint: L10n.string("凭据请求"), collection: false)
        }
    }

    func fulfillRequest(
        config: ServerConfig,
        requestId: String,
        decision: String,
        values: [String: String]?,
        username: String?
    ) async throws -> VaultRequestFulfillResponse {
        let request = VaultRequestFulfillRequest(
            decision: decision,
            values: values,
            username: username
        )
        return try await base.send(
            config: config,
            path: "/requests/\(requestId)/fulfill",
            method: "POST",
            body: request,
            endpoint: L10n.string("凭据请求")
        ) { http, data in
            try checkStatus(http, data: data, endpoint: L10n.string("凭据请求"), collection: false)
        }
    }

    // MARK: - Status Checking

    private func checkStatus(
        _ http: HTTPURLResponse,
        data: Data,
        endpoint: String,
        collection: Bool
    ) throws {
        switch http.statusCode {
        case 200...299:
            return
        case 401:
            throw VaultBridgeError.unauthorized
        case 404:
            throw collection
                ? VaultBridgeError.failed(L10n.string("凭据库功能未启用"))
                : VaultBridgeError.failed(L10n.string("凭据条目已不存在"))
        default:
            if let message = base.serverMessage(data) {
                if let safe = ServerErrorText.userSafe(message) {
                    throw VaultBridgeError.failed(safe)
                }
                ChatDiagTrace.record(
                    "Vault 桥错误原文未过安全门 [\(endpoint) \(http.statusCode)] \(message)"
                )
                throw VaultBridgeError.failed(
                    L10n.format("%@返回了无法识别的错误，请稍后再试。", endpoint)
                )
            }
            throw VaultBridgeError.failed(
                L10n.format("%@返回 %@", endpoint, String(http.statusCode))
            )
        }
    }
}
