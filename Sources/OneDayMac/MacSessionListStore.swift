import Foundation
import Observation
import OneDayCore

/// 会话列表店（棒 1，对位 #9）：经现行网关 API 拉真
/// 实会话（可见段＋归档段分开拉），搜索本地过滤，置
/// 顶/归档/删除/改名一律走服务端围栏写口（客户端
/// HermesMacClient 同 iOS 口径），落定后回读对账。
/// 已读账本地记：每会话记「最后一次打开时见到的消
/// 息数」，列表未读数＝服务端消息数－已读数（与
/// iOS 已读账同义的 Mac 形态）。
@MainActor
@Observable
final class MacSessionListStore {
    private(set) var sessions: [ServerSession] = []
    private(set) var archivedSessions: [ServerSession] = []
    private(set) var isLoading = false
    var loadError: String?
    var searchText = ""
    var showArchived = false

    private(set) var readCounts: [String: Int] = [:]
    private let readCountsKey = "mac.readCounts.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: readCountsKey),
           let decoded = try? JSONDecoder().decode(
               [String: Int].self, from: data
           ) {
            readCounts = decoded
        }
    }

    // MARK: - 呈现口径

    /// 标题单口径：服务端标题 → 渠道显示名 → 占位
    static func titleText(for session: ServerSession) -> String {
        if let title = session.serverTitle?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty {
            return title
        }
        if let name = session.displayName?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return name
        }
        return "新对话"
    }

    /// 当前段经搜索过滤后的列表：置顶在前、段内按
    /// 开始时间倒序（与 iOS 列表同序）
    var visibleSessions: [ServerSession] {
        let base = showArchived ? archivedSessions : sessions
        let query = searchText.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).lowercased()
        let filtered = query.isEmpty ? base : base.filter {
            Self.titleText(for: $0).lowercased().contains(query)
                || ($0.model?.lowercased().contains(query) ?? false)
        }
        return filtered.sorted { a, b in
            let pinA = a.isPinned == true
            let pinB = b.isPinned == true
            if pinA != pinB { return pinA }
            return (a.startedAt ?? 0) > (b.startedAt ?? 0)
        }
    }

    func unreadCount(for session: ServerSession) -> Int {
        guard let total = session.messageCount else { return 0 }
        return max(0, total - (readCounts[session.id] ?? 0))
    }

    var totalUnread: Int {
        sessions.reduce(0) { $0 + unreadCount(for: $1) }
    }

    /// 打开会话时落已读账（消息数以服务端行为准）
    func markRead(_ session: ServerSession) {
        guard let total = session.messageCount else { return }
        readCounts[session.id] = total
        persistReadCounts()
    }

    /// 消息落定后按真实行数校准已读账（会话店回调用）
    func markRead(sessionID: String, messageCount: Int) {
        readCounts[sessionID] = messageCount
        persistReadCounts()
    }

    private func persistReadCounts() {
        if let data = try? JSONEncoder().encode(readCounts) {
            UserDefaults.standard.set(data, forKey: readCountsKey)
        }
    }

    // MARK: - 拉取

    func load(from session: SessionStore) async {
        guard let config = session.config, let key = session.apiKey
        else { return }
        isLoading = true
        loadError = nil
        do {
            let visible = try await session.chatClient.sessionsPage(
                config: config, apiKey: key, limit: 200, offset: 0,
                archived: "exclude"
            )
            let archived = try await session.chatClient.sessionsPage(
                config: config, apiKey: key, limit: 200, offset: 0,
                archived: "only"
            )
            sessions = visible.sessions
            archivedSessions = archived.sessions
        } catch let error as HermesError {
            loadError = error.userMessage
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - 写动作（围栏写口在客户端内，落定回读）

    private func mutate(
        from session: SessionStore,
        _ body: (HermesMacClient, ServerConfig, String) async throws -> Void,
        target: ServerSession
    ) async {
        guard let config = session.config, let key = session.apiKey
        else { return }
        do {
            try await body(session.chatClient, config, key)
            await load(from: session)
        } catch let error as HermesError {
            loadError = error.userMessage
        } catch {
            loadError = error.localizedDescription
        }
        _ = target
    }

    func togglePin(_ target: ServerSession, from session: SessionStore) {
        Task {
            await mutate(from: session, { client, config, key in
                try await client.updateSession(
                    config: config, apiKey: key, id: target.id,
                    title: nil, pinned: !(target.isPinned == true),
                    archived: nil
                )
            }, target: target)
        }
    }

    func setArchived(
        _ target: ServerSession, archived: Bool,
        from session: SessionStore
    ) {
        Task {
            await mutate(from: session, { client, config, key in
                try await client.updateSession(
                    config: config, apiKey: key, id: target.id,
                    title: nil, pinned: nil, archived: archived
                )
            }, target: target)
        }
    }

    func rename(
        _ target: ServerSession, title: String,
        from session: SessionStore
    ) {
        Task {
            await mutate(from: session, { client, config, key in
                try await client.updateSession(
                    config: config, apiKey: key, id: target.id,
                    title: title, pinned: nil, archived: nil
                )
            }, target: target)
        }
    }

    func delete(_ target: ServerSession, from session: SessionStore) {
        Task {
            await mutate(from: session, { client, config, key in
                try await client.deleteSession(
                    config: config, apiKey: key, id: target.id
                )
            }, target: target)
        }
    }

    /// 新建会话：服务端建行（不带标题，两段式标题由
    /// 首轮内容自生，与 iOS 建旁聊同口径），回执 id
    /// 为准、建成即回读列表
    func create(from session: SessionStore) async -> ServerSession? {
        guard let config = session.config, let key = session.apiKey
        else { return nil }
        do {
            let created = try await session.chatClient.createSession(
                config: config, apiKey: key, id: UUID().uuidString,
                title: nil
            )
            await load(from: session)
            return created
        } catch let error as HermesError {
            loadError = error.userMessage
            return nil
        } catch {
            loadError = error.localizedDescription
            return nil
        }
    }
}
