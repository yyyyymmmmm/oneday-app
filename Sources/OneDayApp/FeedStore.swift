import Foundation
import OneDayCore

/// 动态数据中枢（P3，0.35.0）：oneday-bridge /feed 的
/// 状态面。口径：①桥未连接/未开通与 GoalsStore 同分
/// 法（共用其静态映射）；②§232 起轻动作改乐观时序：
/// 已读与点赞都是本地先落呈现、后台以桥回执对账
/// （桥仍是最终真源）——已读失败静默留下轮纠正、点
/// 赞失败恢复原帖＋轻提醒，不再等回执才翻面、更不
/// 许失败静默吞；③账面（generation）只供空态
/// 口径（§126 起胶囊行已删、未读数不再上任何提醒
/// 面，账面仅静默留存），拉不到时降级、不假造；
/// ④帖子排序/分组/
/// 胶囊/相对时间的呈现口径全收口在 Core FeedBoard。
@MainActor
@Observable
final class FeedStore {
    typealias LoadState = GoalsStore.LoadState

    private(set) var loadState: LoadState = .loading
    private(set) var posts: [BridgeFeedPost] = []
    /// 双生产者账面（汇编状态＋段二节奏＋未读数）；
    /// 旧桥无此端点时为 nil，对应呈现降级
    private(set) var generation: BridgeFeedGeneration?
    /// 简报两层（0.38.0）：兴趣层＋执行层＋扩写状态；
    /// 拉不到时为 nil，简报行与编辑器呈现降级
    private(set) var briefDoc: BridgeBriefDoc?
    private(set) var briefSaving = false
    /// 简报保存的就地错误（人话，呈现于编辑器内）
    private(set) var briefError: String?
    /// 点赞失败的轻提醒（§232）：乐观翻心被后台回执
    /// 否掉时落此一句，视图层以轻提示呈现、用户点掉
    /// 即清；成功路径恒 nil
    private(set) var likeNotice: String?

    private let client = OneDayBridgeClient()
    private var loadInFlight = false
    /// 点赞在飞集（FA-1）：同帖连点防竞态——在飞期
    /// 间再点直接忽略，等回执落定后才接受下一次
    private var likeInFlight: Set<String> = []

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
            morningLastRunAt: generation?.segmentTwo?.lastRunAt,
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
            loadState = .failed(L10n.string("尚未连接服务器。"))
            return
        }
        loadInFlight = true
        defer { loadInFlight = false }
        do {
            installLoadedPosts(
                try await client.feedPosts(config: config)
            )
            loadState = .ready
            // §208 包 3：名单到手即扫存量旧预填草稿
            // ——逐字再生核验须拿原帖，本点是最早能
            // 严格核验的时点；清扫幂等、逐字不符一
            // 字不动（判定与留痕在 SideChatStore）
            appState.sideChats.purgeLegacyFeedDiscussDrafts(
                posts: posts
            )
        } catch let error as OneDayBridgeError {
            if loadState == .ready { return }
            loadState = GoalsStore.state(for: error)
        } catch {
            if loadState == .ready { return }
            loadState = .failed(L10n.string("动态没读出来，可能是网络或服务暂时没响应"))
        }
        // 附带面：账面失败只降级胶囊/空态口径，帖子照常
        if let fetched = try? await client.feedGeneration(
            config: config
        ) {
            generation = fetched
        }
        // 简报两层同为附带面：失败只降级简报行
        if let doc = try? await client.feedBrief(config: config) {
            briefDoc = doc
        }
    }

    // MARK: - 简报两层（0.38.0）

    /// 保存兴趣层：回执即保存后全文；扩写在桥侧异步
    /// 进行，回来时以 expandStarted 知会「已开始整理」，
    /// 执行层与新帖在下次加载/回读时对账
    @discardableResult
    func saveInterest(appState: AppState, _ text: String) async -> Bool {
        await saveBrief(appState: appState) {
            try await $0.saveFeedInterest(config: $1, interest: text)
        }
    }

    /// 保存执行层（用户在编辑器里直改正式简报）
    @discardableResult
    func savePrompt(appState: AppState, _ text: String) async -> Bool {
        await saveBrief(appState: appState) {
            try await $0.saveFeedPrompt(config: $1, brief: text)
        }
    }

    private func saveBrief(
        appState: AppState,
        _ call: (OneDayBridgeClient, ServerConfig) async throws
            -> BridgeBriefDoc
    ) async -> Bool {
        guard let config = appState.config, !briefSaving else {
            return false
        }
        briefSaving = true
        defer { briefSaving = false }
        do {
            briefDoc = try await call(client, config)
            briefError = nil
            // 对账：扩写状态与账面一并回读，呈现不靠猜
            if let gen = try? await client.feedGeneration(
                config: config
            ) {
                generation = gen
            }
            return true
        } catch let error as OneDayBridgeError {
            briefError = GoalsStore.message(for: error)
            return false
        } catch {
            briefError = L10n.string("保存失败，请稍后再试。")
            return false
        }
    }

    /// 手动起一轮调研（编辑器/空态入口）；在跑时桥回
    /// 409，错误原样回给呈现层
    @discardableResult
    func generateNow(appState: AppState) async -> Bool {
        guard let config = appState.config else { return false }
        do {
            try await client.generateFeed(config: config)
            if let gen = try? await client.feedGeneration(
                config: config
            ) {
                generation = gen
            }
            return true
        } catch let error as OneDayBridgeError {
            briefError = GoalsStore.message(for: error)
            return false
        } catch {
            briefError = L10n.string("没能开始生成，请稍后再试。")
            return false
        }
    }

    // MARK: - 点赞（§232 乐观时序：点即翻心，桥回执对账）

    /// 名单装载收口（load 与测试共用一个落点）：整表
    /// 替换，附带清扫仍由 load 在装载后单独走
    func installLoadedPosts(_ loaded: [BridgeFeedPost]) {
        posts = loaded
    }

    /// 乐观翻心（同步落点，点按当拍生效）：只改目标
    /// 帖的 likedAt，其余帖原样；帖不在名单里不动
    func applyOptimisticLike(
        postID: String, liked: Bool, at ts: Double
    ) {
        posts = posts.map {
            $0.id == postID
                ? $0.withLikedAt(liked ? ts : nil)
                : $0
        }
    }

    /// 回执落定（整帖替换，桥的最终形态为准）
    func settlePost(_ settled: BridgeFeedPost) {
        posts = posts.map { $0.id == settled.id ? settled : $0 }
    }

    /// 失败恢复（以动作前的原帖整帖放回，呈现回到点
    /// 按前；帖已被新名单换掉时不强插）
    func restorePost(_ original: BridgeFeedPost) {
        posts = posts.map { $0.id == original.id ? original : $0 }
    }

    func clearLikeNotice() {
        likeNotice = nil
    }

    /// 点/取消点赞：目标态由当前态取反——**点按当拍
    /// 先翻本地呈现**，后台走桥幂等写（契约 rev2
    /// §1.9），回执到达整帖替换对账；失败恢复原帖＋
    /// 落轻提醒（likeNotice），不许再 try? 静默吞。
    /// 在飞期同帖连点忽略（防两次相反写竞态）
    func toggleLiked(appState: AppState, post: BridgeFeedPost) async {
        guard let config = appState.config,
              !likeInFlight.contains(post.id),
              let current = self.post(id: post.id) else { return }
        likeInFlight.insert(post.id)
        defer { likeInFlight.remove(post.id) }
        let target = !current.isLiked
        applyOptimisticLike(
            postID: post.id, liked: target,
            at: Date().timeIntervalSince1970
        )
        do {
            let settled = try await client.setFeedPostLiked(
                config: config, id: post.id, liked: target
            )
            settlePost(settled)
        } catch {
            restorePost(current)
            likeNotice = L10n.string("点赞没成功，请稍后再试。")
        }
    }

    // MARK: - 已读（§232 本地先行：先落呈现，后台确认）

    /// 本地先落已读（同步落点）：目标帖换已读副本＋
    /// 账面未读数即时按本地名单重算；重复调用幂等
    func applyLocalRead(postID: String, at ts: Double) {
        guard let current = post(id: postID), !current.isRead
        else { return }
        settlePost(current.markedRead(at: ts))
        if let gen = generation {
            generation = BridgeFeedGeneration(
                assembly: gen.assembly,
                morning: gen.morning,
                research: gen.research,
                unread: FeedBoard.unreadCount(posts)
            )
        }
    }

    /// 打开帖子即标记：**本地先落已读**（呈现与未读
    /// 数当拍生效），再向桥确认——回执到达整帖替换
    /// 对账；确认失败静默保留本地已读（低危纯呈现
    /// 态，下轮 load 以服务端名单纠正，不打扰用户）
    func markRead(appState: AppState, post: BridgeFeedPost) async {
        guard !post.isRead else { return }
        applyLocalRead(
            postID: post.id, at: Date().timeIntervalSince1970
        )
        guard let config = appState.config else { return }
        if let settled = try? await client.markFeedPostRead(
            config: config, id: post.id
        ) {
            settlePost(settled)
        }
    }
}
