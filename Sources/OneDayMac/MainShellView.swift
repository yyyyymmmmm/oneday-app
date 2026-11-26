import SwiftUI
import OneDayDesign
import OneDayCore

/// 一级项（拟案信息架构）：iOS 底栏五格＋凭据库提级
/// ＋枢纽，逐件对位表落点见 docs/mac-parity.md
enum MacSection: String, CaseIterable, Identifiable {
    case chat
    case feed
    case ideas
    case goals
    case files
    case vault
    case hub

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chat: return "聊天"
        case .feed: return "动态"
        case .ideas: return "想法"
        case .goals: return "目标"
        case .files: return "文件"
        case .vault: return "凭据库"
        case .hub: return "枢纽"
        }
    }

    var symbol: String {
        switch self {
        case .chat: return "bubble.left.and.bubble.right"
        case .feed: return "newspaper"
        case .ideas: return "lightbulb"
        case .goals: return "target"
        case .files: return "folder"
        case .vault: return "key"
        case .hub: return "point.3.connected.trianglepath.dotted"
        }
    }
}

/// 三栏主窗：NavigationSplitView 三栏——侧边栏（一
/// 级项＋连接状态卡）、中栏（随一级项切换的列表）、
/// 详情区。棒 3 做实动态/想法/目标/文件四面（对位
/// #2–#5/#34–#38）＋全局搜索（#10）唤出与落点。
struct MainShellView: View {
    @Environment(SessionStore.self) private var session
    @Environment(MacStatusStore.self) private var statusStore
    @Environment(MacApprovalStore.self) private var approvalStore
    @Environment(MacVaultStore.self) private var vaultStore
    @State private var section: MacSection? = .chat
    @State private var listStore = MacSessionListStore()
    @State private var conversation = MacConversationStore()
    @State private var selectedSessionID: String?
    @State private var vaultSelection: MacVaultSelection?
    // 棒 3 四面：状态店与选中态
    @State private var feedStore = MacFeedStore()
    @State private var ideasStore = MacIdeasStore()
    @State private var goalsStore = MacGoalsStore()
    @State private var filesStore = MacFilesStore()
    @State private var feedSelection: String?
    @State private var ideaSelection: String?
    @State private var goalSelection: String?
    @State private var fileSelection: String?
    @State private var showSearch = false

    var body: some View {
        NavigationSplitView {
            sidebar
        } content: {
            contentColumn
        } detail: {
            detailColumn
        }
        .frame(minWidth: 980, minHeight: 620)
        .onChange(of: selectedSessionID) { _, newID in
            guard let newID,
                  let target = (listStore.sessions
                      + listStore.archivedSessions)
                      .first(where: { $0.id == newID })
            else { return }
            Task {
                await conversation.open(
                    target, from: session, listStore: listStore
                )
            }
        }
        .onChange(of: section) { _, newSection in
            if newSection != .chat {
                conversation.saveDraft()
            }
        }
        .onChange(of: listStore.totalUnread) { _, newValue in
            statusStore.noteUnread(newValue)
        }
        .task {
            statusStore.noteUnread(listStore.totalUnread)
        }
        .sheet(isPresented: $showSearch) {
            MacSearchView(
                filesStore: filesStore,
                onOpenSession: { id in
                    showSearch = false
                    openSession(id)
                },
                onOpenFile: { path in
                    showSearch = false
                    section = .files
                    fileSelection = path
                },
                onClose: { showSearch = false }
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .macOpenGlobalSearch)) { _ in
            showSearch = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .macOpenSession)) { note in
            if let id = note.userInfo?["sessionID"] as? String {
                openSession(id)
            }
        }
    }

    /// 打开会话落点（搜索命中/速记窗共用）：先回读列
    /// 表再选中，onChange 承接打开
    private func openSession(_ id: String) {
        section = .chat
        Task {
            if !(listStore.sessions + listStore.archivedSessions)
                .contains(where: { $0.id == id }) {
                await listStore.load(from: session)
            }
            selectedSessionID = id
        }
    }

    /// 引用到聊天落点（#34/§208）：切聊天面、起新对
    /// 话、引用挂发送舱（startNew 后写，防被清）
    private func quoteToChat(_ post: BridgeFeedPost) {
        section = .chat
        selectedSessionID = nil
        conversation.startNew()
        conversation.pendingFeedQuote = FeedPostQuote(post: post)
    }

    // MARK: - 栏 1：侧边栏

    private var sidebar: some View {
        List(selection: $section) {
            Section {
                ForEach([MacSection.chat, .feed, .ideas, .goals, .files, .vault]) { item in
                    HStack {
                        Label(item.title, systemImage: item.symbol)
                        if badgeCount(for: item) > 0 {
                            Spacer()
                            Text("\(badgeCount(for: item))")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Palette.primary, in: Capsule())
                        }
                    }
                    .tag(item)
                }
            }
            Section("频道") {
                Text("暂无频道")
                    .foregroundStyle(.tertiary)
            }
            Section("旁聊") {
                Text("暂无旁聊")
                    .foregroundStyle(.tertiary)
            }
            Section {
                Label(MacSection.hub.title, systemImage: MacSection.hub.symbol)
                    .tag(MacSection.hub)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top) {
            connectionCard
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
    }

    private func badgeCount(for item: MacSection) -> Int {
        switch item {
        case .chat: return listStore.totalUnread
        case .feed: return feedStore.unreadCount
        default: return 0
        }
    }

    /// 侧边栏顶：当前服务器＋健康点（拟案信息架构：
    /// 连接状态卡是侧边栏第一件）
    private var connectionCard: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.green)
                .frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 1) {
                Text(session.config?.host ?? "已连接")
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text("已连接")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - 栏 2：列表列

    @ViewBuilder
    private var contentColumn: some View {
        switch section ?? .chat {
        case .chat:
            MacSessionListView(
                listStore: listStore,
                selectedSessionID: $selectedSessionID,
                onSelect: { _ in },
                onNew: {
                    selectedSessionID = nil
                    conversation.startNew()
                }
            )
            .navigationSplitViewColumnWidth(min: 240, ideal: 300, max: 380)
        case .feed:
            MacFeedView(store: feedStore, selection: $feedSelection)
                .navigationSplitViewColumnWidth(
                    min: 260, ideal: 320, max: 400
                )
        case .ideas:
            MacIdeasView(store: ideasStore, selection: $ideaSelection)
                .navigationSplitViewColumnWidth(
                    min: 260, ideal: 320, max: 400
                )
        case .goals:
            MacGoalsView(store: goalsStore, selection: $goalSelection)
                .navigationSplitViewColumnWidth(
                    min: 260, ideal: 320, max: 400
                )
        case .files:
            MacFilesView(store: filesStore, selection: $fileSelection)
                .navigationSplitViewColumnWidth(
                    min: 260, ideal: 320, max: 400
                )
        case .vault:
            MacVaultView(store: vaultStore, selection: $vaultSelection)
                .navigationSplitViewColumnWidth(min: 240, ideal: 300, max: 380)
        case .hub:
            ContentUnavailableView(
                "枢纽",
                systemImage: MacSection.hub.symbol,
                description: Text("工作／审计／电脑／身份／邮件五面在枢纽棒接入。")
            )
        }
    }

    // MARK: - 栏 3：详情区

    @ViewBuilder
    private var detailColumn: some View {
        switch section ?? .chat {
        case .chat:
            MacChatView(conversation: conversation, listStore: listStore)
        case .feed:
            MacFeedDetailView(
                store: feedStore, postID: feedSelection,
                onQuoteToChat: quoteToChat
            )
        case .ideas:
            MacIdeaDetailView(
                store: ideasStore, ideaID: ideaSelection,
                selection: $ideaSelection
            )
        case .goals:
            MacGoalDetailView(
                store: goalsStore, goalID: goalSelection,
                selection: $goalSelection
            )
        case .files:
            MacFileDetailView(store: filesStore, path: fileSelection)
        case .vault:
            MacVaultDetailView(store: vaultStore, selection: vaultSelection)
        case .hub:
            ContentUnavailableView(
                "枢纽",
                systemImage: MacSection.hub.symbol,
                description: Text("本面在枢纽棒按对位表接入。")
            )
        }
    }
}
