import OneDayCore
import OneDayDesign
import SwiftUI

/// 动态格（P3，0.35.0；0.38.0 换代）：形态按设计档
/// 第三章向 Muse 动态页收——大标题下简报行（兴趣
/// 摘要＋未读数，点开进简报编辑器）、帖子扁平排版
/// （kind 瓷砖＋标题＋正文摘＋真图缩略＋refs 蓝字内
/// 链＋相对时间）、按日分组。
/// 数据口径：双生产者在桥端（段一确定性汇编＋段二
/// 简报驱动的调研五步链），App 只读＋已读回写；已
/// 读以服务端 readAt 为真源。简报两层在编辑器里分
/// 开存分开改（兴趣层用户原话、执行层 AI 整理）。
/// 空态二分如实（从未产出/今日无素材），不许假帖
/// 填充。refs 点达对象详情走本栈复用各详情页。
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
    /// 简报编辑器（0.38.0 两层制）呈现
    @State private var briefEditorShown = false

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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        briefEditorShown = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .accessibilityLabel("编辑简报")
                }
            }
            .sheet(isPresented: $briefEditorShown) {
                FeedBriefEditorView(store: store)
            }
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
                    systemImage: "doc.text",
                    description: Text(
                        "写下你感兴趣什么，我每天替你去看；第一轮明早 8:30 到。站内的新点子、新简报也会汇编到这里。"
                    )
                )
            case .quiet:
                ContentUnavailableView(
                    "近来没有新动态",
                    systemImage: "moon.zzz",
                    description: Text(
                        "今天没有值得一提的新发现；有动静时这里会先更新。"
                    )
                )
            }
        } else {
            List {
                Section {
                    if let doc = store.briefDoc {
                        briefRow(doc)
                    } else {
                        capsuleRow
                    }
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

    /// 横幅行共用外壳（0.41.0 收口批 P4）：胶囊行与简
    /// 报行原各写一套 spacing 10／横 padding 14／纵 12
    /// ／圆角 16／insets 6·16 的自定值——收成一处：
    /// 横 padding 走 spacingM（14→16、与页面行内容缘
    /// 同线）、纵 spacingSM、圆角 radiusPreview、行间
    /// 距走 cardInnerGap（消费点 HStack）
    private func bannerRowChrome<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(.horizontal, OneDayMetrics.spacingM)
            .padding(.vertical, OneDayMetrics.spacingSM)
            .background(
                Palette.surface,
                in: RoundedRectangle(
                    cornerRadius: OneDayMetrics.radiusPreview
                )
            )
            .contentShape(Rectangle())
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(
                top: OneDayMetrics.rowInnerGap,
                leading: OneDayMetrics.spacingM,
                bottom: OneDayMetrics.rowInnerGap,
                trailing: OneDayMetrics.spacingM
            ))
    }

    /// 简报胶囊：今日汇编摘要＋未读数，点开落对应帖
    /// （落点口径在 FeedBoard.capsulePost）；无帖时只
    /// 显今日暂无、不做假入口
    private var capsuleRow: some View {
        bannerRowChrome {
        HStack(spacing: OneDayMetrics.cardInnerGap) {
            Image(systemName: "doc.text")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(Palette.inkSecondary)
            if let post = store.capsulePost {
                Text(post.title)
                    .font(.subheadline)
                    .foregroundStyle(Palette.ink)
                    // 0.43.0（A11Y-D3）：AX 档放宽行数
                    .a11yLineLimit(1, ax: 2)
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
                    .padding(.vertical, OneDayMetrics.stackGap)
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
        }
        .onTapGesture {
            if let post = store.capsulePost {
                path.append(Route.post(post.id))
            }
        }
        // 0.43.0（A11Y-V4）：整行合并为一个元素——
        // 拼读序：题→未读数（C5 文字已在行内）；有
        // 帖时才是按钮（无帖行只是状态陈述、不给假
        // 按钮语义），默认动作与点按同一落点
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(
            store.capsulePost != nil ? .isButton : []
        )
        .accessibilityAction {
            if let post = store.capsulePost {
                path.append(Route.post(post.id))
            }
        }
    }

    /// 简报行（0.38.0）：兴趣摘要＋未读数，点开进简
    /// 报编辑器（两层制）；还没写过兴趣时走引导文案。
    /// 旧胶囊的「点开落帖」自此退役——这一行只管简报
    private func briefRow(_ doc: BridgeBriefDoc) -> some View {
        bannerRowChrome {
        HStack(spacing: OneDayMetrics.cardInnerGap) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Palette.inkSecondary)
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                if let line = FeedBriefBoard.summaryLine(doc) {
                    Text(line)
                        .font(.subheadline)
                        .foregroundStyle(Palette.ink)
                        // 0.43.0（A11Y-D3）：AX 档放宽
                        .a11yLineLimit(1, ax: 2)
                    Text("我的简报 · 点按编辑")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                } else {
                    Text("写下你感兴趣什么，我每天替你去看")
                        .font(.subheadline)
                        .foregroundStyle(Palette.ink)
                        // 0.43.0（A11Y-D3）：AX 档放宽
                        .a11yLineLimit(1, ax: 2)
                    Text("点按写简报")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if doc.expanding {
                ProgressView()
                    .controlSize(.small)
            }
            if store.unreadCount > 0 {
                Text("\(store.unreadCount) 未读")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Palette.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, OneDayMetrics.stackGap)
                    .background(
                        Palette.selectionFill,
                        in: Capsule()
                    )
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.inkSecondary)
        }
        }
        .onTapGesture {
            briefEditorShown = true
        }
        // 0.43.0（A11Y-V4）：整行合并为按钮元素（拼
        // 读：摘要→说明→未读数），默认动作与点按同
        // 一入口（开简报编辑器）
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            briefEditorShown = true
        }
    }

    /// 帖子扁平行：kind 瓷砖＋标题（未读点）＋正文摘
    /// ＋refs 蓝字内链＋动作行（类别左、相对时间右）
    private func postRow(_ post: BridgeFeedPost) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // 类别字形瓷砖是装饰（类别词在动作行有文
            // 字）——0.43.0（A11Y-V4）对 VO 隐藏
            kindTile(post.kind)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: OneDayMetrics.iconTextGap) {
                // 0.43.0（A11Y-V4）：题＋摘拆成独立合并
                // 元素——整行不再是一个含内链的巨型元
                // 素：题摘合读、自成按钮开帖；refs 内
                // 链与动作行留在元素外各自可达。内层
                // 间距与外层同值，几何逐字不变
                VStack(
                    alignment: .leading,
                    spacing: OneDayMetrics.iconTextGap
                ) {
                    HStack(alignment: .top, spacing: OneDayMetrics.rowInnerGap) {
                        Text(post.title)
                            // 0.41.0（收口批 C14）：行题回收
                            // 角色表——.headline（17 semibold）
                            // 与 Body regular 双轨并存是本条病
                            // 灶，同点子行一并归 .rowTitle
                            .font(.rowTitle)
                            .foregroundStyle(Palette.ink)
                            // 0.43.0（A11Y-D3）：AX 档放宽
                            .a11yLineLimit(2, ax: 4)
                        if !post.isRead {
                            Circle()
                                .fill(Palette.primary)
                                .frame(width: 7, height: 7)
                                .padding(.top, OneDayMetrics.rowInnerGap)
                                // 未读状态字在下方动作行
                                // （C5 已落）——蓝点对 VO
                                // 隐藏、免同义双报
                                .accessibilityHidden(true)
                        }
                    }
                    if !post.body.isEmpty {
                        Text(FeedBoard.excerpt(post.body))
                            .font(.subheadline)
                            .foregroundStyle(Palette.inkSecondary)
                            // 0.43.0（A11Y-D3）：AX 档放宽
                            .a11yLineLimit(3, ax: 6)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction {
                    path.append(Route.post(post.id))
                }
                if !post.refs.isEmpty {
                    refsRow(post.refs)
                }
                HStack {
                    Text(post.kind.label)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                    if let direction = post.direction,
                       !direction.isEmpty {
                        Text(direction)
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                            .lineLimit(1)
                    }
                    // 0.36.0（无障碍 A11Y-C5）：未读除蓝
                    // 点外补文字通道——不靠颜色单独传信
                    // 息，VoiceOver/色弱下同样可辨
                    if !post.isRead {
                        Text("未读")
                            .font(.footnote)
                            .foregroundStyle(Palette.primary)
                    }
                    Spacer()
                    Text(FeedBoard.relativeText(
                        for: post.createdAt, now: Date()
                    ))
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                }
                // 0.43.0（A11Y-V4）：动作行自成合并元素
                // （类别→未读→时间一次读完）
                .accessibilityElement(children: .combine)
            }
            // 配图缩略（0.38.0）：只显第一张来源真图；
            // 无图不占位，行高不为图让路
            if let first = post.images.first,
               let url = URL(string: first.url) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        Palette.surface
                    }
                }
                .frame(width: 54, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: OneDayMetrics.radiusThumb))
                // 0.43.0（A11Y-V4）：配图缩略是帖的装
                // 饰预览（点开帖内有大图与来源）——
                // 对 VO 隐藏，不冒充内容
                .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            path.append(Route.post(post.id))
        }
    }

    private func kindTile(_ kind: FeedPostKind) -> some View {
        RoundedRectangle(cornerRadius: OneDayMetrics.radiusTile)
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
            HStack(spacing: OneDayMetrics.spacingSM) {
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
                            // 0.41.0（C14/P5）：字面量收编
                            // 内容标题定点 FontRoles
                            // .contentTitle（值不变）
                            .font(.contentTitle)
                            .foregroundStyle(Palette.ink)
                        // 整幅图（0.38.0）：第一张来源真图；
                        // 加载失败/无图整块不显，不摆假图
                        if let first = post.images.first,
                           let url = URL(string: first.url) {
                            AsyncImage(url: url) { phase in
                                if case .success(let image) = phase {
                                    image
                                        .resizable()
                                        .scaledToFit()
                                }
                            }
                            .clipShape(
                                RoundedRectangle(cornerRadius: OneDayMetrics.radiusCard)
                            )
                            // 0.43.0（A11Y-V2）：详情大图的
                            // 文本等价——以图片 URL 文件名
                            // 为最低口径（A11yText 拼装）
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(
                                A11yText.imageLabel(
                                    fileName: url.lastPathComponent
                                )
                            )
                        }
                        MarkdownText(post.body)
                        if let why = post.why, !why.isEmpty {
                            VStack(alignment: .leading, spacing: OneDayMetrics.rowInnerGap) {
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
                                in: RoundedRectangle(cornerRadius: OneDayMetrics.radiusCard)
                            )
                        }
                        if let card = post.sourceCard {
                            sourceCardView(card)
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
                                            HStack(spacing: OneDayMetrics.rowInnerGap) {
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
                                            HStack(spacing: OneDayMetrics.rowInnerGap) {
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
                    systemImage: "doc.text",
                    description: Text("可能已过期或被删除。")
                )
            }
        }
        // 0.41.0（收口批 P5，随 C9 先例）：栏题「动态」
        // 与帖子自身大标题并存属标题冗余（宪法 §5）——
        // 撤栏题、内容领头；回退靠系统返回钮自明
    }

    /// 来源嵌入卡（0.38.0）：头像＋名＋简介＋事实行，
    /// 整卡点开来源原页；数据全是桥侧真抓，App 只摆
    @ViewBuilder
    private func sourceCardView(_ card: BridgeFeedSourceCard) -> some View {
        let content = HStack(alignment: .top, spacing: OneDayMetrics.cardInnerGap) {
            if let imageUrl = card.imageUrl,
               let url = URL(string: imageUrl) {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image
                            .resizable()
                            .scaledToFill()
                    } else {
                        Palette.selectionFill
                    }
                }
                .frame(width: 40, height: 40)
                .clipShape(Circle())
            }
            VStack(alignment: .leading, spacing: OneDayMetrics.stackGap) {
                Text(card.name)
                    // 0.41.0（C14 同账）：副题级加粗回收
                    // 角色——来源名走 rowSubtitle regular，
                    // 与行题单轨同理
                    .font(.rowSubtitle)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                if !card.description.isEmpty {
                    Text(card.description)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(2)
                }
                if !card.facts.isEmpty {
                    HStack(spacing: 12) {
                        ForEach(
                            Array(card.facts.enumerated()),
                            id: \.offset
                        ) { _, fact in
                            Text("\(fact.label) \(fact.value)")
                                .font(.footnote)
                                .foregroundStyle(Palette.inkSecondary)
                        }
                    }
                }
            }
            Spacer()
            Image(systemName: "arrow.up.forward")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.inkSecondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Palette.surface,
            in: RoundedRectangle(cornerRadius: OneDayMetrics.radiusCard)
        )
        if let url = URL(string: card.url) {
            Link(destination: url) { content }
        } else {
            content
        }
    }
}


/// 简报编辑器（0.38.0 两层制）：上层只写自己的话，
/// 保存后由 AI 整理成下层的正式简报；正式简报可见
/// 可改、直改保存同样算数。两层分开存、分开保存，
/// 不许让用户对着空白框自写完整执行提示词——示例
/// 只作参考呈现，点「填入示例」才进输入框。
struct FeedBriefEditorView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let store: FeedStore

    @State private var interestText = ""
    @State private var promptText = ""
    @State private var initialized = false
    @State private var savedNote: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $interestText)
                        .frame(minHeight: 110)
                } header: {
                    Text("我感兴趣什么")
                } footer: {
                    Text("用自己的话写就行：关心哪几个方向、"
                         + "什么样的内容不要。保存后我来整理"
                         + "成下面的正式简报。")
                }

                Section {
                    Text(FeedBriefBoard.exampleInterest)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                    Button {
                        interestText = FeedBriefBoard.exampleInterest
                    } label: {
                        Label("填入示例改一改",
                              systemImage: "text.badge.plus")
                    }
                } header: {
                    Text("示例")
                }

                Section {
                    Button {
                        Task { await saveInterest() }
                    } label: {
                        HStack {
                            Text("保存兴趣")
                            Spacer()
                            if store.briefSaving {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                    }
                    .disabled(
                        store.briefSaving || !interestChanged
                    )
                } footer: {
                    Text("保存后先整理简报；整理出新版就立刻"
                         + "按新简报去看一轮。平时每天早上 "
                         + "8:30 例行一轮，有新发现就多一篇，"
                         + "没有就不凑数。")
                }

                if let doc = store.briefDoc, doc.expanding {
                    Section {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("正在整理简报…")
                                .foregroundStyle(Palette.inkSecondary)
                        }
                    }
                }
                if let error = store.briefDoc?.expandError,
                   !error.isEmpty {
                    Section {
                        Text("上次整理没成功：\(error)")
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }

                Section {
                    TextEditor(text: $promptText)
                        .frame(minHeight: 150)
                } header: {
                    Text("正式简报")
                } footer: {
                    Text("这是每天真正照着去看的那份，由上"
                         + "面的兴趣自动整理。你也可以直接改"
                         + "它：保存后立刻按新简报去看一轮。")
                }

                Section {
                    Button {
                        Task { await savePrompt() }
                    } label: {
                        Text("保存正式简报")
                    }
                    .disabled(store.briefSaving || !promptChanged)
                }

                if let note = savedNote {
                    Section {
                        Text(note)
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }
                if let error = store.briefError {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("我的简报")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .task {
                if store.briefDoc == nil {
                    await store.load(appState: appState)
                }
                if !initialized {
                    interestText = store.briefDoc?.interest ?? ""
                    promptText = store.briefDoc?.brief ?? ""
                    initialized = true
                }
            }
        }
    }

    private var interestChanged: Bool {
        FeedBriefBoard.textChanged(
            store.briefDoc?.interest ?? "", interestText
        )
    }

    private var promptChanged: Bool {
        FeedBriefBoard.textChanged(
            store.briefDoc?.brief ?? "", promptText
        )
    }

    private func saveInterest() async {
        if await store.saveInterest(
            appState: appState, interestText
        ) {
            savedNote = store.briefDoc?.expandStarted == true
                ? "已保存，正在整理简报；整理出新版会立刻去看一轮。"
                : "已保存。"
        }
    }

    private func savePrompt() async {
        if await store.savePrompt(appState: appState, promptText) {
            savedNote = store.briefDoc?.expandStarted == true
                ? "已保存，正在按新简报去看一轮。"
                : "已保存。"
        }
    }
}
