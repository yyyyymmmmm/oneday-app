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
       
...[truncated 33947 chars]