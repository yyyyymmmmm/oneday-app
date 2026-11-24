import Foundation
import OneDayCore
import SwiftData

/// 乐观删除协调器（§232 立、第 67 条包二降为转发
/// 壳）：删除引擎本体（队列/墓碑/后台围栏删/恢复）
/// 自包二起归 SessionLedger 持有的 SessionDeletion-
/// Engine，删除走账本单管线。本类只留旧调用面转
/// 发——各面 begin/resumePending 调用点与既有测试
/// 一字不改；AppState 接线后一律落账本引擎，未接
/// 线（独立测试装配）时落本壳自持的同型引擎（存
/// 储键与语义逐字一致）。
@MainActor
@Observable
final class SessionDeletionCoordinator {

    /// 账本本体（AppState init 接线）
    @ObservationIgnored
    weak var ledger: SessionLedger?

    /// 未接线时的自持引擎（测试装配用；生产经
    /// AppState 接线恒走账本引擎）
    @ObservationIgnored
    private let fallbackEngine: SessionDeletionEngine

    init(defaults: UserDefaults = .standard) {
        fallbackEngine = SessionDeletionEngine(
            defaults: defaults
        )
    }

    private var engine: SessionDeletionEngine {
        ledger?.deletions ?? fallbackEngine
    }

    /// 待删队列本体（转发账本引擎）
    var queue: PendingSessionDeletionQueue {
        engine.queue
    }

    /// 恢复信号代号（转发账本引擎；消费面见引擎注）
    var restoreRevision: Int {
        engine.restoreRevision
    }

    /// 服务端删除执行口（转发账本引擎注入口）
    var deleteAction: (AppState, String) async
        -> ServerSessionActions.Outcome {
        get { engine.deleteAction }
        set { engine.deleteAction = newValue }
    }

    /// 目录恢复重拉口（转发账本引擎注入口）
    var catalogRefresher: (AppState) async
        -> [ServerSession]? {
        get { engine.catalogRefresher }
        set { engine.catalogRefresher = newValue }
    }

    func isPending(sessionID: String) -> Bool {
        engine.isPending(sessionID: sessionID)
    }

    /// 删除起手（转发账本引擎；时序口径见引擎头注）
    func begin(
        sessionID: String, title: String,
        appState: AppState, modelContext: ModelContext
    ) {
        engine.begin(
            sessionID: sessionID, title: title,
            appState: appState, modelContext: modelContext
        )
    }

    /// 启动续跑（转发账本引擎）
    func resumePending(
        appState: AppState, modelContext: ModelContext
    ) {
        engine.resumePending(
            appState: appState, modelContext: modelContext
        )
    }
}
