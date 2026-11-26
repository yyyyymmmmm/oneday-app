import Foundation
import OneDayCore
import SwiftData

/// Phase 4.2：本地单一真源协调器（Local SSOT Coordinator）。
///
/// 收敛客户端三处本地存储的读写边界与生命周期：
/// 1. **SwiftData (`ModelContext`)**：聊天线程 (`ChatThread`) 与消息条目 (`ChatEntry`) 的结构化本地真源；
/// 2. **Keychain (`IdentityValueStore`)**：本机主线身份、设备令牌等敏感凭据真源；
/// 3. **SessionLedger**：会话名单、主线归属、已读进度与发件箱/删除协调真源。
///
/// 新业务模块统一通过本协调器访问线程快照、原子落盘与发件箱状态，避免直接散落读写 `UserDefaults` 或重复维护内存副本。
@MainActor
final class LocalStoreCoordinator {
    let modelContext: ModelContext
    let ledger: SessionLedger
    let identityStore: IdentityValueStore

    init(
        modelContext: ModelContext,
        ledger: SessionLedger,
        identityStore: IdentityValueStore = KeychainIdentityValueStore()
    ) {
        self.modelContext = modelContext
        self.ledger = ledger
        self.identityStore = identityStore
    }

    // MARK: - 线程与消息只读快照

    /// 按最近活跃时间倒序读取全部本地聊天线程（SwiftData 单一真源）。
    func fetchThreads() -> [ChatThread] {
        let descriptor = FetchDescriptor<ChatThread>(
            sortBy: [SortDescriptor(\ChatThread.updatedAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// 按 `id` 精确查找本地线程。
    func thread(id: UUID) -> ChatThread? {
        let descriptor = FetchDescriptor<ChatThread>(
            predicate: #Predicate<ChatThread> { $0.id == id }
        )
        return try? modelContext.fetch(descriptor).first
    }

    /// 读取当前本地主线线程（与 `SessionLedger.mainThreadID` 保持一致）。
    func mainThread() -> ChatThread? {
        guard let mainID = ledger.mainThreadID else { return nil }
        return thread(id: mainID)
    }

    /// 统计当前所有处于发件箱等待/发送中/失败态的消息数量，供全局角标或重试调度读取。
    func pendingOutboxCount() -> Int {
        let threads = fetchThreads()
        var total = 0
        for thread in threads {
            for entry in thread.entries {
                if entry.sendFailed {
                    total += 1
                    continue
                }
                if let state = entry.sendState {
                    switch state {
                    case .queued, .uploading, .linking, .sending:
                        total += 1
                    default:
                        break
                    }
                }
            }
        }
        return total
    }

    // MARK: - 原子落盘与一致性维护

    /// 将当前 `ModelContext` 变更原子落盘，并在失败时记录诊断日志而非静默丢失。
    @discardableResult
    func saveIfNeeded(reason: String) -> Bool {
        guard modelContext.hasChanges else { return true }
        do {
            try modelContext.save()
            return true
        } catch {
            ChatDiagTrace.record("LocalStoreCoordinator save 失败（\(reason)）：\(error.localizedDescription)")
            return false
        }
    }

    /// 令会话名单新鲜度失效并保存本地结构化变更，确保下一次刷新与 SwiftData 状态一致。
    func invalidateAndSync(reason: String) {
        _ = saveIfNeeded(reason: reason)
        ledger.invalidateListFreshness()
    }
}
