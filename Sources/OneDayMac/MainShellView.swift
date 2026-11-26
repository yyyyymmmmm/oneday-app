import SwiftUI
import OneDayDesign

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

/// 三栏主窗（棒 1 做实聊天列）：NavigationSplitView
/// 三栏——侧边栏（一级项＋连接状态卡）、中栏（聊天
/// 时为会话列表，其余面占位明示棒次）、详情区（聊
/// 天面）。会话选中经列表店/会话店驱动聊天面打开。
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
    }

    // MARK: - 栏 1：侧边栏

    private var sidebar: some View {
        List(selection: $section) {
            Section {
                ForEach(
                    [MacSection.chat, .feed, .ideas, .goals, .files, .vault]
                ) { item in
                    HStack {
                        Label(item.title, systemImage: item.symbol)
                        if item == .chat, listStore.totalUnread > 0 {
                            Spacer()
                            Text("\(listStore.totalUnread)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Palette.primary, in: Capsule()
                                )
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
            .navigationSplitViewColumnWidth(
                min: 240, ideal: 300, max: 380
            )
        case .vault:
            MacVaultView(
                store: vaultStore, selection: $vaultSelection
            )
            .navigationSplitViewColumnWidth(
                min: 240, ideal: 300, max: 380
            )
        case .hub:
            ContentUnavailableView(
                "枢纽",
                systemImage: MacSection.hub.symbol,
                description: Text("工作／审计／电脑／身份／邮件五面在枢纽棒接入。")
            )
        default:
            ContentUnavailableView(
                (section ?? .chat).title,
                systemImage: (section ?? .chat).symbol,
                description: Text("本面列表在后续棒按对位表接入。")
            )
        }
    }

    // MARK: - 栏 3：详情区

    @ViewBuilder
    private var detailColumn: some View {
        if section == .chat {
            MacChatView(
                conversation: conversation, listStore: listStore
            )
        } else if section == .vault {
            MacVaultDetailView(
                store: vaultStore, selection: vaultSelection
            )
        } else {
            ContentUnavailableView(
                (section ?? .chat).title,
                systemImage: (section ?? .chat).symbol,
                description: Text("本面在后续棒按对位表接入。")
            )
        }
    }

}
