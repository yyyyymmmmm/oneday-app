import OneDayCore
import OneDayDesign
import PhotosUI
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

    /// 系统文件行副题（0.36.31，规格 §七实拍口径）：
    /// 文件夹只给「文件夹」；文件给「类型 · 大小」——
    /// 大小走 ByteCountFormatter.file（小文件「字节」、
    /// 大文件 KB/MB，与实拍同制）；日期不进本行（与
    /// 交付物行的大小·日期口径分工：本面是管理面、
    /// 类型优先）
    var browserSubtitle: String {
        if isDirectory {
            return "文件夹"
        }
        let type = DeliverableFileType.label(forFileName: name)
        let sizeText = size.map {
            ByteCountFormatter.string(
                fromByteCount: $0, countStyle: .file
            )
        }
        return [type, sizeText]
            .compactMap { $0 }.joined(separator: " · ")
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
        .background(Palette.fieldFill, in: RoundedRectangle(cornerRadius: OneDayMetrics.radiusThumb))
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
            RoundedRectangle(cornerRadius: OneDayMetrics.radiusTile)
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

/// 上传执行体（0.36.31 抽单源）：选件/相册两路共用
/// 同一条链——上限拦截→（可选）确保目标目录→同名预
/// 检（命中回 needsOverwrite 待宿主确认）→POST→回读
/// 对账（同名条目 size 与本地字节一致才算落定）。
/// 旧 FileUploadControl（控件自带按钮与确认框）退
/// 役：上传入口按规格 §4.2/§七收进各页 ••• 菜单，
/// 控件形态不再适配宿主。
enum FileUploadPerformer {
    enum Outcome {
        case finished(message: String, confirmed: Bool)
        case needsOverwrite(name: String, data: Data)
    }

    static func fetchListing(
        appState: AppState, path: String
    ) async throws -> FilesListing {
        try await appState.performAdmin { client, config in
            try await client.files(config: config, path: path)
        }
    }

    /// 备料段：上限→保目录→同名预检；可直传则继续走
    /// upload(...)，同名则回 needsOverwrite 由宿主弹
    /// 确认后续传
    static func prepare(
        appState: AppState, name: String, data: Data,
        targetDirectory: String, ensureDirectory: Bool
    ) async -> Outcome {
        guard FileBrowserLogic.isUploadSizeAllowed(
            byteCount: data.count
        ) else {
            return .finished(
                message: "「\(name)」超过 25MB，暂不能从 App 上传。",
                confirmed: false
            )
        }
        if ensureDirectory,
           (try? await fetchListing(
               appState: appState, path: targetDirectory
           )) == nil {
            try? await appState.performAdmin { client, config in
                try await client.makeDirectory(
                    config: config, path: targetDirectory
                )
            }
        }
        if let listing = try? await fetchListing(
               appState: appState, path: targetDirectory
           ),
           listing.entries.contains(
               where: { !$0.isDirectory && $0.name == name }
           ) {
            return .needsOverwrite(name: name, data: data)
        }
        return await upload(
            appState: appState, name: name, data: data,
            targetDirectory: targetDirectory
        )
    }

    static func upload(
        appState: AppState, name: String, data: Data,
        targetDirectory: String
    ) async -> Outcome {
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
            if let listing = try? await fetchListing(
                   appState: appState, path: targetDirectory
               ),
               let entry = listing.entries.first(
                   where: { $0.name == name && !$0.isDirectory }
               ),
               entry.size == Int64(data.count) {
                Haptics.success()
                return .finished(
                    message: "已上传「\(name)」并在服务端确认。",
                    confirmed: true
                )
            }
            return .finished(
                message: "上传已发出，但没确认服务器上有了「\(name)」，请刷新核对。",
                confirmed: false
            )
        } catch {
            // 失败改判 error（0.36.2，表 D 语义归位）
            Haptics.error()
            return .finished(
                message: (error as? HermesError)?.userMessage
                    ?? "上传失败，请稍后再试。",
                confirmed: false
            )
        }
    }
}

/// 上传选件修饰器（0.36.31）：fileImporter＋同名覆盖
/// 确认框的宿主无关封装——文件页（菜单组4）与系统
/// 文件页（••• 菜单）共用，确认口径与旧控件一致
struct FileUploadPickerModifier: ViewModifier {
    /// appState 由宿主显式传入（不在 Modifier 里取环
    /// 境值——取值路径稳、宿主两处都现成持有）
    let appState: AppState
    @Binding var isPresented: Bool
    let targetDirectory: String
    var ensureDirectory: Bool = false
    /// (结果文案, 是否已回读确认落盘）
    let onFinished: (String, Bool) -> Void

    @State private var pendingOverwrite: PendingUpload?

    private struct PendingUpload {
        let name: String
        let data: Data
    }

    func body(content: Content) -> some View {
        content
            .fileImporter(
                isPresented: $isPresented,
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
                            let outcome = await FileUploadPerformer
                                .upload(
                                    appState: appState,
                                    name: pending.name,
                                    data: pending.data,
                                    targetDirectory: targetDirectory
                                )
                            if case .finished(
                                let message, let confirmed
                            ) = outcome {
                                onFinished(message, confirmed)
                            }
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
        let outcome = await FileUploadPerformer.prepare(
            appState: appState, name: name, data: data,
            targetDirectory: targetDirectory,
            ensureDirectory: ensureDirectory
        )
        switch outcome {
        case .finished(let message, let confirmed):
            onFinished(message, confirmed)
        case .needsOverwrite(let name, let data):
            pendingOverwrite = PendingUpload(name: name, data: data)
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
    /// 排序方向（0.36.31，规格 §七排序行）：默认名称升序
    @State private var sortAscending = true
    @State private var query = ""
    @State private var notice: String?
    @State private var pendingDelete: WorkspaceFileEntry?
    @State private var shareItem: FileShareItem?
    @State private var mkdirPresented = false
    @State private var newFolderName = ""
    /// 上传两路（0.36.31，规格 §七：••• 只放上传两项）
    @State private var uploadPickerPresented = false
    @State private var photosPickerPresented = false
    @State private var photosPickerItem: PhotosPickerItem?
    @State private var pendingPhotoUpload: PendingPhotoUpload?

    private struct PendingPhotoUpload {
        let name: String
        let data: Data
    }

    /// 图片查看器 zoom 转场命名空间（0.36.4）
    @Namespace private var browserViewerNamespace

    private var rootPath: String {
        listing?.lockedRoot ?? listing?.root ?? "/opt/data"
    }

    private var shownEntries: [WorkspaceFileEntry] {
        guard let listing else { return [] }
        return FileBrowserLogic.sorted(
            FileBrowserLogic.filtered(listing.entries, query: query),
            by: sortKey, ascending: sortAscending
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let listing {
                breadcrumbBar(listing: listing)
                    .padding(.horizontal, OneDayMetrics.pageGutter)
                sortRow
                FileSearchField(query: $query)
                    .padding(.horizontal, OneDayMetrics.pageGutter)
                    .padding(.bottom, OneDayMetrics.spacingS)
            }
            content
        }
        .background(Palette.pageBG)
        // 页头右 •••（§七三件套）：只放上传两项——上
        // 传文件／从相机胶卷上传（上传进当前目录）；
        // 目录未定位前禁用（无当前目录可言）
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        uploadPickerPresented = true
                    } label: {
                        Label("上传文件", systemImage: "arrow.up.doc")
                    }
                    Button {
                        photosPickerPresented = true
                    } label: {
                        Label(
                            "从相机胶卷上传",
                            systemImage: "photo.on.rectangle.angled"
                        )
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .disabled(listing == nil)
                .accessibilityLabel("更多操作")
            }
        }
        .modifier(
            FileUploadPickerModifier(
                appState: appState,
                isPresented: $uploadPickerPresented,
                targetDirectory: listing?.path ?? "/opt/data"
            ) { message, _ in
                notice = message
                Task { await load() }
            }
        )
        .photosPicker(
            isPresented: $photosPickerPresented,
            selection: $photosPickerItem,
            matching: .images
        )
        .onChange(of: photosPickerItem) { _, item in
            guard let item else { return }
            photosPickerItem = nil
            Task { await handlePhotoPick(item) }
        }
        .confirmationDialog(
            "已存在同名文件「\(pendingPhotoUpload?.name ?? "")」，覆盖它？",
            isPresented: Binding(
                get: { pendingPhotoUpload != nil },
                set: { if !$0 { pendingPhotoUpload = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("覆盖上传") {
                if let pending = pendingPhotoUpload,
                   let directory = listing?.path {
                    pendingPhotoUpload = nil
                    Task {
                        let outcome = await FileUploadPerformer
                            .upload(
                                appState: appState,
                                name: pending.name,
                                data: pending.data,
                                targetDirectory: directory
                            )
                        if case .finished(let message, _) = outcome {
                            notice = message
                        }
                        await load()
                    }
                }
            }
            Button("取消", role: .cancel) {
                pendingPhotoUpload = nil
                notice = "已取消上传。"
            }
        } message: {
            Text("覆盖后原文件无法恢复。")
        }
        .task(id: currentPath) { await load() }
        // 行目的地（0.36.4 补注册）：此前全仓无 Work-
        // spaceFileEntry 目的地注册、行点按无落点；
        // 图片直达查看器（zoom 转场、集合＝当前列表
        // 全部图片），其余走 FilePreviewView（Quick-
        // Look）
        .navigationDestination(for: WorkspaceFileEntry.self) { entry in
            if entry.mediaKind == .image {
                let images = shownEntries.filter {
                    $0.mediaKind == .image
                }
                ImageViewerView(
                    items: images.map {
                        ChatImageViewerItem(
                            source: .remotePath($0.path)
                        )
                    },
                    initialIndex: images.firstIndex(of: entry) ?? 0,
                    onDeleteItem: { item in
                        if case .remotePath(let path) = item.source,
                           let target = images.first(
                               where: { $0.path == path }
                           ) {
                            Task { await deleteFromViewer(target) }
                        }
                    }
                )
                .navigationTransition(
                    .zoom(
                        sourceID: entry.path,
                        in: browserViewerNamespace
                    )
                )
            } else {
                FilePreviewView(entry: entry)
            }
        }
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

    /// 排序行（0.36.31，规格 §七）：左＝当前排序键菜
    /// 单（名称／修改时间／大小，当前项对号），右端
    /// ＝方向钮（升 ↑／降 ↓ 点按切换，文件夹恒在前、
    /// 方向只翻组内序，Core 钉测）；新建文件夹钮同
    /// 行右侧——§4.6 既有能力保留，••• 纯度（只放
    /// 上传两项）优先于把它也塞进菜单，此安放为本版
    /// 取舍、已在 §99 记账
    private var sortRow: some View {
        HStack(spacing: OneDayMetrics.spacingM) {
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
                Text(sortKey.label)
                    .font(.callout)
                    .foregroundStyle(Palette.ink)
            }
            .accessibilityLabel("排序方式，当前按\(sortKey.label)")
            Spacer()
            Button {
                newFolderName = ""
                mkdirPresented = true
            } label: {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 17))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.odPressable)
            .accessibilityLabel("新建文件夹")
            Button {
                sortAscending.toggle()
            } label: {
                Image(
                    systemName: sortAscending
                        ? "arrow.up" : "arrow.down"
                )
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.odPressable)
            .accessibilityLabel(
                sortAscending
                    ? "当前升序，点按切换为降序"
                    : "当前降序，点按切换为升序"
            )
        }
        .padding(.horizontal, OneDayMetrics.pageGutter)
        .padding(.vertical, OneDayMetrics.spacingXS)
    }

    /// 相册上传（§七第二项）：取照片字节→时间戳命名
    /// →与文件上传同一条备料链（上限/同名预检/对账）
    private func handlePhotoPick(_ item: PhotosPickerItem) async {
        guard let directory = listing?.path else { return }
        guard let data = try? await item.loadTransferable(
            type: Data.self
        ) else {
            notice = "读取所选照片失败。"
            return
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let name = "照片-\(formatter.string(from: Date())).jpg"
        let outcome = await FileUploadPerformer.prepare(
            appState: appState, name: name, data: data,
            targetDirectory: directory, ensureDirectory: false
        )
        switch outcome {
        case .finished(let message, _):
            notice = message
            await load()
        case .needsOverwrite(let name, let data):
            pendingPhotoUpload = PendingPhotoUpload(
                name: name, data: data
            )
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
        if !entry.isDirectory,
           SensitiveFilePolicy.isSensitive(fileName: entry.name) {
            // 敏感文件锁定行（0.36.31，规格 §4.6 安全
            // 边界）：行可见、行尾锁标记，无导航、无菜
            // 单，点按只给一句说明——凭据文件不经本面
            // 预览/下载/删除（现行可下 auth.json 的外带
            // 缺口在本版堵死；删除同理收回，连长按也不给）
            Button {
                notice = SensitiveFilePolicy.explanation
            } label: {
                FileBrowserRow(entry: entry)
            }
            .buttonStyle(.odPressable)
        } else if entry.isDirectory {
            Button {
                currentPath = entry.path
            } label: {
                FileBrowserRow(entry: entry)
            }
            .buttonStyle(.odPressable)
            .contextMenu {
                // 敏感命名的目录同样不给删除（§4.6 名单
                // 对目录只收删除一项，导航照常——目录里
                // 可能有正常文件，逐行再判）
                if !SensitiveFilePolicy.isSensitive(
                    fileName: entry.name
                ) {
                    Button(role: .destructive) {
                        pendingDelete = entry
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
            }
        } else {
            NavigationLink(value: entry) {
                FileBrowserRow(entry: entry)
                    // zoom 转场源标记（0.36.4）：图片行
                    // 点开自本行长成查看器卡
                    .matchedTransitionSource(
                        id: entry.path, in: browserViewerNamespace
                    )
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

    /// 查看器内删除（0.36.4）：与行删除同通道（删＋
    /// 重拉＋回读核对）；落锤已由查看器发过、成功不
    /// 叠，未生效/失败按既有口径回告
    private func deleteFromViewer(_ entry: WorkspaceFileEntry) async {
        do {
            try await appState.performAdmin { client, config in
                try await client.deleteFile(
                    config: config, path: entry.path,
                    recursive: false
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
            }
        } catch {
            notice = (error as? HermesError)?.userMessage
                ?? "删除失败，请稍后再试。"
            Haptics.error()
        }
    }
}

/// 浏览/电脑段共用文件行：图标盒＋名＋副题＋行尾标
/// 记。副题 0.36.31 改 §七口径（browserSubtitle：
/// 文件夹／类型 · 大小）；敏感文件行尾换锁标记、
/// 无 chevron（不可进、点按只给说明，宿主处理）
struct FileBrowserRow: View {
    let entry: WorkspaceFileEntry

    private var isLocked: Bool {
        !entry.isDirectory
            && SensitiveFilePolicy.isSensitive(fileName: entry.name)
    }

    var body: some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            FileIconBox(entry: entry)
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                Text(entry.name)
                    .font(.callout)
                    .foregroundStyle(Palette.ink)
                    // 0.43.0（A11Y-D3）：AX 档放宽行数
                    .a11yLineLimit(1, ax: 2)
                Text(entry.browserSubtitle)
                    .font(.caption)
                    .foregroundStyle(Palette.inkSecondary)
                    .a11yLineLimit(1, ax: 2)
                    .tabularDigits()
            }
            Spacer(minLength: OneDayMetrics.spacingS)
            if isLocked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Palette.inkMuted)
                    .accessibilityLabel("受保护文件")
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Palette.inkMuted)
                    .accessibilityHidden(true)
            }
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
        // 定尺落在形状层（0.36.24，P-13 续）：旧形态把
        // .aspectRatio(1,.fit) 挂在 ZStack 本体上——.fit
        // 在未指定维度（网格只提议列宽、高度未指定）
        // 取子视图理想尺寸定案，ZStack 的理想尺寸被图
        // 片原尺寸/占位图标带着走：未加载、视频、音频
        // 与小图格的高度各行其是、参差不齐（用户
        // 03:10 对照 Muse 定尺网格点题）。改法：无内
        // 在尺寸的 Rectangle 承担 1:1 定尺（宽随列宽、
        // 高等宽），内容只作 overlay 填充裁切、永不参
        // 与定尺寸——哪一格都同宽同高
        Rectangle()
            .fill(Palette.fieldFill)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                ZStack {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        // 占位只留类型图标（0.36.4）：旧
                        // 占位把原始文件名压在格下——生
                        // 成图名多为哈希串、属面向用户的
                        // 原始名漏出，本版撤除
                        Image(systemName: entry.odIconName)
                            .font(.system(size: 22))
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    if entry.mediaKind == .video {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 26))
                            // 媒体面上的纯白符号恒白字面
                            // （0.6.1：onPrimary 已改深字
                            // 口径、不再借作白字）
                            .foregroundStyle(
                                Color.white, Palette.ink.opacity(0.55)
                            )
                            .accessibilityHidden(true)
                    }
                }
            }
            .clipped()
        .contentShape(Rectangle())
        .task(id: entry.path) {
            guard entry.mediaKind == .image else { return }
            // 缩略图 0.36.31 改走 FileThumbnailStore：
            // ImageIO 降采样解码（360px）＋双缓存＋并
            // 发闸——旧形态 UIImage(data:) 全尺寸解码
            // 大图整段入内存，规格 §4.3 明令禁止
            image = await FileThumbnailStore.shared.thumbnail(
                for: entry, targetPixelSize: 360
            ) {
                try? await appState.performAdmin {
                    client, config in
                    try await client.fileData(
                        config: config, path: entry.path
                    )
                }
            }
        }
    }
}

// MARK: - 预览（与 P1 共用组件）

/// 文件预览：非图文件落临时文件走 QuickLook 原生
/// 预览（PDF 原生阅读、视频/音频原生播放，设计标
/// 准 §5.7/§7）；撤 0.2.x 的自绘 AVPlayer 与内联文
/// 本渲染，不另造预览器。
/// 0.36.4：图片分支整支退役——旧形态先进本页（图
/// 小上置＋标题露原始文件名，哈希名实证漏出）再点
/// 才进全屏查看器，两段式断链；本版图片由各宿主
/// 直达 ImageViewerView，本视图只作防御落点（万一
/// 有旧路径把图片送进来，同样直达查看器、不复活
/// 中间页）。
struct FilePreviewView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let entry: WorkspaceFileEntry

    @State private var quickLookItem: ChatFilePreviewItem?
    @State private var loadError: String?
    @State private var shareItem: FileShareItem?
    @State private var rawData: Data?
    @State private var notice: String?

    private var isSensitive: Bool {
        !entry.isDirectory
            && SensitiveFilePolicy.isSensitive(fileName: entry.name)
    }

    var body: some View {
        if isSensitive {
            // 敏感防御（0.36.31，规格 §4.6）：即便有旧
            // 路径把凭据文件送进预览面，也不加载不渲染
            // ——只给说明，动作只给「知道了」（失败页动
            // 作表对敏感类同此收敛）
            ContentUnavailableView {
                Label("无法预览", systemImage: "lock.fill")
            } description: {
                Text(SensitiveFilePolicy.explanation)
            } actions: {
                Button("知道了") { dismiss() }
            }
            .background(Palette.pageBG)
            .navigationTitle(entry.name)
            .navigationBarTitleDisplayMode(.inline)
        } else if entry.mediaKind == .image {
            ImageViewerView(
                items: [
                    ChatImageViewerItem(source: .remotePath(entry.path))
                ],
                initialIndex: 0
            )
        } else {
            quickLookBody
        }
    }

    private var quickLookBody: some View {
        Group {
            if let quickLookItem {
                QuickLookPreview(url: quickLookItem.url)
            } else if let loadError {
                failureView(loadError)
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
                // 工具栏按类型出项（0.36.31 附记硬规
                // 矩）：旧形态只有一个下载钮——文本/PDF
                // 类现给复制文字（＋文本类的导出 PDF 在
                // 阅读页/条目菜单面，预览面动作表同源
                // readingActions），与阅读页同一策略表
                Menu {
                    ForEach(
                        FileActionPolicy.readingActions(for: entry),
                        id: \.self
                    ) { action in
                        Button {
                            perform(action)
                        } label: {
                            Label(
                                action.label,
                                systemImage: action.systemImage
                            )
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .disabled(rawData == nil)
                .accessibilityLabel("文件操作")
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let notice {
                Text(notice)
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                    .padding(.horizontal, OneDayMetrics.pageGutter)
                    .padding(.vertical, OneDayMetrics.spacingS)
            }
        }
        .sheet(item: $shareItem) { item in
            FileShareSheet(url: item.url)
        }
        .task { await load() }
    }

    /// 失败页按类型给动作（附记硬规矩）：可渲染类给
    /// 重试＋下载（取原文件走分享单，QuickLook 写临
    /// 时文件失败时此路常仍可通），不可渲染类只给下
    /// 载＋知道了
    private func failureView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("预览失败", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            ForEach(
                FileActionPolicy.failureActions(for: entry),
                id: \.self
            ) { action in
                Button(action.label) {
                    performFailure(action)
                }
            }
        }
    }

    private func performFailure(_ action: FileFailureAction) {
        switch action {
        case .retry:
            Task { await load() }
        case .download:
            Task { await shareOriginal() }
        case .dismiss:
            dismiss()
        }
    }

    private func perform(_ action: FileItemAction) {
        switch action {
        case .copyText:
            guard let rawData,
                  let text = FileTextExtractor.plainText(
                      from: rawData, entry: entry
                  )
            else {
                notice = "这个文件没能读出文字。"
                return
            }
            UIPasteboard.general.string = text
            notice = "已复制全文。"
            Haptics.success()
        case .exportPDF:
            exportPDF()
        case .share, .download:
            Task { await shareOriginal() }
        case .preview, .delete:
            // 预览面策略表不给这两项，同阅读页口径：
            // 落到这里即策略表漂移，靠单测钉表本身
            break
        }
    }

    private func exportPDF() {
        guard let rawData,
              let text = FileTextExtractor.plainText(
                  from: rawData, entry: entry
              )
        else {
            notice = "这个文件没能读出文字，无法导出 PDF。"
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
            blocks: DocumentReading.blocks(for: text, kind: kind)
        ) else {
            notice = "导出 PDF 失败，请稍后再试。"
            return
        }
        shareItem = try? FileShareItem.write(
            data: pdf, name: "\(title).pdf"
        )
    }

    private func shareOriginal() async {
        if let rawData {
            shareItem = try? FileShareItem.write(
                data: rawData, name: entry.name
            )
            return
        }
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

    private func load() async {
        loadError = nil
        do {
            let data = try await appState.performAdmin { client, config in
                try await client.fileData(config: config, path: entry.path)
            }
            rawData = data
            let item = try ChatFilePreviewItem.write(
                data: data, name: entry.name
            )
            // §121 题二 b：QL 资格门——不可预览类型
            // （.ipa 等）不写 QL 件硬呈死页，直接落
            // 失败页＋五分文案，动作仍走 failure-
            // Actions 按类出项（.other/.archive＝下
            // 载＋知道了）；取数失败同样走五分，不再
            // 一句状态码兜底
            if item.canPreview {
                quickLookItem = item
            } else {
                loadError = FileOpenFailure.unsupportedType
                    .message()
            }
        } catch let error as HermesError {
            loadError = FileOpenFailure.classify(
                error: error
            ).message()
        } catch {
            loadError = FileOpenFailure.other.message()
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
