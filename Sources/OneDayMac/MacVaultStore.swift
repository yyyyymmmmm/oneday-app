import Foundation
import Observation
import OneDayCore

/// 凭据库状态店（棒 2，对位 #71/#20）：条目元数据
/// 与凭据请求两面。能力门与 iOS 同口径——能力协商
/// features.credential_vault 未广告即按不可用（列
/// 表保持空、不冒充有数据）。值纪律：条目值只在创
/// 建/替换/兑现的表单里短暂存在、直送服务端，本店
/// 不持有、不缓存任何条目值。
@MainActor
@Observable
final class MacVaultStore {
    private(set) var entries: [MacVaultEntry] = []
    private(set) var requests: [MacVaultRequest] = []
    private(set) var loading = false
    private(set) var loaded = false
    var loadError: String?
    var actionNote: String?

    /// 服务端是否广告了凭据库能力（未读到能力信息
    /// 时按未启用呈现，不猜）
    func isSupported(session: SessionStore) -> Bool {
        session.capabilities?.credentialVaultSupported == true
    }

    var pendingRequests: [MacVaultRequest] {
        requests.filter { $0.isPending }
    }

    func refresh(session: SessionStore) async {
        guard !loading else { return }
        guard session.isConnected, let config = session.config,
              let key = session.apiKey else {
            entries = []
            requests = []
            return
        }
        guard isSupported(session: session) else {
            entries = []
            requests = []
            loaded = true
            return
        }
        loading = true
        loadError = nil
        defer { loading = false }
        do {
            entries = try await session.chatClient.vaultEntries(
                config: config, apiKey: key
            )
        } catch let error as HermesError {
            loadError = error.userMessage
        } catch {
            loadError = "凭据库加载失败"
        }
        if let fetched = try? await session.chatClient.vaultRequests(
            config: config, apiKey: key
        ) {
            requests = fetched
        }
        loaded = true
    }

    /// 按号取请求最新状态（聊天内嵌卡用：列表里没有
    /// 时单查；404 等失败原样上抛，卡面落回纯文本）
    func requestStatus(
        session: SessionStore, requestID: String
    ) async throws -> MacVaultRequestStatus {
        guard let config = session.config, let key = session.apiKey
        else {
            throw HermesError.apiKeyRejected
        }
        return try await session.chatClient.vaultRequestStatus(
            config: config, apiKey: key, requestID: requestID
        )
    }

    /// 列表内按号查请求（聊天卡先查本地已拉清单）
    func request(id: String) -> MacVaultRequest? {
        requests.first { $0.id == id }
    }

    // MARK: - 条目写口（成败后回读清单，不认回执自报）

    func createEntry(
        session: SessionStore, request: MacVaultWriteRequest
    ) async -> Bool {
        guard let config = session.config, let key = session.apiKey
        else { return false }
        do {
            _ = try await session.chatClient.createVaultEntry(
                config: config, apiKey: key, request: request
            )
            actionNote = nil
            await refresh(session: session)
            return true
        } catch let error as HermesError {
            actionNote = error.userMessage
        } catch {
            actionNote = "保存没能生效，请稍后再试。"
        }
        return false
    }

    func replaceEntry(
        session: SessionStore, id: String,
        request: MacVaultWriteRequest
    ) async -> Bool {
        guard let config = session.config, let key = session.apiKey
        else { return false }
        do {
            _ = try await session.chatClient.replaceVaultEntry(
                config: config, apiKey: key, id: id, request: request
            )
            actionNote = nil
            await refresh(session: session)
            return true
        } catch let error as HermesError {
            actionNote = error.userMessage
        } catch {
            actionNote = "保存没能生效，请稍后再试。"
        }
        return false
    }

    func revokeEntry(
        session: SessionStore, id: String
    ) async -> Bool {
        guard let config = session.config, let key = session.apiKey
        else { return false }
        do {
            try await session.chatClient.revokeVaultEntry(
                config: config, apiKey: key, id: id
            )
            actionNote = nil
            await refresh(session: session)
            return true
        } catch let error as HermesError {
            actionNote = error.userMessage
        } catch {
            actionNote = "删除没能生效，请稍后再试。"
        }
        return false
    }

    // MARK: - 请求兑现/拒绝

    /// 兑现：decision=fulfill＋逐字段值（值只活在本
    /// 次调用里）；成败后回读请求清单对账
    func fulfillRequest(
        session: SessionStore, requestID: String,
        values: [String: String], username: String?
    ) async -> MacVaultFulfillResponse? {
        guard let config = session.config, let key = session.apiKey
        else { return nil }
        do {
            let response = try await session.chatClient
                .fulfillVaultRequest(
                    config: config, apiKey: key, requestID: requestID,
                    request: MacVaultFulfillRequest(
                        decision: "fulfill", values: values,
                        username: username
                    )
                )
            actionNote = nil
            await refresh(session: session)
            return response
        } catch let error as HermesError {
            actionNote = error.userMessage
        } catch {
            actionNote = "提交没能生效，请稍后再试。"
        }
        return nil
    }

    func rejectRequest(
        session: SessionStore, requestID: String
    ) async -> Bool {
        guard let config = session.config, let key = session.apiKey
        else { return false }
        do {
            _ = try await session.chatClient.fulfillVaultRequest(
                config: config, apiKey: key, requestID: requestID,
                request: MacVaultFulfillRequest(
                    decision: "reject", values: nil, username: nil
                )
            )
            actionNote = nil
            await refresh(session: session)
            return true
        } catch let error as HermesError {
            actionNote = error.userMessage
        } catch {
            actionNote = "拒绝没能生效，请稍后再试。"
        }
        return false
    }
}
