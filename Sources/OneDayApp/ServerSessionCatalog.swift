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

    /// 冷缓存补拉：已热或在飞直接返回；失败不置
    /// hasLoaded（下次开抽屉重试）、不抛错——闸的呈
    /// 现回落＝频道区暂不显，与旧窗口口径的失败形态
    /// 一致（拉不到不误显、不误报）
    func refreshIfCold(appState: AppState) async {
        guard !hasLoaded, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        if let sessions = try? await Self.fetchAll(
            appState: appState, archived: "exclude"
        ) {
            publish(visible: sessions)
        }
    }

    /// 分页拉全：limit 100 逐页至不足一页或达 total，
    /// 上限 10 页（防服务端分页异常时无界拉取）——
    /// 本函数是管理页 fetchAll 收编后的唯一出处（管
    /// 理页同调本函数，两处不许再各抄一份）
    static func fetchAll(
        appState: AppState, archived: String
    ) async throws -> [ServerSession] {
        try await appState.performAdmin { client, config in
            var all: [ServerSession] = []
            var offset = 0
            for _ in 0..<10 {
                let page = try await client.serverSessionsPage(
                    config: config, limit: 100,
                    offset: offset, archived: archived
                )
                all.append(contentsOf: page.sessions)
                if page.sessions.count < 100 { break }
                if let total = page.total, all.count >= total { break }
                offset += 100
            }
            return all
        }
    }
}
