import Foundation
import Observation
import OneDayCore
import SwiftData

extension SessionLedger {
    // MARK: - 读口

    /// 合并名单：账本段名单＋注入的本地线程现场重
    /// 演 join 与合并（合并/分类/投影全在 Core 纯函
    /// 数，本店只摘侧账输入）
    func records(
        appState: AppState, localThreads: [ChatThread]
    ) -> [SessionRecord] {
        SessionLedgerMerge.records(
            visible: visibleSessions,
            archived: archivedSessions,
            localThreads: localThreads.map(LedgerLocalThread.init),
            inputs: SessionLedgerMerge.Inputs(
                mainThreadID: mainThreadID,
                mainServerSessionID: mainServerSessionID,
                archivedKeys: archivedKeys,
                pendingDeletionIDs: deletions.queue.sessionIDs,
                firstUserMessages: appState.sessionTitles
                    .firstUserMessages
            )
        )
    }

    /// 存活集＋完整性（B-1 闸的接口级形态）
    func liveSet() -> (ids: Set<String>,
                       completeness: LedgerCompleteness) {
        (liveSessionIDs, liveCompleteness)
    }

    func drawerSideRows(
        appState: AppState, localThreads: [ChatThread]
    ) -> [SessionRecord] {
        LedgerProjection.drawerSideRows(
            records(appState: appState, localThreads: localThreads)
        )
    }

    func managementVisible(
        appState: AppState, localThreads: [ChatThread]
    ) -> [ServerSession] {
        LedgerProjection.managementVisible(
            records(appState: appState, localThreads: localThreads)
        )
    }

    func managementArchived(
        appState: AppState, localThreads: [ChatThread]
    ) -> [ServerSession] {
        LedgerProjection.managementArchived(
            records(appState: appState, localThreads: localThreads)
        )
    }

    func channelList(
        appState: AppState, localThreads: [ChatThread],
        channelID: String
    ) -> [ServerSession] {
        LedgerProjection.channelList(
            records(appState: appState, localThreads: localThreads),
            channelID: channelID
        )
    }

    func hubSessions(
        appState: AppState, localThreads: [ChatThread]
    ) -> [ServerSession] {
        LedgerProjection.hubSessions(
            records(appState: appState, localThreads: localThreads)
        )
    }

    // MARK: - 同步（唯一拉取者）

    /// 全量刷新（管理页 load 的收编）：两段拉全→合
    /// 并落位→完整时对账回收（B-1 闸：任一段不完整
    /// 跳过对账并留痕，宁可不清、不可误清）→主线兜
    /// 底单查→标题回落素材。§233 归档缓存回写已退
    /// 役（包二）：归档态直接读记录归档列（过回写
    /// 闸的绑定以服务端段为准、余者以本地键为准，
    /// archiveSource 如实分列），不再把服务端态反
    /// 向改写本地键。时序与旧 AllConversationsStore
    /// .load 逐拍一致：可见段拉成即落位（不被归档
    /// 段失败连坐）；任一段 throw 由调用方转人话错误
    func refresh(
        appState: AppState, localThreads: [ChatThread],
        modelContext: ModelContext
    ) async throws {
        let epochAtStart = listFreshnessEpoch
        let visibleFetch = try await Self
            .fetchAll(appState: appState, archived: "exclude")
        let visible = visibleFetch.sessions
        // §232：待删集不进展示与目录（服务端此刻仍
        // 有其行，不过滤会被重拉带回）；对账存活集
        // 用未过滤全集（待删会话在服务端尚存活，其
        // 墓碑线程不许被对账误清）
        let pendingDeletions = deletions.queue.sessionIDs
        visibleSessions = visible.filter {
            !pendingDeletions.contains($0.id)
        }
        hasLoaded = true
        // §370：可见段已按现值落位——新鲜度同拍落账
        // （代次未变才落，横跨写事件不冒充新鲜）；此
        // 后归档段/对账若摘行失效，保守作废、下次读
        // 触发真拉
        if epochAtStart == listFreshnessEpoch {
            listFreshness.stamp(
                configKey: appState.config?.baseString,
                now: Date()
            )
        }
        let archivedFetch = try await Self
            .fetchAll(appState: appState, archived: "only")
        let archived = archivedFetch.sessions
        archivedSessions = archived.filter {
            !pendingDeletions.contains($0.id)
        }
        // §223 名单对账＋B-1 防护闸（2026-11-14）
        if visibleFetch.isComplete && archivedFetch.isComplete {
            liveSessionIDs = Set(visible.map(\.id))
                .union(archived.map(\.id))
            liveCompleteness = .complete
            DeletedSessionCloseout.reconcileLocalThreads(
                threads: localThreads,
                liveSessionIDs: liveSessionIDs,
                appState: appState, modelContext: modelContext
            )
        } else {
            liveCompleteness = .incomplete(
                reason: "可见段："
                    + (visibleFetch.incompleteReason?
                        .traceLabel ?? "完整")
                    + "；归档段："
                    + (archivedFetch.incompleteReason?
                        .traceLabel ?? "完整")
            )
            ChatDiagTrace.record(
                "全部对话名单对账跳过：名单不完整"
                    + "（可见段："
                    + (visibleFetch.incompleteReason?
                        .traceLabel ?? "完整")
                    + "；归档段："
                    + (archivedFetch.incompleteReason?
                        .traceLabel ?? "完整")
                    + "），本地线程本轮不动"
            )
        }
        if let mainID = mainServerSessionID,
           !visible.contains(where: { $0.id == mainID }),
           !archived.contains(where: { $0.id == mainID }) {
            mainFallback = try? await appState.performAdmin {
                client, config in
                try await client.serverSession(
                    config: config, id: mainID
                )
            }
        } else {
            mainFallback = nil
        }
        hasLoadedFull = true
        // 标题回落素材：无服务端标题者才拉消息派生
        await appState.sessionTitles.ensureTitles(
            for: visible + archived, appState: appState,
            budget: 12
        )
        // 存量迁移挂载点（第 90 条收尾）：归档段同步
        // 完成即触发点——触发从管理页首开迁到此处，
        // 此后每次全量刷新完成都会顺带跑一次（计划
        // 为空即无事；失败项留痕＋本地值保留，下轮
        // 刷新再试）
        await runMigrationIfNeeded(
            appState: appState, localThreads: localThreads,
            modelContext: modelContext
        )
    }

    /// 可见段刷新（抽屉/频道页触发点的收编）：旧抽
    /// 屉 loadDrawerData 每开必拉第一页喂 source/标
    /// 题映射；本路改拉可见段全量落账本（现存规模
    /// 下与一页同价），source/标题改读记录列。只喂
    /// 显示、不驱动任何删除——名单不完整也照常落
    /// 位（防护闸只拦以名单为存活集的删除/回收）。
    /// 标题回落素材补拉同在本路（包二：名单面的标
    /// 题补拉只许在账本内发生）。返回是否拉到名单
    /// （频道页据此呈现失败态）
    @discardableResult
    func refreshVisible(
        appState: AppState, localThreads: [ChatThread],
        now: Date = Date()
    ) async -> Bool {
        guard !isRefreshingVisible else { return false }
        isRefreshingVisible = true
        defer { isRefreshingVisible = false }
        let epochAtStart = listFreshnessEpoch
        guard let result = try? await Self
            .fetchAll(appState: appState, archived: "exclude")
        else { return false }
        let pending = deletions.queue.sessionIDs
        visibleSessions = result.sessions.filter {
            !pending.contains($0.id)
        }
        hasLoaded = true
        await appState.sessionTitles.ensureTitles(
            for: result.sessions, appState: appState,
            budget: 12
        )
        // §370：名单＋标题补拉整轮成功才落账新鲜度
        // （失败不落账、不拿旧时刻冒充）；拉取横跨写
        // 事件（代次已变）不落账——下一读触发照旧真
        // 拉对账
        if epochAtStart == listFreshnessEpoch {
            listFreshness.stamp(
                configKey: appState.config?.baseString,
                now: now
            )
        }
        return true
    }

    /// 读触发入口（§370 新鲜度门）：抽屉落定/回前
    /// 台/预挂载三路先过本门——TTL 内且配置键没变
    /// 直接用已载名单、零请求；首载/过期/被写事件
    /// 失效/换服务器才走 refreshVisible 全量。强
    /// 制路（drawerRefreshTick 令牌、行操作
    /// onChanged、频道页）不经此门、直调
    /// refreshVisible（成功同样落账）
    func refreshVisibleIfNeeded(
        appState: AppState, localThreads: [ChatThread],
        now: Date = Date()
    ) async {
        guard !listFreshness.isFresh(
            configKey: appState.config?.baseString, now: now
        ) else { return }
        await refreshVisible(
            appState: appState, localThreads: localThreads,
            now: now
        )
    }

    /// 冷缓存补拉（目录壳 refreshIfCold 的收编）：
    /// 已热或在飞直接返回；失败不置 hasLoaded（下次
    /// 触发重试）、不抛错
    func refreshVisibleIfCold(
        appState: AppState, localThreads: [ChatThread]
    ) async {
        guard !hasLoaded, !isRefreshingVisible else { return }
        await refreshVisible(
            appState: appState, localThreads: localThreads
        )
    }

    /// 收养判定名单（ChatView adoptOnTitleConflict
    /// 的收编）：账本两段齐全时读账本名单（含已归
    /// 档段——占名者可能已归档）；未齐全回落现拉
    /// include 全量。只用于候选检索、不驱动删除，
    /// 不需完整性闸（不完整至多漏候选、方向保守）；
    /// 拉不到返回 nil（调用方照抛原错误、不收养）
    func adoptionSessions(
        appState: AppState
    ) async -> [ServerSession]? {
        if hasLoadedFull {
            var seen = Set<String>()
            return (visibleSessions + archivedSessions).filter {
                seen.insert($0.id).inserted
            }
        }
        return try? await Self.fetchAll(
            appState: appState, archived: "include"
        ).sessions
    }

    // MARK: - 名单写回面（旧 Catalog.publish/remove 语义逐字）

    /// 写回（旧 publish）：调用方已付分页代价且已过
    /// 待删过滤，同份可见集落本店
    func publishVisible(_ visible: [ServerSession]) {
        visibleSessions = visible
        hasLoaded = true
    }

    /// 摘行（旧 Catalog.remove＋管理页 removeLocal
    /// 的合一）：服务端会话已确认删除/不存在，两段
    /// 名单与主线兜底同拍摘除，不等下一轮全量拉取
    func removeSession(sessionID: String) {
        // §370：删除落定即名单写事件——新鲜度作废，
        // 下一次读触发必真拉对账（摘行本身仍即时）
        invalidateListFreshness()
        visibleSessions.removeAll { $0.id == sessionID }
        archivedSessions.removeAll { $0.id == sessionID }
        if mainFallback?.id == sessionID { mainFallback = nil }
    }

    // MARK: - 标题读点（包二：冲突处理归账本一处）

    /// 服务端行标题的唯一读点：存量本地覆盖（迁移
    /// 未排空的遗留改名）优先，其后统一管线（服务
    /// 端标题＞派生＞人话名）。管理页/频道页行标题
    /// 都经本口，不许各面再直读覆盖表与解析器
    func title(
        for session: ServerSession, appState: AppState
    ) -> String {
        appState.sideChats.titleOverrides[session.id]
            ?? appState.sessionTitles.title(for: session)
    }

    // MARK: - 删除落定收口（包二：收口归账本门面）

    /// 单条落定收口（转发 §223 共享收口实现）：服
    /// 务端删除已回查落定后清侧账＋账本摘行＋删绑
    /// 定线程。删除引擎的落定段与名单对账都经账本
    /// 内部路径至此，外部面不许再直调收口件
    func closeoutDeletedSession(
        sessionID: String, appState: AppState,
        threads: [ChatThread], modelContext: ModelContext
    ) {
        DeletedSessionCloseout.apply(
            sessionID: sessionID, appState: appState,
            threads: threads, modelContext: modelContext
        )
    }

    /// 点开已消失会话的防御收口（转发 §223）：清侧
    /// 账＋账本摘行，行即消失
    func noteOpenedSessionMissing(
        sessionID: String, appState: AppState
    ) {
        DeletedSessionCloseout.handleOpenedSessionMissing(
            sessionID: sessionID, appState: appState
        )
    }

    // MARK: - 存量迁移（第 90 条收尾：挂载点迁入）

    /// 迁移失败留痕（逐项人话行）：管理页迁移区直
    /// 读本列呈现；成功落定后由下一轮迁移结果覆盖
    /// 迁移在飞标记：迁移尾步的重拉（refresh）会再
    /// 到触发点，靠本标记防自触发重入

    /// 归档段同步完成事件的挂载口（refresh 尾步调
    /// 用）：每次全量刷新完成都顺带执行一次待迁计
    /// 划；迁移本体自带在飞守卫防自触发重入
    func runMigrationIfNeeded(
        appState: AppState, localThreads: [ChatThread],
        modelContext: ModelContext
    ) async {
        await runMigration(
            appState: appState, localThreads: localThreads,
            modelContext: modelContext
        )
    }

    /// 存量迁移执行（自管理页 AllConversationsStore
    /// 迁入，语义逐字）：计划走 Core 纯函数
    /// （SessionMigration.plan），逐项经动作层回写＋
    /// 回读对账；折叠后成功项清本地（覆盖表删项、
    /// 归档键删项），失败项逐项留痕＋本地值保留。
    /// 迁移后名单重拉（归档项的服务端状态已变）；
    /// 尾步重拉的 refresh 会再到挂载点，靠在飞守
    /// 卫挡下（失败项的再试留给下一轮外部刷新，不
    /// 在本轮内自旋）
    func runMigration(
        appState: AppState, localThreads: [ChatThread],
        modelContext: ModelContext
    ) async {
        guard !isRunningMigration else { return }
        isRunningMigration = true
        defer { isRunningMigration = false }
        let sideChats = appState.sideChats
        let overrides = sideChats.titleOverrides
        let keys = archivedKeys
        let plan = SessionMigration.plan(
            titleOverrides: overrides, archivedKeys: keys
        )
        guard !plan.isEmpty else { return }
        var failureReasons: [SessionMigration.Item: String] = [:]
        for item in plan {
            let outcome: ServerSessionActions.Outcome
            switch item.kind {
            case .rename(let title):
                outcome = await ServerSessionActions.rename(
                    appState: appState, id: item.sessionID, title: title
                )
            case .archive:
                outcome = await ServerSessionActions.setArchived(
                    appState: appState, id: item.sessionID, archived: true
                )
            }
            if case .failed(let reason) = outcome {
                failureReasons[item] = reason
            }
        }
        let outcome = SessionMigration.fold(
            plan: plan, failureReasons: failureReasons,
            titleOverrides: overrides, archivedKeys: keys
        )
        // 退役成功项：本地只删「计划内且已落定」的键
        for id in overrides.keys
        where outcome.remainingTitleOverrides[id] == nil {
            sideChats.setTitleOverride(nil, for: id)
        }
        for key in keys
        where !outcome.remainingArchivedKeys.contains(key)
            && key.hasPrefix("server:") {
            unarchive(
                serverSessionID: String(key.dropFirst("server:".count))
            )
        }
        migrationFailures = outcome.failures.map { failure in
            "「\(failure.item.sessionID)」\(failure.item.actionLabel)没改成：\(failure.reason)"
        }
        try? await refresh(
            appState: appState, localThreads: localThreads,
            modelContext: modelContext
        )
}

    // MARK: - 分页装配核（B-07：自转发壳迁入）

    /// 名单不完整的判定原因（B-1 防护，2026-11-14
    /// 同类横扫定案）：三类信号任一出现即判不完整
    enum IncompleteReason: Equatable {
        /// 10 页上限走满仍未见名单尽头——旧形态在
        /// 此静默截断，尾部整段无声消失
        case pageCapReached
        /// 服务端报的总数与实拉唯一行数对不上（含
        /// 拉取途中总数漂移：多页报数互不一致）
        case totalMismatch(reported: Int, fetched: Int)
        /// 页内/跨页出现重复行——offset 位移的指纹
        /// （拉取途中名单增删）：有重必有漏
        case duplicateRows(count: Int)

        /// 留痕用人话短句（不带状态码原文）
        var traceLabel: String {
            switch self {
            case .pageCapReached:
                return "分页上限走满、名单未见尽头"
            case .totalMismatch(let reported, let fetched):
                return "总数对不上（服务端报 \(reported)、实拉 \(fetched)）"
            case .duplicateRows(let count):
                return "分页出现重复行 \(count) 条"
            }
        }
    }

    /// 拉全结果：名单本体＋完整性判定。完整性是防
    /// 护闸的唯一凭据——以名单为存活集做删除/回收
    /// 的消费点必须先查 isComplete，不完整即跳过动
    /// 作并留痕（宁可不清、不可误清）；只喂显示的
    /// 消费点可直接取 sessions
    struct FetchResult {
        var sessions: [ServerSession]
        var incompleteReason: IncompleteReason?
        var isComplete: Bool { incompleteReason == nil }
    }

    /// 分页拉全：limit 100 逐页至不足一页或达 total，
    /// 上限 10 页（防服务端分页异常时无界拉取）——
    /// 本函数是全 App 唯一实现，两处不许再各抄一份。
    /// B-1 防护（2026-11-14）：旧形态 append 累加、
    /// 无去重、无对账、上限处静默截断，下游对账以
    /// 此名单为存活集清本地线程——截断/漏行会被误
    /// 判「服务端已删」造成数据丢失。本形态：装配
    /// 时去重（保首现序）、全程对账，任一不完整信
    /// 号（上限走满/总数对不上或漂移/出现重行）即
    /// 在结果上打标并留痕，删除向消费点据标跳过
    static func fetchAll(
        appState: AppState, archived: String
    ) async throws -> FetchResult {
        let result = try await appState.performAdmin {
            client, config in
            try await Self.fetchAllPages { offset in
                try await client.serverSessionsPage(
                    config: config, limit: 100,
                    offset: offset, archived: archived
                )
            }
        }
        if let reason = result.incompleteReason {
            ChatDiagTrace.record(
                "会话名单不完整（archived=\(archived)）："
                    + reason.traceLabel
                    + "——以名单为存活集的删除/回收本轮跳过"
            )
        }
        return result
    }

    /// 分页装配核（页取口注入，单测以脚本页直驱）：
    /// 与 fetchAll 同一实现，不许另抄一份。offset 按
    /// 原始页行数推进（与服务端分页口径一致）；唯
    /// 一行集保首现序去重
    static func fetchAllPages(
        fetchPage: (Int) async throws -> SessionsPage
    ) async throws -> FetchResult {
        var all: [ServerSession] = []
        var seen = Set<String>()
        var duplicateCount = 0
        var reportedTotals = Set<Int>()
        var lastReportedTotal: Int?
        var offset = 0
        var ranOutOfPages = true
        for _ in 0..<10 {
            let page = try await fetchPage(offset)
            if let total = page.total {
                reportedTotals.insert(total)
                lastReportedTotal = total
            }
            for session in page.sessions {
                if seen.insert(session.id).inserted {
                    all.append(session)
                } else {
                    duplicateCount += 1
                }
            }
            if page.sessions.count < 100 {
                ranOutOfPages = false
                break
            }
            if let total = page.total, all.count >= total {
                ranOutOfPages = false
                break
            }
            offset += 100
        }
        let reason: IncompleteReason?
        if duplicateCount > 0 {
            reason = .duplicateRows(count: duplicateCount)
        } else if reportedTotals.count > 1 {
            reason = .totalMismatch(
                reported: lastReportedTotal ?? all.count,
                fetched: all.count
            )
        } else if let total = lastReportedTotal, total != all.count {
            reason = .totalMismatch(
                reported: total, fetched: all.count
            )
        } else if ranOutOfPages {
            reason = .pageCapReached
        } else {
            reason = nil
        }
        return FetchResult(
            sessions: all, incompleteReason: reason
        )
    }
}

/// ChatThread → 账本快照（合并注入形）：逐字段摘
/// 出，账本与 Core 合并函数不直碰 SwiftData 本体
extension LedgerLocalThread {
    init(_ thread: ChatThread) {
        self.init(
            id: thread.id, title: thread.title,
            titleIsManual: thread.titleIsManual,
            serverSessionID: thread.serverSessionID,
            isPendingDeletion: thread.isPendingDeletion,
            isPinned: thread.isPinned,
            updatedAt: thread.updatedAt,
            createdAt: thread.createdAt,
            linkFailureCount: thread.linkFailureCount,
            linkLastError: thread.linkLastError
        )
    }
}
