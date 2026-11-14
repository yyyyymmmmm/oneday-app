import OneDayCore
import OneDayDesign
import SwiftData
import SwiftUI

/// 动态格（P3，0.35.0；0.38.0 换代）：形态按设计档
/// 第三章向 Muse 动态页收——帖子扁平排版（kind
/// 瓷砖＋标题＋正文摘＋真图缩略＋refs 蓝字内链＋相
/// 对时间）、单条时间流（§177 撤日期分组：无「今
/// 天/昨天」小节、纯发布时间序，与 Muse 一致）。
/// 紧凑化（§126，用户 2026-11-11 13:24/13:37 拍
/// 板）：顶部简报胶囊行整行删除（§117 胶囊口径作
/// 废），简报设置只归工具栏滑杆钮；一切未读提醒面
/// 撤下（底栏角标/行内蓝点/动作行未读文字，§104/
/// §117 未读口径作废）——已读回写与 readAt 保留为
/// 静默账本，只停提醒面、不停账本；搜索改工具栏
/// 点开式（.toolbar 落点，不再常驻一行）；列表顶
/// 距改条件化（见 topMargin）。§177：帖面不单独设
/// 色——根 List 与点子页同口径隐藏系统滚动底、透
/// 出页面底 pageBG，帖行同色（此前本页根 List 没
/// 隐藏系统滚动底，列表区被系统默认底罩住、与页
/// 底 #FCFCFC 两色；同为 List 形态的点子页早有此
/// 口径，本页此前独缺）。
/// 数据口径：双生产者在桥端（段一确定性汇编＋段二
/// 简报驱动的调研五步链），App 只读＋已读回写；已
/// 读以服务端 readAt 为真源。简报两层在编辑器里分
/// 开存分开改（兴趣层用户原话、执行层 AI 整理）。
/// 空态二分如实（从未产出/今日无素材），不许假帖
/// 填充。refs 点达对象详情走本栈复用各详情页。
struct FeedView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
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
    /// 搜索（0.47.0 §117；§126 改点开式）：落点改
    /// 工具栏（.toolbar）——放大镜在工具栏内点开才
    /// 展开搜索场，不再以 .searchable 默认落点常驻
    /// 一整行；按标题＋正文过滤当前已载帖，收起即
    /// 清过滤态（见 readyContent 的 onChange）
    @State private var searchText = ""
    @State private var isSearching = false
    /// 来源小 sheet 的当前帖（动作行 ⓘ 点按）
    @State private var sourcesPost: BridgeFeedPost?
    /// §208 原帖回跳挂起中的帖 id：回跳请求已消费、
    /// 帖名单未就绪时先挂起，posts 到达后再判（见
    /// resolveFeedOpen）
    @State private var pendingFeedOpenPostID: String?
    /// §208 回跳查无此帖的诚实提示（帖已过期/删除；
    /// 引用块里的快照仍可读，提示只管原帖不在）
    @State private var feedPostGoneNotice = false

    /// 页顶浮层的实测重叠高度（§126）：顶距改条件
    /// 化——§122 的无条件 64pt（spacingXXL＋spacingM）
    /// 在浮层不在场时照收、压出搜索框下约 80pt 死空
    /// （调研量测实证），本包废止。现行壳层没有覆盖
    /// 本页的浮层（全仓核查：任务进展胶囊只在聊天页
    /// safeAreaBar 内，本页工具栏由导航栏安全区托
    /// 管），故本值恒为 nil、顶距恒 0；壳层将来在本
    /// 页上方挂浮层时，把其实测高度写进此处，顶距
    /// 即按 FeedBoard.topClearance 政策（重叠高＋
    /// spacingS）生效。不许再回到无条件写死
    @State private var topOverlayHeight: CGFloat?

    /// 列表顶部边距（§126）：政策收口在 Core
    /// FeedBoard.topClearance——无重叠恒 0，真重叠
    /// ＝实测重叠高度＋spacingS
    private var topMargin: CGFloat {
        FeedBoard.topClearance(
            overlayHeight: topOverlayHeight,
            gap: OneDayMetrics.spacingS
        )
    }

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
                        Label("还没连上你的服务", systemImage: "link.badge.plus")
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
                        Label("动态没读出来，可能是网络或服务暂时没响应", systemImage: "exclamationmark.triangle")
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
            .background {
                Palette.pageBG
                    .ignoresSafeArea()
            }
            .navigationTitle("动态")
            .toolbar {
                // 搜索入口（§126）：.searchable 的
                // .toolbar 落点自带工具栏放大镜，与滑
                // 杆钮同舱呈现；0.47.0 的自绘放大镜钮
                // 与其重复占位，一并退役
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
            .sheet(item: $sourcesPost) { post in
                FeedSourcesSheet(post: post) { ref in
                    sourcesPost = nil
                    path.append(Route.ref(ref))
                }
            }
            // §208：聊天里点动态引用块的原帖回跳——请
            // 求在此消费（清零先行防重入），落点判定走
            // resolveFeedOpen（在名单直达详情、名单就
            // 绪而查无给诚实提示、未就绪挂起等名单）
            .onChange(of: appState.feedOpenPostRequest) { _, id in
                if let id {
                    appState.feedOpenPostRequest = nil
                    pendingFeedOpenPostID = id
                    resolveFeedOpen()
                }
            }
            .onChange(of: store.posts) { _, _ in
                resolveFeedOpen()
            }
            .alert(
                "这篇动态已不在了",
                isPresented: $feedPostGoneNotice
            ) {
                Button("好", role: .cancel) {}
            }
            // §233：点赞乐观翻心被后台否掉的轻提醒
            // （心已恢复原状，这里只告知一声）
            .alert(
                "点赞没成功，请稍后再试。",
                isPresented: Binding(
                    get: { store.likeNotice != nil },
                    set: { if !$0 { store.clearLikeNotice() } }
                )
            ) {
                Button("好", role: .cancel) {
                    store.clearLikeNotice()
                }
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
                // 简报胶囊行已整行删除（§126）：简报
                // 入口只剩工具栏滑杆钮；动态不再有占
                // 行的页头横幅，标题之下直接是帖流
                if isSearching, visiblePosts.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "没有找到相关动态",
                            systemImage: "magnifyingglass"
                        )
                        .listRowBackground(Palette.pageBG)
                    }
                }

                // §177：单条时间流——一个无头 Section
                // 盛全部帖（FeedBoard.sorted 纯时间
                // 序）；日期分组与分组头整套撤下（用
                // 户亲定「不要今天、昨天这些时间」）
                if !visiblePosts.isEmpty {
                    Section {
                        ForEach(FeedBoard.sorted(visiblePosts)) { post in
                            postRow(post)
                        }
                    }
                }
            }
            .listStyle(.plain)
            // §177：帖面与页面同色——与点子页同口径
            // 隐藏 List 系统滚动底、透出页面底（外层
            // Group 已挂 pageBG），帖行再以
            // listRowBackground 同色钉死（postRow）
            .scrollContentBackground(.hidden)
            .background(Palette.pageBG)
            // 分区间距（§126 令牌口径保留）：现行只
            // 余搜索空态段与帖流段两段，段距仍走令牌
            // spacingM，不回系统默认
            .listSectionSpacing(OneDayMetrics.spacingM)
            .contentMargins(.top, topMargin, for: .scrollContent)
            // 搜索点开式（§126）：落点改工具栏——点
            // 放大镜才展开搜索场，不再常驻一行；收起
            // 即清过滤态（下方 onChange）
            .searchable(
                text: $searchText, isPresented: $isSearching,
                placement: .toolbar, prompt: "搜索动态"
            )
            .onChange(of: isSearching) { _, searching in
                if !searching {
                    searchText = ""
                }
            }
            .refreshable {
                await reload()
            }
            // §170（用户 2026-11-11 23:28 亲定「底部导航
            // 栏上边、下边都加上同款朦胧收边，与输入框下
            // 边那套同档」）：本页根 List 底缘挂 .hard——
            // 系统在原生 TabView 坞高内发放与输入框下方收边
            // 同档的均匀收边（坞浮于带内、带的上沿即坞
            // 的上边、下沿即坞的下边；原生坞无独立的上/
            // 下缘 API，映射口径见 DESIGN §170.2）
            // §185 按裁决改 .soft：该边缘内容可流到坞下、.hard 官方定义近乎不透明本身制造色带（solidband 裁决第四节）；§170 的 .hard 口径就此点被 §185 覆盖。
            .scrollEdgeEffectStyle(.soft, for: .bottom)
        }
    }

    /// 搜索过滤（0.47.0）：标题或正文命中即留；排
    /// 序与全量同走 FeedBoard.sorted 唯一口径（单条
    /// 时间流，§177 起不再经 dayGroups 分组——该函
    /// 数保留在 Core 仅作口径存档，不再有呈现调用方）
    private var visiblePosts: [BridgeFeedPost] {
        let query = searchText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard isSearching, !query.isEmpty else { return store.posts }
        return store.posts.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.body.localizedCaseInsensitiveContains(query)
        }
    }

    /// 帖子行（0.47.0 §117 对标形态）：内容 emoji 大
    /// 字（桥值优先、kind 缺省兜底）＋semibold 标题＋
    /// 正文内联（Markdown、链接可点）＋第一张图通栏
    /// 大图＋来源卡＋refs 蓝字内链＋动作行（讨论/类
    /// 别/相对时间/ⓘ来源）。整行点按开详情的旧形态
    /// 退役：标题点按仍可达详情（深链与 ⓘ 的落点），
    /// 正文区让给链接与文本选择。已读口径随全文内联
    /// 改版：行露面即已读（onAppear 回写，§117.3 定
    /// 版），各交互点按同样回写。
    /// 0.48.0（§122）：正文改安全网口径——短帖仍全文
    /// 内联，长帖经 Core FeedBoard.rowBodyPresentation
    /// 句界截断＋「展开全文」进详情；图改 FeedPost-
    /// ImageBox 定尺盒（见该类型注）
    private func postRow(_ post: BridgeFeedPost) -> some View {
        HStack(alignment: .top, spacing: OneDayMetrics.spacingM) {
            Text(post.displayEmoji)
                .font(.system(size: 38))
                .frame(width: 44, height: 44)
                // 内容 emoji 是帖的类别信号、动作行另
                // 有类别文字——对 VO 隐藏免逐字念名
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
                HStack(alignment: .top, spacing: OneDayMetrics.rowInnerGap) {
                    Text(post.title)
                        // 0.47.0（§117.5 记账）：行题经
                        // 用户对标指令改回 semibold——
                        // C14 的 .rowTitle 归轨只限本页
                        // 与点子页，其余页面角色表不动
                        .font(.headline)
                        .foregroundStyle(Palette.ink)
                        // 0.43.0（A11Y-D3）：AX 档放宽
                        .a11yLineLimit(2, ax: 4)
                    // 未读蓝点已撤（§126）：动态取消一切
                    // 未读提醒面；已读回写保留为静默账本
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    openPost(post)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction {
                    openPost(post)
                }
                if !post.body.isEmpty {
                    let rowBody = FeedBoard.rowBodyPresentation(
                        post.body
                    )
                    MarkdownText(rowBody.text)
                    if rowBody.isTruncated {
                        Button {
                            openPost(post)
                        } label: {
                            Text("展开全文")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Palette.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                // 通栏大图：只用第一张来源真图；定尺走
                // FeedPostImageBox（形状层承担 16:9、图
                // 片降 overlay 裁切）。0.47.0 旧形把
                // aspectRatio 挂在 AsyncImage 本体上——
                // 成功相的图片以自然尺寸参与行高求解，
                // 整页截图类长图撑成数屏高（§122 题二
                // 机理，用户 12:41 截图实证）；加载未
                // 成/失败整块不显（宁无图不假图、不摆
                // 占位，旧口径不变）
                if let first = post.images.first,
                   let url = URL(string: first.url) {
                    AsyncImage(url: url) { phase in
                        if case .success(let image) = phase {
                            FeedPostImageBox(
                                image: image,
                                cornerRadius: OneDayMetrics
                                    .radiusPreview
                            )
                        }
                    }
                    .accessibilityHidden(true)
                }
                if let card = post.sourceCard {
                    FeedSourceCardView(card: card)
                }
                if !post.refs.isEmpty {
                    refsRow(post.refs)
                }
                actionRow(post)
            }
        }
        .padding(.vertical, OneDayMetrics.spacingS)
        // §177：帖面与页面同色（与列表滚动底口径成
        // 对，见 readyContent 注）
        .listRowBackground(Palette.pageBG)
        .onAppear {
            markRead(post)
        }
    }

    /// 动作行（0.47.0）：讨论（以本帖开新会话）＋类
    /// 别小字＋相对时间＋ⓘ（来源小 sheet）。行内含
    /// 真按钮，0.43.0 的「动作行合并元素」自此退役
    /// ——合并会吞掉按钮的可达性
    private func actionRow(_ post: BridgeFeedPost) -> some View {
        HStack(spacing: OneDayMetrics.spacingM) {
            // 爱心（FA-1；§233 改乐观时序）：填充态读
            // likedAt、点按当拍先翻本地呈现，后台走
            // FeedStore.toggleLiked 幂等写＋回执对账，
            // 失败恢复原状＋轻提醒；行面只加一钮，
            // 不新增 why/edition 字样（守 §126 行面栈
            // 与 rev2 §1.9 冻结契约）
            Button {
                Task { await store.toggleLiked(appState: appState, post: post) }
            } label: {
                Image(systemName: post.isLiked ? "heart.fill" : "heart")
                    .font(.subheadline)
                    .foregroundStyle(
                        post.isLiked ? Palette.primary : Palette.inkSecondary
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(post.isLiked ? "取消点赞" : "点赞")
            Button {
                discuss(post)
            } label: {
                HStack(spacing: OneDayMetrics.stackGap) {
                    Image(systemName: "text.bubble")
                    Text("讨论")
                }
                .font(.subheadline)
                .foregroundStyle(Palette.inkSecondary)
            }
            .buttonStyle(.plain)
            Text(post.kind.label)
                .font(.footnote)
                .foregroundStyle(Palette.inkSecondary)
            if let direction = post.direction, !direction.isEmpty {
                Text(direction)
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
            }
            // 动作行「未读」文字已撤（§126）：与底栏
            // 角标、行内蓝点同批取消未读提醒面
            Spacer()
            Text(FeedBoard.relativeText(
                for: post.createdAt, now: Date()
            ))
            .font(.footnote)
            .foregroundStyle(Palette.inkSecondary)
            Button {
                markRead(post)
                sourcesPost = post
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.inkSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("来源")
        }
    }

    private func openPost(_ post: BridgeFeedPost) {
        markRead(post)
        path.append(Route.post(post.id))
    }

    /// §208 回跳落点判定：挂起帖在已载名单里→直达
    /// 详情并销挂起；名单已就绪（.ready）而查无→帖
    /// 真不在了，诚实提示并销挂起；名单未就绪→继
    /// 续挂起，等 posts 变更时由 onChange 再判
    private func resolveFeedOpen() {
        guard let id = pendingFeedOpenPostID else { return }
        if store.post(id: id) != nil {
            pendingFeedOpenPostID = nil
            path.append(Route.post(id))
        } else if case .ready = store.loadState {
            pendingFeedOpenPostID = nil
            feedPostGoneNotice = true
        }
    }

    /// 已读回写：未读才发（§233 本地先行——markRead
    /// 先落本地已读再向桥确认，失败静默留下轮名单纠正）
    private func markRead(_ post: BridgeFeedPost) {
        guard !post.isRead else { return }
        Task { await store.markRead(appState: appState, post: post) }
    }

    /// 讨论（0.47.0；§208 引用化）：以本帖为引用开
    /// 一条对话——帖以引用卡挂发送舱（FeedPostQuote
    /// 值快照），输入框恒空、亲笔才是草稿；引用直
    /// 写目标线程的待发状态（AppState.pendingFeed-
    /// QuotesByThread，§210 改挂、ChatView 派生呈
    /// 现），永不进草稿账。
    /// §208 前旧形（预填经 setDraft 直写草稿账）已
    /// 退役：预填文与亲笔在草稿账里同形、被防丢稿
    /// 保活永久保护，没发就赖着不走（用户
    /// 2026-11-13 点名）；存量旧预填由包 3 清扫。
    /// 去重：同帖已有讨论线程复用（FA-1 关联反
    /// 查，threadID(forFeedDiscussPostID:)），不
    /// 再堆空会话；复用不覆盖其草稿（本路根本不
    /// 写草稿账），关联在但线程已删则补建并改写
    /// 关联（与点子流 openIdeaChat 同形）
    /// FA-1：建聊同时登记待发信号关联——该线程
    /// 第一条用户消息发出后，ChatView 据此发一记
    /// discuss 信号（契约 rev2 §1.9；本钮仍不代
    /// 发消息）
    private func discuss(_ post: BridgeFeedPost) {
        markRead(post)
        let thread: ChatThread
        if let linkedID = appState.sideChats.threadID(
            forFeedDiscussPostID: post.id
        ), let existing = fetchThread(linkedID) {
            thread = existing
        } else {
            let fresh = ChatThread()
            modelContext.insert(fresh)
            try? modelContext.save()
            appState.sideChats.linkFeedDiscussThread(
                fresh.id, postID: post.id
            )
            thread = fresh
        }
        // §210：引用直写目标线程的待发状态（落点决定
        // 与引用写入同动作完成），不再经全局种子
        appState.pendingFeedQuotesByThread[thread.id] =
            FeedPostQuote(post: post)
        appState.drawerThreadSelection = thread.id
        appState.mainTabSwitchRequest = .chat
    }

    /// 按 id 取本地线程（点子流 fetchThread 同形）
    private func fetchThread(_ id: UUID) -> ChatThread? {
        let descriptor = FetchDescriptor<ChatThread>(
            predicate: #Predicate { $0.id == id }
        )
        return try? modelContext.fetch(descriptor).first
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
                        // 配图（0.38.0 首版只显第一张；
                        // 0.48.0 §122 题二扩围）：逐张以
                        // 16:9 定尺盒排列——旧形 scaledTo-
                        // Fit 无任何限高，整页截图类长图进
                        // 详情照样按自然比撑爆整页（审计
                        // N1，与行内同根）；与行内同走
                        // FeedPostImageBox，加载失败/无图
                        // 整块不显，不摆假图
                        ForEach(
                            Array(post.images.enumerated()),
                            id: \.offset
                        ) { _, item in
                            if let url = URL(string: item.url) {
                                AsyncImage(url: url) { phase in
                                    if case .success(let image)
                                        = phase {
                                        FeedPostImageBox(
                                            image: image,
                                            cornerRadius:
                                                OneDayMetrics
                                                .radiusCard
                                        )
                                    }
                                }
                                // 0.43.0（A11Y-V2）：详情大
                                // 图的文本等价——以图片 URL
                                // 文件名为最低口径（A11y-
                                // Text 拼装）
                                .accessibilityElement(
                                    children: .ignore
                                )
                                .accessibilityLabel(
                                    A11yText.imageLabel(
                                        fileName: url
                                            .lastPathComponent
                                    )
                                )
                            }
                        }
                        // why 一行（FA-1，契约 rev2
                        // §1.9 冻结）：正文上方一行
                        // 「为什么选这篇 · {why}」——
                        // 此前形态是正文下方的卡片块
                        // （标题＋正文＋底色），与冻结
                        // 契约的一行口径不符，本包归位
                        if let why = post.why, !why.isEmpty {
                            HStack(alignment: .firstTextBaseline, spacing: 0) {
                                // 标题走既有目录键；后段
                                // 是分隔符＋桥下发原文，
                                // 以变量入 Text 走原文呈
                                // 现，不造新本地化键
                                Text("为什么选这篇")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(Palette.inkSecondary)
                                Text(" · " + why)
                                    .font(.footnote)
                                    .foregroundStyle(Palette.inkSecondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        MarkdownText(post.body)
                        if let card = post.sourceCard {
                            FeedSourceCardView(card: card)
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
}

/// 帖图定尺盒（0.48.0，§122 题二）：形状层承担
/// 16:9 定尺寸、图片降为 overlay 以 fill 裁切——
/// 0.36.24 媒体格定案的同族正案（定尺必须落在承
/// 担定尺寸的那一层，不许把比例约束挂在会以自然
/// 尺寸参与求解的图片载体本体上）。帖行（只喂第
/// 一张）与详情（逐张）共用；是否出现由外层
/// AsyncImage 相位决定（成功才建盒，失败整块不
/// 显、无占位，旧口径不变）
private struct FeedPostImageBox: View {
    let image: Image
    let cornerRadius: CGFloat

    var body: some View {
        Color.clear
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                image
                    .resizable()
                    .scaledToFill()
            }
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

/// 来源嵌入卡（0.38.0；0.47.0 抽为共享组件，帖行
/// 与详情页同用一份）：头像＋名＋简介＋事实行，整
/// 卡点开来源原页；数据全是桥侧真抓，App 只摆
struct FeedSourceCardView: View {
    let card: BridgeFeedSourceCard

    var body: some View {
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

/// 来源小 sheet（0.47.0 §117）：动作行 ⓘ 的落点——
/// 为什么选这篇＋外链清单＋站内引用；数据全是帖自
/// 带字段（桥真抓），没有的段整段不出现。点引用先
/// 关 sheet 再由父视图压栈（onOpenRef 回调）
struct FeedSourcesSheet: View {
    @Environment(\.dismiss) private var dismiss
    let post: BridgeFeedPost
    let onOpenRef: (BridgeFeedRef) -> Void

    var body: some View {
        NavigationStack {
            List {
                if let why = post.why, !why.isEmpty {
                    Section {
                        Text(why)
                            .font(.subheadline)
                            .foregroundStyle(Palette.bodyInk)
                    } header: {
                        Text("为什么选这篇")
                    }
                }
                if !post.links.isEmpty {
                    Section {
                        ForEach(
                            Array(post.links.enumerated()), id: \.offset
                        ) { _, link in
                            if let url = URL(string: link.url) {
                                Link(destination: url) {
                                    HStack(spacing: OneDayMetrics.rowInnerGap) {
                                        Image(systemName: "link")
                                            .font(.system(size: 12))
                                        Text(link.title.isEmpty
                                             ? link.url : link.title)
                                            .lineLimit(2)
                                    }
                                    .font(.subheadline)
                                }
                            }
                        }
                    } header: {
                        Text("链接")
                    }
                }
                if !post.refs.isEmpty {
                    Section {
                        ForEach(
                            Array(post.refs.enumerated()), id: \.offset
                        ) { _, ref in
                            if let type = ref.refType {
                                Button {
                                    dismiss()
                                    onOpenRef(ref)
                                } label: {
                                    HStack(spacing: OneDayMetrics.rowInnerGap) {
                                        Image(systemName: type.symbolName)
                                            .font(.system(size: 12))
                                        Text(type.label)
                                            .foregroundStyle(Palette.bodyInk)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(Palette.inkSecondary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } header: {
                        Text("引用")
                    }
                }
                if post.why == nil || post.why?.isEmpty == true,
                   post.links.isEmpty, post.refs.isEmpty {
                    Section {
                        Text("这篇没有附带来源信息")
                            .font(.subheadline)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }
            }
            .navigationTitle("来源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
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
                    // S2-11：保存钮提主钮层级——照 §118 审批
                    // 卡主钮同款形态（通栏胶囊、高
                    // ApprovalCardSpec.buttonHeight、蓝实心
                    // 白字），不再用 Form 文本行式 Button
                    Button {
                        Task { await saveInterest() }
                    } label: {
                        ZStack {
                            Text("保存兴趣")
                                .font(.headline)
                                .foregroundStyle(Color.white)
                            if store.briefSaving {
                                HStack {
                                    Spacer()
                                    ProgressView()
                                        .controlSize(.small)
                                        .tint(Color.white)
                                }
                                .padding(
                                    .trailing,
                                    OneDayMetrics.spacingM
                                )
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: ApprovalCardSpec.buttonHeight)
                        .background(Palette.primary, in: Capsule())
                        .contentShape(Capsule())
                        .opacity(
                            store.briefSaving || !interestChanged
                                ? 0.45 : 1
                        )
                    }
                    .buttonStyle(.odPressable)
                    .disabled(
                        store.briefSaving || !interestChanged
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
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
                    // S2-11：次钮同几何、降一档——浅灰填充
                    // 墨字通栏胶囊，与上方主钮主次分明
                    Button {
                        Task { await savePrompt() }
                    } label: {
                        Text("保存正式简报")
                            .font(.headline)
                            .foregroundStyle(Palette.ink)
                            .frame(maxWidth: .infinity)
                            .frame(
                                height: ApprovalCardSpec.buttonHeight
                            )
                            .background(
                                Palette.selectionFill, in: Capsule()
                            )
                            .contentShape(Capsule())
                            .opacity(
                                store.briefSaving || !promptChanged
                                    ? 0.45 : 1
                            )
                    }
                    .buttonStyle(.odPressable)
                    .disabled(store.briefSaving || !promptChanged)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
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
