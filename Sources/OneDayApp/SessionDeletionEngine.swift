import Foundation
import OneDayCore
import SwiftData

/// 乐观删除引擎（§232，用户 2026-11-14 亲定口
/// 径，覆盖 0.50.30「服务端先行」；第 67 条包二
/// 起归 SessionLedger 持有——删除走账本单管线，
/// SessionDeletionCoordinator 降为转发壳）：会话删除时序
/// ＝①本地先删——绑定线程打墓碑（isPendingDele-
/// tion，抽屉名单单点过滤）＋共享目录摘行，确认
/// 后同拍消失、UI 不等服务端；②服务端后台删——
/// ServerSessionActions.delete 原样（围栏 DELETE
/// 在客户端层、删后回查落定），UI 不阻塞无转圈；
/// ③落定→DeletedSessionCloseout 物理收口（删线
/// 程本体＋清侧账）；④最终失败→解墓碑＋目录重拉
/// 恢复呈现＋人话提醒（AppState.sessionDeletion-
/// FailureNotice，ChatView 提示条消费，不露接口
/// 原文）。
///
/// 待删队列落盘（UserDefaults JSON，键 session-
/// Deletions.pendingQueue，与 SideChatStore 同模
/// 式）：进程被杀/重启后 ChatView 启动任务调 re-
/// sumePending 续跑——盘上队列逐条重演隐藏并重跑
/// 后台删除，续跑失败同样恢复＋提醒。入队先于打
/// 墓碑落盘（崩溃窗口只会留下「在队未打标」，re-
/// sume 重演即补上）；另扫墓碑线程补队兜底。
@MainActor
@Observable
final class SessionDeletionEngine {

    /// 待删队列本体（落盘镜像，只经本类改）
    private(set) var queue = PendingSessionDeletionQueue()
    /// 恢复信号代号：任一条最终失败并恢复后 +1。
    /// 第 67 条包二起账本面（全部对话页/频道页）直
    /// 接读账本投影自对齐、不再监听本信号；只剩非
    /// 账本面（服务端会话页，定版分工自持名单）仍
    /// 监听后重拉（线程墓碑与账本名单由本类直接恢
    /// 复，不经此信号）
    private(set) var restoreRevision = 0
    /// 在飞执行集（begin 与 resume 并发同条去重）
    private var inFlight: Set<String> = []
    private let defaults: UserDefaults
    private static let storageKey = "sessionDeletions.pendingQueue"

    /// 服务端删除执行口（默认＝动作层真删；测试注
    /// 入替身定落定/失败，不为测试另造网络桩）
    var deleteAction: (AppState, String) async
        -> ServerSessionActions.Outcome = { appState, id in
            await ServerSessionActions.delete(
                appState: appState, id: id
            )
        }
    /// 目录恢复重拉口（默认＝账本全量拉取；测试替
    /// 身）。名单只喂显示与回行、不驱动删除，名单
    /// 不完整也照常取 sessions（B-1 防护闸只拦存
    /// 活集删除/回收，见 SessionLedger 装配核）
    var catalogRefresher: (AppState) async -> [ServerSession]? = {
        appState in
        (try? await SessionLedger.fetchAll(
            appState: appState, archived: "exclude"
        ))?.sessions
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(
               PendingSessionDeletionQueue.self, from: data
           ) {
            queue = decoded
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(queue) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    func isPending(sessionID: String) -> Bool {
        queue.contains(sessionID: sessionID)
    }

    // MARK: - 起手（同步乐观段＋后台执行）

    /// 删除起手：调用方（抽屉/行组件/管理页/频道
    /// 页）已完成二次确认。主线钦定 id 整件不动
    /// （与 DeletedSessionCloseout 同一保护）。本
    /// 函数同步返回——服务端动作全在后台，UI 不
    /// 阻塞；宿主自持的名单行由宿主在调用同拍自
    /// 行摘除（行组件 onDeleteRequested 钩子）
    func begin(
        sessionID: String, title: String,
        appState: AppState, modelContext: ModelContext
    ) {
        guard sessionID != appState.sessionLedger.mainServerSessionID
        else { return }
        if queue.enqueue(PendingSessionDeletion(
            sessionID: sessionID, title: title, enqueuedAt: Date()
        )) {
            persist()
        }
        applyHiding(
            sessionID: sessionID, appState: appState,
            modelContext: modelContext
        )
        launch(
            sessionID: sessionID, appState: appState,
            modelContext: modelContext
        )
    }

    /// 启动续跑：盘上队列逐条重演隐藏＋重跑后台删
    /// 除；先扫墓碑线程补队（入队落盘与打标之间崩
    /// 溃的残留、以及任何「有墓碑不在队」的异态都
    /// 在此收敛回队列）。已落定的条在执行里经回查
    /// 自然收口（服务端已无此条＝verified），不重
    /// 复打扰用户
    func resumePending(
        appState: AppState, modelContext: ModelContext
    ) {
        var dirty = false
        for thread in fetchThreads(modelContext)
        where thread.isPendingDeletion {
            guard let sessionID = thread.serverSessionID,
                  !sessionID.isEmpty else { continue }
            if queue.enqueue(PendingSessionDeletion(
                sessionID: sessionID, title: thread.title,
                enqueuedAt: Date()
            )) {
                dirty = true
            }
        }
        if dirty { persist() }
        for record in queue.records {
            applyHiding(
                sessionID: record.sessionID, appState: appState,
                modelContext: modelContext
            )
            launch(
                sessionID: record.sessionID, appState: appState,
                modelContext: modelContext
            )
        }
    }

    // MARK: - 隐藏与恢复

    /// 隐藏段（begin/resume 共用、幂等）：共享目
    /// 录摘行＋绑定线程打墓碑；正在看的线程先经
    /// drawerDeletedThreadID 通知 ChatView 置空当
    /// 前线程（与物理删除同一通道、同一清理面）。
    /// 侧账 purge 不在此段——它不可逆，留到落定
    /// 收口，失败恢复才无损
    private func applyHiding(
        sessionID: String, appState: AppState,
        modelContext: ModelContext
    ) {
        appState.sessionLedger.removeSession(sessionID: sessionID)
        var changed = false
        for thread in fetchThreads(modelContext)
        where thread.serverSessionID == sessionID {
            guard !SideChatClassifier.isMain(
                localThreadID: thread.id,
                linkedServerSessionID: thread.serverSessionID,
                mainThreadID: appState.sessionLedger.mainThreadID,
                mainServerSessionID: appState.sessionLedger
                    .mainServerSessionID
            ) else { continue }
            if DeletedSessionCloseout.isCurrentThread(
                thread, appState: appState
            ) {
                appState.router.drawerDeletedThreadID = thread.id
            }
            if !thread.isPendingDeletion {
                thread.isPendingDeletion = true
                changed = true
            }
        }
        if changed { try? modelContext.save() }
    }

    /// 恢复段（最终失败）：解墓碑（线程本体从未物
    /// 理删，解标即原样回到删除前状态）→出队→恢
    /// 复信号＋目录重拉（仍在待删集的会话不被重拉
    /// 带回）→人话提醒置位待 ChatView 消费
    private func restore(
        sessionID: String, appState: AppState,
        modelContext: ModelContext
    ) {
        let record = queue.dequeue(sessionID: sessionID)
        persist()
        var changed = false
        for thread in fetchThreads(modelContext)
        where thread.serverSessionID == sessionID
            && thread.isPendingDeletion {
            thread.isPendingDeletion = false
            changed = true
        }
        if changed { try? modelContext.save() }
        restoreRevision += 1
        Task {
            if let sessions = await catalogRefresher(appState) {
                let pending = queue.sessionIDs
                appState.sessionLedger.publishVisible(
                    sessions.filter {
                        !pending.contains($0.id)
                    }
                )
            }
        }
        let title = record?.title ?? ""
        appState.sessionDeletionFailureNotice = title.isEmpty
            ? "删除没成功，已恢复。"
            : "「\(title)」删除没成功，已恢复。"
    }

    // MARK: - 后台执行

    private func launch(
        sessionID: String, appState: AppState,
        modelContext: ModelContext
    ) {
        guard !inFlight.contains(sessionID) else { return }
        inFlight.insert(sessionID)
        Task { [weak self] in
            await self?.execute(
                sessionID: sessionID, appState: appState,
                modelContext: modelContext
            )
        }
    }

    private func execute(
        sessionID: String, appState: AppState,
        modelContext: ModelContext
    ) async {
        defer { inFlight.remove(sessionID) }
        let outcome = await deleteAction(appState, sessionID)
        switch outcome {
        case .verified:
            // 落定收口：物理删墓碑线程＋清侧账＋账
            // 本摘行（已摘、幂等）——经账本收口门面
            // 走 §223 共享收口，本类不另写一份清理
            appState.sessionLedger.closeoutDeletedSession(
                sessionID: sessionID, appState: appState,
                threads: fetchThreads(modelContext),
                modelContext: modelContext
            )
            queue.dequeue(sessionID: sessionID)
            persist()
        case .failed:
            restore(
                sessionID: sessionID, appState: appState,
                modelContext: modelContext
            )
        }
    }

    private func fetchThreads(
        _ modelContext: ModelContext
    ) -> [ChatThread] {
        (try? modelContext.fetch(FetchDescriptor<ChatThread>())) ?? []
    }
}
