import OneDayCore
import OneDayDesign
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// 文件域共享组件（0.14.0 P8 立、0.20.0 拆分）：原
/// FilesView 四段壳（影音/交付物/浏览/电脑）随应用
/// 格退役拆解——交付物＋影音升底栏文件格（Deliver-
/// ablesView.swift 独立成页）、浏览段迁设置「管理」
/// 组服务器文件、电脑段归 ComputerView；本文件只留
/// 各面共用的呈现与动作组件（条目扩展/搜索/图标盒/
/// 上传/浏览器/媒体格/预览/分享），访问级由 private
/// 升 internal 供两处宿主共用。

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

struct FileSearchField: View {
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
                .buttonStyle(.odPressable)
                .accessibilityLabel("清空搜索")
            }
        }
        .padding(.horizontal, OneDayMetrics.spacingM)
        .padding(.vertical, OneDayMetrics.spacingS)
        .background(Palette.fieldFill, in: RoundedRectangle(cornerRadius: 10))
    }
}

/// 类型图标盒 v2（0.22.0，视觉审计 F2 图标规格）：
/// 字形与底色改由 Core 的 DeliverableIconStyle 表驱
/// 动——办公三件白色粗体单字（W/P/X＋品牌色）、PDF
/// 红、媒体各有身份色，与 Muse 资源库的类型真图标
/// 对位；0.20.0 的「SF 通用字形＋pastel 类别轮换」
/// （颜色不表类型）退役，pastel 只留枢纽等装饰面。
/// 盒 36pt、圆角 9（行高口径：交付物行 64、浏览器
/// 行 46 均可容纳）。图片在影音段另有 MediaCell 真
/// 缩略图面，本盒只给回落字形（规格表 photo.fill）
struct FileIconBox: View {
    let entry: WorkspaceFileEntry

    var body: some View {
        let style = DeliverableIconStyle.style(
            forFileName: entry.name, isDirectory: entry.isDirectory
        )
        ZStack {
            RoundedRectangle(cornerRadius: 9)
                .fill(Color(hexRGB: style.backgroundHex))
            switch style.glyph {
            case .letter(let letter):
                Text(letter)
                    // 图标字形非阅读文字，固定字号合法
                    // （审计图标规格：17 bold 白）
                    // 0.23.0：数值改引用 FrameworkIcon
                    // .fileGlyphSize 单源（17 不变，审计 G3）
                    .font(.system(
                        size: FrameworkIcon.fileGlyphSize,
                        weight: .bold
                    ))
                    .foregroundStyle(Color.white)
            case .symbol(let name):
                Image(systemName: name)
                    .font(.system(size: 16))
                    .foregroundStyle(Color.white)
            }
        }
        .frame(width: 36, height: 36)
        .accessibilityHidden(true)
    }
}

extension Color {
    /// RRGGBB hex 字面量 → Color（DeliverableIconStyle
    /// 的身份底色落色用；非法输入回落中性灰，不崩）
    init(hexRGB hex: String) {
        let value = UInt32(hex, radix: 16) ?? 0x949B9F
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

/// 上传控件（交付物段与浏览段共用）：选件→读字节→上限
/// 拦截→（可选）确保目标目录→同名预检确认→POST→回读
/// 对账（同名条目 size 与本地字节一致才算落定）。
struct FileUploadControl: View {
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
                    "上传已发出，但没确认服务器上有了「\(name)」，请刷新核对。",
                    false
                )
            }
        } catch {
            // 失败改判 error（0.36.2，表 D 语义归位）
            Haptics.error()
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
struct FilesBrowserView: View {
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
                // 触感矩阵（规格 §2.3）：删除确认
                // 落锤＝impact heavy；删除成功后不
                // 再叠 success（同一因果链只震一次）
                Haptics.impact(.heavy)
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
                    .buttonStyle(.odPressable)
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
                notice = "新建请求已发出，但再确认时没见到「\(name)」，请刷新核对。"
            }
        } catch {
            notice = (error as? HermesError)?.userMessage
                ?? "新建文件夹失败，请稍后再试。"
            // 失败改判 error（0.36.2，表 D 语义归位）
            Haptics.error()
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
                // 保留 warning 本义：请求已发、结果
                // 未确认——需注意未失败（规格 §2.3）
                Haptics.warning()
            } else {
                notice = "已删除「\(entry.name)」。"
                // 成功无触感：确认时的 heavy 落锤已
                // 代表本链（同一因果链只震一次）
            }
        } catch {
            notice = (error as? HermesError)?.userMessage
                ?? "删除失败，请稍后再试。"
            // 失败改判 error（0.36.2，表 D 语义归位）
            Haptics.error()
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

struct MediaCell: View {
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
                        .foregroundStyle(Palette.inkSecondary)
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
struct FilePreviewView: View {
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

struct FileShareItem: Identifiable {
    let url: URL
    var id: String { url.path }

    static func write(data: Data, name: String) throws -> FileShareItem {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(name)
        try data.write(to: url)
        return FileShareItem(url: url)
    }
}

struct FileShareSheet: UIViewControllerRepresentable {
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
