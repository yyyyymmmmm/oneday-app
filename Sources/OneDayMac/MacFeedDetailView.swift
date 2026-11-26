import SwiftUI
import OneDayCore

/// 动态详情（棒 3，对位 #34）：正文 Markdown 全文＋
/// why＋链接＋配图；动作＝点赞、引用到聊天（§208 引
/// 用化：FeedPostQuote 值快照挂发送舱，输入框恒空，
/// 不走已退役的草稿预填）。打开即已读（桥落字）。
struct MacFeedDetailView: View {
    @Environment(SessionStore.self) private var session
    var store: MacFeedStore
    let postID: String?
    /// 引用到聊天：宿主切聊天面并把引用挂上发送舱
    var onQuoteToChat: (BridgeFeedPost) -> Void

    private var post: BridgeFeedPost? {
        guard let postID else { return nil }
        return store.posts.first { $0.id == postID }
    }

    var body: some View {
        Group {
            if let post {
                ScrollView {
                    VStack(
                        alignment: .leading, spacing: 14
                    ) {
                        header(post)
                        MacMarkdownView(text: post.body)
                        if let why = post.why, !why.isEmpty {
                            VStack(
                                alignment: .leading, spacing: 4
                            ) {
                                Text("为什么推给你")
                                    .font(.headline)
                                Text(why)
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                        if !post.images.isEmpty {
                            images(post)
                        }
                        if !post.links.isEmpty {
                            links(post)
                        }
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .task(id: post.id) {
                    await store.markRead(session: session, post: post)
                }
            } else {
                ContentUnavailableView(
                    "选择一篇动态",
                    systemImage: "newspaper",
                    description: Text("在中间列表点开一篇，这里看全文。")
                )
            }
        }
    }

    private func header(_ post: BridgeFeedPost) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(MacFeedView.kindLabel(post.kind))
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Color.secondary.opacity(0.15), in: Capsule()
                    )
                Text(MacTimeText.full(post.createdAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let name = post.sourceCard?.name, !name.isEmpty {
                    Text(name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    Task {
                        await store.toggleLike(
                            session: session, post: post
                        )
                    }
                } label: {
                    Label(
                        post.isLiked ? "已赞" : "点赞",
                        systemImage: post.isLiked
                            ? "heart.fill" : "heart"
                    )
                }
                .foregroundStyle(post.isLiked ? .red : .primary)
                Button {
                    onQuoteToChat(post)
                } label: {
                    Label("引用到聊天", systemImage: "quote.bubble")
                }
            }
            Text(
                "\(post.displayEmoji.isEmpty ? "" : post.displayEmoji + " ")\(post.title)"
            )
            .font(.title3.weight(.bold))
            .textSelection(.enabled)
        }
    }

    private func images(_ post: BridgeFeedPost) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(
                Array(post.images.enumerated()), id: \.offset
            ) { _, image in
                AsyncImage(url: URL(string: image.url)) { phase in
                    switch phase {
                    case .success(let loaded):
                        loaded
                            .resizable()
                            .scaledToFit()
                            .clipShape(
                                RoundedRectangle(cornerRadius: 8)
                            )
                    default:
                        EmptyView()
                    }
                }
            }
        }
    }

    private func links(_ post: BridgeFeedPost) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("链接")
                .font(.headline)
            ForEach(
                Array(post.links.enumerated()), id: \.offset
            ) { _, link in
                if let url = URL(string: link.url) {
                    Link(destination: url) {
                        HStack(spacing: 6) {
                            Image(systemName: "link")
                            Text(
                                link.title.isEmpty
                                    ? link.url : link.title
                            )
                            .lineLimit(1)
                        }
                        .font(.callout)
                    }
                }
            }
        }
    }
}
