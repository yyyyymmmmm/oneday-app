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
/// 只扫十个产出根（uploads／cache 的 images、
/// documents、screenshots、videos、audio、scratch／
/// cron/output／image_cache、audio_cache，递归 ≤3
/// 层）＋根目录散文件（系统文件 deny list 剔除），
/// 按 mtime 倒序。服务端文件全量浏览不在本页（已
/// 迁设置「管理」服务器文件）。v1 缺口如实记 §47：
/// 产出与会话之间无关联字段，来源只标到产出目录
/// 级；聊天内附件（本地 imageData）与服务端工作区
/// 散件不在此面。
struct DeliverablesView: View {
    @Environment(AppState.self) private var appState

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
                .buttonStyle(.plain)
                .accessibilityLabel("会话列表")
                Spacer()
                Button {
                    withAnimation(.default) {
                        searchVisible.toggle()
                        if !searchVisible { query = "" }
                    }
                } label: {
                    headerCircleButton("magnifyingglass")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(searchVisible ? "收起搜索" : "搜索文件")
            }
            IdentityAnchor(
                name: appState.identityName ?? AgentName.fallback,
                statusWord: appState.config == nil ? "未连接" : "在线",
                statusColor: appState.config == nil
                    ? Palette.inkMuted : Palette.success
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
            .odFloatPaper(in: Circle())
    }

    // MARK: - 大分段（照 Muse 资源库图自制）

    /// 分段控件照图复刻：图中段高约 63pt、段字约
    /// 22pt 半粗——系统 segmented（约 28 高/13 字）
    /// 量级明显不符，本页自制（偏离原生登记 §47）：
    /// 浅灰槽＋选中段白面浮起，段字 20 半粗、高 52，
    /// 动画只用系统 .default、不自绘曲线
    private var segmentControl: some View {
        HStack(spacing: 0) {
            segmentButton(title: "文件", tag: 0)
            segmentButton(title: "影音内容", tag: 1)
        }
        .padding(4)
        .background(
            Palette.selectionFill,
            in: RoundedRectangle(
                cornerRadius: 22, style: .continuous
            )
        )
        .padding(.horizontal, OneDayMetrics.pageGutter)
        .padding(.vertical, OneDayMetrics.spacingSM)
    }

    private func segmentButton(title: String, tag: Int) -> some View {
        let selected = segment == tag
        return Button {
            withAnimation(.default) { segment = tag }
        } label: {
            Text(title)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(
                    selected ? Palette.ink : Palette.inkSecondary
                )
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(
                    selected ? Palette.surface : Color.clear,
                    in: RoundedRectangle(
                        cornerRadius: 18, style: .continuous
                    )
                )
                .shadow(
                    color: selected
                        ? Palette.shadowBase.opacity(0.08) : .clear,
                    radius: 6, y: 2
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                    if query.isEmpty {
                        EmptyState(
                            icon: "doc.text.magnifyingglass",
                            title: "暂无交付物",
                            message: "智能体生成的文件与定时任务产出会出现在这里。"
                        )
                        .padding(.top, OneDayMetrics.spacingXXL)
                    } else {
                        EmptyState(
                            icon: "magnifyingglass",
                            title: "没有匹配的文件",
                            message: "换个关键词试试。"
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
                    .font(.system(size: 20))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text(
                    DeliverableFileType.label(
                        forFileName: item.entry.name
                    )
                )
                .font(.system(size: 15))
                .foregroundStyle(Palette.inkSecondary)
                .lineLimit(1)
            }
            Spacer(minLength: OneDayMetrics.spacingS)
            Menu {
                Button {
                    previewEntry = item.entry
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
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("更多操作")
        }
        .padding(.horizontal, OneDayMetrics.spacingM)
        .frame(minHeight: 64)
        .contentShape(Rectangle())
        .onTapGesture { previewEntry = item.entry }
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
                EmptyState(
                    icon: "photo.on.rectangle.angled",
                    title: "暂无影音交付",
                    message: "智能体生成的图片、视频与音频会出现在这里。"
                )
                .padding(.top, OneDayMetrics.spacingXXL)
            } else {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(mediaItems) { item in
                        Button {
                            previewEntry = item.entry
                        } label: {
                            MediaCell(entry: item.entry)
                        }
                        .buttonStyle(.plain)
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
    /// 护）＋根目录散文件（排除已知系统文件与隐藏文
    /// 件），按 mtime 倒序、路径去重
    private func collect() async {
        var found: [Deliverable] = []
        var seenPaths = Set<String>()
        func absorb(_ entry: WorkspaceFileEntry, source: String) {
            guard !entry.isDirectory,
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
                guard !entry.name.hasPrefix("."),
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
            Haptics.success()
            await collect()
        } catch {
            notice = (error as? HermesError)?.userMessage
                ?? "删除失败，请稍后再试。"
            Haptics.warning()
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
    /// 产出根（路径, 来源名）——P8 实查口径沿用；
    /// uploads 为 App 上传落点
    fileprivate static let outputRoots: [(path: String, label: String)] = [
        ("/opt/data/uploads", "App 上传"),
        ("/opt/data/cache/images", "生成图片"),
        ("/opt/data/cache/documents", "生成文档"),
        ("/opt/data/cache/screenshots", "浏览器截图"),
        ("/opt/data/cache/videos", "生成的视频"),
        ("/opt/data/cache/audio", "生成的音频"),
        ("/opt/data/cache/scratch", "临时产出"),
        ("/opt/data/cron/output", "定时任务产出"),
        ("/opt/data/image_cache", "图片缓存"),
        ("/opt/data/audio_cache", "音频缓存"),
    ]

    /// 根目录散文件的排除名单：服务端自身的配置/人
    /// 格/状态文件，不是交付物
    fileprivate static let rootDenyList: Set<String> = [
        "config.yaml", ".env", "auth.json",
        "SOUL.md", "AGENTS.md", "USER.md", "MEMORY.md", "IDENTITY.md",
    ]
}
