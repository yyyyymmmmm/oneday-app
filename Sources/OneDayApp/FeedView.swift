import OneDayCore
import OneDayDesign
import SwiftUI

/// 动态格（P3，0.35.0）：形态按设计档第三章向 Muse
/// 动态页收——大标题下简报胶囊（今日汇编摘要＋未读
/// 数，点开落对应帖）、帖子扁平排版（kind 瓷砖＋标
/// 题＋正文摘＋refs 蓝字内链＋相对时间）、按日分组。
/// 数据口径：双生产者在桥端（段一确定性汇编＋段二
/// 晨报），App 只读＋已读回写；已读以服务端 readAt
/// 为真源。空态二分如实（从未产出/今日无素材），不
/// 许假帖填充。refs 点达对象详情走本栈复用各详情页。
struct FeedView: View {
    @Environment(AppState.self) private var appState
    @State private var store = FeedStore()
    /// refs 点达与标题解析的数据源（与点子/目标格同
    /// 一套 Store，本格持有自己的实例、按需加载）
    @State private var ideasStore = IdeasStore()
    @State private var goalsStore = GoalsStore()
    @State private var kanban = KanbanStore()
    @State private var monitorsStore = MonitorsStore()
    @State private var path = NavigationPath()

    enum Route: Hashable {
        case post(String)
        case ref(BridgeFeedRef)
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                switch store.loadState {
                case .loading:
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .notConnected(let message):
                    ContentUnavailableView {
                        Label("数据桥未连接", systemImage: "link.badge.plus")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("重新检查") {
                            Task { await reload() }
                        }
                        .buttonStyle(.bordered)
                    }
                case .failed(let message):
                    ContentUnavailableView {
                        Label("动态读取失败", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("重试") {
                            Task { await reload() }
                        }
                        .buttonStyle(.bordered)
                    }
                case .ready:
                    readyContent
                }
            }
            .background(Palette.pageBG)
            .navigationTitle("动态")
            .task {
                await reload()
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .post(let id):
                    FeedPostDetailView(store: store, postID: id) { ref in
                        path.append(Route.ref(ref))
                    }
                case .ref(let ref):
                    refDestination(ref)
                }
            }
        }
    }

    private func reload() async {
        await store.load(appState: appState)
        // refs 标题解析面：失败只降级为类别文案，不挡帖子
        async let ideas: Void = ideasStore.load(appState: appState)
        async let goals: Void = goalsStore.load(appState: appState)
        async let board: Void = kanban.load(appState: appState)
        async let monitors: Void = monitorsStore.load(appState: appState)
        _ = await (ideas, goals, board, monitors)
    }

    // MARK: - 就绪内容

    @ViewBuilder
    private var readyContent: some View {
        if store.posts.isEmpty {
            switch store.emptyKind {
            case .neverProduced:
                ContentUnavailableView(
                    "动态刚上线",
                    systemImage: "newspaper",
                    description: Text(
                        "站内有新点子、新简报或任务变化时，这里会先汇编一篇；第一篇晨报明早 8:30 到。"
                    )
                )
            case .quiet:
                ContentUnavailableView(
                    "近来没有新动态",
                    systemImage: "moon.zzz",
                    description: Text(
                        "今天没有值得汇编的事，晨报也还没有新一篇；有动静时这里会先更新。"
                    )
                )
            }
        } else {
            List {
                Section {
                    capsuleRow
                }
                .listRowSeparator(.hidden)

                ForEach(store.dayGroups, id: \.title) { group in
                    Section(group.title) {
                        ForEach(group.posts) { post in
                            postRow(post)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .refreshable {
                await reload()
            }
        }
    }

    /// 简报胶囊：今日汇编摘要＋未读数，点开落对应帖
    /// （落点口径在 FeedBoard.capsulePost）；无帖时只
    /// 显今日暂无、不做假入口
    private var capsuleRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "newspaper")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(Palette.inkSecondary)
            if let post = store.capsulePost {
                Text(post.title)
                    .font(.subheadline)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
            } else {
                Text("今日暂无动态")
                    .font(.subheadline)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
            }
            Spacer()
            if store.unreadCount > 0 {
                Text("\(store.unreadCount) 未读")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Palette.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Palette.selectionFill,
                        in: Capsule()
                    )
            }
            if store.capsulePost != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16))
        .contentShape(Rectangle())
        .onTapGesture {
            if let post = store.capsulePost {
                path.append(Route.post(post.id))
            }
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
    }

    /// 帖子扁平行：kind 瓷砖＋标题（未读点）＋正文摘
    /// ＋refs 蓝字内链＋动作行（类别左、相对时间右）
    private func postRow(_ post: BridgeFeedPost) -> some View {
        HStack(alignment: .top, spacing: 12) {
            kindTile(post.kind)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .top, spacing: 6) {
                    Text(post.title)
                        .font(.headline)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(2)
                    if !post.isRead {
                        Circle()
                            .fill(Palette.primary)
                            .frame(width: 7, height: 7)
                            .padding(.top, 6)
                    }
                }
                if !post.body.isEmpty {
                    Text(FeedBoard.excerpt(post.body))
                        .font(.subheadline)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(3)
                }
                if !post.refs.isEmpty {
                    refsRow(post.refs)
                }
                HStack {
                    Text(post.kind.label)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                    Spacer()
                    Text(FeedBoard.relativeText(
                        for: post.createdAt, now: Date()
                    ))
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            path.append(Route.post(post.id))
        }
    }

    private func kindTile(_ kind: FeedPostKind) -> some View {
        RoundedRectangle(cornerRadius: 9)
            .fill(Palette.selectionFill)
            .frame(width: 34, height: 34)
            .overlay {
                Image(systemName: kind.symbolName)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Palette.ink)
            }
    }

    /// refs 蓝字内链：横滑小链，点达对象详情（标题
    /// 解析不到时回类别文案，不编名）
    private func refsRow(_ refs: [BridgeFeedRef]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(
                    Array(refs.enumerated()), id: \.offset
                ) { _, ref in
                    if ref.refType != nil {
                        Button {
                            path.append(Route.ref(ref))
                        } label: {
                            HStack(spacing: 4) {
                                Image(
                                    systemName: ref.refType!.symbolName
                                )
                                .font(.system(size: 11))
                                Text(refLabel(ref))
                                    .lineLimit(1)
                            }
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Palette.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func refLabel(_ ref: BridgeFeedRef) -> String {
        switch ref.refType {
        case .idea:
            return ideasStore.ideas.first { $0.id == ref.id }?.title
                ?? "点子"
        case .goal:
            return goalsStore.goals.first { $0.id == ref.id }?.title
                ?? "目标"
        case .task:
            return kanban.snapshot?.tasks.first { $0.id == ref.id }?.title
                ?? "任务"
        case .monitor:
            return monitorsStore.monitors
                .first { $0.id == ref.id }?.name ?? "监测"
        case .briefing:
            if let gid = ref.goalId,
               let goal = goalsStore.goals.first(where: { $0.id == gid }) {
                return "《\(goal.title)》的简报"
            }
            return "目标简报"
        case nil:
            return "引用"
        }
    }

    // MARK: - refs 点达

    @ViewBuilder
    private func refDestination(_ ref: BridgeFeedRef) -> some View {
        switch ref.refType {
        case .idea:
            IdeaDetailView(
                store: ideasStore, kanban: kanban, ideaID: ref.id
            )
        case .goal:
            GoalDetailView(store: goalsStore, goalID: ref.id)
        case .briefing:
            if let gid = ref.goalId {
                GoalDetailView(store: goalsStore, goalID: gid)
            } else {
                ContentUnavailableView(
                    "简报所属目标已不在",
                    systemImage: "envelope.badge"
                )
            }
        case .task:
            KanbanTaskDetailView(store: kanban, taskID: ref.id)
        case .monitor:
            MonitorDetailView(store: monitorsStore, monitorID: ref.id)
        case nil:
            ContentUnavailableView(
                "引用已失效", systemImage: "link.badge.plus"
            )
        }
    }
}

/// 帖子详情：正文 Markdown 全文＋why＋链接清单＋引用
/// 列表；打开即已读（服务端真源，FeedStore.markRead
/// 以桥回执对账）
struct FeedPostDetailView: View {
    @Environment(AppState.self) private var appState
    let store: FeedStore
    let postID: String
    let onOpenRef: (BridgeFeedRef) -> Void

    var body: some View {
        Group {
            if let post = store.post(id: postID) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 8) {
                            Image(systemName: post.kind.symbolName)
                                .font(.system(size: 15))
                                .foregroundStyle(Palette.inkSecondary)
                            Text(post.kind.label)
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(Palette.inkSecondary)
                            Spacer()
                            Text(FeedBoard.relativeText(
                                for: post.createdAt, now: Date()
                            ))
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                        }
                        Text(post.title)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Palette.ink)
                        MarkdownText(post.body)
                        if let why = post.why, !why.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("为什么选这篇")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(Palette.inkSecondary)
                                Text(why)
                                    .font(.subheadline)
                                    .foregroundStyle(Palette.ink)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(
                                Palette.surface,
                                in: RoundedRectangle(cornerRadius: 12)
                            )
                        }
                        if !post.links.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("链接")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(Palette.inkSecondary)
                                ForEach(
                                    Array(post.links.enumerated()),
                                    id: \.offset
                                ) { _, link in
                                    if let url = URL(string: link.url) {
                                        Link(destination: url) {
                                            HStack(spacing: 6) {
                                                Image(
                                                    systemName: "link"
                                                )
                                                .font(.system(size: 12))
                                                Text(link.title.isEmpty
                                                     ? link.url : link.title)
                                                    .lineLimit(2)
                                                    .multilineTextAlignment(.leading)
                                            }
                                            .font(.subheadline)
                                            .foregroundStyle(Palette.primary)
                                        }
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if !post.refs.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("引用")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(Palette.inkSecondary)
                                ForEach(
                                    Array(post.refs.enumerated()),
                                    id: \.offset
                                ) { _, ref in
                                    if let type = ref.refType {
                                        Button {
                                            onOpenRef(ref)
                                        } label: {
                                            HStack(spacing: 6) {
                                                Image(
                                                    systemName: type.symbolName
                                                )
                                                .font(.system(size: 12))
                                                Text(type.label)
                                                Spacer()
                                                Image(
                                                    systemName: "chevron.right"
                                                )
                                                .font(.system(size: 11,
                                                                weight: .semibold))
                                            }
                                            .font(.subheadline)
                                            .foregroundStyle(Palette.primary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(16)
                }
                .background(Palette.pageBG)
                .task {
                    await store.markRead(appState: appState, post: post)
                }
            } else {
                ContentUnavailableView(
                    "帖子已不在",
                    systemImage: "newspaper",
                    description: Text("可能已过期或被删除。")
                )
            }
        }
        .navigationTitle("动态")
        .navigationBarTitleDisplayMode(.inline)
    }
}
