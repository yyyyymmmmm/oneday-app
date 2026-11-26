import SwiftUI
import OneDayCore

/// 动态列表（棒 3，对位 #2/#34）：近 30 天帖流中栏
/// ——晨报＋汇编双生产者同流（kind 徽标分型）、未读
/// 点、点赞态；工具栏带刷新/立即生成/简报三动作。
struct MacFeedView: View {
    @Environment(SessionStore.self) private var session
    var store: MacFeedStore
    @Binding var selection: String?
    @State private var showBrief = false

    var body: some View {
        Group {
            if let error = store.loadError, store.posts.isEmpty {
                ContentUnavailableView {
                    Label("动态加载失败", systemImage: "newspaper")
                } description: {
                    Text(error)
                } actions: {
                    Button("重试") {
                        Task { await store.refresh(session: session) }
                    }
                }
            } else if store.loaded && store.posts.isEmpty {
                ContentUnavailableView(
                    "暂无动态",
                    systemImage: "newspaper",
                    description: Text("近 30 天还没有动态帖。")
                )
            } else {
                List(store.posts, selection: $selection) { post in
                    row(post)
                        .tag(post.id)
                }
                .listStyle(.inset)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    Task { await store.generateNow(session: session) }
                } label: {
                    Label("立即生成", systemImage: "sparkles")
                }
                .help("手动起一轮调研")
                Button { showBrief = true } label: {
                    Label("简报", systemImage: "doc.text")
                }
                .help("查看/编辑动态简报")
                Button {
                    Task { await store.refresh(session: session) }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
            }
        }
        .sheet(isPresented: $showBrief) {
            MacBriefView(store: store)
        }
        .task {
            if !store.loaded {
                await store.refresh(session: session)
            }
        }
    }

    private func row(_ post: BridgeFeedPost) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(post.isRead ? Color.clear : Color.accentColor)
                .frame(width: 8, height: 8)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(Self.kindLabel(post.kind))
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            Color.secondary.opacity(0.15),
                            in: Capsule()
                        )
                    Text(post.title.isEmpty ? "（无标题）" : post.title)
                        .font(.body.weight(post.isRead ? .regular : .semibold))
                        .lineLimit(2)
                }
                HStack(spacing: 6) {
                    if !post.displayEmoji.isEmpty {
                        Text(post.displayEmoji)
                    }
                    Text(MacTimeText.short(post.createdAt))
                    if let name = post.sourceCard?.name,
                       !name.isEmpty {
                        Text(name).lineLimit(1)
                    }
                    if post.isLiked {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(.red)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    static func kindLabel(_ kind: FeedPostKind) -> String {
        switch kind {
        case .morning: return "晨报"
        case .digest: return "汇编"
        case .research: return "调研"
        case .event: return "事件"
        case .seed: return "种子"
        case .unknown: return "动态"
        }
    }
}
