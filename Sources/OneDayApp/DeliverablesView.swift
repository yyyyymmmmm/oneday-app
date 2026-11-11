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
/// 沿 P8（0.14.0）产出聚合通道——/api/files（根锁
/// /opt/data）扫产出根（递归 ≤3 层、600 封顶）＋根
/// 目录散文件，全量先过 DeliverableAdmission 准入
/// （0.22.0 去污）与敏感名单第二道（单源 Sensitive-
/// FilePolicy.protectedNames，0.36.31 并源）。服务端
/// 文件全量浏览不在本页（••• 菜单组3「系统文件」与
/// 设置「管理」共用 FilesBrowserView）。
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

    /// 0＝文件、1＝影音内容
    @State private var segment = 0
    @State private var deliverables: [Deliverable]?
    @State private var loadError: String?
    @State private var pendingDelete: Deliverable?
    @State private var shareItem: FileShareItem?
    @State private var notice: String?
    @State private var query = ""
    @State private var searchVisible = false
    @State private var previewEntry: WorkspaceFileEntry?
    @State private var readerEntry: WorkspaceFileEntry?
    /// 图片查看器路由（0.36.4）：图片直达查看器（系
    /// 统 zoom 转场、源＝格/卡的 matched 标记），不
    /// 再先进 FilePreviewView 预览页
    @State private var viewerRoute: ImageViewerRoute?
    @Namespace private var viewerNamespace
    /// 上次打开记录（§4.3/§4.5 排序辅助，本地表）
    @State private var openHistory = FileOpenHistoryStore()
    /// 显示方式与排序：页级状态、持久化（§4.2）
    @AppStorage("files.displayMode")
    private var displayModeRaw = LibraryDisplayMode.list.rawValue
    @AppStorage("files.sort")
    private var sortRaw = LibrarySort.lastOpened.rawValue
    @State private var uploadPickerPresented = false
    @State private var systemFilesPresented = false

    private var displayMode: LibraryDisplayMode {
        LibraryDisplayMode(rawValue: displayModeRaw) ?? .list
    }

    private var sort: LibrarySort {
        LibrarySort(rawValue: sortRaw) ?? .lastOpened
    }

    /// 查看器集合载荷：同段图片条目＋起始索引
    private struct ImageViewerRoute: Identifiable, Hashable {
        let entries: [WorkspaceFileEntry]
        let initialIndex: Int
        var id: String { entries[initialIndex].path }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                identityHeader
                if searchVisible {
                    searchFieldRow
                }
                segmentControl
                if segment == 0 {
                    filesContent
                } else {
                    mediaContent
                }
            }
            // 0.43.0（A11Y-V7）：「文件」Rotor——条目
            // 与行/卡标记同名对位（见 fileRotorNames-
            // pace 注）
            .accessibilityRotor(
                L10n.string("文件")
            ) {
                ForEach(rotorEntryNames, id: \.self) { name in
                    AccessibilityRotorEntry(
                        DeliverableFileType.displayTitle(
                            forFileName: name
                        ),
                        name, in: fileRotorNamespace
                    )
                }
            }
            .background(Palette.pageBG)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $previewEntry) { entry in
                FilePreviewView(entry: entry)
            }
            .navigationDestination(item: $readerEntry) { entry in
                DocumentReaderView(entry: entry)
            }
            .navigationDestination(
                isPresented: $systemFilesPresented
            ) {
                FilesBrowserView()
                    .navigationTitle("系统文件")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .navigationDestination(item: $viewerRoute) { route in
                ImageViewerView(
                    items: route.entries.map {
                        ChatImageViewerItem(source: .remotePath($0.path))
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
            .task { await collect() }
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
    }

    // MARK: - 顶部身份区（左抽屉钮／中央胶囊／右 •••）

    private var identityHeader: some View {
        ZStack {
            HStack {
                Button {
                    appState.drawerPresented = true
                } label: {
                    headerCircleButton("line.3.horizontal")
                }
                .buttonStyle(.odPressable)
                .accessibilityLabel("会话列表")
                Spacer()
                // §4.1/§4.2：右上改 ••• 菜单钮（搜索钮
                // 撤除）——组1 显示、组2 排序（每组单
                // 选、当前项占对号列）、组3 系统文件、
                // 组4 上传文件（OneDay 扩展，规格标注）
                Menu {
                    Section("显示") {
                        ForEach(
                            LibraryDisplayMode.allCases, id: \.self
                        ) { mode in
                            Button {
                                displayModeRaw = mode.rawValue
                            } label: {
                                if mode == displayMode {
                                    Label(
                                        mode.label,
                                        systemImage: "checkmark"
                                    )
                                } else {
                                    Text(mode.label)
                                }
                            }
                        }
                    }
                    Section("排序") {
                        ForEach(
                            LibrarySort.allCases, id: \.self
                        ) { option in
                            Button {
                                sortRaw = option.rawValue
                            } label: {
                                if option == sort {
                                    Label(
                                        option.label,
                                        systemImage: "checkmark"
                                    )
                                } else {
                                    Text(option.label)
                                }
                            }
                        }
                    }
                    Section {
                        Button {
                            systemFilesPresented = true
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
                    headerCircleButton("ellipsis")
                }
                .accessibilityLabel("文件页菜单")
            }
            IdentityAnchor(
                // 0.36.22：名与头像收敛档案出口
                name: appState.agentDisplayName,
                statusWord: appState.config == nil ? "未连接" : "在线",
                statusColor: appState.config == nil
                    ? Palette.inkMuted : Palette.success,
                // 真头像注入（0.22.0 审计 F3），与聊天页
                // 胶囊同一头像源
                avatarImage: appState.agentAvatarImage
            )
        }
        .padding(.horizontal, OneDayMetrics.pageGutter)
        .padding(.top, OneDayMetrics.spacingS)
        .padding(.bottom, OneDayMetrics.spacingXS)
    }

    private func headerCircleButton(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(
                size: HeaderButtonSpec.glyphPointSize,
                weight: .regular
            ))
            .foregroundStyle(Palette.ink)
            .frame(
                width: HeaderButtonSpec.diameter,
                height: HeaderButtonSpec.diameter
            )
            // 与聊天页顶栏圆钮同族材质：系统玻璃
            // .glassEffect(.regular)，视觉盘 40 不变
            .glassEffect(.regular, in: Circle())
            // 命中域外扩 44（视觉盘居中不变）
            .frame(
                width: OneDayMetrics.minTapTarget,
                height: OneDayMetrics.minTapTarget
            )
            .contentShape(Rectangle())
    }

    /// 下拉露出搜索栏（§4.2）：搜当前聚合集的文件名
    /// （本地过滤）；展开/收起由内容滚动偏移驱动（见
    /// handleScrollOffset），不新增手势识别器
    private var searchFieldRow: some View {
        FileSearchField(query: $query)
            .padding(.horizontal, OneDayMetrics.pageGutter)
            .padding(.bottom, OneDayMetrics.spacingSM)
    }

    /// 下拉触发口径：内容被下拉过顶 56pt 露出搜索；
    /// 回滚到顶且关键词为空才收起（输入态——关键词
    /// 非空——保持展开，§4.2）
    private func handleScrollOffset(_ y: CGFloat) {
        if y < -56, !searchVisible {
            withAnimation(
                MotionTokens.resolved(
                    MotionTokens.swap, reduceMotion: reduceMotion
                )
            ) { searchVisible = true }
        } else if y > 10, searchVisible, query.isEmpty {
            withAnimation(
                MotionTokens.resolved(
                    MotionTokens.swap, reduceMotion: reduceMotion
                )
            ) { searchVisible = false }
        }
    }

    // MARK: - 大分段（照 Muse 资源库图自制，0.36.2 落值）

    /// 分段控件：轨道＝surface 白＋发丝边、全胶囊，
    /// 总高 48；选中药丸＝selectionFill 灰垫、高 36、
    /// 内缩 6、无阴影；字 17 semibold 两态皆 ink——
    /// 选中区分只靠灰垫有无（规格 §1.6 落值，Seg-
    /// mentedControlSpec 钉死）。切换＝药丸 matched-
    /// Geometry 滑移＋selection 触感（表 D）
    @Namespace private var segmentNamespace

    /// 「文件」Rotor 命名空间（0.43.0，A11Y-V7）：
    /// 长列表/网格里按文件名直达——条目随当前段
    /// 现算（rotorEntryNames），行/卡标记挂在各行
    /// 构建处（deliverableRow/mediaRow/fileCard/
    /// 影音网格钮），id＝文件名与条目一一对位
    @Namespace private var fileRotorNamespace

    /// Rotor 条目名册（当前段）：文件段＝文档集、
    /// 影音段＝媒体集，呈现标题走 displayTitle
    /// （与行面同源）
    private var rotorEntryNames: [String] {
        segment == 0
            ? sortedDocuments.map(\.name)
            : sortedMedia.map(\.name)
    }

    private var segmentControl: some View {
        HStack(spacing: 0) {
            segmentButton(title: "文件", tag: 0)
            segmentButton(title: "影音内容", tag: 1)
        }
        .padding(SegmentedControlSpec.inset)
        .background(Palette.surface, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(Palette.separator, lineWidth: 1)
        }
        .padding(.horizontal, SegmentedControlSpec.horizontalMargin)
        .padding(.vertical, OneDayMetrics.spacingSM)
        // 触感矩阵（规格 §2.3）：分段切换＝selection
        .sensoryFeedback(.selection, trigger: segment)
    }

    private func segmentButton(title: String, tag: Int) -> some View {
        let selected = segment == tag
        return Button {
            withAnimation(
                MotionTokens.resolved(
                    MotionTokens.selectionSpring,
                    reduceMotion: reduceMotion
                )
            ) { segment = tag }
        } label: {
            Text(title)
                .font(.bodyText.weight(.semibold))
                .foregroundStyle(Palette.ink)
                .frame(
                    maxWidth: .infinity,
                    minHeight: SegmentedControlSpec.pillHeight
                )
                .background {
                    if selected {
                        Capsule()
                            .fill(Palette.selectionFill)
                            .matchedGeometryEffect(
                                id: "segmentPill",
                                in: segmentNamespace
                            )
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.odPressable)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    // MARK: - 派生集（过滤→页级排序→分组）

    /// App 上传落点（与 P8 同址：managed 根下专属目录）
    static var uploadsPath: String {
        FileBrowserLogic.joinPath(
            directory: "/opt/data",
            name: FileBrowserLogic.uploadsDirectoryName
        )
    }

    private func matchesQuery(_ item: Deliverable) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty
            || item.entry.name.localizedCaseInsensitiveContains(trimmed)
    }

    private var documents: [Deliverable] {
        (deliverables ?? []).filter {
            $0.entry.mediaKind == nil && matchesQuery($0)
        }
    }

    private var mediaItems: [Deliverable] {
        (deliverables ?? []).filter {
            $0.entry.mediaKind != nil && matchesQuery($0)
        }
    }

    /// 排序后的条目（Core LibraryOrdering 单源：上次
    /// 打开＝本地记录优先、无记录 mtime 兜底）
    private func ordered(
        _ items: [Deliverable]
    ) -> [WorkspaceFileEntry] {
        LibraryOrdering.sorted(
            items.map(\.entry), by: sort,
            openedAt: openHistory.openedAtMap
        )
    }

    private var sortedDocuments: [WorkspaceFileEntry] {
        ordered(documents)
    }

    private var sortedMedia: [WorkspaceFileEntry] {
        ordered(mediaItems)
    }

    private func deliverable(
        for entry: WorkspaceFileEntry
    ) -> Deliverable {
        deliverables?.first(where: { $0.entry.path == entry.path })
            ?? Deliverable(entry: entry, source: "")
    }

    // MARK: - 文件段

    @ViewBuilder
    private var filesContent: some View {
        if deliverables == nil && loadError == nil {
            loadingState
        } else if let loadError, deliverables == nil {
            failureState(message: loadError)
        } else if documents.isEmpty {
            emptyState(
                title: query.isEmpty ? "暂无交付物" : "没有匹配的文件",
                symbol: query.isEmpty
                    ? "doc.text.magnifyingglass" : "magnifyingglass",
                message: query.isEmpty
                    ? "智能体生成的文件与定时任务产出会出现在这里。"
                    : "换个关键词试试。"
            )
        } else if displayMode == .list {
            fileListView
        } else {
            fileGridView
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
        ContentUnavailableView(
            title, systemImage: symbol,
            description: Text(message)
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

    /// 列表态：平铺不分组（§4.5——分组只在网格态）
    private var fileListView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(spacing: 0) {
                    ForEach(
                        Array(sortedDocuments.enumerated()),
                        id: \.element.id
                    ) { index, entry in
                        if index > 0 {
                            GroupDivider(
                                inset: OneDayMetrics.dividerInset
                            )
                        }
                        deliverableRow(entry)
                    }
                }
                noticeView
            }
            .padding(.top, OneDayMetrics.spacingXS)
            .padding(.bottom, OneDayMetrics.spacingXL)
        }
        .background(Palette.pageBG)
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y
        } action: { _, newValue in
            handleScrollOffset(newValue)
        }
    }

    /// 文件行：类型图标盒＋展示标题（去扩展名，§4.3
    /// 行口径修正）＋类型小字＋行尾 ⋮；⋮ 与长按同出
    /// 一套按类型适配的动作集（FileActionPolicy 附记
    /// 硬规矩，覆盖 §4.7 的两件旧口径）；点行按类型
    /// 分流打开
    private func deliverableRow(
        _ entry: WorkspaceFileEntry
    ) -> some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            // 0.43.0（A11Y-V4）：图标＋题＋类型合并为
            // 一个按钮元素（默认动作与点行同一入口）；
            // ⋮ 菜单留在元素外独立可达。内外间距同
            // 值，几何逐字不变
            HStack(spacing: OneDayMetrics.spacingSM) {
                FileIconBox(entry: entry)
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
                    Text(
                        DeliverableFileType.label(
                            forFileName: entry.name
                        )
                    )
                    .font(.rowSubtitle)
                    .foregroundStyle(Palette.inkSecondary)
                    .a11yLineLimit(1, ax: 2)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                openEntry(entry, among: sortedDocuments)
            }
            Spacer(minLength: OneDayMetrics.spacingS)
            Menu {
                actionItems(for: entry, among: sortedDocuments)
            } label: {
                Image(systemName: "ellipsis")
                    .rotationEffect(.degrees(90))
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(Palette.inkSecondary)
                    // 命中域 44（0.22.0 审计 F4，字形不变）
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("更多操作")
        }
        .padding(.horizontal, OneDayMetrics.spacingM)
        .frame(minHeight: 64)
        .contentShape(Rectangle())
        // 0.43.0（A11Y-V7）：Rotor 行标记
        .accessibilityRotorEntry(id: entry.name, in: fileRotorNamespace)
        .onTapGesture {
            openEntry(entry, among: sortedDocuments)
        }
        .contextMenu {
            actionItems(for: entry, among: sortedDocuments)
        }
    }

    /// 网格态（§4.3）：双列、边距 16/列距 12/行距
    /// 16；排序≠标题时分「最近/全部」两组（§4.5）
    private var fileGridView: some View {
        let sections = LibraryOrdering.grouped(
            sortedDocuments,
            openedAt: openHistory.openedAtMap, now: Date()
        )
        return ScrollView {
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingL) {
                ForEach(
                    Array(sections.enumerated()), id: \.offset
                ) { _, section in
                    VStack(
                        alignment: .leading,
                        spacing: OneDayMetrics.spacingM
                    ) {
                        if let title = section.title {
                            Text(title)
                                .font(.sectionLabel)
                                .foregroundStyle(Palette.inkSecondary)
                                .padding(
                                    .horizontal,
                                    OneDayMetrics.spacingM
                                )
                        }
                        LazyVGrid(
                            columns: Self.cardColumns,
                            spacing: OneDayMetrics.spacingM
                        ) {
                            ForEach(section.entries) { entry in
                                fileCard(entry)
                            }
                        }
                        .padding(
                            .horizontal, OneDayMetrics.spacingM
                        )
                    }
                }
                noticeView
            }
            .padding(.top, OneDayMetrics.spacingM)
            .padding(.bottom, OneDayMetrics.spacingXL)
        }
        .background(Palette.pageBG)
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y
        } action: { _, newValue in
            handleScrollOffset(newValue)
        }
    }

    private static let cardColumns = [
        GridItem(.flexible(), spacing: OneDayMetrics.spacingSM),
        GridItem(.flexible(), spacing: OneDayMetrics.spacingSM),
    ]

    /// 内容卡（§4.3）：预览区 112（缩略首面/类型面，
    /// FileThumbnailStore 分档生成）＋信息条 64（展
    /// 示标题 semibold 一行＋类型签）；卡上无 ⋮（与
    /// 实拍一致），动作走长按菜单；图片卡带 zoom 转
    /// 场源标记（0.36.4 衔接）
    private func fileCard(_ entry: WorkspaceFileEntry) -> some View {
        Button {
            openEntry(entry, among: sortedDocuments)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                FileThumbnailView(entry: entry, targetPixelSize: 440)
                    .frame(height: 112)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .matchedTransitionSource(
                        id: entry.path, in: viewerNamespace
                    )
                VStack(
                    alignment: .leading, spacing: OneDayMetrics.spacingMicro
                ) {
                    Text(
                        DeliverableFileType.displayTitle(
                            forFileName: entry.name
                        )
                    )
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    Text(typeTag(for: entry))
                        .font(.meta)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, OneDayMetrics.spacingSM)
                .padding(.vertical, OneDayMetrics.spacingS)
                .frame(height: 64, alignment: .top)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(
                Palette.surface,
                in: RoundedRectangle(cornerRadius: OneDayMetrics.radiusPreview)
            )
            .overlay {
                RoundedRectangle(cornerRadius: OneDayMetrics.radiusPreview)
                    .strokeBorder(Palette.separator, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: OneDayMetrics.radiusPreview))
        }
        .buttonStyle(.odPressable)
        // 0.43.0（A11Y-V7）：Rotor 卡标记（网格态）
        .accessibilityRotorEntry(id: entry.name, in: fileRotorNamespace)
        .contextMenu {
            actionItems(for: entry, among: sortedDocuments)
        }
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

    // MARK: - 影音段

    @ViewBuilder
    private var mediaContent: some View {
        if deliverables == nil && loadError == nil {
            loadingState
        } else if let loadError, deliverables == nil {
            failureState(message: loadError)
        } else if mediaItems.isEmpty {
            emptyState(
                title: query.isEmpty
                    ? "暂无影音交付" : "没有匹配的文件",
                symbol: query.isEmpty
                    ? "photo.on.rectangle.angled" : "magnifyingglass",
                message: query.isEmpty
                    ? "智能体生成的图片、视频与音频会出现在这里。"
                    : "换个关键词试试。"
            )
        } else if displayMode == .grid {
            mediaGridView
        } else {
            mediaListView
        }
    }

    private let mediaColumns = [
        GridItem(.flexible(), spacing: OneDayMetrics.spacingMicro),
        GridItem(.flexible(), spacing: OneDayMetrics.spacingMicro),
        GridItem(.flexible(), spacing: OneDayMetrics.spacingMicro),
    ]

    /// 影音网格维持三列方形媒体格（§4.4：媒体本身即
    /// 内容、方形格是系统相册惯例，不随文件段网格变）
    private var mediaGridView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                LazyVGrid(columns: mediaColumns, spacing: OneDayMetrics.spacingMicro) {
                    ForEach(sortedMedia, id: \.id) { entry in
                        Button {
                            openEntry(entry, among: sortedMedia)
                        } label: {
                            MediaCell(entry: entry)
                                // zoom 转场源标记（0.36.4）
                                .matchedTransitionSource(
                                    id: entry.path,
                                    in: viewerNamespace
                                )
                        }
                        .buttonStyle(.odPressable)
                        // 0.43.0（A11Y-V7）：Rotor 卡标记
                        .accessibilityRotorEntry(
                            id: entry.name, in: fileRotorNamespace
                        )
                        .contextMenu {
                            actionItems(
                                for: entry, among: sortedMedia
                            )
                        }
                    }
                }
                noticeView
            }
            .padding(.bottom, OneDayMetrics.spacingXL)
        }
        .background(Palette.pageBG)
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y
        } action: { _, newValue in
            handleScrollOffset(newValue)
        }
    }

    /// 影音列表（§4.4 新补）：56pt 缩略行——标题＋类
    /// 型签＋大小·日期小字（服务端无时长字段，时长
    /// 不摆、如实以大小日期代，§七同口径）
    private var mediaListView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(spacing: 0) {
                    ForEach(
                        Array(sortedMedia.enumerated()),
                        id: \.element.id
                    ) { index, entry in
                        if index > 0 {
                            GroupDivider(
                                inset: OneDayMetrics.dividerInset
                            )
                        }
                        mediaRow(entry)
                    }
                }
                noticeView
            }
            .padding(.top, OneDayMetrics.spacingXS)
            .padding(.bottom, OneDayMetrics.spacingXL)
        }
        .background(Palette.pageBG)
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y
        } action: { _, newValue in
            handleScrollOffset(newValue)
        }
    }

    private func mediaRow(_ entry: WorkspaceFileEntry) -> some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            // 0.43.0（A11Y-V4）：与文件行同式——缩略
            // ＋题＋副题合并为按钮元素，⋮ 菜单独立
            HStack(spacing: OneDayMetrics.spacingSM) {
                ZStack {
                    FileThumbnailView(entry: entry, targetPixelSize: 168)
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: OneDayMetrics.radiusThumb))
                    if entry.mediaKind == .video {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(
                                Color.white, Palette.ink.opacity(0.55)
                            )
                            .accessibilityHidden(true)
                    }
                }
                .matchedTransitionSource(
                    id: entry.path, in: viewerNamespace
                )
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
                    Text(mediaSubtitle(entry))
                        .font(.rowSubtitle)
                        .foregroundStyle(Palette.inkSecondary)
                        .a11yLineLimit(1, ax: 2)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                openEntry(entry, among: sortedMedia)
            }
            Spacer(minLength: OneDayMetrics.spacingS)
            Menu {
                actionItems(for: entry, among: sortedMedia)
            } label: {
                Image(systemName: "ellipsis")
                    .rotationEffect(.degrees(90))
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(Palette.inkSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("更多操作")
        }
        .padding(.horizontal, OneDayMetrics.spacingM)
        .frame(minHeight: 64)
        .contentShape(Rectangle())
        // 0.43.0（A11Y-V7）：Rotor 行标记
        .accessibilityRotorEntry(id: entry.name, in: fileRotorNamespace)
        .onTapGesture {
            openEntry(entry, among: sortedMedia)
        }
        .contextMenu {
            actionItems(for: entry, among: sortedMedia)
        }
    }

    private func mediaSubtitle(
        _ entry: WorkspaceFileEntry
    ) -> String {
        let size = entry.size.map {
            ByteCountFormatter.string(
                fromByteCount: $0, countStyle: .file
            )
        }
        let date = AdminFormat.short(entry.modifiedAt)
        return [typeTag(for: entry), size, date]
            .compactMap { $0 }.joined(separator: " · ")
    }

    // MARK: - 条目动作（按类型适配，附记硬规矩）

    /// ⋮ 与长按共用同一动作集：FileActionPolicy.menu-
    /// Actions 按类型出项（文本类多复制文字/导出
    /// PDF、二进制只给分享/下载/删除），删除项红色
    @ViewBuilder
    private func actionItems(
        for entry: WorkspaceFileEntry,
        among siblings: [WorkspaceFileEntry]
    ) -> some View {
        ForEach(
            FileActionPolicy.menuActions(for: entry), id: \.self
        ) { action in
            if action == .delete {
                Button(role: .destructive) {
                    pendingDelete = deliverable(for: entry)
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
        }
    }

    /// 条目打开分流（0.36.31 按类型）：先写上次打开
    /// 记录；图片直达查看器（集合＝同段全部图片、可
    /// 翻页）；可读文本进文档阅读页（资料库层）；其
    /// 余走 FilePreviewView（QuickLook）
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
        } else if FileActionPolicy.opensInReader(entry) {
            readerEntry = entry
        } else {
            previewEntry = entry
        }
    }

    private func fetchData(
        _ entry: WorkspaceFileEntry
    ) async throws -> Data {
        try await appState.performAdmin { client, config in
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

    /// 查看器内删除（0.36.4）：与行删除同通道（管理
    /// 接口删＋重聚合）；落锤触感已由查看器在点删
    /// 时发过、本处成功不叠、失败 error
    private func deleteFromViewer(_ entry: WorkspaceFileEntry) async {
        do {
            try await appState.performAdmin { client, config in
                try await client.deleteFile(
                    config: config, path: entry.path,
                    recursive: false
                )
            }
            notice = "已删除「\(entry.name)」。"
            await collect()
        } catch {
            notice = (error as? HermesError)?.userMessage
                ?? "删除失败，请稍后再试。"
            Haptics.error()
        }
    }

    // MARK: - 聚合与动作（P8 通道沿用）

    /// 聚合各产出根（每根递归 ≤3 层、全局条目上限保
    /// 护）＋根目录散文件；全部条目先过 Deliverable-
    /// Admission 准入（0.22.0 去污：形态拦截全来源、
    /// 根散另过扩展名白名单），根散再过敏感名单第二
    /// 道（单源 SensitiveFilePolicy，0.36.31 并源）。
    /// 排序不在此处定案——视图层按页级排序状态走
    /// LibraryOrdering（本函数只负责聚合集本身）
    private func collect() async {
        var found: [Deliverable] = []
        var seenPaths = Set<String>()
        func absorb(_ entry: WorkspaceFileEntry, source: String) {
            guard !entry.isDirectory,
                  DeliverableAdmission.isAdmitted(
                      name: entry.name, isRootLooseFile: false
                  ),
                  seenPaths.insert(entry.path).inserted else { return }
            found.append(Deliverable(entry: entry, source: source))
        }
        for root in Self.outputRoots {
            var queue: [(path: String, depth: Int)] = [(root.path, 0)]
            var visited = 0
            while !queue.isEmpty {
                let (path, depth) = queue.removeFirst()
                guard let listing = try? await appState.performAdmin(
                    { client, config in
                        try await client.files(config: config, path: path)
                    }
                ) else { continue }
                visited += listing.entries.count
                for entry in listing.entries {
                    if entry.isDirectory {
                        if depth < 3 {
                            queue.append((entry.path, depth + 1))
                        }
                    } else {
                        absorb(entry, source: root.label)
                    }
                }
                if visited >= 600 { break }
            }
        }
        if let rootListing = try? await appState.performAdmin(
            { client, config in
                try await client.files(config: config, path: nil)
            }
        ) {
            for entry in rootListing.entries where !entry.isDirectory {
                guard DeliverableAdmission.isAdmitted(
                          name: entry.name, isRootLooseFile: true
                      ),
                      !SensitiveFilePolicy.protectedNames
                          .contains(entry.name)
                else { continue }
                absorb(entry, source: "工作区根目录")
            }
        }
        if found.isEmpty && deliverables == nil {
            let probe = try? await appState.performAdmin { client, config in
                try await client.files(config: config, path: nil)
            }
            if probe == nil {
                loadError = "产出目录没读出来，可能是网络或服务暂时没响应"
            }
        }
        deliverables = found.sorted {
            ($0.entry.mtime ?? 0) > ($1.entry.mtime ?? 0)
        }
        if loadError != nil && !(deliverables?.isEmpty ?? true) {
            loadError = nil
        }
    }

    private func delete(_ item: Deliverable) async {
        do {
            try await appState.performAdmin { client, config in
                try await client.deleteFile(
                    config: config, path: item.entry.path,
                    recursive: false
                )
            }
            notice = "已删除「\(item.entry.name)」。"
            // 成功无触感：确认时的 heavy 落锤已代表
            // 本链（规格 §2.3，同一因果链只震一次）
            await collect()
        } catch {
            notice = (error as? HermesError)?.userMessage
                ?? "删除失败，请稍后再试。"
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
struct Deliverable: Identifiable {
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

extension DeliverablesView {
    /// 产出根（路径, 来源名）——P8 实查口径起，0.22.0
    /// 按审计 F1 策展规格收紧为七；0.36.31 新增
    /// attachments（聊天发送的文件副本落点，0.36.29
    /// 文件真发送通道）：服务端副本无自动过期，本面
    /// 呈现＋既有删除通道即其生命周期出口
    fileprivate static let outputRoots: [(path: String, label: String)] = [
        ("/opt/data/uploads", "App 上传"),
        ("/opt/data/attachments", "聊天发送"),
        ("/opt/data/cache/images", "生成图片"),
        ("/opt/data/cache/documents", "生成文档"),
        ("/opt/data/cache/screenshots", "浏览器截图"),
        ("/opt/data/cache/videos", "生成的视频"),
        ("/opt/data/cache/audio", "生成的音频"),
        ("/opt/data/cron/output", "定时任务产出"),
    ]
}
