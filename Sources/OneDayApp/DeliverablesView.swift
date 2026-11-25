import OneDayCore
import OneDayDesign
import SwiftUI
import UIKit

/// 文件格（0.20.0 底栏第四格）：照用户给的 Muse 资
/// 源库页——顶部身份区（左抽屉钮／中央身份胶囊／右
/// 钮），其下大分段 [文件｜影音内容]。
///
/// **交付物口径（用户原话：用户让做的东西做好之后
/// 放里面的，如 PPT——不是服务器全部文件）**：数据
/// 自 A-06（伴生 1.0.66）起走文件库聚合读面（GET
/// /api/oneday-bridge/file-library）单流下发——产出
/// 根走查、准入（0.22.0 去污形态拦截＋根散白名单＋
/// 敏感名单第二道）、去重、排序全在服务端，单一事
/// 实源在 oneday_seg_filelibrary.py。P8（0.14.0）起
/// 的客户端爬 /api/files 目录树聚合（8 根硬编码、
/// 递归 ≤3 层、600 静默截断、客户端准入）已退役。
/// 服务端文件全量浏览不在本页（••• 菜单组3「系统
/// 文件」与设置「管理」共用 FilesBrowserView）。
///
/// **0.36.31 文件页 v2（规格 files-page-design-
/// 20261110 §4＋两附记）**：右上搜索钮撤除、改 •••
/// 菜单收纳（组1 显示 列表/网格、组2 排序 上次打开/
/// 上次修改/标题——页级状态 @AppStorage 持久化、两
/// 段共用；组3 系统文件；组4 上传文件）；搜索改下拉
/// 露出（滚动偏移触发、无新增手势件；下拉刷新因此
/// 退役——同一拉动手势只供一主，失败态给显式重试钮
/// 补位）；文件段网格＝双列内容卡（缩略首面＋展示标
/// 题＋类型签，§4.3 落值）；影音段补列表态；网格态
/// 文件段按 7 天窗分「最近/全部」（§4.5 自有口径）；
/// 打开写本地上次打开记录（排序辅助、丢了不伤数
/// 据，非第二真源——规格 §六切割声明）；条目菜单与
/// 打开分流按类型走 Core FileActionPolicy（附记硬规
/// 矩：文本类进文档阅读页并给复制文字/导出 PDF，敏
/// 感文件在本面已被准入挡下、浏览器面另有锁定）；
/// 聚合根新增 attachments（聊天发送的文件副本，
/// 0.36.29 通道落点——服务端无自动过期，本面呈现＋
/// 删除即其生命周期出口）。
struct DeliverablesView: View {
    @Environment(AppState.self) private var appState
    // 动效走令牌＋resolved 出口（0.25.0 起本面口径）
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 文件库聚合读面客户端（A-06）：聚合集唯一来源
    private let bridgeClient = OneDayBridgeClient()

    /// §452 定版③：类别筛选片（全部/文档/图片/影
    /// 音/其他）——文件/影音分段退役，单列表单源
    @State private var category: LibraryCategory = .all
    /// §452 定版①：来源筛选（""＝全部来源）
    @State private var sourceFilter = ""
    /// §452.9：最近搜索（本地存、最近在前、上限 8）
    @AppStorage("library.recentSearches")
    private var recentSearchesRaw = "" 
    /// §369（缓存 C4）：名单走 AppState 共享店＋落盘
    /// 快照（LibraryListStore）——冷启先显快照、后台
    /// 对账换新，删除本地摘行不重拉；本面只读消费
    private var listStore: LibraryListStore {
        appState.sharedLibraryListStore()
    }
    private var deliverables: [Deliverable]? {
        listStore.deliverables
    }
    /// F1：派生快照指纹缓存（LibrarySnapshotCache，
    /// 输入未变回存量快照、不整趟重算）
    @State private var snapshotCache = LibrarySnapshotCache()
    @State private var loadError: String?
    @State private var pendingDelete: Deliverable?
    @State private var shareItem: FileShareItem?
    @State private var notice: String?
    @State private var query = ""
    @State private var searchVisible = false
    /// 非图条目打开目的地（§125 合并）：旧
    /// previewEntry/readerEntry 双状态分流（预览页/
    /// 阅读页）退役，统一先进文件打开页
    @State private var previewEntry: WorkspaceFileEntry?

    /// 身份簇点按进中枢（§498：ContentPageHeader 的
    /// onOpenHub 落点，与动态/点子同式——原小胶囊在
    /// 本页不可点，收编后同义补齐）
    @State private var showHub = false
    /// 图片查看器路由（0.36.4）：图片直达查看器（系
    /// 统 zoom 转场、源＝格/卡的 matched 标记），不
    /// 再先进预览页
    @State private var viewerRoute: ImageViewerRoute?
    @Namespace private var viewerNamespace
    /// 上次打开记录（§4.3/§4.5 排序辅助，本地表）
    @State private var openHistory = FileOpenHistoryStore()
    /// 显示方式与排序：页级状态、持久化（§4.2）
    @AppStorage("files.displayMode")
    private var displayModeRaw = LibraryDisplayMode.list.rawValue
    @AppStorage("files.sort")
    private var sortRaw = LibrarySort.lastModified.rawValue
    @State private var uploadPickerPresented = false
    @State private var systemFilesRoute: SystemFilesRoute?
    /// 定位高亮（§131）：「在文件页中打开」消费后置
    /// 位目标路径，行/卡闪高亮、数秒后自清
    @State private var revealedPath: String?

    /// 系统文件目的地（§131 泛化）：常规入口 dir/
    /// highlight 皆空；定位回指落空（文件不在聚合集
    /// 内）时带父目录＋文件名直达浏览器定位
    private struct SystemFilesRoute: Identifiable, Hashable {
        let dir: String?
        let highlight: String?
        var id: String { "\(dir ?? "")|\(highlight ?? "")" }
    }

    /// 置顶集（§131）：全 App 单例，与打开页切换态
    /// 同一份（FilePinStore 口径）
    private var pinStore: FilePinStore { .shared }

    private var displayMode: LibraryDisplayMode {
        LibraryDisplayMode.resolved(rawValue: displayModeRaw)
    }

    private var sort: LibrarySort {
        LibrarySort.resolved(rawValue: sortRaw)
    }

    /// 「更多」菜单两组 Picker 的 selection 绑定（样式
    /// 二期 S2-04）：读经 Core resolved 解析（未知原值
    /// 回落默认档、恰一勾），写回落盘原值
    private var displayModeBinding: Binding<LibraryDisplayMode> {
        Binding(
            get: { displayMode },
            set: { displayModeRaw = $0.rawValue }
        )
    }

    private var sortBinding: Binding<LibrarySort> {
        Binding(
            get: { sort },
            set: { sortRaw = $0.rawValue }
        )
    }

    /// 查看器集合载荷：同段图片条目＋起始索引
    private struct ImageViewerRoute: Identifiable, Hashable {
        let entries: [WorkspaceFileEntry]
        let initialIndex: Int
        var id: String { entries[initialIndex].path }
    }

    var body: some View {
        // §363（S4）：派生快照一趟只算一次、下传内容面
        // 共用（旧计算属性每访问整表重排，见
        // LibraryListSnapshot 头注）；F1（2026-11-23）：
        // 入口改走指纹缓存——输入未变回存量快照，整
        // 趟重算只在名单／搜索／排序／打开史／置顶／
        // 分段真变时发生
        let snapshot = snapshotCache.snapshot(
            deliverables: deliverables,
            query: query,
            sort: sort,
            openedAt: openHistory.openedAtMap,
            pinned: pinStore.pinnedPaths,
            segment: 0,
            category: category,
            source: sourceFilter
        )
        return NavigationStack {
            VStack(spacing: 0) {
                identityHeader
                pageTitleRow
                if searchVisible {
                    searchFieldRow
                }
                filterChipsRow
                if searchVisible && query.isEmpty {
                    searchSuggestions
                } else {
                    libraryContent(snapshot)
                }
            }
            // 0.43.0（A11Y-V7）：「文件」Rotor——条目
            // 与行/卡标记同名对位（见 fileRotorNames-
            // pace 注）
            .accessibilityRotor(
                L10n.string("文件")
            ) {
                ForEach(
                    snapshot.sortedItems.map(\.name),
                    id: \.self
                ) { name in
                    AccessibilityRotorEntry(
                        DeliverableFileType.displayTitle(
                            forFileName: name
                        ),
                        name, in: fileRotorNamespace
                    )
                }
            }
            .background {
                Palette.pageBG
                    .ignoresSafeArea()
            }
            .toolbar(.hidden, for: .navigationBar)
            // H2 收编：中枢改 cover 呈现（与聊天页
            // 同一宿主），原 push 入中枢退役
            .hubCover(isPresented: $showHub)
            // §125：打开分流收口——非图条目一律落文
            // 件打开页（中间页），文本类的阅读在其页
            // 内主钮进阅读页；旧 previewEntry/
            // readerEntry 双目的地分流退役（状态合并
            // 至 previewEntry）
            .navigationDestination(item: $previewEntry) { entry in
                FileOpenContent(
                    target: FileOpenTarget(entry: entry),
                    origin: .serverFile
                )
            }
            .navigationDestination(item: $systemFilesRoute) { route in
                FilesBrowserView(
                    initialPath: route.dir,
                    highlightName: route.highlight
                )
                .navigationTitle("系统文件")
                .navigationBarTitleDisplayMode(.inline)
            }
            .navigationDestination(item: $viewerRoute) { route in
                ImageViewerView(
                    items: route.entries.map {
                        ChatImageViewerItem(
                            source: .remotePath($0.path),
                            mtime: $0.mtime ?? 0
                        )
                    },
                    initialIndex: route.initialIndex,
                    onDeleteItem: { item in
                        if case .remotePath(let path) = item.source,
                           let entry = route.entries.first(
                               where: { $0.path == path }
                           ) {
                            Task { await deleteFromViewer(entry) }
                        }
                    }
                )
                .navigationTransition(
                    .zoom(
                        sourceID: route.entries[route.initialIndex]
                            .path,
                        in: viewerNamespace
                    )
                )
            }
            // §131：以文件库修订号为键——打开页改名成
            // 功递增修订号，本页重聚合不留旧名残影
            .task(id: appState.fileLibraryRevision) {
                await collectIfNeeded()
            }
            .onChange(of: appState.router.fileRevealPath) { _, _ in
                consumeRevealIfReady()
            }
            .modifier(
                FileUploadPickerModifier(
                    appState: appState,
                    isPresented: $uploadPickerPresented,
                    targetDirectory: Self.uploadsPath,
                    ensureDirectory: true
                ) { message, confirmed in
                    notice = message
                    if confirmed {
                        Task { await collect() }
                    }
                }
            )
            .confirmationDialog(
                "删除「\(pendingDelete?.entry.name ?? "")」？",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("删除", role: .destructive) {
                    // 触感矩阵（规格 §2.3）：删除确认
                    // 落锤＝impact heavy；删除成功后不
                    // 再叠 success（同一因果链只震一次）
                    Haptics.impact(.heavy)
                    if let item = pendingDelete {
                        Task { await delete(item) }
                    }
                    pendingDelete = nil
                }
                Button("取消", role: .cancel) { pendingDelete = nil }
            } message: {
                Text("删除后无法恢复。")
            }
            .sheet(item: $shareItem) { item in
                FileShareSheet(url: item.url)
            }
        }
        .fullscreenPopBridge()
    }

    // MARK: - 页大标题（§473 件四②）

    /// 大标题「资源库」：本页导航栏按定版隐藏
    /// （.toolbar(.hidden, for: .navigationBar)，身份
    /// 胶囊行代行顶栏），兄弟页的 .navigationTitle
    /// 大字阶在本页无处落——标题改置内容区顶部，
    /// 字阶与兄弟页统一（.largeTitle.weight(.bold)），
    /// 横向边距走 pageGutter 与筛选片/列表同线。
    private var pageTitleRow: some View {
        Text("资源库")
            .font(.largeTitle.weight(.bold))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, OneDayMetrics.pageGutter)
            .padding(.top, OneDayMetrics.spacingSM)
            .padding(.bottom, OneDayMetrics.spacingS)
    }

    // MARK: - 顶部身份区（§498 共同簇：左抽屉钮／中央身份区／右放大镜＋菜单）

    /// 页头簇（§498 收编）：ContentPageHeader 共同簇
    /// 本体（与聊天基准/动态/点子/目标同件同数），
    /// 取代自写 identityHeader＋IdentityAnchor 小横
    /// 胶囊＋headerCircleButton 私有副本。右位登记
    /// ＝放大镜（开搜索行）＋菜单钮（下四组功能）
    private var identityHeader: some View {
        ContentPageHeader(
            onOpenHub: {
                HubCoverPresenter.present(
                    $showHub, reduceMotion: reduceMotion
                )
            }
        ) {
            HStack(spacing: OneDayMetrics.spacingS) {
                // §452.9：搜索钮——放大镜图标钮与菜单
                // 钮同排同级（点开顶栏下原地展开搜索
                // 行＋取消，见 searchFieldRow）
                PageHeaderCircleButton(
                    symbol: "magnifyingglass",
                    label: "搜索"
                ) {
                    toggleSearch()
                }
                // §4.1/§4.2：右上菜单钮——组1 显示、组2 排序（每组单
                // 选）、组3 系统文件、组4 上传文件
                // （OneDay 扩展，规格标注）。两组单选改
                // 系统 Picker 承载（样式二期 S2-04）：
                // 勾由系统按 selection 绘制、占固定左
                // 槽、文字同 x 对齐；旧手工对勾塞 Label
                // 图标位的形态（选中行文字右移、无勾行
                // 贴边，与模型双勾 P-04 同根）整段退役，
                // 正道据 ChatView 模型菜单注释与苹果反
                // 馈 FB16679936（Toggle/Picker）
                Menu {
                    Section("显示") {
                        Picker("显示", selection: displayModeBinding) {
                            ForEach(
                                LibraryDisplayMode.allCases, id: \.self
                            ) { mode in
                                Text(mode.label).tag(mode)
                            }
                        }
                    }
                    Section("排序") {
                        Picker("排序", selection: sortBinding) {
                            ForEach(
                                LibrarySort.allCases, id: \.self
                            ) { option in
                                Text(option.label).tag(option)
                            }
                        }
                    }
                    Section {
                        Button {
                            systemFilesRoute = SystemFilesRoute(
                                dir: nil, highlight: nil
                            )
                        } label: {
                            Label("系统文件", systemImage: "folder")
                        }
                    }
                    Section {
                        Button {
                            uploadPickerPresented = true
                        } label: {
                            Label(
                                "上传文件",
                                systemImage: "arrow.up.doc"
                            )
                        }
                    }
                } label: {
                    PageHeaderCircleGlyph(symbol: "ellipsis")
                }
                .accessibilityLabel("资源库菜单")
            }
        }
    }

    /// 下拉露出搜索栏（§4.2）：搜当前聚合集的文件名
    /// （本地过滤）；展开/收起由内容滚动偏移驱动（见
    /// handleScrollOffset），不新增手势识别器
    private var searchFieldRow: some View {
        HStack(spacing: OneDayMetrics.spacingS) {
            FileSearchField(query: $query, autoFocus: true)
                .onSubmit { recordRecentSearch() }
            Button("取消") { cancelSearch() }
                .font(.body)
                .foregroundStyle(Palette.primary)
                .buttonStyle(.odPressable)
        }
        .padding(.horizontal, OneDayMetrics.pageGutter)
        .padding(.bottom, OneDayMetrics.spacingSM)
    }

    /// §452.9②：顶栏放大镜钮开关搜索行（原地展开、
    /// 键盘随字段聚焦升起，见 FileSearchField 的
    /// autoFocus）；收起即清查询回全集
    private func toggleSearch() {
        withAnimation(
            MotionTokens.resolved(
                MotionTokens.swap, reduceMotion: reduceMotion
            )
        ) { searchVisible.toggle() }
        if !searchVisible { query = "" }
    }

    /// §452.9⑤：取消——字段撤除键盘自落、查询清空、
    /// 列表回搜索前全集（滚动位置以列表身份稳定近
    /// 似保持）
    private func cancelSearch() {
        withAnimation(
            MotionTokens.resolved(
                MotionTokens.swap, reduceMotion: reduceMotion
            )
        ) { searchVisible = false }
        query = ""
    }

    private var recentSearches: [String] {
        recentSearchesRaw.isEmpty
            ? []
            : recentSearchesRaw.components(separatedBy: "\n")
    }

    private func recordRecentSearch() {
        let term = query.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return }
        var list = recentSearches.filter { $0 != term }
        list.insert(term, at: 0)
        recentSearchesRaw = list.prefix(8)
            .joined(separator: "\n")
    }

    /// 筛选片行（§452 定版③＋452.9③）：类别片与
    /// 搜索范围片同一套——搜索内外同源、不许两套
    /// 并存；行尾来源菜单片（定版①：每项标来源、
    /// 可按来源筛）
    private var filterChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: OneDayMetrics.spacingS) {
                ForEach(LibraryCategory.allCases, id: \.self) { item in
                    Button {
                        category = item
                    } label: {
                        chipLabel(
                            title: item.label,
                            selected: category == item
                        )
                    }
                    .buttonStyle(.odPressable)
                }
                Menu {
                    Button(LibrarySourceFilter.all.label) {
                        sourceFilter = LibrarySourceFilter.all.rawValue
                    }
                    Button(LibrarySourceFilter.agent.label) {
                        sourceFilter = LibrarySourceFilter.agent.rawValue
                    }
                    Button(LibrarySourceFilter.user.label) {
                        sourceFilter = LibrarySourceFilter.user.rawValue
                    }
                } label: {
                    chipLabel(
                        title: sourceFilter.isEmpty
                            ? "全部来源" : sourceFilter,
                        selected: !sourceFilter.isEmpty
                    )
                }
            }
            .padding(.horizontal, OneDayMetrics.pageGutter)
        }
        .padding(.vertical, OneDayMetrics.spacingS)
        .sensoryFeedback(.selection, trigger: category)
    }

    private func chipLabel(
        title: String, selected: Bool
    ) -> some View {
        Text(title)
            .font(.subheadline.weight(
                selected ? .semibold : .regular
            ))
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, OneDayMetrics.spacingSM)
            .padding(.vertical, 6)
            .background(
                selected ? Palette.selectionFill : Palette.surface,
                in: Capsule()
            )
            .overlay {
                if !selected {
                    Capsule().strokeBorder(
                        Palette.separator, lineWidth: 1
                    )
                }
            }
    }

    /// 搜索空输入态（§452.9④）：最近搜索（无历史
    /// 不显此区）＋热门类型入口（点即切类别片），
    /// 不放装饰内容
    private var searchSuggestions: some View {
        ScrollView {
            VStack(
                alignment: .leading,
                spacing: OneDayMetrics.spacingL
            ) {
                if !recentSearches.isEmpty {
                    VStack(
                        alignment: .leading,
                        spacing: OneDayMetrics.spacingS
                    ) {
                        HStack {
                            Text("最近搜索")
                                .font(.sectionLabel)
                                .foregroundStyle(Palette.inkSecondary)
                            Spacer()
                            Button("清除") {
                                recentSearchesRaw = ""
                            }
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                            .buttonStyle(.odPressable)
                        }
                        ForEach(recentSearches, id: \.self) { term in
                            Button {
                                query = term
                            } label: {
                                HStack(
                                    spacing: OneDayMetrics.spacingS
                                ) {
                                    Image(
                                        systemName: "clock.arrow.circlepath"
                                    )
                                    .foregroundStyle(Palette.inkMuted)
                                    Text(term)
                                        .foregroundStyle(Palette.ink)
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.odPressable)
                        }
                    }
                }
                VStack(
                    alignment: .leading,
                    spacing: OneDayMetrics.spacingS
                ) {
                    Text("热门类型")
                        .font(.sectionLabel)
                        .foregroundStyle(Palette.inkSecondary)
                    HStack(spacing: OneDayMetrics.spacingS) {
                        suggestionType(
                            "文档", symbol: "doc.text",
                            target: .documents
                        )
                        suggestionType(
                            "图片", symbol: "photo",
                            target: .images
                        )
                        suggestionType(
                            "影音", symbol: "play.rectangle",
                            target: .media
                        )
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, OneDayMetrics.pageGutter)
            .padding(.top, OneDayMetrics.spacingS)
        }
    }

    private func suggestionType(
        _ title: String, symbol: String,
        target: LibraryCategory
    ) -> some View {
        Button {
            category = target
        } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                Text(title)
            }
            .font(.subheadline)
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, OneDayMetrics.spacingSM)
            .padding(.vertical, OneDayMetrics.spacingS)
            .background(Palette.surface, in: Capsule())
            .overlay {
                Capsule().strokeBorder(
                    Palette.separator, lineWidth: 1
                )
            }
        }
        .buttonStyle(.odPressable)
    }

    /// 下拉触发口径：内容被下拉过顶 56pt 露出搜索；
    /// 回滚到顶且关键词为空才收起（输入态——关键词
    /// 非空——保持展开，§4.2）
    private func handleScrollOffset(_ y: CGFloat) {
        // §452.9：搜索改顶栏钮驱动——旧「下拉 56pt
        // 露出/回滚收起」驱动就此退役，本函只留滚动
        // 观察位（四滚动面同挂，不再动 searchVisible）
    }

    // MARK: - 筛选片与搜索建议（§452 定版③/452.9）

    /// 分段控件沿革：0.36.2 照 Muse 资源库图自制
    /// （SegmentedControlSpec 落值：总高 48／药丸 36
    /// ／内缩 6）；2026-11-15 主线裁决「系统件优先
    /// 为默认、自制为例外」，本面纯文字两段无例外
    /// 理由、自制件退役——现行形态与形态差见
    /// segmentControl 注

    /// 「文件」Rotor 命名空间（0.43.0，A11Y-V7）：
    /// 长列表/网格里按文件名直达——条目随当前段
    /// 取自 body 快照（§363），行/卡标记挂在各行
    /// 构建处（deliverableRow/mediaRow/fileCard/
    /// 影音网格钮），id＝文件名与条目一一对位
    @Namespace private var fileRotorNamespace

    // MARK: - 派生集（过滤→页级排序→分组）

    /// App 上传落点（与 P8 同址：managed 根下专属目录）
    static var uploadsPath: String {
        FileBrowserLogic.joinPath(
            directory: "/opt/data",
            name: FileBrowserLogic.uploadsDirectoryName
        )
    }

    // §363（S4）：过滤/排序/按路径查一并收进
    // LibraryListSnapshot（body 一趟算一次下传）——
    // 旧 matchesQuery/documents/mediaItems/ordered/
    // sortedDocuments/sortedMedia/deliverable(for:)
    // 计算属性组就此退役（每访问整表重排＋每查线性
    // 扫描的病根，见快照头注与 DESIGN §363）

    // MARK: - 文件段

    @ViewBuilder
    /// 统一内容面（§452 定版③：单列表单数据源，
    /// 文件/影音同面——列表/网格两显示模式共用同
    /// 一已排序集）
    private func libraryContent(
        _ snapshot: LibraryListSnapshot
    ) -> some View {
        if deliverables == nil && loadError == nil {
            loadingState
        } else if let loadError, deliverables == nil {
            failureState(message: loadError)
        } else if snapshot.items.isEmpty {
            // §473 件四：空态分支必须占满内容区——
            // ODEmptyState 是刚性高度，若直接放进根
            // VStack，整栈会收缩为内容高被宿主垂直居
            // 中（页头被推离顶部，真机截图实证：页头
            // 落到屏高约 39%）；占满后根栈恒全高、页
            // 头钉顶，空态本体在内容区内居中（与
            // ContentUnavailableView 同形态）
            emptyState(
                title: query.isEmpty ? "暂无交付物" : "没有匹配的文件",
                symbol: query.isEmpty
                    ? "doc.text.magnifyingglass" : "magnifyingglass",
                message: query.isEmpty
                    ? (category == .all && sourceFilter.isEmpty
                        ? "在聊天中智能体发给你的和你发送的文件会出现在这里。"
                        : "换个筛选试试。")
                    : "换个关键词试试。"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if displayMode == .list {
            fileListView(snapshot)
        } else {
            fileGridView(snapshot)
        }
    }

    private var loadingState: some View {
        ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 失败态带显式重试（下拉刷新退役后的补位，见页头注）
    private func failureState(message: String) -> some View {
        ContentUnavailableView {
            Label("没读出来", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("重试") {
                Task { await collect() }
            }
        }
    }

    private func emptyState(
        title: String, symbol: String, message: String
    ) -> some View {
        // 空态编排（台账 177，§391）：走共用编排件
        // （分阶段入场＋减动效降级），两调用点同受益
        ODEmptyState(
            title, systemImage: symbol, description: message
        )
    }

    @ViewBuilder
    private var noticeView: some View {
        if let notice {
            Text(notice)
                .font(.footnote)
                .foregroundStyle(Palette.inkSecondary)
                .padding(.top, OneDayMetrics.spacingM)
                .padding(.horizontal, OneDayMetrics.pageGutter)
        }
    }

    /// 列表态：平铺不分组（§4.5——分组只在网格态）；
    /// §131 加 ScrollViewReader 承定位滚动（行 id＝
    /// 路径，与 reveal 消费同口径）
    private func fileListView(
        _ snapshot: LibraryListSnapshot
    ) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // §363（S4）：急切 VStack 改 LazyVStack
                    // ——首建只建首屏行（骨架量测：1500 行
                    // 首建主线程卡顿 1799ms→51ms 量级，
                    // 见 DESIGN §363）；行 id 与 reveal
                    // 定位口径不变
                    LazyVStack(spacing: 0) {
                        ForEach(
                            Array(
                                snapshot.sortedItems
                                    .enumerated()
                            ),
                            id: \.element.id
                        ) { index, entry in
                            if index > 0 {
                                GroupDivider(
                                    inset: OneDayMetrics.dividerInset
                                )
                            }
                            deliverableRow(
                                entry, snapshot: snapshot
                            )
                        }
                    }
                    noticeView
                }
                .padding(.top, OneDayMetrics.spacingXS)
                .padding(.bottom, OneDayMetrics.spacingXL)
            }
            .background(Palette.pageBG)
            // §170（用户 2026-11-11 23:28 亲定）：底部导
            // 航栏同档收边（与输入框下方收边同档）——本格四个滚动面
            // （文件列表/网格、影音列表/网格）底缘一律
            // 挂 .hard，口径与映射见 FeedView 同注与
            // DESIGN §170.2
            // §185 按裁决改 .soft：该边缘内容可流到坞下、.hard 官方定义近乎不透明本身制造色带（solidband 裁决第四节）；§170 的 .hard 口径就此点被 §185 覆盖。
            .scrollEdgeEffectStyle(.soft, for: .bottom)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y
            } action: { _, newValue in
                handleScrollOffset(newValue)
            }
            .onChange(of: revealedPath) { _, path in
                scrollToRevealed(path, proxy: proxy)
            }
        }
    }

    /// 定位滚动（§131 四面共用）：revealedPath 置位即
    /// 滚到该行居中；清零不滚
    private func scrollToRevealed(
        _ path: String?, proxy: ScrollViewProxy
    ) {
        guard let path else { return }
        withAnimation(
            MotionTokens.resolved(
                MotionTokens.swap, reduceMotion: reduceMotion
            )
        ) {
            proxy.scrollTo(path, anchor: .center)
        }
    }

    /// 文件行：类型图标盒＋展示标题（去扩展名，§4.3
    /// 行口径修正）＋类型小字＋行尾 ⋮；⋮ 与长按同出
    /// 一套按类型适配的动作集（FileActionPolicy 附记
    /// 硬规矩，覆盖 §4.7 的两件旧口径）；点行按类型
    /// 分流打开
    /// 列表行领先视觉：图片/视频/PDF 出 42×42 紧凑真
    /// 缩略图（带 0.5pt 描边）；其余保持扁平矢量图标
    private func listUsesThumbnail(
        for entry: WorkspaceFileEntry
    ) -> Bool {
        if entry.isDirectory { return false }
        if entry.mediaKind == .image || entry.mediaKind == .video {
            return true
        }
        return (entry.name as NSString).pathExtension.lowercased() == "pdf"
    }

    private func deliverableRow(
        _ entry: WorkspaceFileEntry,
        snapshot: LibraryListSnapshot
    ) -> some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            Button {
                openEntry(entry, among: snapshot.sortedItems)
            } label: {
                HStack(spacing: OneDayMetrics.spacingSM) {
                    if listUsesThumbnail(for: entry) {
                        FileThumbnailView(
                            entry: entry,
                            targetPixelSize: 160,
                            compact: true
                        )
                        .frame(width: 42, height: 42)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Palette.hairline, lineWidth: 0.5)
                        }
                    } else {
                        FileIconBox(entry: entry, size: 42)
                    }
                    VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                        Text(
                            DeliverableFileType.displayTitle(
                                forFileName: entry.name
                            )
                        )
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.ink)
                        // 0.43.0（A11Y-D3）：AX 档放宽
                        .a11yLineLimit(1, ax: 2)
                        Text(rowMetaLine(
                            for: entry, snapshot: snapshot
                        ))
                            .font(.rowSubtitle)
                        .foregroundStyle(Palette.inkSecondary)
                        .a11yLineLimit(1, ax: 2)
                    }
                }
                .frame(
                    maxWidth: .infinity, minHeight: 64,
                    alignment: .leading
                )
                .contentShape(Rectangle())
                .accessibilityElement(children: .combine)
            }
            .buttonStyle(.odPressable)
            Spacer(minLength: OneDayMetrics.spacingS)
            Menu {
                actionItems(
                    for: entry, among: snapshot.sortedItems,
                    deliverable: snapshot.deliverable(for: entry)
                )
            } label: {
                Image(systemName: "ellipsis")
                    .rotationEffect(.degrees(90))
                    .font(.system(size: FrameworkIcon.moreGlyphSize, weight: .regular))
                    .foregroundStyle(Palette.inkSecondary)
                    // 命中域 44（0.22.0 审计 F4，字形不变）
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("更多操作")
        }
        .padding(.horizontal, OneDayMetrics.spacingM)
        .frame(minHeight: 64)
        // §131：定位高亮（reveal 消费置位、数秒自清）
        .background(
            revealedPath == entry.path
                ? Palette.selectionFill : Color.clear
        )
        .contentShape(Rectangle())
        .id(entry.path)
        // 0.43.0（A11Y-V7）：Rotor 行标记
        .accessibilityRotorEntry(id: entry.name, in: fileRotorNamespace)
        .contextMenu {
            actionItems(
                for: entry, among: snapshot.sortedItems,
                deliverable: snapshot.deliverable(for: entry)
            )
        }
    }

    /// 网格双列：拉开列距至 14pt，消除卡片挤在一起的观感
    private static let cardColumns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14),
    ]

    /// 网格态：双列宽松排版（列距 14、行距 16、外边距 pageGutter）
    private func fileGridView(
        _ snapshot: LibraryListSnapshot
    ) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    LazyVGrid(
                        columns: Self.cardColumns,
                        spacing: OneDayMetrics.spacingM
                    ) {
                        ForEach(snapshot.sortedItems) { entry in
                            fileCard(entry, snapshot: snapshot)
                        }
                    }
                    .padding(
                        .horizontal, OneDayMetrics.pageGutter
                    )
                    noticeView
                }
                .padding(.top, OneDayMetrics.spacingM)
                .padding(.bottom, OneDayMetrics.spacingXL)
            }
            .background(Palette.pageBG)
            // §185：底缘 .soft（口径见 fileListView 同注）
            .scrollEdgeEffectStyle(.soft, for: .bottom)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y
            } action: { _, newValue in
                handleScrollOffset(newValue)
            }
            .onChange(of: revealedPath) { _, path in
                scrollToRevealed(path, proxy: proxy)
            }
        }
    }

    /// 网格内容卡（大厂无框宽松卡片）：
    /// - 预览区 120pt，按三档渲染策略呈现；
    /// - 信息区：标题拿到全宽、最多 2 行，不再被右侧大按钮挤截断；
    /// - 副信息行右下角放轻量 ⋯ 菜单（24×24 视觉、44×44 热区），
    ///   同时整卡支持长按 contextMenu；
    /// - 去掉 1pt 硬边框，改用 0.5pt 发丝描边 + 轻投影。
    private func fileCard(
        _ entry: WorkspaceFileEntry,
        snapshot: LibraryListSnapshot
    ) -> some View {
        Button {
            openEntry(entry, among: snapshot.sortedItems)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                FileThumbnailView(entry: entry, targetPixelSize: 440)
                    .frame(height: 120)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .matchedTransitionSource(
                        id: entry.path, in: viewerNamespace
                    )
                    .accessibilityHidden(true)
                VStack(
                    alignment: .leading,
                    spacing: OneDayMetrics.spacingXS
                ) {
                    Text(
                        DeliverableFileType.displayTitle(
                            forFileName: entry.name
                        )
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Spacer(minLength: 0)
                    HStack(spacing: OneDayMetrics.spacingXS) {
                        Text(cardMetaLine(
                            for: entry, snapshot: snapshot
                        ))
                        .font(.meta)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                        Spacer(minLength: 0)
                        Color.clear
                            .frame(width: 24, height: 20)
                    }
                }
                .padding(.horizontal, OneDayMetrics.spacingSM)
                .padding(.vertical, 10)
                .frame(height: 76, alignment: .top)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(
                Palette.surface,
                in: RoundedRectangle(cornerRadius: OneDayMetrics.radiusPreview)
            )
            .overlay {
                RoundedRectangle(cornerRadius: OneDayMetrics.radiusPreview)
                    .strokeBorder(Palette.hairline, lineWidth: 0.5)
            }
            .overlay {
                // §131：定位高亮（reveal 消费置位、数秒自清）
                if revealedPath == entry.path {
                    RoundedRectangle(
                        cornerRadius: OneDayMetrics.radiusPreview
                    )
                    .strokeBorder(Palette.primary, lineWidth: 2)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: OneDayMetrics.radiusPreview))
            .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
            .contentShape(
                RoundedRectangle(cornerRadius: OneDayMetrics.radiusPreview)
            )
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.odPressable)
        .overlay(alignment: .bottomTrailing) {
            Menu {
                actionItems(
                    for: entry, among: snapshot.sortedItems,
                    deliverable: snapshot.deliverable(for: entry)
                )
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.inkSecondary)
                    .frame(width: 24, height: 20)
                    .frame(
                        width: OneDayMetrics.minTapTarget,
                        height: OneDayMetrics.minTapTarget
                    )
                    .contentShape(Rectangle())
                    .padding(.horizontal, -(OneDayMetrics.minTapTarget - 24) / 2)
                    .padding(.vertical, -(OneDayMetrics.minTapTarget - 20) / 2)
            }
            .accessibilityLabel("更多操作")
            .padding(.trailing, OneDayMetrics.spacingSM)
            .padding(.bottom, 10)
        }
        .id(entry.path)
        // 0.43.0（A11Y-V7）：Rotor 卡标记（网格态）
        .accessibilityRotorEntry(id: entry.name, in: fileRotorNamespace)
        .contextMenu {
            actionItems(
                for: entry, among: snapshot.sortedItems,
                deliverable: snapshot.deliverable(for: entry)
            )
        }
    }

    /// 卡/行副行（§452 定版①：类型签＋来源标）：
    /// 来源即聚合集 Deliverable.source（双向单库的
    /// 归属标），空来源不挂尾
    private func cardMetaLine(
        for entry: WorkspaceFileEntry,
        snapshot: LibraryListSnapshot
    ) -> String {
        let deliverable = snapshot.deliverable(for: entry)
        let source = LibrarySourceFilter.displayLabel(for: deliverable)
        let tag = typeTag(for: entry)
        return "\(tag) · \(source)"
    }

    private func rowMetaLine(
        for entry: WorkspaceFileEntry,
        snapshot: LibraryListSnapshot
    ) -> String {
        let deliverable = snapshot.deliverable(for: entry)
        let source = LibrarySourceFilter.displayLabel(for: deliverable)
        let label = DeliverableFileType.label(
            forFileName: entry.name
        )
        return "\(label) · \(source)"
    }

    /// 类型签（§4.3）：媒体给人话词（图片/视频/音
    /// 频）、文本类给「文本」，其余沿 Deliverable-
    /// FileType 大写扩展名表（PDF/DOCX/PPTX/HTML…）
    private func typeTag(
        for entry: WorkspaceFileEntry
    ) -> String {
        switch entry.mediaKind {
        case .image: return "图片"
        case .video: return "视频"
        case .audio: return "音频"
        case nil: break
        }
        if DocumentTextKind.kind(forFileName: entry.name) != nil {
            return "文本"
        }
        return DeliverableFileType.label(forFileName: entry.name)
    }

    // MARK: - 条目动作（按类型适配，附记硬规矩）

    /// ⋮ 与长按共用同一动作集：FileActionPolicy.menu-
    /// Actions 按类型出项（文本类多复制文字/导出
    /// PDF、二进制只给分享/下载/删除），删除项红色
    @ViewBuilder
    private func actionItems(
        for entry: WorkspaceFileEntry,
        among siblings: [WorkspaceFileEntry],
        deliverable: Deliverable
    ) -> some View {
        ForEach(
            FileActionPolicy.menuActions(for: entry), id: \.self
        ) { action in
            if action == .delete {
                Button(role: .destructive) {
                    pendingDelete = deliverable
                } label: {
                    Label(
                        action.label,
                        systemImage: action.systemImage
                    )
                }
            } else {
                Button {
                    perform(action, on: entry, among: siblings)
                } label: {
                    Label(
                        action.label,
                        systemImage: action.systemImage
                    )
                }
            }
        }
    }

    private func perform(
        _ action: FileItemAction,
        on entry: WorkspaceFileEntry,
        among siblings: [WorkspaceFileEntry]
    ) {
        switch action {
        case .preview:
            openEntry(entry, among: siblings)
        case .copyText:
            Task { await copyText(entry) }
        case .exportPDF:
            Task { await exportPDF(entry) }
        case .share, .download:
            // 分享与下载到本地同走系统分享单（全 App
            // 既有口径：取回临时文件→分享单，含「存
            // 储到文件」出口）
            Task { await download(entry) }
        case .delete:
            // 删除在菜单构造处直接挂确认（actionItems），
            // 不经本分发
            break
        case .pin, .unpin, .rename, .openInFiles:
            // 条目菜单（menuActions）不出这四项（打开页
            // 专属，见 openPageActions），落到即策略表
            // 漂移——静默不执行
            break
        }
    }

    /// 条目打开分流：先写上次打开记录；图片直达查
    /// 看器（集合＝同段全部图片、可翻页）；其余一律
    /// 落文件打开页（§125 中间页，类型内分流归它）
    private func openEntry(
        _ entry: WorkspaceFileEntry,
        among siblings: [WorkspaceFileEntry]
    ) {
        openHistory.record(path: entry.path)
        if entry.mediaKind == .image {
            let images = siblings.filter {
                $0.mediaKind == .image
            }
            viewerRoute = ImageViewerRoute(
                entries: images,
                initialIndex: images.firstIndex(of: entry) ?? 0
            )
        } else {
            // §125：文本类不再从本面直达阅读页——与
            // 聊天/文件浏览器同路先进中间页（单源壳）
            previewEntry = entry
        }
    }

    /// 影音网格预取（§144）：以刚露面的格为锚，向后
    /// 6 格（2 行）的图片/视频先把 360 档/海报暖进缩
    /// 略缓存（FileThumbnailStore 自带去重与并发闸，
    /// 已缓存的格零成本跳过）；滚动中只做占位→360
    /// 的单向填充，不阻塞布局
    private func prefetchMedia(
        after entry: WorkspaceFileEntry,
        among sorted: [WorkspaceFileEntry]
    ) {
        guard let index = sorted.firstIndex(
            where: { $0.path == entry.path }) else { return }
        let upcoming = sorted
            .dropFirst(index + 1).prefix(6)
            .filter {
                $0.mediaKind == .image || $0.mediaKind == .video
            }
        guard !upcoming.isEmpty else { return }
        Task {
            for next in upcoming {
                _ = await FileThumbnailStore.shared.thumbnail(
                    for: next, targetPixelSize: 360,
                    loader: FileThumbnailStore.originalLoader(
                        appState: appState, path: next.path),
                    renditionLoader: FileThumbnailStore
                        .renditionLoader(
                            appState: appState, path: next.path)
                )
            }
        }
    }

    private func fetchData(
        _ entry: WorkspaceFileEntry
    ) async throws -> Data {
        if let deliveryID = entry.deliveryID,
           let config = appState.config,
           let data = try? await bridgeClient.deliveryContent(
               config: config, id: deliveryID
           ) {
            return data
        }
        return try await appState.performAdmin { client, config in
            try await client.fileData(config: config, path: entry.path)
        }
    }

    private func copyText(_ entry: WorkspaceFileEntry) async {
        do {
            let data = try await fetchData(entry)
            guard let text = FileTextExtractor.plainText(
                from: data, entry: entry
            ) else {
                notice = "「\(entry.name)」没能读出文字。"
                Haptics.error()
                return
            }
            UIPasteboard.general.string = text
            notice = "已复制「\(entry.name)」的文字。"
            Haptics.success()
        } catch {
            notice = (error as? HermesError)?.userMessage
                ?? "文件没读出来，可能是网络或服务暂时没响应"
            Haptics.error()
        }
    }

    private func exportPDF(_ entry: WorkspaceFileEntry) async {
        do {
            let data = try await fetchData(entry)
            guard let text = FileTextExtractor.plainText(
                from: data, entry: entry
            ) else {
                notice = "「\(entry.name)」没能读出文字，无法导出 PDF。"
                Haptics.error()
                return
            }
            let kind = DocumentTextKind.kind(
                forFileName: entry.name
            ) ?? .plain
            let title = DeliverableFileType.displayTitle(
                forFileName: entry.name
            )
            guard let pdf = DocumentPDFExporter.pdfData(
                title: title,
                blocks: DocumentReading.blocks(
                    for: text, kind: kind
                )
            ) else {
                notice = "导出 PDF 失败，请稍后再试。"
                Haptics.error()
                return
            }
            shareItem = try FileShareItem.write(
                data: pdf, name: "\(title).pdf"
            )
        } catch {
            notice = (error as? HermesError)?.userMessage
                ?? "导出 PDF 失败，请稍后再试。"
            Haptics.error()
        }
    }

    /// 查看器内删除（0.36.4）：与行删除同通道（§369
    /// 起同走名单店本地摘行＋真接口删、不重聚合）；
    /// 落锤触感已由查看器在点删时发过、本处成功不
    /// 叠、失败 error
    private func deleteFromViewer(_ entry: WorkspaceFileEntry) async {
        let outcome = await listStore.delete(
            paths: [entry.path]
        ) { path in
            try await appState.performAdmin { client, config in
                try await client.deleteFile(
                    config: config, path: path,
                    recursive: false
                )
            }
        }
        switch outcome {
        case .success:
            notice = "已删除「\(entry.name)」。"
        case .failed(let message):
            notice = message
            Haptics.error()
        }
    }

    // MARK: - 定位消费（§131「在文件页中打开」）

    /// 定位请求消费：聚合未完成先不消费（collect 末
    /// 尾再试）；消费即清零请求、收栈回根、清搜索
    /// ——命中聚合集切到对应段滚动高亮；不在聚合集
    /// 的文件（任意服务器路径）落系统文件浏览器父
    /// 目录＋文件名高亮，不假装它在文件页收录里
    private func consumeRevealIfReady() {
        guard let path = appState.router.fileRevealPath else { return }
        guard deliverables != nil else { return }
        appState.router.fileRevealPath = nil
        systemFilesRoute = nil
        previewEntry = nil
        viewerRoute = nil
        query = ""
        // §363：成员判定走快照过滤（不付排序账）
        let base = LibraryListSnapshot.filtered(
            deliverables: deliverables, query: query
        )
        if let hit = (deliverables ?? []).first(
            where: { $0.entry.path == path }
        ) {
            // §452 定版③：定位改切类别片＋清来源筛
            // 选（分段退役），命中集内滚动高亮不变
            category = LibraryCategory.bucket(for: hit.entry)
            sourceFilter = ""
            flashReveal(path: path)
        } else {
            systemFilesRoute = SystemFilesRoute(
                dir: (path as NSString).deletingLastPathComponent,
                highlight: (path as NSString).lastPathComponent
            )
        }
    }

    private func flashReveal(path: String) {
        revealedPath = path
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            if revealedPath == path { revealedPath = nil }
        }
    }

    // MARK: - 聚合与动作（A-06 服务端读面）

    /// 聚合集只从伴生文件库读面单流消费（GET /file-
    /// library，伴生 1.0.66）：产出根走查、准入、去重、
    /// mtime 倒序全在服务端（oneday_seg_filelibrary
    /// 为单一事实源），本函数只做条目映射。0.50.60 前
    /// 的客户端 BFS 爬 /api/files（8 根硬编码、深度 3、
    /// 600 静默截断、客户端准入）已整套退役。
    /// 排序不在此处定案——视图层按页级排序状态走
    /// LibraryOrdering（本函数只负责聚合集本身）。
    /// 失败口径：首拉失败给错误态；已有数据时刷新失败
    /// 保留旧集不清屏（回响链同口径）
    /// §369（缓存 C4）：聚合走名单店对账——店内先以
    /// 落盘快照播种（冷启不等网络先上屏）、再恰一次
    /// 全量拉取差异合并换新；本函数只做接线（桥读面
    /// 单流）与既有 loadError 口径回填：无数据失败／
    /// 无配置才给错误态、成功且非空清错误、已有数据
    /// 刷新失败保留旧集不清屏（店内已保、本处不置错）
    /// 桥读面单流取数（collect 两口共用闭包本体）
    private func fetchLibraryPage() async throws
        -> [Deliverable] {
        guard let config = appState.config else {
            // 键非 nil 时配置同源必在；店内当前键
            // 为 nil 时不会调用本闭包
            throw HermesError.sessionExpired
        }
        // 演示态回落演示回执（§421，§401.4 缺口一
        // 修向）：桥读面无 demo 分支、演示态无桥钥，
        // 走桥恒落错误面；改从演示客户端 files 种
        // 子面装配（冻结清单内），不给桥加 demo 分支
        if appState.isDemo {
            return try await Self.demoDeliverables(
                client: appState.client, config: config
            )
        }
        let page = try await bridgeClient.fileLibrary(
            config: config
        )
        return page.items.map {
            Deliverable(entry: $0.entry, source: $0.source)
        }
    }

    /// 对账（强制口）：上传落定/失败重试走本口——
    /// 不经新鲜度门、必真拉
    /// 名单键（§421 演示隔离）：演示 config 与真实
    /// 连接同为 hermes.didichou.site、同键会让种子
    /// 快照与真实快照串用（店口径：快照不得跨服务
    /// 器／账号串用），演示恒加后缀键。collect 与
    /// collectIfNeeded 共用（§416×§421 并存合并）
    private var libraryConfigKey: String? {
        guard let base = appState.config?.baseString
        else { return nil }
        return appState.isDemo ? base + "#demo" : base
    }

    private func collect() async {
        let outcome = await listStore.refresh(
            currentConfigKey: libraryConfigKey
        ) {
            try await fetchLibraryPage()
        }
        applyCollectOutcome(outcome)
    }

    /// 对账（读触发口，§416）：进面 .task 走本口
    /// ——店内先播种快照、门内新鲜整轮零请求；改
    /// 名失效与修订号同拍（失效口在 FileOpenView
    /// 改名落点），修订触发的重跑不被门吞
    private func collectIfNeeded() async {
        let outcome = await listStore.refreshIfNeeded(
            currentConfigKey: libraryConfigKey
        ) {
            try await fetchLibraryPage()
        }
        applyCollectOutcome(outcome)
    }

    /// 对账结局回填（两口共用）：loadError 口径与
    /// §369 逐字同——无数据失败/无配置才给错误态、
    /// 成功且非空清错误、已有数据刷新失败保留旧
    /// 集不清屏（店内已保、本处不置错）
    private func applyCollectOutcome(
        _ outcome: LibraryListStore.RefreshOutcome
    ) {
        switch outcome {
        case .loaded, .stillFresh:
            if !(deliverables?.isEmpty ?? true) {
                loadError = nil
            }
            // 聚合落定后补消费定位请求（请求先于数
            // 据到达时 onChange 已触发过、那时 deli-
            // verables 为空未消费，见 consumeReveal-
            // IfReady 的守卫）
            consumeRevealIfReady()
        case .noConfig, .failedNoData:
            if deliverables == nil {
                loadError = "产出目录没读出来，可能是网络或服务暂时没响应"
            }
        case .keptAfterFailure, .alreadyInFlight:
            break
        }
    }

    /// 演示态名单装配（§421）：从演示客户端 files 种
    /// 子面走查种子目录集装配名单——目录集与 Demo-
    /// HermesClient.files 的存量种子目录逐一对应
    /// （2026-11-11 冻结清单「文件种子面」，不扩种
    /// 子）；只收文件条目（目录行跳过，其内容经各自
    /// 目录入集）、按 path 去重，来源记种子目录（数
    /// 据层记录口径，与桥回执 source 同位）。分类走
    /// entry.mediaKind 既有口径（文件段／影音段），
    /// 本函数不另立判据。
    static func demoDeliverables(
        client: HermesClientProtocol, config: ServerConfig
    ) async throws -> [Deliverable] {
        let seedDirectories = [
            "/opt/data",
            "/opt/data/cache/images",
            "/opt/data/cache/videos",
            "/opt/data/cache/audio",
            "/opt/data/cache/documents",
            "/opt/data/cache/screenshots",
            "/opt/data/cron/output",
            "/opt/data/image_cache",
            "/opt/data/images",
            "/opt/data/reports",
            "/opt/data/cache/scratch",
            "/opt/data/audio_cache",
        ]
        var seenPaths = Set<String>()
        var items: [Deliverable] = []
        for directory in seedDirectories {
            let listing = try await client.files(
                config: config, path: directory
            )
            for entry in listing.entries
            where !entry.isDirectory {
                guard seenPaths.insert(entry.path).inserted
                else { continue }
                items.append(
                    Deliverable(entry: entry, source: directory)
                )
            }
        }
        return items
    }

    /// §369（缓存 C4）：删除走名单店本地摘行——先摘
    /// 行上屏、真接口确认，成功不整表重拉；失败店内
    /// 原位回滚，本处只管回执与触感
    private func delete(_ item: Deliverable) async {
        let outcome = await listStore.delete(
            paths: [item.entry.path]
        ) { path in
            try await appState.performAdmin { client, config in
                try await client.deleteFile(
                    config: config, path: path,
                    recursive: false
                )
            }
        }
        switch outcome {
        case .success:
            notice = "已删除「\(item.entry.name)」。"
            // 成功无触感：确认时的 heavy 落锤已代表
            // 本链（规格 §2.3，同一因果链只震一次）
        case .failed(let message):
            notice = message
            // 失败改判 error（0.36.2，表 D 语义归位）
            Haptics.error()
        }
    }

    /// 分享＝先把文件取回本机临时文件再调系统分享单
    /// （FileShareItem/FileShareSheet，P8 同通道）
    private func download(_ entry: WorkspaceFileEntry) async {
        do {
            let data = try await fetchData(entry)
            shareItem = try FileShareItem.write(
                data: data, name: entry.name
            )
        } catch {
            notice = (error as? HermesError)?.userMessage
                ?? "下载失败，请稍后再试。"
        }
    }
}

/// 交付物：工作区文件条目＋来源（产出目录语义名；
/// 来源只作数据层记录与排查，本页行副题按图只给类
/// 型词、不上屏来源）
struct Deliverable: Identifiable, Equatable {
    let entry: WorkspaceFileEntry
    let source: String

    var id: String { entry.path }

    var subtitle: String {
        let size = entry.size.map {
            ByteCountFormatter.string(
                fromByteCount: $0, countStyle: .file
            )
        }
        let date = AdminFormat.short(entry.modifiedAt)
        return [source, size, date]
            .compactMap { $0 }.joined(separator: " · ")
    }
}
