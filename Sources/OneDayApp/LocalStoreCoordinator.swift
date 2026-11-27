import Foundation
import OneDayCore

// MARK: - 本地单一真源协调器（#38 SSOT Facade）

/// 收口客户端本地持久化边界：
/// - 凭据与票据：`KeychainStore`（已迁至 KeychainAccess）
/// - 会话账本与旁聊态：`SessionLedger` / `SideChatStore`
/// - 在途任务与发件箱：`RunLedgerStore` / `OutboxRetryStore`
/// - 强类型本地偏好：`AppPreferences`
/// 视图层与 AppState 通过单一入口协调状态与清理生命周期，消除多头散落写入。
@MainActor
final class LocalStoreCoordinator {
    let sessionLedger: SessionLedger
    let sideChats: SideChatStore
    let runLedger: RunLedgerStore
    let outboxRetry: OutboxRetryStore
    let isPersisted: Bool

    init(
        sessionLedger: SessionLedger,
        sideChats: SideChatStore,
        runLedger: RunLedgerStore,
        outboxRetry: OutboxRetryStore,
        isPersisted: Bool
    ) {
        self.sessionLedger = sessionLedger
        self.sideChats = sideChats
        self.runLedger = runLedger
        self.outboxRetry = outboxRetry
        self.isPersisted = isPersisted
    }

    /// 凭据快照读取（供启动恢复使用）
    func restoredServerBaseURL() -> String? {
        guard isPersisted else { return nil }
        return KeychainStore.read(account: CredentialKey.baseURL)
    }

    func hasAPIKey() -> Bool {
        guard isPersisted else { return false }
        return KeychainStore.read(account: CredentialKey.apiKey) != nil
    }

    func clearCredentials() {
        guard isPersisted else { return }
        KeychainStore.clearAll()
    }
}
