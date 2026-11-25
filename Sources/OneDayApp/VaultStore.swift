import Foundation
import SwiftUI
import OneDayCore

@MainActor
@Observable
final class VaultStore {
    private(set) var entries: [VaultEntryMeta] = []
    private(set) var loading = false
    private(set) var loadError: String?

    private let client = VaultBridgeClient()

    var isAvailable: Bool {
        guard let capabilities = AppState.shared.capabilities else {
            return false
        }
        return capabilities.credentialVaultSupported == true
    }

    func refresh(appState: AppState) async {
        guard !loading else { return }
        guard appState.phase == .connected, let config = appState.config else {
            entries = []
            return
        }
        guard isAvailable else {
            entries = []
            return
        }
        if appState.isDemo {
            entries = []
            return
        }

        loading = true
        loadError = nil
        defer { loading = false }

        do {
            entries = try await client.listEntries(config: config)
        } catch let error as VaultBridgeError {
            switch error {
            case .noKey, .unauthorized:
                loadError = L10n.string("凭据库未连接")
            case .failed(let message):
                loadError = message
            }
        } catch {
            loadError = L10n.string("凭据库加载失败")
        }
    }

    func getEntry(appState: AppState, id: String) async throws -> VaultEntryMeta {
        guard let config = appState.config else {
            throw VaultBridgeError.failed(L10n.string("未连接服务器"))
        }
        return try await client.getEntry(config: config, id: id)
    }

    func createEntry(
        appState: AppState,
        name: String,
        service: String,
        domains: [String],
        values: [String: String],
        username: String?
    ) async throws -> VaultEntryWriteResponse {
        guard let config = appState.config else {
            throw VaultBridgeError.failed(L10n.string("未连接服务器"))
        }
        let response = try await client.createEntry(
            config: config,
            name: name,
            service: service,
            domains: domains,
            values: values,
            username: username
        )
        await refresh(appState: appState)
        return response
    }

    func replaceEntry(
        appState: AppState,
        id: String,
        name: String,
        service: String,
        domains: [String],
        values: [String: String],
        username: String?
    ) async throws -> VaultEntryWriteResponse {
        guard let config = appState.config else {
            throw VaultBridgeError.failed(L10n.string("未连接服务器"))
        }
        let response = try await client.replaceEntry(
            config: config,
            id: id,
            name: name,
            service: service,
            domains: domains,
            values: values,
            username: username
        )
        await refresh(appState: appState)
        return response
    }

    func revokeEntry(appState: AppState, id: String) async throws {
        guard let config = appState.config else {
            throw VaultBridgeError.failed(L10n.string("未连接服务器"))
        }
        _ = try await client.revokeEntry(config: config, id: id)
        await refresh(appState: appState)
    }

    func listRequests(appState: AppState) async throws -> [VaultRequestMeta] {
        guard let config = appState.config else {
            throw VaultBridgeError.failed(L10n.string("未连接服务器"))
        }
        return try await client.listRequests(config: config)
    }

    func getRequestStatus(appState: AppState, requestId: String) async throws -> VaultRequestStatus {
        guard let config = appState.config else {
            throw VaultBridgeError.failed(L10n.string("未连接服务器"))
        }
        return try await client.getRequestStatus(config: config, requestId: requestId)
    }

    func fulfillRequest(
        appState: AppState,
        requestId: String,
        decision: String,
        values: [String: String]?,
        username: String?
    ) async throws -> VaultRequestFulfillResponse {
        guard let config = appState.config else {
            throw VaultBridgeError.failed(L10n.string("未连接服务器"))
        }
        return try await client.fulfillRequest(
            config: config,
            requestId: requestId,
            decision: decision,
            values: values,
            username: username
        )
    }
}

final class VaultAlwaysAskPreferences: @unchecked Sendable {
    static let shared = VaultAlwaysAskPreferences()

    private let defaults = UserDefaults.standard
    private let key = "vault_always_ask_entries"

    private init() {}

    func isAlwaysAsk(entryId: String) -> Bool {
        let stored = defaults.stringArray(forKey: key) ?? []
        return stored.contains(entryId)
    }

    func setAlwaysAsk(entryId: String, enabled: Bool) {
        var stored = defaults.stringArray(forKey: key) ?? []
        if enabled {
            if !stored.contains(entryId) {
                stored.append(entryId)
            }
        } else {
            stored.removeAll { $0 == entryId }
        }
        defaults.set(stored, forKey: key)
    }
}
