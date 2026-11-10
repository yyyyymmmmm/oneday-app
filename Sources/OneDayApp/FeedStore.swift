import Foundation
import OneDayCore

/// 动态数据中枢（P3，0.35.0）：oneday-bridge /feed 的
/// 状态面。口径：①桥未连接/未开通与 GoalsStore 同分
/// 法（共用其静态映射）；②已读是服务端真源——打开
/// 帖子走 POST /feed/{id}/read、以桥回执对账本地，
/// 不自立本地已读账；③账面（generation）只供胶囊与
/// 空态口径，拉不到时降级、不假造；④帖子排序/分组/
/// 胶囊/相对时间的呈现口径全收口在 Core FeedBoard。
@MainActor
@Observable
final class FeedStore {
    typealias LoadState = GoalsStore.LoadState

    private(set) var loadState: LoadState = .loading
    private(set) var posts: [BridgeFeedPost] = []
    /// 双生产者账面（汇编状态＋晨报节奏＋未读数）；
    /// 旧桥无此端点时为 nil，对应呈现降级
    private(set) var generation: BridgeFeedGeneration?

    private let client = OneDayBridgeClient()
    private var loadInFlight = false

    // MARK: - 呈现口径（收口在 Core FeedBoard）

    var sortedPosts: [BridgeFeedPost] {
        FeedBoard.sorted(posts)
    }

    var dayGroups: [FeedBoard.DayGroup] {
        FeedBoard.dayGroups(sortedPosts, now: Date())
    }

    var unreadCount: Int {
        FeedBoard.unreadCount(posts)
    }

    /// 简报胶囊落点（今日汇编优先，见 FeedBoard）
    var capsulePost: BridgeFeedPost? {
        FeedBoard.capsulePost(posts, now: Date())
    }

    var emptyKind: FeedBoard.EmptyKind {
        FeedBoard.emptyKind(
            hasAnyPost: !posts.isEmpty,
            morningLastRunAt: generation?.morning?.lastRunAt,
            eventsToday: generation?.assembly?.eventsToday ?? 0
        )
    }

    func post(id: String) -> BridgeFeedPost? {
        posts.first { $0.id == id }
    }

    // MARK: - 加载

    func load(appState: AppState) async {
        guard !loadInFlight else { return }
        guard let config = appState.config else {
            loadState = .failed("尚未连接服务器。")
            return
        }
        loadInFlight = true
        defer { loadInFlight = false }
        do {
            posts = try await client.feedPosts(config: config)
            loadState = .ready
        } catch let error as OneDayBridgeError {
            if loadState == .ready { return }
            loadState = GoalsStore.state(for: error)
        } catch {
            if loadState == .ready { return }
            loadState = .failed("动态读取失败，请稍后重试。")
        }
        // 附带面：账面失败只降级胶囊/空态口径，帖子照常
        if let fetched = try? await client.feedGeneration(
            config: config
        ) {
            generation = fetched
        }
    }

    // MARK: - 已读（服务端真源）

    /// 打开帖子即标记：回执到达以桥落字替换本地行；
    /// 失败不本地造已读（下次打开重试，列表未读数以
    /// 服务端口径为准）
    func markRead(appState: AppState, post: BridgeFeedPost) async {
        guard !post.isRead, let config = appState.config else {
            return
        }
        if let settled = try? await client.markFeedPostRead(
            config: config, id: post.id
        ) {
            posts = posts.map { $0.id == settled.id ? settled : $0 }
            if let gen = generation {
                generation = BridgeFeedGeneration(
                    assembly: gen.assembly,
                    morning: gen.morning,
                    unread: FeedBoard.unreadCount(posts)
                )
            }
        }
    }
}
