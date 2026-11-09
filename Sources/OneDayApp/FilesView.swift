import OneDayCore
import OneDayDesign
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// 文件格（0.14.0 P8 升级）：四段——影音（交付影音网格）、
/// 交付物（产出聚合列表＋搜索＋上传）、浏览（managed 根
/// 目录浏览器：面包屑/排序/段内搜索/上传/新建文件夹/删
/// 除）、电脑（Box /workspace 产出，契约 box-files-
/// contract-20261109.md；桥侧文件面未部署前如实露未开通）。
/// 数据源口径：/api/files 根被 locked_root 锁死在服务端
/// 数据目录 /opt/data 内（0.2.1 生产实查），列表/读/下载/
/// 删除/上传/建夹同走 9119 会话通道；写动作（上传/建夹/
/// 删除）不依赖回执形态，一律回读列表对账才算落定。
/// 产出与会话之间没有关联字段——来源只标到产出目录级，
/// 不编造会话溯源。
struct FilesView: View {
    /// 0.6.0：自应用格进入时挂「应用」返回钮（口径同总览）
    var onBackToApps: (() -> Void)? = nil

    @Environment(AppState.self) private var appState

    @State private var segment = 0
    @State private var deliverables: [Deliverable]?
    @State private var loadError: String?
    @State private var pendingDelete: Deliverable?
    @State private var shareItem: FileShareItem?
    @State private var notice: String?
    @State private var deliverableQuery = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 身份锚点（0.3.8 基线补遗增量令 1）：与总览/
                // 聊天同一组件、同一位置口径，切页锚点不动
                HStack {
                    Spacer()
                    IdentityAnchor(
                        name: "Hermes",
                        statusWord: appState.config == nil ? "未连接" : "在线",
                        statusColor: appState.config == nil
                            ? Palette.inkMuted : Palette.success
                    )
                    Spacer()
                }
                .padding(.top, OneDayMetrics.spacingS)
                Picker("浏览方式", selection: $segment) {
                    Text("影音").tag(0)
                    Text("交付物").tag(1)
                    Text("浏览").tag(2)
                    Text("电脑").tag(3)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, OneDayMetrics.pageGutter)
                .padding(.vertical, OneDayMetrics.spacingS)
                if segment == 0 {
                    mediaGrid
                } else if segment == 1 {
                    fileList
                } else if segment == 2 {
                    FilesBrowserView()
                } else {
                    BoxFilesView()
                }
            }
            .background(Palette.pageBG)
            .navigationTitle("文件")
            .toolbar {
                if let onBackToApps {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: onBackToApps) {
                            Label("应用", systemImage: "chevron.left")
                        }
                    }
                }
            }
            .navigationDestination(for: WorkspaceFileEntry.self) { entry in
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
                    // 0.3.2：确认点不再挂触觉，结果点在 delete()
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

    // MARK: - 交付物段

    /// App 上传落点（managed 根下专属目录，聚合里标
    /// 「App 上传」来源）
    static var uploadsPath: String {
        FileBrowserLogic.joinPath(
            directory: "/opt/data",
            name: FileBrowserLogic.uploadsDirectoryName
        )
    }

    private func matchesQuery(_ item: Deliverable) -> Bool {
        let query = deliverableQuery.trimmingCharacters(in: .whitespaces)
        return query.isEmpty
            || item.entry.name.localizedCaseInsensitiveContains(query)
    }

    private var documents: [Deliverable] {
        (deliverables ?? []).filter {
            $0.entry.mediaKind == nil && matchesQuery($0)
        }
    }

    private var fileList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: OneDayMetrics.spacingM) {
                    FileSearchField(query: $deliverableQuery)
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
                .padding(.bottom, OneDayMetrics.spacingM)
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
                    if deliverableQuery.isEmpty {
                        EmptyState(
                            icon: "doc.text.magnifyingglass",
                            title: "暂无交付物",
                            message: "智能体生成的文件、图片与定时任务产出会出现在这里。"
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
                        ForEach(Array(documents.enumerated()), id: \.element.id) { index, item in
                            if index > 0 {
                                GroupDivider(inset: OneDayMetrics.dividerInset)
                            }
                            deliverableRow(item)
                        }
                    }
                    .odGroup()
                }
                if let notice {
                    Text(notice)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.top, OneDayMetrics.spacingM)
                }
            }
            .padding(.horizontal, OneDayMetrics.pageGutter)
            .padding(.top, OneDayMetrics.spacingS)
            .padding(.bottom, OneDayMetrics.spacingXL)
        }
        .background(Palette.pageBG)
    }

    private func deliverableRow(_ item: Deliverable) -> some View {
        NavigationLink(value: item.entry) {
            HStack(spacing: OneDayMetrics.spacingSM) {
                FileIconBox(entry: item.entry)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.entry.name)
                        .font(.callout)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Text(item.subtitle)
                        .font(.caption)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                        // 条 6 补落点（0.3.2）：大小/日期读数等宽
                        .tabularDigits()
                }
                Spacer(minLength: OneDayMetrics.spacingS)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Palette.inkMuted)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, OneDayMetrics.spacingM)
            .frame(minHeight: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.odPressable)
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

    // MARK: - 影音段

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
                        NavigationLink(value: item.entry) {
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

    // MARK: - 聚合与动作

    /// 聚合各产出根（每根递归 ≤3 层、全局条目上限保护）＋根目录
    /// 散文件（排除已知系统文件与隐藏文件），按 mtime 倒序、
    /// 路径去重
    private func collect() async {
        var found: [Deliverable] = []
        var seenPaths = Set<String>()
        func absorb(_ entry: WorkspaceFileEntry, source: String) {
            guard !entry.isDirectory, seenPaths.insert(entry.path).inserted else { return }
            found.append(Deliverable(entry: entry, source: source))
        }
        for root in Self.outputRoots {
            var queue: [(path: String, depth: Int)] = [(root.path, 0)]
            var visited = 0
            while !queue.isEmpty {
                let (path, depth) = queue.removeFirst()
                guard let listing = try? await appState.performAdmin({ client, config in
                    try await client.files(config: config, path: path)
                }) else { continue }
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
        if let rootListing = try? await appState.performAdmin({ client, config in
            try await client.files(config: config, path: nil)
        }) {
            for entry in rootListing.entries where !entry.isDirectory {
                guard !entry.name.hasPrefix("."),
                      !Self.rootDenyList.contains(entry.name) else { continue }
                absorb(entry, source: "工作区根目录")
            }
        }
        if found.isEmpty && deliverables == nil {
            // 全部根都拉不到才算失败；部分失败静默（空产出目录
            // 在新部署上是正常态，不把空当错）
            let probe = try? await appState.performAdmin { client, config in
                try await client.files(config: config, path: nil)
            }
            if probe == nil {
                loadError = "产出目录读取失败，请下拉重试。"
            }
        }
        deliverables = found.sorted { ($0.entry.mtime ?? 0) > ($1.entry.mtime ?? 0) }
        if loadError != nil && !(deliverables?.isEmpty ?? true) {
            loadError = nil
        }
    }

    private func delete(_ item: Deliverable) async {
        do {
            try await appState.performAdmin { client, config in
                try await client.deleteFile(
                    config: config, path: item.entry.path, recursive: false
                )
            }
            notice = "已删除「\(item.entry.name)」。"
            // 结果触感（0.3.2 纪律）：操作成功 .success
            Haptics.success()
            await collect()
        } catch {
            notice = (error as? HermesError)?.userMessage ?? "删除失败，请稍后再试。"
            Haptics.warning()
        }
    }

    private func download(_ entry: WorkspaceFileEntry) async {
        do {
            let data = try await appState.performAdmin { client, config in
                try await client.fileData(config: config, path: entry.path)
            }
            shareItem = try FileShareItem.write(data: data, name: entry.name)
        } catch {
            notice = (error as? HermesError)?.userMessage ?? "下载失败，请稍后再试。"
        }
    }
}

/// 交付物：工作区文件条目＋来源（产出目录语义名）
private struct Deliverable: Identifiable {
    let entry: WorkspaceFileEntry
    let source: String

    var id: String { entry.path }

    var subtitle: String {
        let size = entry.size.map {
            ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)
        }
        let date = AdminFormat.short(entry.modifiedAt)
        return [source, size, date].compactMap { $0 }.joined(separator: " · ")
    }
}

extension FilesView {
    /// 产出根（路径, 来源名）——实查口径见文件头注释；
    /// uploads 为 0.14.0 新增的 App 上传落点
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

    /// 根目录散文件的排除名单：服务端自身的配置/人格/状态文件，
    /// 不是交付物
    fileprivate static let rootDenyList: Set<String> = [
        "config.yaml", ".env", "auth.json",
        "SOUL.md", "AGENTS.md", "USER.md", "MEMORY.md", "IDENTITY.md",
    ]
}

// MARK: - 条目呈现扩展

extension WorkspaceFileEntry {
    var odIconName: String {
        if isDirectory { return "folder" }
        switch mediaKind {
        case .image: return "photo"
        case .video: return "film"
        case .audio: return "waveform"
        case nil:
            return isTextLike ? "doc.text" : "doc"
        }
    }

    var odSubtitle: String {
        if isDirectory {
            return "文件夹"
        }
        let size = size.map {
            ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)
        }
        let date = AdminFormat.short(modifiedAt)
        return [size, date].compactMap { $0 }.joined(separator: " · ")
    }
}

// MARK: - 共享小件（搜索/图标盒/上传）

private struct FileSearchField: View {
    @Binding var query: String

    var body: some View {
        HStack(spacing: OneDayMetrics.spacingS) {
            Image(systemName: "magnifyingglass")
                .font(.footnote)
                .foregroundStyle(Palette.inkMuted)
                .accessibilityHidden(true)
            TextField("搜索文件名", text: $query)
                .textFieldStyle(.plain)
                .font(.callout)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Palette.inkMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清空搜索")
            }
        }
        .padding(.horizontal, OneDayMetrics.spacingM)
        .padding(.vertical, OneDayMetrics.spacingS)
        .background(Palette.fieldFill, in: RoundedRectangle(cornerRadius: 10))
    }
}

/// 类型图标盒（设计标准 §7 P8 锚：文件行＝LinkRow＋类型
/// 图标盒 pastel 轮换；轮换序号由 FileBrowserLogic 按
/// 类别稳定给出）
private struct FileIconBox: View {
    let entry: WorkspaceFileEntry

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(tint)
            Image(systemName: entry.odIconName)
                .font(.system(size: 15))
                .foregroundStyle(Palette.ink)
        }
        .frame(width: 32, height: 32)
        .accessibilityHidden(true)
    }

    private var tint: Color {
        [
            Palette.tintSky, Palette.tintGreen,
            Palette.tintLavender, Palette.tintOrange,
        ][FileBrowserLogic.tintIndex(for: entry)]
    }
}

/// 上传控件（交付物段与浏览段共用）：选件→读字节→上限
/// 拦截→（可选）确保目标目录→同名预检确认→POST→回读
/// 对账（同名条目 size 与本地字节一致才算落定）。
private struct FileUploadControl: View {
    @Environment(AppState.self) private var appState

    let targetDirectory: String
    var ensureDirectory: Bool = false
    /// (结果文案, 是否已回读确认落盘）
    let onFinished: (String, Bool) -> Void

    @State private var pickerPresented = false
    @State private var pendingOverwrite: PendingUpload?
    @State private var isUploading = false

    private struct PendingUpload {
        let name: String
        let data: Data
    }

    var body: some View {
        Button {
            pickerPresented = true
        } label: {
            Label(
                isUploading ? "上传中…" : "上传文件",
                systemImage: "arrow.up.doc"
            )
            .font(.callout)
        }
        .disabled(isUploading)
        .fileImporter(
            isPresented: $pickerPresented,
            allowedContentTypes: [.item]
        ) { result in
            Task { await handlePick(result) }
        }
        .confirmationDialog(
            "已存在同名文件「\(pendingOverwrite?.name ?? "")」，覆盖它？",
            isPresented: Binding(
                get: { pendingOverwrite != nil },
                set: { if !$0 { pendingOverwrite = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("覆盖上传") {
                if let pending = pendingOverwrite {
                    pendingOverwrite = nil
                    Task {
                        await upload(
                            name: pending.name, data: pending.data
                        )
                    }
                }
            }
            Button("取消", role: .cancel) {
                pendingOverwrite = nil
                onFinished("已取消上传。", false)
            }
        } message: {
            Text("覆盖后原文件无法恢复。")
        }
    }

    private func fetchListing(_ path: String) async throws -> FilesListing {
        try await appState.performAdmin { client, config in
            try await client.files(config: config, path: path)
        }
    }

    private func handlePick(_ result: Result<URL, Error>) async {
        guard case .success(let url) = result else {
            onFinished("没有选到文件。", false)
            return
        }
        let name = url.lastPathComponent
        let scoped = url.startAccessingSecurityScopedResource()
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            if scoped { url.stopAccessingSecurityScopedResource() }
            onFinished("读取所选文件失败。", false)
            return
        }
        if scoped { url.stopAccessingSecurityScopedResource() }
        guard FileBrowserLogic.isUploadSizeAllowed(byteCount: data.count)
        else {
            onFinished("「\(name)」超过 25MB，暂不能从 App 上传。", false)
            return
        }
        isUploading = true
        if ensureDirectory,
           (try? await fetchListing(targetDirectory)) == nil {
            try? await appState.performAdmin { client, config in
                try await client.makeDirectory(
                    config: config, path: targetDirectory
                )
            }
        }
        if let listing = try? await fetchListing(targetDirectory),
           listing.entries.contains(
               where: { !$0.isDirectory && $0.name == name }
           ) {
            isUploading = false
            pendingOverwrite = PendingUpload(name: name, data: data)
            return
        }
        await upload(name: name, data: data)
    }

    private func upload(name: String, data: Data) async {
        isUploading = true
        defer { isUploading = false }
        do {
            let target = FileBrowserLogic.joinPath(
                directory: targetDirectory, name: name
            )
            let dataURL = FileBrowserLogic.makeDataURL(
                data: data, fileName: name
            )
            try await appState.performAdmin { client, config in
                try await client.uploadFile(
                    config: config, path: target,
                    dataURL: dataURL, overwrite: true
                )
            }
            // 回读对账：同名条目在且字节数一致才算落定
            if let listing = try? await fetchListing(targetDirectory),
               let entry = listing.entries.first(
                   where: { $0.name == name && !$0.isDirectory }
               ),
               entry.size == Int64(data.count) {
                Haptics.success()
                onFinished("已上传「\(name)」并在服务端确认。", true)
            } else {
                onFinished(
                    "上传已发出，但回读没有确认「\(name)」落盘，请刷新核对。",
                    false
                )
            }
        } catch {
            Haptics.warning()
            onFinished(
                (error as? HermesError)?.userMessage
                    ?? "上传失败，请稍后再试。",
                false
            )
        }
    }
}

// MARK: - 浏览段（目录浏览器）

/// 状态驱动路径的目录浏览器：面包屑点跳、排序三键、
/// 段内搜索；下钻不走导航栈（与外层栈的文件预览目的地
/// 互不干扰），返回靠面包屑回到任意层。
private struct FilesBrowserView: View {
    @Environment(AppState.self) private var appState

    /// nil = 尚未定位，首拉用服务端默认根，回来后落具体路径
    @State private var currentPath: String?
    @State private var listing: FilesListing?
    @State private var loadError: String?
    @State private var sortKey: FileBrowserLogic.SortKey = .name
    @State private var query = ""
    @State private var notice: String?
    @State private var pendingDelete: WorkspaceFileEntry?
    @State private var shareItem: FileShareItem?
    @State private var mkdirPresented = false
    @State private var newFolderName = ""

    private var rootPath: String {
        listing?.lockedRoot ?? listing?.root ?? "/opt/data"
    }

    private var shownEntries: [WorkspaceFileEntry] {
        guard let listing else { return [] }
        return FileBrowserLogic.sorted(
            FileBrowserLogic.filtered(listing.entries, query: query),
            by: sortKey
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let listing {
                breadcrumbBar(listing: listing)
                    .padding(.horizontal, OneDayMetrics.pageGutter)
                HStack(spacing: OneDayMetrics.spacingM) {
                    FileUploadControl(
                        targetDirectory: listing.path
                    ) { message, _ in
                        notice = message
                        Task { await load() }
                    }
                    Button {
                        newFolderName = ""
                        mkdirPresented = true
                    } label: {
                        Label("新建文件夹", systemImage: "folder.badge.plus")
                            .font(.callout)
                    }
                    Spacer()
                    Menu {
                        ForEach(
                            FileBrowserLogic.SortKey.allCases, id: \.self
                        ) { key in
                            Button {
                                sortKey = key
                            } label: {
                                if sortKey == key {
                                    Label(key.label, systemImage: "checkmark")
                                } else {
                                    Text(key.label)
                                }
                            }
                        }
                    } label: {
                        Label(
                            "按\(sortKey.label)",
                            systemImage: "arrow.up.arrow.down"
                        )
                        .font(.callout)
                    }
                }
                .padding(.horizontal, OneDayMetrics.pageGutter)
                .padding(.vertical, OneDayMetrics.spacingS)
                FileSearchField(query: $query)
                    .padding(.horizontal, OneDayMetrics.pageGutter)
                    .padding(.bottom, OneDayMetrics.spacingS)
            }
            content
        }
        .background(Palette.pageBG)
        .task(id: currentPath) { await load() }
        .alert("新建文件夹", isPresented: $mkdirPresented) {
            TextField("文件夹名", text: $newFolderName)
            Button("取消", role: .cancel) {}
            Button("新建") {
                Task { await createFolder() }
            }
        }
        .confirmationDialog(
            "删除「\(pendingDelete?.name ?? "")」？",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let entry = pendingDelete {
                    Task { await delete(entry) }
                }
                pendingDelete = nil
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("删除后无法恢复。文件夹只能删空的。")
        }
        .sheet(item: $shareItem) { item in
            FileShareSheet(url: item.url)
        }
    }

    @ViewBuilder
    private var content: some View {
        if listing == nil && loadError == nil {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let loadError, listing == nil {
            EmptyState(
                icon: "exclamationmark.triangle",
                title: "读取失败",
                message: loadError
            )
            .padding(.top, OneDayMetrics.spacingXXL)
            Spacer()
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if shownEntries.isEmpty {
                        EmptyState(
                            icon: query.isEmpty
                                ? "folder" : "magnifyingglass",
                            title: query.isEmpty
                                ? "这个文件夹是空的" : "没有匹配的文件",
                            message: query.isEmpty
                                ? "可以上传文件或新建文件夹。"
                                : "换个关键词试试。"
                        )
                        .padding(.top, OneDayMetrics.spacingXXL)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(
                                Array(shownEntries.enumerated()),
                                id: \.element.id
                            ) { index, entry in
                                if index > 0 {
                                    GroupDivider(
                                        inset: OneDayMetrics.dividerInset
                                    )
                                }
                                row(entry)
                            }
                        }
                        .odGroup()
                        .padding(.horizontal, OneDayMetrics.pageGutter)
                    }
                    if let notice {
                        Text(notice)
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                            .padding(.horizontal, OneDayMetrics.pageGutter)
                            .padding(.top, OneDayMetrics.spacingM)
                    }
                }
                .padding(.top, OneDayMetrics.spacingS)
                .padding(.bottom, OneDayMetrics.spacingXL)
            }
        }
    }

    private func breadcrumbBar(listing: FilesListing) -> some View {
        let crumbs = FileBrowserLogic.breadcrumbs(
            root: rootPath, path: listing.path
        )
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: OneDayMetrics.spacingXS) {
                ForEach(Array(crumbs.enumerated()), id: \.element.id) {
                    index, crumb in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.inkMuted)
                            .accessibilityHidden(true)
                    }
                    Button {
                        currentPath = crumb.path
                    } label: {
                        Text(crumb.name)
                            .font(.callout)
                            .foregroundStyle(
                                index == crumbs.count - 1
                                    ? Palette.ink : Palette.primary
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(index == crumbs.count - 1)
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ entry: WorkspaceFileEntry) -> some View {
        if entry.isDirectory {
            Button {
                currentPath = entry.path
            } label: {
                FileBrowserRow(entry: entry)
            }
            .buttonStyle(.odPressable)
            .contextMenu {
                Button(role: .destructive) {
                    pendingDelete = entry
                } label: {
                    Label("删除", systemImage: "trash")
                }
            }
        } else {
            NavigationLink(value: entry) {
                FileBrowserRow(entry: entry)
            }
            .buttonStyle(.odPressable)
            .contextMenu {
                Button {
                    Task { await download(entry) }
                } label: {
                    Label("下载到本地", systemImage: "arrow.down.to.line")
                }
                Button(role: .destructive) {
                    pendingDelete = entry
                } label: {
                    Label("删除", systemImage: "trash")
                }
            }
        }
    }

    private func load() async {
        do {
            let result = try await appState.performAdmin {
                client, config in
                try await client.files(config: config, path: currentPath)
            }
            listing = result
            currentPath = result.path
            loadError = nil
        } catch {
            let message = (error as? HermesError)?.userMessage
                ?? "读取目录失败，请稍后再试。"
            if listing == nil {
                loadError = message
            } else {
                notice = message
            }
        }
    }

    private func createFolder() async {
        guard let directory = listing?.path else { return }
        let name = newFolderName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard FileBrowserLogic.isValidFolderName(newFolderName) else {
            notice = "文件夹名不合法：不能为空，也不能带「/」。"
            return
        }
        do {
            let target = FileBrowserLogic.joinPath(
                directory: directory, name: name
            )
            try await appState.performAdmin { client, config in
                try await client.makeDirectory(
                    config: config, path: target
                )
            }
            await load()
            if listing?.entries.contains(
                where: { $0.path == target && $0.isDirectory }
            ) == true {
                notice = "已新建文件夹「\(name)」。"
                Haptics.success()
            } else {
                notice = "新建请求已发出，但回读未见「\(name)」，请刷新核对。"
            }
        } catch {
            notice = (error as? HermesError)?.userMessage
                ?? "新建文件夹失败，请稍后再试。"
            Haptics.warning()
        }
    }

    private func delete(_ entry: WorkspaceFileEntry) async {
        do {
            try await appState.performAdmin { client, config in
                try await client.deleteFile(
                    config: config, path: entry.path, recursive: false
                )
            }
            await load()
            if listing?.entries.contains(
                where: { $0.path == entry.path }
            ) == true {
                notice = "删除未生效，「\(entry.name)」仍在目录中。"
                Haptics.warning()
            } else {
                notice = "已删除「\(entry.name)」。"
                Haptics.success()
            }
        } catch {
            notice = (error as? HermesError)?.userMessage
                ?? "删除失败，请稍后再试。"
            Haptics.warning()
        }
    }

    private func download(_ entry: WorkspaceFileEntry) async {
        do {
            let data = try await appState.performAdmin {
                client, config in
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

/// 浏览/电脑段共用文件行：图标盒＋名＋大小/时间＋chevron
struct FileBrowserRow: View {
    let entry: WorkspaceFileEntry

    var body: some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            FileIconBox(entry: entry)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.callout)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text(entry.odSubtitle)
                    .font(.caption)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
                    .tabularDigits()
            }
            Spacer(minLength: OneDayMetrics.spacingS)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Palette.inkMuted)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, OneDayMetrics.spacingM)
        .frame(minHeight: 46)
        .contentShape(Rectangle())
    }
}

// MARK: - 影音格

private struct MediaCell: View {
    @Environment(AppState.self) private var appState
    let entry: WorkspaceFileEntry
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Palette.fieldFill
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                VStack(spacing: OneDayMetrics.spacingXS) {
                    Image(systemName: entry.odIconName)
                        .font(.system(size: 22))
                        .foregroundStyle(Palette.inkSecondary)
                    Text(entry.name)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Palette.inkMuted)
                        .lineLimit(1)
                        .padding(.horizontal, OneDayMetrics.spacingXS)
                }
            }
            if entry.mediaKind == .video {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 26))
                    // 媒体面上的纯白符号恒白字面（0.6.1：
                    // onPrimary 已改深字口径、不再借作白字）
                    .foregroundStyle(
                        Color.white, Palette.ink.opacity(0.55)
                    )
                    .accessibilityHidden(true)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipped()
        .contentShape(Rectangle())
        .task(id: entry.path) {
            guard entry.mediaKind == .image else { return }
            // 缩略图走与预览相同的下载通道（客户端带会话 cookie）
            if let data = try? await appState.performAdmin({ client, config in
                try await client.fileData(config: config, path: entry.path)
            }) {
                image = UIImage(data: data)
            }
        }
    }
}

// MARK: - 预览（与 P1 共用组件）

/// 文件预览（0.14.0 预览深化）：图片页内显示、点开走与
/// 聊天同一个全屏查看器（ImageFullScreenView，remotePath
/// 源）；其余类型一律落临时文件走 QuickLook 原生预览
/// （PDF 原生阅读、视频/音频原生播放，设计标准 §5.7/§7）；
/// 撤 0.2.x 的自绘 AVPlayer 与内联文本渲染，不另造预览器。
private struct FilePreviewView: View {
    @Environment(AppState.self) private var appState
    let entry: WorkspaceFileEntry

    @State private var image: UIImage?
    @State private var quickLookItem: ChatFilePreviewItem?
    @State private var loadError: String?
    @State private var shareItem: FileShareItem?
    @State private var rawData: Data?
    @State private var fullScreenImage = false

    var body: some View {
        Group {
            if let image {
                ScrollView {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .padding(OneDayMetrics.spacingM)
                }
                .onTapGesture { fullScreenImage = true }
            } else if let quickLookItem {
                QuickLookPreview(url: quickLookItem.url)
            } else if let loadError {
                EmptyState(
                    icon: "exclamationmark.triangle",
                    title: "预览失败",
                    message: loadError
                )
                .padding(.top, OneDayMetrics.spacingXXL)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Palette.pageBG)
        .navigationTitle(entry.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if let rawData {
                        shareItem = try? FileShareItem.write(
                            data: rawData, name: entry.name
                        )
                    }
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .disabled(rawData == nil)
                .accessibilityLabel("下载到本地")
            }
        }
        .sheet(item: $shareItem) { item in
            FileShareSheet(url: item.url)
        }
        .fullScreenCover(isPresented: $fullScreenImage) {
            ImageFullScreenView(
                item: ChatImageViewerItem(source: .remotePath(entry.path))
            )
        }
        .task { await load() }
    }

    private func load() async {
        do {
            let data = try await appState.performAdmin { client, config in
                try await client.fileData(config: config, path: entry.path)
            }
            rawData = data
            if entry.mediaKind == .image {
                image = UIImage(data: data)
                if image == nil {
                    loadError = "图片数据无法解析。"
                }
            } else {
                quickLookItem = try ChatFilePreviewItem.write(
                    data: data, name: entry.name
                )
            }
        } catch {
            loadError = (error as? HermesError)?.userMessage
                ?? "读取文件失败。"
        }
    }
}

// MARK: - 分享小件

private struct FileShareItem: Identifiable {
    let url: URL
    var id: String { url.path }

    static func write(data: Data, name: String) throws -> FileShareItem {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(name)
        try data.write(to: url)
        return FileShareItem(url: url)
    }
}

private struct FileShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(
        context: Context
    ) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: [url], applicationActivities: nil
        )
    }

    func updateUIViewController(
        _ controller: UIActivityViewController, context: Context
    ) {}
}
