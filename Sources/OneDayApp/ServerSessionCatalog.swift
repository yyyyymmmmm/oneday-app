import OneDayCore
import Observation

/// 服务端会话全量目录（§198，抽屉包题一）：全部对
/// 话页为名单付的分页拉全代价，全 App 共享一份——
/// 可见集（archived=exclude）落本目录：管理页拉完
/// 写回（write-through），抽屉开时冷缓存异步补拉。
/// 频道显行闸自此读本目录的全量集现算分类，与管理
/// 页频道段同源同数；开抽屉既有的 limit 100 一路拉
/// 取只喂旁聊行来源过滤与标题解析、口径不变（频
/// 道规格 §3.3 纪律：名单拉取不加码，补拉只在缓存
/// 冷时发生一轮，热后开抽屉零新增拉取）
@MainActor
@Observable
final class ServerSessionCatalog {
    /// 可见全量（archived=exclude 分页拉全的结果）
    private(set) var visibleSessions: [ServerSession] = []
    /// 是否已有一轮全量结果（冷/热的唯一判定：拉到
    /// 空集也是结果——服务端真无会话时不许每开一次
    /// 抽屉就重拉一轮全量）
    private(set) var hasLoaded = false
    /// 补拉在飞标记（开抽屉/回前台/刷新令牌多路触发
    /// 只合并成一轮）
    private var isRefreshing = false

    /// 管理页写回：它已付分页代价，顺手把同份可见集
    /// 存进本目录（与管理页 store.sessions 同源同批）
    func publish(visible: [ServerSession]) {
        visibleSessions = visible
        hasLoaded = true
    }

    /// 摘行（§223 删除全域收口）：服务端会话已回查
    /// 确认删除/不存在，目录里的对应行立即摘掉——
    /// 删除面（管理页/频道页）与点开 404 防御共用，
    /// 不等下一轮全量拉取才消失
    func remove(sessionID: String) {
        visibleSessions.removeAll { $0.id == sessionID }
    }

    /// 冷缓存补拉：已热或在飞直接返回；失败不置
    /// hasLoaded（下次开抽屉重试）、不抛错——闸的呈
    /// 现回落＝频道区暂不显，与旧窗口口径的失败形态
    /// 一致（拉不到不误显、不误报）。本目录只喂显
    /// 示、不驱动任何删除，名单不完整也照常 publish
    /// （防护闸只拦以名单为存活集的删除/回收，见
    /// fetchAll 注）
    func refreshIfCold(appState: AppState) async {
        guard !hasLoaded, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        if let result = try? await Self.fetchAll(
            appState: appState, archived: "exclude"
        ) {
            // §232：待删集不被补拉带回（乐观删除后台
            // 未落定期间服务端仍有其行）
            let pending = appState.sessionDeletions
                .queue.sessionIDs
            publish(
                visible: result.sessions.filter {
                    !pending.contains($0.id)
                }
            )
        }
    }

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
    /// 本函数是管理页 fetchAll 收编后的唯一出处（管
    /// 理页同调本函数，两处不许再各抄一份）。
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
