import Foundation
import Observation
import OneDayCore

/// 动态状态店（棒 3，对位 #2/#34）：帖流（晨报＋汇
/// 编双生产者同流）＋简报全文。点赞/已读以桥回执全
/// 形为唯一真源（契约口径），不本地拼装假状态。
@MainActor
@Observable
final class MacFeedStore {
    private(set) var posts: [BridgeFeedPost] = []
    private(set) var brief: BridgeBriefDoc?
    private(set) var loading = false
    private(set) var loaded = false
    var loadError: String?
    var actionNote: String?

    var unreadCount: Int { posts.filter { !$0.isRead }.count }

    func refresh(session: SessionStore) async {
        guard !loading else { return }
        guard session.isConnected, let config = session.config,
              let key = session.apiKey else {
            posts = []
            return
        }
        loading = true
        loadError = nil
        defer { loading = false }
        do {
            posts = try await session.chatClient.feedPosts(
                config: config, apiKey: key
            )
        } catch let error as HermesError {
            loadError = error.userMessage
        } catch {
            loadError = "动态加载失败"
        }
        if let doc = try? await session.chatClient.feedBrief(
            config: config, apiKey: key
        ) {
            brief = doc
        }
        loaded = true
    }

    /// 点赞切换：回执整帖替换（likedAt 以桥落字为准）
    func toggleLike(session: SessionStore, post: BridgeFeedPost) async {
        guard let config = session.config, let key = session.apiKey
        else { return }
        do {
            let settled = try await session.chatClient.feedSetLiked(
                config: config, apiKey: key, id: post.id,
                liked: !post.isLiked
            )
            replace(settled)
        } catch let error as HermesError {
            actionNote = error.userMessage
        } catch {
            actionNote = "点赞失败"
        }
    }

    /// 打开帖即已读：回执整帖替换（readAt 以桥落字为准）
    func markRead(session: SessionStore, post: BridgeFeedPost) async {
        guard !post.isRead, let config = session.config,
              let key = session.apiKey else { return }
        if let settled = try? await session.chatClient.feedMarkRead(
            config: config, apiKey: key, id: post.id
        ) {
            replace(settled)
        }
    }

    /// 保存简报全文：回执为保存后全文（含润色状态）
    func saveBrief(session: SessionStore, text: String) async -> Bool {
        guard let config = session.config, let key = session.apiKey
        else { return false }
        do {
            brief = try await session.chatClient.saveFeedBrief(
                config: config, apiKey: key, text: text
            )
            return true
        } catch let error as HermesError {
            actionNote = error.userMessage
            return false
        } catch {
            actionNote = "简报保存失败"
            return false
        }
    }

    /// 手动起一轮调研：在跑时桥回 409，文案原样上呈
    func generateNow(session: SessionStore) async {
        guard let config = session.config, let key = session.apiKey
        else { return }
        do {
            try await session.chatClient.generateFeed(
                config: config, apiKey: key
            )
            actionNote = "已起一轮调研，稍后刷新可见新帖"
        } catch let error as HermesError {
            actionNote = error.userMessage
        } catch {
            actionNote = "生成失败"
        }
    }

    private func replace(_ post: BridgeFeedPost) {
        guard let index = posts.firstIndex(where: { $0.id == post.id })
        else { return }
        posts[index] = post
    }
}
