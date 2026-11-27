import NukeUI
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
/// 距改条件化（见 topMargin）。
/// §486（2026-11-24，三页审计全抄）：页头安排再
/// 换代——§126 的「简报胶囊行删除＋工具栏点开搜
/// 索」口径就此作废：页内自持页头簇（身份簇＋34
/// 大标题＋标题下字段槽），字段槽静止态＝简报胶
/// 囊（胶囊行以此形态回归，与 §126 删的旧行不同
/// 件）、滚过阈值后＝搜索字段顶替【推定待真机帧
/// 翻案】；链接改 OG 式预览卡、链接出处图不再整
/// 幅渲染。细则见 DESIGN §486 与 feedPageHead。§177：帖面不单独设
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var store = FeedStore()
    /// refs 点达与标题解析的数据源（与点子/目标格同
    /// 一套 Store）：台账 199 改走 AppState 共享单例
    /// （§259 先例补齐），与点子格／目标格／目标详
    /// 情同一份，不再自持实例
    private var ideasStore: IdeasStore {
        appState.sharedIdeasStore()
    }
    private var goalsStore: GoalsStore {
        appState.sharedGoalsStore()
    }
    /// §259 三店合一：任务/监测两店走 AppState 共享
    /// 单例，与枢纽/目标/点子各面同一份，不再私建
    private var kanban: KanbanStore {
        appState.sharedKanbanStore()
    }
    private var monitorsStore: MonitorsStore {
        appState.sharedMonitorsStore()
    }
    @State private var path = NavigationPath()
    @State private var imageViewerSession: ImageViewerSession?
    /// 简报编辑器（0.38.0 两层制）呈现
    @State private var briefEditorShown = false
    /// 页头身份簇开中枢（§486：簇自聊天页同件接入
    /// 本页，落点与聊天页同为本栈推 AgentHubView）
    @State private var showHub = false
    /// 页头字段槽切换态（§498）：列表内容偏移驱动
    /// （onScrollGeometryChange）——过阈值字段槽由简
    /// 报胶囊换搜索入口；共同簇与大标题行恒常驻（§
    /// 486.4 的整簇收起已废止，本状态不再触碰簇）
    @State private var fieldSlotSwapped = false

    /// 字段槽切换阈值（§486.2 翻案单点之一）：内容
    /// 上滚超此值字段槽换搜索形态（§498：只动字段
    /// 槽，不再收簇）
    private static let collapseThreshold: CGFloat = 24
    /// 搜索（0.47.0 §117；§126 改点开式；§486 改
    /// 页头字段槽）：激活态由标题下字段槽的搜索行
    /// 承载（FileSearchField 单源件），不再走 .sea-
    /// rchable 工具栏落点；按标题＋正文过滤当前已
    /// 载帖，收起即清过滤态（见 body 的 onChange）
    @State private var searchText = ""
    @State private var isSearching = false
    /// 「关于」展开节当前展开的帖 id（§453：动作
    /// 行 ⓘ 原地 toggle，一次至多一帖展开）
    @State private var expandedAboutID: String?
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

    /// §415：派生快照指纹缓存（visiblePosts 收口，
    /// 照资源库 LibrarySnapshotCache 模板）
    @State private var snapshotCache = FeedSnapshotCache()

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
        // §415：派生快照一趟算齐下传（旧 visiblePosts
        // 计算属性＋readyContent 内 sorted 每趟重排
        // 已退役，派生收口 FeedListSnapshot）
        let snapshot = snapshotCache.snapshot(
            posts: store.posts, searchText: searchText,
            isSearching: isSearching
        )
        return NavigationStack(path: $path) {
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
                    readyContent(snapshot)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaBar(edge: .top, spacing: 0) {
                feedTopHeader
            }
            .background {
                Palette.pageBG
                    .ignoresSafeArea()
            }
            // §486：页头整簇改页内自持（ContentPage-
            // Header＋大标题＋字段槽，见 feedPageHead），
            // 系统导航栏在本页根隐藏——推入的详情页
            // 各自声明栏可见性（与文件页同式）；§126
            // 的工具栏滑杆钮与 .searchable 工具栏落点
            // 随之退役（滑杆进页头簇、搜索进字段槽）
            .toolbar(.hidden, for: .navigationBar)
            // H2 收编：中枢改 cover 呈现（与聊天页
            // 同一宿主），原 push 入中枢退役
            .hubCover(isPresented: $showHub)
            .onChange(of: isSearching) { _, searching in
                if !searching {
                    searchText = ""
                }
            }
            // §208：聊天里点动态引用块的原帖回跳——请
            // 求在此消费（清零先行防重入），落点判定走
            // resolveFeedOpen（在名单直达详情、名单就
            // 绪而查无给诚实提示、未就绪挂起等名单）
            .onChange(of: appState.router.feedOpenPostRequest) { _, id in
                if let id {
                    appState.router.feedOpenPostRequest = nil
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
                await loadIfNeeded()
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .post(let id):
                    FeedPostDetailView(
                        store: store, postID: id,
                        refInfo: { ref in
                            // §459：事件帖来源行存亡判据
                            // 与列表同源（就绪＋解析不到
                            // 才算已删除）
                            guard let type = ref.refType
                            else { return (nil, false) }
                            let title = refResolvedTitle(ref)
                            return (
                                title,
                                refSourceReady(type)
                                    && title == nil
                            )
                        },
                        onOpenImage: { post, url in
                            openPostImage(post, url: url, previewLongEdge: 1600)
                        },
                        onOpenImageGallery: {
                            imageViewerSession = $0
                        }
                    ) { ref in
                        path.append(Route.ref(ref))
                    }
                case .ref(let ref):
                    refDestination(ref)
                }
            }
        }
        .fullscreenPopBridge()
        .fullScreenCover(item: $imageViewerSession) { session in
            ImageViewerView(items: session.items, initialIndex: session.initialIndex)
        }
        .topAnchoredPanel(isPresented: $briefEditorShown) { size in
            FeedBriefEditorView(
                store: store,
                screenHeight: size.height,
                onClose: { briefEditorShown = false }
            )
        }
    }

    /// 强制重拉（下拉刷新/错误态重试专用）：只拉本
    /// 面——跨面联动已拆（§367.5）：点子/目标/看板/
    /// 监测各面按自己的触发自治，refs 标题解析改读
    /// 各店已载数据、缺数降级类别文案（既有口径）
    private func reload() async {
        await store.load(appState: appState)
    }

    /// 读触发入口（.task）：过新鲜度门，TTL 内零请求
    private func loadIfNeeded() async {
        await store.loadIfNeeded(appState: appState)
    }

    // MARK: - 页头（§486）

    /// 顶部固定身份簇：只固定圆钮、头像与身份胶囊，
    /// 大标题与简报/搜索槽随列表上下滑动
    private var feedTopHeader: some View {
        ContentPageHeader(
            onOpenHub: {
                HubCoverPresenter.present(
                    $showHub, reduceMotion: reduceMotion
                )
            }
        ) {
            PageHeaderCircleButton(
                symbol: "slider.horizontal.3",
                label: "编辑简报"
            ) {
                briefEditorShown = true
            }
        }
    }

    /// 随列表滑动的大标题与字段槽
    private var feedScrollTitleBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("动态")
                .font(.pageTitle)
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, OneDayMetrics.pageGutter)
                .padding(.top, OneDayMetrics.spacingS)
            fieldSlot
                .padding(.horizontal, OneDayMetrics.pageGutter)
                .padding(.top, OneDayMetrics.spacingS)
                .padding(.bottom, OneDayMetrics.spacingS)
        }
    }

    /// 字段槽切换判定：过阈值换搜索入口、回阈值内
    /// 还简报胶囊（状态不变不重写，免无谓重绘）
    private func updateFieldSlot(_ offset: CGFloat) {
        let swapped = offset > Self.collapseThreshold
        if swapped != fieldSlotSwapped {
            fieldSlotSwapped = swapped
        }
    }

    /// 标题下字段槽的形态（§486.2【推定待真机帧翻
    /// 案】）：静止态＝简报胶囊首行、滚过阈值＝搜索
    /// 字段顶替、搜索激活中＝真搜索行。依据＝审计
    /// §1.3 槽位推定（静止帧见简报胶囊、滚动帧同位
    /// 见搜索字段）；翻案时只改本判定与 collapse-
    /// Threshold，两形态件本体不动。§498：本切换是
    /// 全 App 唯一保留的滚动形态变化——整行交互件
    /// 互换、非收起（簇与标题不动、编辑简报另有滑
    /// 杆钮常驻入口）
    private enum FieldMode {
        case brief
        case searchEntry
        case searching
    }

    private var fieldMode: FieldMode {
        if isSearching { return .searching }
        return fieldSlotSwapped ? .searchEntry : .brief
    }

    @ViewBuilder
    private var fieldSlot: some View {
        switch fieldMode {
        case .searching:
            // 真搜索行：内嵌搜索件单源 FileSearchField
            // （第 88 条对账）＋取消，与资源库页同式；
            // 过滤仍走既有快照（searchText/isSearching）
            HStack(spacing: OneDayMetrics.spacingS) {
                FileSearchField(
                    query: $searchText,
                    placeholder: "搜索动态",
                    autoFocus: true
                )
                Button("取消") {
                    isSearching = false
                }
                .font(.body)
                .foregroundStyle(Palette.primary)
                .buttonStyle(.odPressable)
            }
        case .searchEntry:
            // 滚动帧的搜索字段形态（照参照量测：浅灰
            // 填充、高 50、大圆角、占位「搜索动态」）：
            // 点按进真搜索行
            Button {
                isSearching = true
            } label: {
                HStack(spacing: OneDayMetrics.spacingS) {
                    Image(systemName: "magnifyingglass")
                    Text("搜索动态")
                    Spacer(minLength: 0)
                }
                .font(.body)
                .foregroundStyle(Palette.inkSecondary)
                .padding(.horizontal, OneDayMetrics.spacingM)
                .frame(height: 50)
                .background(
                    Palette.fieldFill,
                    in: RoundedRectangle(
                        cornerRadius: OneDayMetrics.radiusPreview
                    )
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.odPressable)
            .accessibilityLabel("搜索动态")
        case .brief:
            // 简报胶囊（静止帧形态）：当前生效简报首
            // 行单行省略；点按开简报编辑器（与滑杆钮
            // 同落点）。简报未载/为空显引导文案（与空
            // 态同句），不假造内容
            Button {
                briefEditorShown = true
            } label: {
                HStack(spacing: OneDayMetrics.spacingS) {
                    Text(briefPillText)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .font(.subheadline)
                .foregroundStyle(Palette.inkSecondary)
                .padding(.horizontal, OneDayMetrics.spacingM)
                .frame(height: 40)
                .background(Palette.fieldFill, in: Capsule())
                .contentShape(Rectangle())
            }
            .buttonStyle(.odPressable)
            .accessibilityLabel("编辑简报")
        }
    }

    /// 简报胶囊文案：生效全文（FeedBriefBoard 单源
    /// 口径，与编辑器同读）的首行
    private var briefPillText: String {
        let text = store.briefDoc
            .map(FeedBriefBoard.effectiveText) ?? ""
        let firstLine = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .first.map(String.init) ?? ""
        let trimmed = firstLine.trimmingCharacters(
            in: .whitespaces
        )
        return trimmed.isEmpty
            ? "写下你感兴趣什么，我每天替你去看" : trimmed
    }

    // MARK: - 就绪内容

    @ViewBuilder
    private func readyContent(
        _ snapshot: FeedListSnapshot
    ) -> some View {
        if store.posts.isEmpty, !store.seedPosts.isEmpty {
            List {
                Section {
                    feedScrollTitleBlock
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    ForEach(store.seedPosts) { post in
                        postRow(post)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .listSectionSpacing(OneDayMetrics.spacingM)
            .contentMargins(.top, topMargin, for: .scrollContent)
            .scrollEdgeEffectStyle(.soft, for: .top)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, newValue in
                updateFieldSlot(newValue)
            }
            .refreshable {
                await reload()
            }
        } else if store.posts.isEmpty {
            VStack(spacing: 0) {
                feedScrollTitleBlock
                Group {
                    switch store.emptyKind {
                    case .neverProduced:
                        ODEmptyState(
                            "动态刚上线",
                            systemImage: "doc.text",
                            description: "写下你感兴趣什么，我每天替你去看；第一轮明早 8:30 到。站内的新点子、新简报也会汇编到这里。"
                        )
                    case .quiet:
                        ODEmptyState(
                            "近来没有新动态",
                            systemImage: "moon.zzz",
                            description: "今天没有值得一提的新发现；有动静时这里会先更新。"
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                Section {
                    feedScrollTitleBlock
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                if isSearching, snapshot.visiblePosts.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "没有找到相关动态",
                            systemImage: "magnifyingglass"
                        )
                        .listRowBackground(Color.clear)
                    }
                }

                if !snapshot.visiblePosts.isEmpty {
                    Section {
                        ForEach(snapshot.visiblePosts) { post in
                            postRow(post)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .listSectionSpacing(OneDayMetrics.spacingM)
            .contentMargins(.top, topMargin, for: .scrollContent)
            .scrollEdgeEffectStyle(.soft, for: .top)
            // §498：滚动偏移只驱动字段槽切换（归一
            // 化偏移＝offset＋顶 inset，静止恒 0）
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, newValue in
                updateFieldSlot(newValue)
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
    /// 句界截断＋「展开全文」进详情；帖图使用定尺预览。
    private func postRow(_ post: BridgeFeedPost) -> some View {
        HStack(alignment: .top, spacing: OneDayMetrics.spacingM) {
            Image(systemName: post.kind.symbolName)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: FrameworkIcon.fileGlyphSize, weight: .semibold))
                .foregroundStyle(post.kind.kickerTint)
                .frame(width: 24, height: 24)
                .background(
                    post.kind.kickerColor,
                    in: RoundedRectangle(
                        cornerRadius: OneDayMetrics.radiusTile,
                        style: .continuous
                    )
                )
                // kicker 字形块是帖的类别信号、动作行另
                // 有类别文字——对 VO 隐藏免逐字念名
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingM) {
                Button {
                    openPost(post)
                } label: {
                    HStack(alignment: .top, spacing: OneDayMetrics.rowInnerGap) {
                        Text(post.title)
                            // §364（台账 23）：行题升内容行题
                            // 例外角色 contentListTitle
                            // （Title3 semibold）——§117.5 例
                            // 外经用户 2026-11-22 裁定扩展至
                            // 目标面，三面同例
                            // 大厂对标（2026-11-27）：改用
                            // .title3 regular，去 semibold
                            // 保持轻盈（HIG Typography 标准）
                            .font(.title3)
                            .foregroundStyle(Palette.ink)
                            // 0.43.0（A11Y-D3）：AX 档放宽
                            .a11yLineLimit(2, ax: 4)
                        // 未读蓝点已撤（§126）：动态取消一切
                        // 未读提醒面；已读回写保留为静默账本
                        Spacer(minLength: OneDayMetrics.spacingS)
                        // 可点指示（2026-11-15 第 88 条，宪法
                        // §9「可点必有指示」）：标题可点进详
                        // 情此前与正文同貌无任何指示，补行尾
                        // 弱色 chevron；VO 侧本有 .isButton＋
                        // accessibilityAction、不受影响
                        DisclosureChevron(font: .caption2.weight(.semibold))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.odPressable)
                .accessibilityElement(children: .combine)
                .padding(.bottom, OneDayMetrics.spacingS)
                // §459：category chip——简报方向原文
                // （如「GitHub 热门」）；事件/小结帖为
                // nil 不渲染，不拿 kind 名冒充。视觉收编
                // （fix/feed-design-20261127）：字号由
                // subheadline（15pt）降至 footnote（13pt），
                // 对位标杆元信息档
                if let category = post.category,
                   !category.trimmingCharacters(
                       in: .whitespacesAndNewlines
                   ).isEmpty {
                    Text(category)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(
                            .horizontal, OneDayMetrics.spacingSM
                        )
                        .padding(
                            .vertical, OneDayMetrics.spacingXS
                        )
                        .background(
                            Palette.selectionFill,
                            in: RoundedRectangle(
                                cornerRadius: OneDayMetrics.radiusTile
                            )
                        )
                        .lineLimit(1)
                        .padding(.bottom, OneDayMetrics.spacingS)
                }
                if !post.body.isEmpty {
                    let rowBody = FeedBoard.rowBodyPresentation(
                        post.body
                    )
                    MarkdownText(rowBody.text, onOpenImageGallery: { session in
                        markRead(post)
                        imageViewerSession = session
                    })
                    .padding(.bottom, OneDayMetrics.spacingM)
                    if rowBody.isTruncated {
                        Button {
                            openPost(post)
                        } label: {
                            Text("展开全文")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Palette.primary)
                        }
                        .buttonStyle(.plain)
                        .padding(.bottom, OneDayMetrics.spacingM)
                    }
                }
                // 列表首张独立配图可打开同帖相册；链接封面归来源卡。
                if let url = post.images.first(where: {
                    $0.galleryURL != nil && !isLinkCoverImage($0, of: post)
                })?.galleryURL {
                    FeedPostImagePreview(
                        url: url, longEdgeCap: 1200,
                        cornerRadius: OneDayMetrics.radiusPreview
                    ) {
                        markRead(post)
                        openPostImage(post, url: url, previewLongEdge: 1200)
                    }
                    .padding(.bottom, OneDayMetrics.spacingM)
                }
                if !post.refs.isEmpty {
                    refsRow(post)
                    .padding(.bottom, OneDayMetrics.spacingS)
                }
                if expandedAboutID == post.id {
                    aboutSection(post)
                }
                actionRow(post)
            }
        }
        .padding(.vertical, OneDayMetrics.spacingM)
        .listRowBackground(Color.clear)
        .onAppear {
            markRead(post)
        }
    }

    /// 动作行（0.47.0；§453 收简约对 Muse 卡底
    /// 定版）：♡＋讨论＋短相对时间＋ⓘ 四件——类别
    /// 与方向撤出卡底归详情头，精确时刻搬进 ⓘ 的
    /// 「关于」展开节。行内含真按钮，0.43.0 的「动
    /// 作行合并元素」自此退役——合并吞按钮可达性
    @ViewBuilder
    private func actionRow(_ post: BridgeFeedPost) -> some View {
        if FeedSeedPosts.isSeed(post.id) {
            // FA-2 种子动作行：讨论（同真帖，带原文开
            // 旁聊）＋删除（本地标记、删了不复活）＋
            // 「上手指南」kicker 明示；无点赞/来源/时间
            // （不在桥上，没有这些账）
            HStack(spacing: OneDayMetrics.spacingM) {
                Button {
                    discuss(post)
                } label: {
                    HStack(spacing: OneDayMetrics.spacingXS) {
                        Image(systemName: "text.bubble")
                        Text("讨论")
                    }
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                }
                .buttonStyle(.plain)
                Button {
                    store.deleteSeed(post)
                } label: {
                    HStack(spacing: OneDayMetrics.spacingXS) {
                        Image(systemName: "trash")
                        Text("删除")
                    }
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                }
                .buttonStyle(.plain)
                Text(post.kind.label)
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                Spacer()
            }
        } else {
            seedlessActionRow(post)
        }
    }

    private func seedlessActionRow(_ post: BridgeFeedPost) -> some View {
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
                    .font(.footnote)
                    .foregroundStyle(
                        post.isLiked ? Palette.primary : Palette.inkSecondary
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(post.isLiked ? "取消点赞" : "点赞")
            Button {
                discuss(post)
            } label: {
                HStack(spacing: OneDayMetrics.spacingXS) {
                    Image(systemName: "text.bubble")
                    Text("讨论")
                        .lineLimit(1)
                }
                .font(.footnote)
                .foregroundStyle(Palette.inkSecondary)
                .fixedSize(horizontal: true, vertical: false)
            }
            .buttonStyle(.plain)
            // §453：类别（kind.label）与方向撤出卡
            // 底——归详情页头部（类别原已在详情头，
            // 本包补方向），卡面只留四件
            // 动作行「未读」文字已撤（§126）：与底栏
            // 角标、行内蓝点同批取消未读提醒面
            Spacer()
            Text(FeedBoard.relativeShortText(
                for: post.createdAt, now: Date()
            ))
            .font(.footnote)
            .foregroundStyle(Palette.inkSecondary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            Button {
                markRead(post)
                // §489（HIG 批 A／P1-01）：字面动画收编
                // 令牌册——折叠展开走 swap 档、经 resolved
                // 出口（Reduce Motion 开启即瞬时）
                withAnimation(MotionTokens.resolved(
                    MotionTokens.swap, reduceMotion: reduceMotion
                )) {
                    expandedAboutID =
                        expandedAboutID == post.id ? nil : post.id
                }
            } label: {
                Image(systemName: expandedAboutID == post.id
                      ? "info.circle.fill" : "info.circle")
                    .font(.footnote)
                    .foregroundStyle(
                        expandedAboutID == post.id
                            ? Palette.ink : Palette.inkSecondary
                    )
                    // 第 83 条（命中域收口）：字形不变、命
                    // 中域外扩 44；负内边距按字形名义 15 抵
                    // 消（(44−15)/2），帖头行高由同排脚注文
                    // 本主导、布局不动
                    .frame(
                        width: OneDayMetrics.minTapTarget,
                        height: OneDayMetrics.minTapTarget
                    )
                    .contentShape(Rectangle())
                    .padding(-(OneDayMetrics.minTapTarget - 15) / 2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                expandedAboutID == post.id ? "收起关于" : "关于"
            )
        }
    }

    /// 「关于」展开节（§453 对 Muse 定版）：ⓘ 在
    /// 卡内原地展开——标题「为何我创建这篇帖子」＋
    /// 生成理由（why 真字段）＋节底精确时刻；无理
    /// 由的帖只给时刻、不编理由。内容裁决在 Core
    /// FeedBoard.aboutSection，展开态与 ⓘ 实心态绑定
    @ViewBuilder
    private func aboutSection(_ post: BridgeFeedPost) -> some View {
        let about = FeedBoard.aboutSection(for: post)
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
            Divider()
            if about.showsHeading {
                Text("为何我创建这篇帖子")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.inkSecondary)
                if let reason = about.reason {
                    Text(reason)
                        .font(.subheadline)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            Text(about.preciseTime)
                .font(.subheadline)
                .foregroundStyle(Palette.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(.opacity)
    }

    private func openPost(_ post: BridgeFeedPost) {
        markRead(post)
        path.append(Route.post(post.id))
    }

    private func openPostImage(
        _ post: BridgeFeedPost, url: URL, previewLongEdge: Int
    ) {
        imageViewerSession = ImageViewerSession(
            feedImages: post.images, selectedURL: url, previewLongEdge: previewLongEdge
        )
    }

    /// 链接出处图判定（§486.3）：图注 sourceUrl 命
    /// 中本帖任一链接或来源卡的 url＝该页的 OG 图
    /// （桥抓图口径：图出自来源页，见 BridgeFeed-
    /// Image）；空 sourceUrl 不命中
    private func isLinkCoverImage(
        _ image: BridgeFeedImage, of post: BridgeFeedPost
    ) -> Bool {
        guard !image.sourceUrl.isEmpty else { return false }
        if post.links.contains(where: { $0.url == image.sourceUrl }) {
            return true
        }
        return post.sourceCard?.url == image.sourceUrl
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
        if let linkedID = appState.sessionLedger.threadID(
            forFeedDiscussPostID: post.id
        ), let existing = fetchThread(linkedID) {
            thread = existing
        } else {
            let fresh = ChatThread()
            modelContext.insert(fresh)
            try? modelContext.save()
            appState.sessionLedger.linkFeedDiscussThread(
                fresh.id, postID: post.id
            )
            thread = fresh
        }
        // §210：引用直写目标线程的待发状态（落点决定
        // 与引用写入同动作完成），不再经全局种子
        appState.pendingQuotes.feedQuotesByThread[thread.id] =
            FeedPostQuote(post: post)
        appState.router.drawerThreadSelection = thread.id
        appState.router.mainTabSwitchRequest = .chat
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
    private func refsRow(_ post: BridgeFeedPost) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: OneDayMetrics.spacingSM) {
                ForEach(
                    Array(post.refs.enumerated()), id: \.offset
                ) { _, ref in
                    if let type = ref.refType {
                        if post.kind == .event,
                           refSourceReady(type),
                           refResolvedTitle(ref) == nil {
                            // §459 事件帖来源行：源头实体
                            // 已不在（删除/过期）——帖仍
                            // 在，来源置灰标已删除、不给
                            // 假链接
                            HStack(spacing: OneDayMetrics.spacingXS) {
                                Image(
                                    systemName: type.symbolName
                                )
                                .font(.caption2)
                                Text("\(type.label) · 已删除")
                                    .lineLimit(1)
                            }
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Palette.inkSecondary)
                        } else {
                            Button {
                                path.append(Route.ref(ref))
                            } label: {
                                HStack(spacing: OneDayMetrics.spacingXS) {
                                    Image(
                                        systemName: type.symbolName
                                    )
                                    .font(.caption2)
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
    }

    /// ref 源名单就绪判据（§459）：对应 store 已成
    /// 功加载过才许下「已删除」结论；未就绪（本会话
    /// 还没去过那个面）时存亡未知，事件帖来源行回
    /// 既有中性呈现（蓝链＋类别文案，点达后详情自
    /// 带懒拉见真章），不许把没加载冒充已删除
    private func refSourceReady(_ type: FeedRefType) -> Bool {
        switch type {
        case .idea:
            return ideasStore.loadState == .ready
        case .goal, .briefing:
            return goalsStore.loadState == .ready
        case .task:
            return kanban.snapshot != nil
        case .monitor:
            return monitorsStore.loadState == .ready
        }
    }

    /// ref 标题真解析：实体在对应名单里才有标题；
    /// 解析不到回 nil（与 refLabel 的类别文案兜底分
    /// 工——那是呈现兜底、这是存亡判据，不许混用）
    private func refResolvedTitle(
        _ ref: BridgeFeedRef
    ) -> String? {
        switch ref.refType {
        case .idea:
            return ideasStore.ideas
                .first { $0.id == ref.id }?.title
        case .goal:
            return goalsStore.goals
                .first { $0.id == ref.id }?.title
        case .task:
            return kanban.snapshot?.tasks
                .first { $0.id == ref.id }?.title
        case .monitor:
            return monitorsStore.monitors
                .first { $0.id == ref.id }?.name
        case .briefing:
            guard let gid = ref.goalId,
                  let goal = goalsStore.goals
                    .first(where: { $0.id == gid })
            else { return nil }
            return "《\(goal.title)》的简报"
        case nil:
            return nil
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
    /// ref 呈现信息（§459）：标题真解析＋已删除判据
    /// 由列表面注入（与卡面来源行同源）；缺省＝无标
    /// 题、不断言已删除（独立呈现时不断言存亡）
    var refInfo: (BridgeFeedRef) -> (
        title: String?, isDeleted: Bool
    ) = { _ in (nil, false) }
    let onOpenImage: (BridgeFeedPost, URL) -> Void
    let onOpenImageGallery: (ImageViewerSession) -> Void
    let onOpenRef: (BridgeFeedRef) -> Void

    var body: some View {
        Group {
            if let post = store.post(id: postID) {
                ScrollView {
                    VStack(alignment: .leading, spacing: OneDayMetrics.spacingM) {
                        HStack(spacing: OneDayMetrics.spacingS) {
                            Image(systemName: post.kind.symbolName)
                                .font(.subheadline)
                                .foregroundStyle(Palette.inkSecondary)
                            Text(post.kind.label)
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(Palette.inkSecondary)
                            // §453：方向自卡底撤出后归
                            // 此（类别原已在详情头）
                            if let direction = post.direction,
                               !direction.isEmpty {
                                Text(direction)
                                    .font(.footnote.weight(.medium))
                                    .foregroundStyle(Palette.inkSecondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            // FA-2：种子帖无产出时刻，
                            // 详情头不显相对时间
                            if !FeedSeedPosts.isSeed(post.id) {
                                Text(FeedBoard.relativeText(
                                    for: post.createdAt, now: Date()
                                ))
                                .font(.footnote)
                                .foregroundStyle(Palette.inkSecondary)
                            }
                        }
                        // §459：有用度只作弱提示——详情
                        // 头下一行小字，不进卡面主视觉、
                        // 不参与任何本地排序
                        if let usefulness = post.usefulness {
                            Text("有用度 \(Int(usefulness.rounded()))")
                                .font(.footnote)
                                .foregroundStyle(Palette.inkSecondary)
                        }
                        Text(post.title)
                            // 0.41.0（C14/P5）：字面量收编
                            // 内容标题定点 FontRoles
                            // .contentTitle（值不变）
                            .font(.contentTitle)
                            .foregroundStyle(Palette.ink)
                        // 每张配图都能从自身位置打开同帖相册。
                        ForEach(
                            Array(post.images.enumerated()),
                            id: \.offset
                        ) { _, item in
                            if let url = item.galleryURL {
                                FeedPostImagePreview(
                                    url: url, longEdgeCap: 1600,
                                    cornerRadius: OneDayMetrics.radiusCard
                                ) {
                                    onOpenImage(post, url)
                                }
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
                        MarkdownText(post.body, onOpenImageGallery: onOpenImageGallery)
                        if let card = post.sourceCard {
                            FeedSourceCardView(card: card)
                        }
                        if !post.links.isEmpty {
                            VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
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
                                                .font(.caption)
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
                            VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
                                Text("引用")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(Palette.inkSecondary)
                                ForEach(
                                    Array(post.refs.enumerated()),
                                    id: \.offset
                                ) { _, ref in
                                    if let type = ref.refType {
                                        let info = refInfo(ref)
                                        if post.kind == .event,
                                           info.isDeleted {
                                            // §459：源头已删除
                                            // ——置灰、不给假链接
                                            HStack(spacing: OneDayMetrics.rowInnerGap) {
                                                Image(
                                                    systemName: type.symbolName
                                                )
                                                .font(.caption)
                                                Text("\(type.label) · 已删除")
                                                Spacer()
                                            }
                                            .font(.subheadline)
                                            .foregroundStyle(Palette.inkSecondary)
                                        } else {
                                            Button {
                                                onOpenRef(ref)
                                            } label: {
                                                HStack(spacing: OneDayMetrics.rowInnerGap) {
                                                    Image(
                                                        systemName: type.symbolName
                                                    )
                                                    .font(.caption)
                                                    Text(
                                                        post.kind == .event
                                                            ? (info.title ?? type.label)
                                                            : type.label
                                                    )
                                                    Spacer()
                                                    Image(
                                                        systemName: "chevron.right"
                                                    )
                                                    .font(.caption2.weight(.semibold))
                                                }
                                                .font(.subheadline)
                                                .foregroundStyle(Palette.primary)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(OneDayMetrics.spacingM)
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

/// 列表和详情共用的 16:9 帖图入口，加载成功后显示。
private struct FeedPostImagePreview: View {
    let url: URL
    let longEdgeCap: Int
    let cornerRadius: CGFloat
    let onOpen: () -> Void

    var body: some View {
        LazyImage(request: RemoteImageRequestFactory.publicRequest(
            url: url, longEdgeCap: longEdgeCap
        )) { state in
            if let image = state.image {
                Button(action: onOpen) {
                    Color.clear
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .overlay { image.resizable().scaledToFill() }
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                        .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
                }
                .buttonStyle(.odPressable)
                .accessibilityLabel(A11yText.imageLabel(fileName: url.lastPathComponent))
                .accessibilityHint(L10n.string("查看大图"))
            }
        }
        .pipeline(OneDayImagePipelines.remote)
        .id(url)
    }
}

private extension BridgeFeedImage {
    var galleryURL: URL? {
        guard let url = URL(string: self.url),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              url.host != nil
        else { return nil }
        return url
    }
}

extension ImageViewerSession {
    init?(feedImages: [BridgeFeedImage], selectedURL: URL, previewLongEdge: Int) {
        var seen: Set<URL> = []
        let urls = feedImages.compactMap(\.galleryURL).filter {
            seen.insert($0).inserted
        }
        guard let index = urls.firstIndex(of: selectedURL) else { return nil }
        self.init(
            items: urls.map {
                ChatImageViewerItem(source: .publicURL($0, previewLongEdge: previewLongEdge))
            },
            initialIndex: index
        )
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
                // §418：同口径换 LazyImage；未成/失败显
                // selectionFill 的旧回落由 else 分支保留
                LazyImage(
                    request: RemoteImageRequestFactory
                        .publicRequest(
                            url: url, longEdgeCap: 160)
                ) { state in
                    if let image = state.image {
                        image
                            .resizable()
                            .scaledToFill()
                    } else {
                        Palette.selectionFill
                    }
                }
                .pipeline(OneDayImagePipelines.remote)
                .id(url)
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
                    HStack(spacing: OneDayMetrics.spacingSM) {
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
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Palette.inkSecondary)
        }
        .padding(OneDayMetrics.spacingSM)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Palette.surface,
            in: RoundedRectangle(
                cornerRadius: OneDayMetrics.radiusCard,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: OneDayMetrics.radiusCard,
                style: .continuous
            )
            .strokeBorder(Palette.hairline, lineWidth: 1)
        }
        if let url = URL(string: card.url) {
            Link(destination: url) { content }
        } else {
            content
        }
    }
}

/// 链接预览卡（§486.3）：照 Muse 动态页 OG 卡形
/// 态——站点名（小字，顶）＋标题（大字 semibold）
/// ＋域名（小字，底），整卡点开链接。数据只用桥下
/// 发的 link{title, url}：桥不下发 og:site_name／
/// og:description，App 不自拼不假造（来源卡 §0.38
/// 同旨）——站点名位与域名位同由 url 的 host 派生
/// （去 www.），域名位在路径非根时带路径以与站点
/// 名位区分；根路径时域名位与站点名位同值、只显
/// 站点名位一行。卡面与来源卡同族（surface 底＋
/// radiusCard）
struct FeedLinkPreviewCard: View {
    let link: BridgeFeedLink

    @Environment(\.openURL) private var openURL

    private var url: URL? { URL(string: link.url) }

    /// 站点标识：host 去 www.（URL 事实派生，非编造）
    private var host: String {
        guard let host = url?.host(percentEncoded: false)
        else { return "" }
        return host.hasPrefix("www.")
            ? String(host.dropFirst(4)) : host
    }

    /// 域名行：host＋非根路径；根路径返回 nil（不与
    /// 站点名行重复）
    private var domainLine: String? {
        guard let url, !host.isEmpty else { return nil }
        let path = url.path(percentEncoded: false)
        guard !path.isEmpty, path != "/" else { return nil }
        return host + path
    }

    var body: some View {
        Button {
            if let url { openURL(url) }
        } label: {
            VStack(
                alignment: .leading,
                spacing: OneDayMetrics.spacingS
            ) {
                if !host.isEmpty {
                    Text(host)
                        .font(.subheadline)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                }
                Text(link.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let domainLine {
                    Text(domainLine)
                        .font(.subheadline)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(OneDayMetrics.spacingM)
            .background(
                Palette.surface,
                in: RoundedRectangle(
                    cornerRadius: OneDayMetrics.radiusCard,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: OneDayMetrics.radiusCard,
                    style: .continuous
                )
                .strokeBorder(Palette.hairline, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.odPressable)
        .accessibilityLabel("链接：\(link.title)")
    }
}

/// 来源小 sheet 已退役（§453）：ⓘ 改 Muse 式
/// 「关于」原地展开节——why 归展开节，links/refs
/// 归详情页（详情头与正文区已全量呈现），卡面不
/// 再开 sheet

/// 简报编辑器（§459 单层制，推翻 0.38.0 两层制）：
/// 只有一个文本框绑服务端 text——打开见当前生效
/// 全文（润色稿仅在与原文逐字对齐时才由服务端出
/// 数，见 FeedBriefBoard.effectiveText），保存只发
/// PUT /meta/brief {"text"} 原样落盘；润色状态以
/// 极小提示如实呈现，不许假装已润色。本地未保存
/// 草稿与服务端不一致时打开先弹问、不许静默吞
/// 简报编辑器（§487 呈现换轨）：内容逻辑沿 §473
/// 件一定版（打开必回读／pending 轻轮询／已改字不
/// 覆盖／保存恒可用，逻辑一字未动）；呈现弃底部全
/// 屏 sheet，改顶部锚定覆盖面板（TopAnchoredPanel
/// 组件，几何与主题照参照录屏量测抄，DESIGN
/// §487）。页头只剩两行——标题＋一句说明（用户
/// 2026-11-24 12:09 亲令简化）；其余说明性文字全
/// 删（清点见 §487），只留错误回执（保存失败／上
/// 次整理失败）——回执不是说明。
struct FeedBriefEditorView: View {
    @Environment(AppState.self) private var appState
    let store: FeedStore
    /// 呈现根层屏高（TopAnchoredPanel 闭包下传）：
    /// 卡高按 TopPanelMetrics 占比取
    let screenHeight: CGFloat
    /// 关闭呈现（代旧 sheet 的 dismiss 环境值）
    let onClose: () -> Void

    @State private var text = ""
    @State private var initialized = false
    /// 回读基线（§473 件一）：打开时回读到的服务端生
    /// 效全文——变更判定与草稿对账以它为准；轮询换
    /// 新时仅在用户未改字时让编辑框跟随、已改字只换
    /// 基线不动编辑框；保存成功后随回执更新
    @State private var baselineText = ""
    @State private var draftConflictShown = false

    /// 未改字判定（与草稿对账同源 FeedBriefBoard）：
    /// 保存钮灰置档位以此为准——仅视觉档位，钮恒可
    /// 用（§473 定版：禁用只剩 briefSaving 一因）
    private var textUnchanged: Bool {
        !FeedBriefBoard.textChanged(baselineText, text)
    }

    var body: some View {
        VStack(spacing: TopPanelMetrics.cardButtonGap) {
            card
            buttonRow
        }
        .task {
            // 打开必回读最新 briefDoc（§473 件一）：
            // 不许再以「已有缓存」跳过——服务端润
            // 色写回的专业稿靠本回读进编辑器（简报
            // 定版第 3 条的 App 侧断链就此接上）
            await store.loadBrief(appState: appState)
            if !initialized {
                let server = serverText
                baselineText = server
                if let draft = store.briefDraftText,
                   FeedBriefBoard.textChanged(server, draft) {
                    // 未保存草稿与服务端回读不一致：先以
                    // 草稿占位并弹问，不许静默吞（§459）
                    text = draft
                    draftConflictShown = true
                } else {
                    text = server
                }
                initialized = true
            }
            // pending 期轻轮询（§473 件一）：约 10s
            // 回读一次、done/error 即停；只换基线，
            // 编辑框跟随与否在 onChange(briefDoc)
            // 按「未改字才跟随」口径处理
            while !Task.isCancelled,
                  let doc = store.briefDoc,
                  Self.polishInFlight(doc) {
                try? await Task.sleep(for: .seconds(10))
                if Task.isCancelled { break }
                await store.loadBrief(appState: appState)
            }
        }
        .onAppear {
            // 面板落位触感（用户 2026-11-25 裁定）：
            // 顶部锚定面板入位（内容挂载＝状态真翻转）
            // 即震 impact .light，表 D 既有语义，只接线
            Haptics.impact(.light)
        }
        .onChange(of: store.briefDoc) { _, newDoc in
            // 轮询换新（§473 件一）：编辑框仍等于旧
            // 基线（用户未改字）时跟随新全文；已改
            // 字只换基线、不覆盖编辑框
            guard initialized, let newDoc else { return }
            let newServer = FeedBriefBoard
                .effectiveText(newDoc)
            if !FeedBriefBoard.textChanged(baselineText, text) {
                text = newServer
            }
            baselineText = newServer
        }
        .onChange(of: text) { _, newValue in
            if initialized {
                store.noteBriefDraft(
                    newValue, serverText: baselineText
                )
            }
        }
        .confirmationDialog(
            "有未保存的修改",
            isPresented: $draftConflictShown,
            titleVisibility: .visible
        ) {
            Button("继续编辑未保存的内容") {}
            Button(
                "用服务器上的版本", role: .destructive
            ) {
                text = baselineText
                store.discardBriefDraft()
            }
        } message: {
            Text("上次写的内容还没保存，和服务器上的简报不一样。")
        }
    }

    /// 编辑卡：页头两行钉住（标题＋一句说明，错误回
    /// 执随页头同钉）＋正文卡内滚动、上下缘淡出遮罩
    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            FeedBriefPanelHeader(
                briefError: store.briefError,
                expandError: store.briefDoc?.expandError
            )
            TextEditor(text: $text)
                .font(.body)
                .foregroundStyle(.white)
                .tint(.white)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                // TextEditor 内建 5pt 行首缩进补偿：
                // 正文左缘与页头标题对齐（参照同形）
                .padding(.leading, -5)
                .padding(.top, 6)
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.07),
                            .init(color: .black, location: 0.93),
                            .init(color: .clear, location: 1),
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                }
        }
        .padding(
            .horizontal, TopPanelMetrics.contentHorizontalInset
        )
        .padding(.top, 24)
        .padding(.bottom, 14)
        .frame(
            height: TopPanelMetrics.cardHeight(
                screenHeight: screenHeight
            )
        )
        .frame(maxWidth: .infinity)
        .background(
            TopPanelMetrics.cardFill,
            in: RoundedRectangle(
                cornerRadius: TopPanelMetrics.cornerRadius,
                style: .continuous
            )
        )
        .padding(
            .horizontal, TopPanelMetrics.cardHorizontalInset
        )
    }

    /// 双钮出卡固定（§487 照参照）：卡下 10pt、黑底
    /// 上等宽胶囊；保存未改字呈灰置观感（仅视觉档
    /// 位、恒可用，见 textUnchanged）
    private var buttonRow: some View {
        HStack(spacing: TopPanelMetrics.buttonSpacing) {
            Button {
                onClose()
            } label: {
                Text("取消")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: TopPanelMetrics.buttonHeight)
                    .background(
                        TopPanelMetrics.cardFill, in: Capsule()
                    )
                    .contentShape(Capsule())
            }
            .buttonStyle(.odPressable)
            Button {
                Task { await save() }
            } label: {
                ZStack {
                    Text("保存")
                        .font(.headline)
                        .foregroundStyle(
                            textUnchanged
                                ? TopPanelMetrics.saveIdleLabel
                                : .white
                        )
                    if store.briefSaving {
                        HStack {
                            Spacer()
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        }
                        .padding(
                            .trailing, OneDayMetrics.spacingM
                        )
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: TopPanelMetrics.buttonHeight)
                .background(
                    TopPanelMetrics.cardFill, in: Capsule()
                )
                .contentShape(Capsule())
            }
            .buttonStyle(.odPressable)
            .disabled(store.briefSaving)
        }
        .padding(
            .horizontal,
            TopPanelMetrics.buttonRowHorizontalInset
        )
    }

    /// 服务端生效全文（store 回读口径；baselineText
    /// 是打开时定格的基线快照，本口只在初始化时用）
    private var serverText: String {
        store.briefDoc.map(FeedBriefBoard.effectiveText) ?? ""
    }

    /// 润色在飞判定（新契约 pending／旧桥 idle 且
    /// expanding 同义，§459 旧口径）：轮询口径
    private static func polishInFlight(
        _ doc: BridgeBriefDoc
    ) -> Bool {
        doc.polishState == .pending
            || (doc.polishState == .idle && doc.expanding)
    }

    private func save() async {
        // 保存成功即关页（对齐参照表单形态：保存＝
        // 落盘＋离开）；失败留在页内看 briefError
        // 触感补接线（§487）：走全 App 单源表 D 既
        // 有语义（保存＝任务成功／操作失败），只接
        // 线不新造；失败震以 briefError 回执在案为
        // 准——无回执的静默 false（如未连接时保存
        // 守卫）不震
        if await store.saveBriefText(appState: appState, text) {
            baselineText = serverText
            Haptics.success()
            onClose()
        } else if store.briefError != nil {
            Haptics.error()
        }
    }
}
/// 简报面板页头（§487）：只剩两行——标题「动态说
/// 明」＋一句说明，钉在卡顶不随正文滚；错误回执
/// （保存失败／上次整理失败）随页头同钉、恒可见。
/// 独立成件以便钉测实测其高（见 §487 钉测）。
struct FeedBriefPanelHeader: View {
    let briefError: String?
    let expandError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("动态说明")
                .font(.title2.bold())
                .foregroundStyle(.white)
            Text("你的动态版块由以下指示驱动。"
                 + "你对此说明做出的任何编辑，"
                 + "都将应用于今后的动态帖子。")
                .font(.subheadline)
                .foregroundStyle(
                    TopPanelMetrics.textSecondary
                )
            // 错误回执（功能必需，§487 清点留）：
            // 保存失败即时回执
            if let briefError {
                Text(briefError)
                    .font(.footnote)
                    .foregroundStyle(
                        TopPanelMetrics.errorText
                    )
            }
            // 错误回执（同上）：上次整理失败的服务
            // 端回执（旧 weakPolishHint 的 expandError
            // 分支——其余弱提示文案已按 §487 全删）
            if let expandError, !expandError.isEmpty {
                Text("上次整理没成功：\(expandError)")
                    .font(.footnote)
                    .foregroundStyle(
                        TopPanelMetrics.errorText
                    )
            }
        }
    }
}

// MARK: - Kicker 字形块映射（§462）

extension FeedPostKind {
    /// kicker 字形块底色（§462）：按类别映射到 Palette
    /// 既有令牌——扁平色块，去卡通化
    var kickerColor: Color {
        switch self {
        case .digest: return Palette.tintSky
        // §459 合并补 case（0.50.111 组版）：.event 为
        // §459 复活的本地事件成帖新 kind，§462 映射表
        // 成表时该 kind 不存在；事件帖同属系统装配面，
        // 与 .digest 同族取 tintSky，不新造令牌
        case .event: return Palette.tintSky
        case .morning: return Palette.tintOrange
        case .research: return Palette.tintLavender
        case .seed: return Palette.tintGreen
        case .unknown: return Palette.primaryPale
        }
    }

    /// kicker 图标语义前景色（Batch 5 #51）：与 kickerColor 成对，
    /// 对齐通知页与点子页分层渲染风格
    var kickerTint: Color {
        switch self {
        case .digest, .event: return Palette.tintSkyInk
        case .morning: return Palette.tintOrangeInk
        case .research: return Palette.tintLavenderInk
        case .seed: return Palette.tintGreenInk
        case .unknown: return Palette.primary
        }
    }
}
