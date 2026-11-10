import OneDayCore
import OneDayDesign
import SwiftUI

/// 文件格（0.20.0 第七条，底栏第四格由「应用」换
/// 「文件」）：照用户给的 Muse 资源库页重做——顶部
/// 身份区沿用聊天页同款（左抽屉钮／中央身份胶囊／
/// 右搜索钮），其下大分段 [文件｜影音内容]，文件段
/// ＝交付物列表（类型图标＋标题＋类型小字＋行尾
/// ⋮），影音段＝媒体三列网格。
///
/// **交付物口径（用户原话：用户让做的东西做好之后
/// 放里面的，如 PPT——不是服务器全部文件）**：数据
/// 沿 P8（0.14.0）既有产出聚合通道，是全仓唯一现成
/// 的「产出」信号面——/api/files（根锁 /opt/data）
/// 扫产出根（递归 ≤3 层）＋根目录散文件，按 mtime
/// 倒序。服务端文件全量浏览不在本页（已迁设置「管
/// 理」服务器文件）。v1 缺口如实记 §47：产出与会话
/// 之间无关联字段，来源只标到产出目录级；聊天内附
/// 件（本地 imageData）与服务端工作区散件不在此面。
/// **0.22.0 去污（视觉审计 F1，用户 00:12 实机首屏
/// 9 行全是 state.db-wal 类服务器内脏）**：准入改
/// Core 纯函数 DeliverableAdmission 四层把守——产
/// 出根十→七（scratch 临时产出与 image/audio_cache
/// 下载缓存退出本面、仍可在服务器文件里达）、根散
/// 文件改扩展名白名单、内部名形态拦截全来源生效、
/// 旧 deny 名单保留作第二道；拒收样本以实机 9 个污
/// 染文件名作单测钉死。此后本面首屏只应剩真交付物。
struct DeliverablesView: View {
    @Environment(AppState.self) private var appState
    // 0.25.0（动效专包）：本面动画走令牌＋resolved 出口
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
    /// 图片查看器路由（0.36.4）：图片直达查看器（系
    /// 统 zoom 转场、源＝网格 cell 的 matched 标记），
    /// 不再先进 FilePreviewView 预览页
    @State private var viewerRoute: ImageViewerRoute?
    @Namespace private var viewerNamespace

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
                segmentControl
                if searchVisible {
                    searchRow
                }
                if segment == 0 {
                    fileList
                } else {
                    mediaGrid
                }
            }
            .background(Palette.pageBG)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $previewEntry) { entry in
                FilePreviewView(entry: entry)
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
            .refreshable { await collect() }
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

    // MARK: - 顶部身份区（沿用聊天页同款三件）

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
                Button {
                    // 0.25.0（动效专包）：原 withAnimation
                    // (.default) 裸动画——收编 swap 令牌＋
                    // resolved 出口（Reduce Motion 时瞬时）
                    withAnimation(
                        MotionTokens.resolved(
                            MotionTokens.swap, reduceMotion: reduceMotion
                        )
                    ) {
                        searchVisible.toggle()
                        if !searchVisible { query = "" }
                    }
                } label: {
                    headerCircleButton("magnifyingglass")
                }
                .buttonStyle(.odPressable)
                .accessibilityLabel(searchVisible ? "收起搜索" : "搜索文件")
            }
            IdentityAnchor(
                name: appState.identityName ?? AgentName.fallback,
                statusWord: appState.config == nil ? "未连接" : "在线",
                statusColor: appState.config == nil
                    ? Palette.inkMuted : Palette.success,
                // 0.22.0（审计 F3）：真头像注入，与聊天页
                // 胶囊同一头像源（此前是 sparkles 占位、
                // 切换器并排即露馅的身份双源）
                avatarImage: Image("SangouPartner")
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
            // 0.23.0（审计 T2）：与聊天页顶栏圆钮同改
            // ——白浮纸换系统玻璃 .glassEffect(.regular)，
            // 与同排身份胶囊同族材质；视觉盘 40 不变
            .glassEffect(.regular, in: Circle())
            // 0.23.0（命中域审计）：命中域外扩 44（视觉
            // 盘居中不变），与聊天页顶栏钮同口径
            .frame(
                width: OneDayMetrics.minTapTarget,
                height: OneDayMetrics.minTapTarget
            )
            .contentShape(Rectangle())
    }

    // MARK: - 大分段（照 Muse 资源库图自制）

    /// 分段控件（0.36.2 按体验三件规格 §1.6 重做）：
    /// 系统 segmented 量级不符、本页自制（偏离原生
    /// 登记 §47）。旧形态三宗错——角色反置（轨道灰
    /// selectionFill／药丸白 surface＋阴影浮起）、全
    /// 面偏大（总高 60／药丸 52，源头是旧注「段高约
    /// 63 照图复刻」的目测高估）、未选字灰化。本版
    /// 按实测落值（SegmentedControlSpec 钉死）：轨道
    /// ＝surface 白＋发丝边、全胶囊，总高 48；选中
    /// 药丸＝selectionFill 灰垫、高 36、内缩 6、无
    /// 阴影；字 17 semibold 两态皆 ink——选中区分
    /// 只靠灰垫有无。切换＝药丸 matchedGeometry 滑
    /// 移（弹簧走动效宪法默认档 selectionSpring，
    /// 无手势来源零回弹）＋selection 触感（表 D）。
    @Namespace private var segmentNamespace

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
                // 字 17 semibold、两态皆 ink（规格
                // §1.6：字号沿现行 17，只改字重与
                // 未选色——区分只靠灰垫）
                .font(.bodyText.weight(.semibold))
                .foregroundStyle(Palette.ink)
                .frame(
                    maxWidth: .infinity,
                    minHeight: SegmentedControlSpec.pillHeight
                )
                .background {
                    if selected {
                        // 药丸圆角 18＝药丸高/2，Capsule
                        // 与落值同值（SegmentedControlSpec
                        // .pillCorner 同心口径）
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

    private var searchRow: some View {
        HStack(spacing: OneDayMetrics.spacingM) {
            FileSearchField(query: $query)
            FileUploadControl(
                targetDirectory: Self.uploadsPath,
                ensureDirectory: true
            ) { message, confirmed in
                notice = message
                if confirmed {
                    Task { await collect() }
                }
            }
        }
        .padding(.horizontal, OneDayMetrics.pageGutter)
        .padding(.bottom, OneDayMetrics.spacingSM)
    }

    // MARK: - 文件段（交付物列表）

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

    private var fileList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if deliverables == nil && loadError == nil {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, OneDayMetrics.spacingXXL)
                } else if let loadError, deliverables == nil {
                    EmptyState(
                        icon: "exclamationmark.triangle",
                        title: "读取失败",
                        message: loadError
                    )
                    .padding(.top, OneDayMetrics.spacingXXL)
                } else if documents.isEmpty {
                    // 0.24.0：空态迁系统 ContentUnavail-
                    // ableView 原生形态（图标/标题/副题全
                    // 走系统默认排版），自绘 EmptyState 在
                    // 本页退役（他页仍用，见 §51）
                    if query.isEmpty {
                        ContentUnavailableView(
                            "暂无交付物",
                            systemImage: "doc.text.magnifyingglass",
                            description: Text(
                                "智能体生成的文件与定时任务产出会出现在这里。"
                            )
                        )
                        .padding(.top, OneDayMetrics.spacingXXL)
                    } else {
                        ContentUnavailableView(
                            "没有匹配的文件",
                            systemImage: "magnifyingglass",
                            description: Text("换个关键词试试。")
                        )
                        .padding(.top, OneDayMetrics.spacingXXL)
                    }
                } else {
                    VStack(spacing: 0) {
                        ForEach(
                            Array(documents.enumerated()),
                            id: \.element.id
                        ) { index, item in
                            if index > 0 {
                                GroupDivider(
                                    inset: OneDayMetrics.dividerInset
                                )
                            }
                            deliverableRow(item)
                        }
                    }
                }
                if let notice {
                    Text(notice)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.top, OneDayMetrics.spacingM)
                        .padding(.horizontal, OneDayMetrics.pageGutter)
                }
            }
            .padding(.top, OneDayMetrics.spacingXS)
            .padding(.bottom, OneDayMetrics.spacingXL)
        }
        .background(Palette.pageBG)
    }

    /// 交付物行（照 Muse 资源库 Files 图）：类型图
    /// 标盒＋标题（20）＋类型小字（15 灰，Deliver-
    /// ableFileType）＋行尾 ⋮（菜单只两件：预览/分
    /// 享）；点行本体进预览（FilePreviewView，
    /// QuickLook）；删除留在长按菜单（与 P8 同口径，
    /// 带确认）
    private func deliverableRow(_ item: Deliverable) -> some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            FileIconBox(entry: item.entry)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.entry.name)
                    // 0.23.0：行题/类型小字落字阶角色
                    // rowTitleL/rowSubtitle（默认 20/15 等值）
                    .font(.rowTitleL)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text(
                    DeliverableFileType.label(
                        forFileName: item.entry.name
                    )
                )
                .font(.rowSubtitle)
                .foregroundStyle(Palette.inkSecondary)
                .lineLimit(1)
            }
            Spacer(minLength: OneDayMetrics.spacingS)
            Menu {
                Button {
                    openEntry(item.entry, among: documents)
                } label: {
                    Label("预览", systemImage: "eye")
                }
                Button {
                    Task { await download(item.entry) }
                } label: {
                    Label("分享", systemImage: "square.and.arrow.up")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .rotationEffect(.degrees(90))
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(Palette.inkSecondary)
                    // 0.22.0（审计 F4）：命中域 32→44
                    // （字形 18 不变、行高 64 内可容纳）
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("更多操作")
        }
        .padding(.horizontal, OneDayMetrics.spacingM)
        .frame(minHeight: 64)
        .contentShape(Rectangle())
        .onTapGesture { openEntry(item.entry, among: documents) }
        .contextMenu {
            Button {
                Task { await download(item.entry) }
            } label: {
                Label("下载到本地", systemImage: "arrow.down.to.line")
            }
            Button(role: .destructive) {
                pendingDelete = item
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    /// 条目打开分流（0.36.4）：图片直达查看器（集
    /// 合＝同段全部图片、可翻页），其余仍走 File-
    /// PreviewView（QuickLook）。文件段条目恒非图
    /// 片（documents 已按 mediaKind 过滤），分流在
    /// 此只对影音段实际生效、文件段同路无副作用
    private func openEntry(
        _ entry: WorkspaceFileEntry, among siblings: [Deliverable]
    ) {
        if entry.mediaKind == .image {
            let images = siblings.map(\.entry).filter {
                $0.mediaKind == .image
            }
            viewerRoute = ImageViewerRoute(
                entries: images,
                initialIndex: images.firstIndex(of: entry) ?? 0
            )
        } else {
            previewEntry = entry
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

    // MARK: - 影音段（媒体三列网格）

    private var mediaItems: [Deliverable] {
        (deliverables ?? []).filter {
            $0.entry.mediaKind != nil && matchesQuery($0)
        }
    }

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
    ]

    private var mediaGrid: some View {
        ScrollView {
            if deliverables == nil && loadError == nil {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, OneDayMetrics.spacingXXL)
            } else if mediaItems.isEmpty {
                // 0.24.0：同文件段，迁系统 ContentUn-
                // availableView 原生形态
                ContentUnavailableView(
                    "暂无影音交付",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text(
                        "智能体生成的图片、视频与音频会出现在这里。"
                    )
                )
                .padding(.top, OneDayMetrics.spacingXXL)
            } else {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(mediaItems) { item in
                        Button {
                            openEntry(item.entry, among: mediaItems)
                        } label: {
                            MediaCell(entry: item.entry)
                                // zoom 转场源标记（0.36.4）：
                                // 点开的图自本格长成查看器卡
                                .matchedTransitionSource(
                                    id: item.entry.path,
                                    in: viewerNamespace
                                )
                        }
                        .buttonStyle(.odPressable)
                        .contextMenu {
                            Button(role: .destructive) {
                                pendingDelete = item
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .background(Palette.pageBG)
    }

    // MARK: - 聚合与动作（P8 通道沿用）

    /// 聚合各产出根（每根递归 ≤3 层、全局条目上限保
    /// 护）＋根目录散文件，按 mtime 倒序、路径去重；
    /// 全部条目先过 DeliverableAdmission 准入（0.22.0
    /// 去污：形态拦截全来源、根散另过扩展名白名单）
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
                // 0.22.0：根散文件准入＝扩展名白名单＋形
                // 态拦截（DeliverableAdmission）；旧 deny
                // 名单保留作第二道（.md 白名单会放行人
                // 格文件、靠它挡回）
                guard DeliverableAdmission.isAdmitted(
                          name: entry.name, isRootLooseFile: true
                      ),
                      !Self.rootDenyList.contains(entry.name)
                else { continue }
                absorb(entry, source: "工作区根目录")
            }
        }
        if found.isEmpty && deliverables == nil {
            let probe = try? await appState.performAdmin { client, config in
                try await client.files(config: config, path: nil)
            }
            if probe == nil {
                loadError = "产出目录读取失败，请下拉重试。"
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
            let data = try await appState.performAdmin { client, config in
                try await client.fileData(
                    config: config, path: entry.path
                )
            }
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
    /// 按审计 F1 策展规格收紧十→七：cache/scratch（临
    /// 时产出）、image_cache、audio_cache（下载缓存）
    /// 退出本面——它们的东西在设置「管理」服务器文件
    /// 里仍可达，交付物面只认成果；uploads 为 App 上
    /// 传落点
    fileprivate static let outputRoots: [(path: String, label: String)] = [
        ("/opt/data/uploads", "App 上传"),
        ("/opt/data/cache/images", "生成图片"),
        ("/opt/data/cache/documents", "生成文档"),
        ("/opt/data/cache/screenshots", "浏览器截图"),
        ("/opt/data/cache/videos", "生成的视频"),
        ("/opt/data/cache/audio", "生成的音频"),
        ("/opt/data/cron/output", "定时任务产出"),
    ]

    /// 根目录散文件的排除名单：服务端自身的配置/人
    /// 格/状态文件，不是交付物
    fileprivate static let rootDenyList: Set<String> = [
        "config.yaml", ".env", "auth.json",
        "SOUL.md", "AGENTS.md", "USER.md", "MEMORY.md", "IDENTITY.md",
    ]
}
