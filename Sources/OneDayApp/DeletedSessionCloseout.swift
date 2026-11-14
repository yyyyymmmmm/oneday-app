import OneDayCore
import SwiftData

/// 删除全域收口（§217）：服务端会话删除回查落定
/// （ServerSessionActions.Outcome.verified）之后
/// 的本地收尾，全 App 唯一实现——清侧账＋共享目
/// 录摘行＋按 serverSessionID 删绑定本地线程。
///
/// 沿革：0.50.30 抽屉删除流是全仓唯一做本地收口
/// 的路（performDeleteThread 私有实现）；管理页
/// 单删/批删、频道页行删除只删服务端，本地线程
/// 与目录行残留、点开撞 404（2026-11-14 用户真
/// 机实报，定因见诊断报告题一）。本件把抽屉那份
/// 收口提成共享件：任何面拿到 .verified 都调它，
/// 未落定本地一律不动（与抽屉流同纪律）。
@MainActor
enum DeletedSessionCloseout {

    /// 单条收口：sessionID 对应的本地投影全清。
    /// 线程删除双重保护——钦定主线会话本体与主线
    /// 线程永不许被本收口带走（管理页批删/prune/
    /// 对账都可能把主线 id 递进来，保护在收口内兜
    /// 死，不靠调用方自觉）
    static func apply(
        sessionID: String,
        appState: AppState,
        threads: [ChatThread],
        modelContext: ModelContext
    ) {
        // 钦定主线会话 id 递进来＝整件不动（侧账/目
        // 录/线程全不碰）：主线在任何删除面都没有入
        // 口，此为收口内的最后兜底
        guard sessionID != appState.sideChats.mainServerSessionID
        else { return }
        appState.sideChats.purgeServerSessionRecords(sessionID)
        appState.serverSessionCatalog.remove(sessionID: sessionID)
        for thread in threads
        where thread.serverSessionID == sessionID {
            guard !SideChatClassifier.isMain(
                localThreadID: thread.id,
                linkedServerSessionID: thread.serverSessionID,
                mainThreadID: appState.sideChats.mainThreadID,
                mainServerSessionID: appState.sideChats
                    .mainServerSessionID
            ) else { continue }
            deleteLocalThread(
                thread, appState: appState, modelContext: modelContext
            )
        }
    }

    /// 名单对账回收（§217）：存活集（管理页全量可
    /// 见＋已归档并集）之外的本地绑定会话即服务端
    /// 已消失——覆盖 prune 清理与他端删除留下的残
    /// 留。只清过真删闸的绑定（oneday- 自有旁聊；
    /// 主线/合并桶/导入会话的绑定一律保留——导入
    /// 会话的名单口径与本存活集未必同源，不许凭一
    /// 份名单误清他方历史）。返回清掉的会话 id 集
    /// （调用方/测试对账用）
    @discardableResult
    static func reconcileLocalThreads(
        threads: [ChatThread],
        liveSessionIDs: Set<String>,
        appState: AppState,
        modelContext: ModelContext
    ) -> [String] {
        var seen = Set<String>()
        var purged: [String] = []
        for thread in threads {
            guard let sessionID = thread.serverSessionID,
                  !liveSessionIDs.contains(sessionID),
                  seen.insert(sessionID).inserted,
                  SideChatLink.mayHardDeleteOnThreadDelete(
                      sessionID: sessionID,
                      mainSessionID: appState.sideChats
                          .mainServerSessionID
                  )
            else { continue }
            apply(
                sessionID: sessionID, appState: appState,
                threads: threads, modelContext: modelContext
            )
            purged.append(sessionID)
        }
        return purged
    }

    /// 点开已消失会话的防御收口（§217）：导入路撞
    /// 404 时调用——该会话本地没有线程（有线程走切
    /// 换路、到不了导入），要清的是侧账与目录行，
    /// 清完行即消失、不会再被点第二次
    static func handleOpenedSessionMissing(
        sessionID: String,
        appState: AppState
    ) {
        appState.sideChats.purgeServerSessionRecords(sessionID)
        appState.serverSessionCatalog.remove(sessionID: sessionID)
    }

    /// 删本地线程本体（自抽屉 deleteLocalThread 提
    /// 成共享件，语义一字不变）：删的若是用户正在
    /// 看的线程，先经 drawerDeletedThreadID 通知
    /// ChatView 置空当前线程并清其草稿/滚动锚/附件
    /// 格（0.4.5 通道）。「正在看」判定读 AppState
    /// 当前对象引用＋频道观看出处（抽屉旧实现读它
    /// 自家的 drawerSelection，其中对象引用即同一
    /// 本账；呈现层在上层覆盖时对象引用仍是 Chat-
    /// View 正在显示的那条，按它判才对得上）
    static func deleteLocalThread(
        _ thread: ChatThread,
        appState: AppState,
        modelContext: ModelContext
    ) {
        if isCurrentThread(thread, appState: appState) {
            appState.drawerDeletedThreadID = thread.id
        }
        modelContext.delete(thread)
        try? modelContext.save()
    }

    /// 当前线程判定：对象引用指向本线程（旁聊直
    /// 指/主线且本线程是主线），或本线程正是从频
    /// 道点开正在看的那条（0.36.29 频道出处）
    static func isCurrentThread(
        _ thread: ChatThread, appState: AppState
    ) -> Bool {
        switch appState.currentDrawerObject {
        case .side(let id) where id == thread.id:
            return true
        case .main:
            if SideChatClassifier.isMain(
                localThreadID: thread.id,
                linkedServerSessionID: thread.serverSessionID,
                mainThreadID: appState.sideChats.mainThreadID,
                mainServerSessionID: appState.sideChats
                    .mainServerSessionID
            ) {
                return true
            }
        case .channel, .side, nil:
            break
        }
        if let sessionID = thread.serverSessionID,
           sessionID == appState.channelViewingOrigin?.sessionID {
            return true
        }
        return false
    }
}
