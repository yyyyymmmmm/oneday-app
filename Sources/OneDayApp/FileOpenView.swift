import OneDayCore
import OneDayDesign
import SwiftUI
import UIKit

/// 文件来源行口径（§125 文件头）：人话来源只两档——
/// 聊天点开是「来自这条对话」，文件页点开是「服务器
/// 上的文件」；原始路径只进低频详情，不上文件头
enum FileOpenOrigin {
    case conversation
    case serverFile

    var line: String {
        switch self {
        case .conversation: return L10n.string("来自这条对话")
        case .serverFile: return L10n.string("服务器上的文件")
        }
    }
}

/// 文件打开页（§125 中间页，sheet 形态）：微信/Muse
/// 式两段式打开的第一段——先落一页看清这是什么文件、
/// 再决定怎么打开，取代旧「点牌直达 QuickLook/分享
/// 单」。单源共建：聊天文件牌与文件页条目都构造本页
/// （FileOpenContent），旧 FilePreviewView 收编退役。
/// 路由走 Core FileOpenRoute 纯函数表、动作走
/// FileActionPolicy 落点列＋readingActions、失败走
/// FileOpenFailure 五分——三单源不另立第二套。
struct FileOpenView: View {
    let target: FileOpenTarget
    var origin: FileOpenOrigin = .serverFile
    /// §129：404 时「让智能体重新发」的宿主落点
    /// （聊天来源由 ChatView 注入：预填落当前线程
    /// 输入舱）；不注入时 FileOpenContent 走新建
    /// 对话同制（文件页/资料库来源）
    var onRequestResend: ((String) -> Void)? = nil

    var body: some View {
        NavigationStack {
            FileOpenContent(
                target: target, origin: origin,
                showsCloseButton: true,
                onRequestResend: onRequestResend
            )
        }
    }
}

struct FileOpenContent: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    /// 当前呈现目标（§131）：构造时以入参为种子，改
    /// 名成功后切到新名新路径的新目标——页内一切呈
    /// 现与动作都读 target 计算属性，只换此一处
    @State private var currentTarget: FileOpenTarget
    private var target: FileOpenTarget { currentTarget }
    var origin: FileOpenOrigin = .serverFile
    var showsCloseButton: Bool = false
    var onRequestResend: ((String) -> Void)? = nil

    init(
        target: FileOpenTarget,
        origin: FileOpenOrigin = .serverFile,
        showsCloseButton: Bool = false,
        onRequestResend: ((String) -> Void)? = nil
    ) {
        _currentTarget = State(initialValue: target)
        self.origin = origin
        self.showsCloseButton = showsCloseButton
        self.onRequestResend = onRequestResend
    }

    private enum Phase: Equatable {
        case ready
        case downloading
        case failed(FileOpenFailure)
    }

    private enum Destination: Hashable {
        case reader
        case quickLook
        case spreadsheet
    }

    @State private var phase: Phase = .ready
    @State private var destination: Destination?
    @State private var previewItem: ChatFilePreviewItem?
    @State private var downloadedData: Data?
    @State private var shareItem: FileShareItem?
    @State private var notice: String?
    @State private var showDetails = false
    @State private var metaDone = false
    @State private var downloadTask: Task<Void, Never>?
    /// 改名表单（§131）：草稿＋待确认新名（扩展名变
    /// 更时先过确认框，确认后才执行组合链）
    @State private var renamePresented = false
    @State private var renameDraft = ""
    @State private var pendingRenameName: String?

    private var store: FileMetadataStore { .shared }
    private var pinStore: FilePinStore { .shared }
    private var entry: WorkspaceFileEntry { target.workspaceEntry }
    private var route: FileOpenRoute {
        FileOpenRoute.resolve(target: target)
    }

    private var resolvedSize: Int64? {
        target.size ?? store.metadata(for: target.path)?.size
    }

    private var resolvedModified: Date? {
        target.modifiedAt
            ?? store.metadata(for: target.path)?.modifiedAt
    }

    /// 元信息未回且目标自带无大小时主钮禁用（规格五
    /// 态之一：加载中骨架＋主钮禁用）；回读失败也算
    /// 一轮已回——不许无限禁用
    private var metaPending: Bool {
        target.size == nil
            && store.metadata(for: target.path)?.size == nil
            && !metaDone
    }

    private var subtitle: String {
        let type = DeliverableFileType.label(forFileName: target.name)
        let sizeText = resolvedSize.map {
            ByteCountFormatter.string(
                fromByteCount: $0, countStyle: .file
            )
        }
        return [type, sizeText]
            .compactMap { $0 }.joined(separator: " · ")
    }

    private var landingPrimary: FileLandingAction? {
        FileActionPolicy.landingPrimary(for: entry)
    }

    private var secondaryActions: [FileItemAction] {
        FileActionPolicy.readingActions(for: entry)
    }

    /// 顶栏菜单动作集（§131，D8）：打开页全集——置
    /// 顶态＋类型专属＋分享/下载＋重命名＋回指文件
    /// 页（openPageActions 单源）；页内动作列仍走
    /// readingActions 快捷子集，两处不另立第二套表
    private var menuActions: [FileItemAction] {
        FileActionPolicy.openPageActions(
            for: entry, isPinned: pinStore.isPinned(path: target.path)
        )
    }

    var body: some View {
        Group {
            switch route {
            case .locked:
                lockedView
            case .imageViewer:
                // 防御落点：宿主（聊天/文件页）对图片恒
                // 直达查看器，落到这里仍给真查看器、
                // 不给空白页
                ImageViewerView(
                    items: [
                        ChatImageViewerItem(
                            source: .remotePath(target.path)
                        ),
                    ],
                    initialIndex: 0
                )
            default:
                mainBody
            }
        }
        .background(Palette.pageBG)
        .navigationTitle(target.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsCloseButton {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("关闭")
                }
            }
            if route != .locked {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(menuActions, id: \.self) { action in
                            Button {
                                performMenu(action)
                            } label: {
                                Label(
                                    action.label,
                                    systemImage: action.systemImage
                                )
                            }
                        }
                        if !menuActions.isEmpty {
                            Divider()
                        }
                        Button {
                            showDetails = true
                        } label: {
                            Label(
                                "详情", systemImage: "info.circle"
                            )
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("更多操作")
                }
            }
        }
        .navigationDestination(item: $destination) { dest in
            switch dest {
            case .reader:
                DocumentReaderView(entry: entry, anchor: target.anchor)
            case .quickLook:
                if let previewItem {
                    QuickLookHostView(
                        entry: entry, url: previewItem.url,
                        data: downloadedData
                    )
                }
            case .spreadsheet:
                SpreadsheetReaderView(target: target)
            }
        }
        .sheet(item: $shareItem) { item in
            FileShareSheet(url: item.url)
        }
        .sheet(isPresented: $showDetails) {
            FileOpenDetailsView(
                target: target, size: resolvedSize,
                modifiedAt: resolvedModified
            )
        }
        .alert("重命名", isPresented: $renamePresented) {
            TextField("文件名", text: $renameDraft)
            Button("取消", role: .cancel) {}
            Button("保存") { requestRename() }
        } message: {
            Text("只改名字，文件还在原来的文件夹。")
        }
        .confirmationDialog(
            "扩展名变了",
            isPresented: Binding(
                get: { pendingRenameName != nil },
                set: { if !$0 { pendingRenameName = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("继续改名") {
                if let name = pendingRenameName {
                    pendingRenameName = nil
                    Task { await performRename(to: name) }
                }
            }
            Button("取消", role: .cancel) { pendingRenameName = nil }
        } message: {
            Text("新名字的扩展名和原来不一样，文件类型会跟着变。确定要改吗？")
        }
        .task {
            if target.size == nil {
                await store.ensureSize(
                    path: target.path, appState: appState
                )
            }
            metaDone = true
        }
    }

    // MARK: - 页面构成

    private var mainBody: some View {
        ScrollView {
            VStack(
                alignment: .leading, spacing: OneDayMetrics.spacingL
            ) {
                header
                actionZone
                if let notice {
                    Text(notice)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(OneDayMetrics.pageGutter)
        }
    }

    private var header: some View {
        HStack(
            alignment: .top, spacing: OneDayMetrics.spacingSM
        ) {
            FileIconBox(name: target.name, size: 56)
            VStack(
                alignment: .leading, spacing: OneDayMetrics.spacingXS
            ) {
                Text(target.name)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(3)
                if metaPending {
                    HStack(spacing: OneDayMetrics.spacingXS) {
                        ProgressView()
                            .controlSize(.mini)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                } else {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Palette.inkSecondary)
                }
                Text(origin.line)
                    .font(.caption)
                    .foregroundStyle(Palette.inkSecondary)
                if let resolvedModified {
                    Text(
                        L10n.format(
                            "修改于 %@", AdminFormat.short(resolvedModified)
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(Palette.inkSecondary)
                }
            }
        }
    }

    @ViewBuilder
    private var actionZone: some View {
        switch phase {
        case .downloading:
            downloadingView
        case .failed(let failure):
            failureView(failure)
        case .ready:
            VStack(
                alignment: .leading, spacing: OneDayMetrics.spacingM
            ) {
                if route == .infoOnly {
                    Text("这类文件不能在 App 内预览，可以下载到本地或分享到其他 App 打开。")
                        .font(.callout)
                        .foregroundStyle(Palette.inkSecondary)
                } else if let landingPrimary {
                    Button {
                        runPrimary(landingPrimary)
                    } label: {
                        Label(
                            landingPrimary.label,
                            systemImage: landingPrimary.systemImage
                        )
                    }
                    .buttonStyle(.odPrimary)
                    .disabled(metaPending)
                }
                if !secondaryActions.isEmpty {
                    secondaryList
                }
            }
        }
    }

    private var secondaryList: some View {
        VStack(spacing: 0) {
            ForEach(
                Array(secondaryActions.enumerated()), id: \.element
            ) { index, action in
                if index > 0 { GroupDivider() }
                Button {
                    performSecondary(action)
                } label: {
                    HStack {
                        Label(
                            action.label,
                            systemImage: action.systemImage
                        )
                        .font(.callout)
                        .foregroundStyle(Palette.ink)
                        Spacer(minLength: 0)
                    }
                    .frame(
                        minHeight: OneDayMetrics.rowHeight,
                        alignment: .leading
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.odPressable)
            }
        }
    }

    private var downloadingView: some View {
        VStack(spacing: OneDayMetrics.spacingSM) {
            HStack(spacing: OneDayMetrics.spacingSM) {
                ProgressView()
                VStack(
                    alignment: .leading, spacing: OneDayMetrics.spacingXS
                ) {
                    Text("正在下载…")
                        .font(.callout)
                        .foregroundStyle(Palette.ink)
                    if let resolvedSize {
                        Text(
                            L10n.format(
                                "共 %@",
                                ByteCountFormatter.string(
                                    fromByteCount: resolvedSize,
                                    countStyle: .file
                                )
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(Palette.inkSecondary)
                    }
                }
                Spacer(minLength: 0)
            }
            Button("取消") {
                downloadTask?.cancel()
                phase = .ready
            }
            .buttonStyle(.odSecondary)
        }
    }

    private func failureView(_ failure: FileOpenFailure) -> some View {
        VStack(spacing: OneDayMetrics.spacingSM) {
            HStack(
                alignment: .top, spacing: OneDayMetrics.spacingSM
            ) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(Palette.warning)
                Text(failure.message())
                    .font(.callout)
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: 0)
            }
            HStack(spacing: OneDayMetrics.spacingSM) {
                ForEach(
                    failureActions(for: failure), id: \.self
                ) { action in
                    Button(action.label) {
                        performFailure(action)
                    }
                    .buttonStyle(.odSecondary)
                }
                Spacer(minLength: 0)
            }
            // §129：404 专属回路——文件根本不在服务
            // 器上时，出路是让写它的人重新交付：预
            // 填一条带原路径的草稿回对话（拼装在
            // Core FileResendPrefill，落点见
            // requestResend），不在本页硬撑
            if failure == .notFound {
                Button {
                    requestResend()
                } label: {
                    Label(
                        "让智能体重新发",
                        systemImage: "paperplane"
                    )
                }
                .buttonStyle(.odSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(OneDayMetrics.spacingSM)
        .background(
            Palette.surface,
            in: RoundedRectangle(
                cornerRadius: OneDayMetrics.radiusCard
            )
        )
    }

    /// 失败动作集（§129 对账）：策略表原样打底，
    /// 唯 404 一档收掉「下载到本地」——文件确证不
    /// 在，再下载必然再 404，是死按钮；404 的出路
    /// 是重试与「让智能体重新发」（诊断 §4.1.5）。
    /// 其余失败档（超时/过大/不可预览等）策略表
    /// 不动
    private func failureActions(
        for failure: FileOpenFailure
    ) -> [FileFailureAction] {
        var actions = FileActionPolicy.failureActions(for: entry)
        if failure == .notFound {
            actions.removeAll { $0 == .download }
        }
        return actions
    }

    /// 「让智能体重新发」落点（§129）：宿主注入了
    /// 落点（聊天来源）就交给宿主（预填落当前线程
    /// 输入舱）；没有注入（文件页/资料库来源）照
    /// §123 讨论同制——新建一条对话、预填进草稿、
    /// 切到聊天格。两路都只预填不代发；执行后关
    /// 本页（push 形态下 dismiss 即返回上一层）
    private func requestResend() {
        let prefill = FileResendPrefill.make(
            name: target.name, path: target.path
        )
        if let onRequestResend {
            onRequestResend(prefill)
        } else {
            let thread = ChatThread()
            modelContext.insert(thread)
            try? modelContext.save()
            appState.sideChats.setDraft(prefill, for: thread.id)
            appState.drawerThreadSelection = thread.id
            appState.mainTabSwitchRequest = .chat
        }
        dismiss()
    }

    private var lockedView: some View {
        ContentUnavailableView {
            Label("无法预览", systemImage: "lock.fill")
        } description: {
            Text(SensitiveFilePolicy.explanation)
        } actions: {
            Button("知道了") { dismiss() }
        }
    }

    // MARK: - 动作与取数

    private func runPrimary(_ action: FileLandingAction) {
        notice = nil
        switch route {
        case .reader:
            destination = .reader
        case .spreadsheet:
            destination = .spreadsheet
        case .quickLook:
            startPreviewDownload()
        case .saveOnly:
            downloadAndShare()
        case .imageViewer, .infoOnly, .locked:
            break
        }
    }

    /// QL 路：取字节→落临时目录→验资格——可预览进
    /// 页内 QL 承载，不可预览落失败态 unsupportedType
    /// （§121 资格门落点升级：旧形态直落分享单，中间
    /// 页收编后落本页失败态＋failureActions，机制与
    /// 五分文案不变）
    private func startPreviewDownload() {
        downloadTask = Task {
            phase = .downloading
            do {
                let data = try await fetchBytes()
                if Task.isCancelled {
                    phase = .ready
                    return
                }
                let item = try ChatFilePreviewItem.write(
                    data: data, name: target.name
                )
                if item.canPreview {
                    previewItem = item
                    phase = .ready
                    destination = .quickLook
                } else {
                    phase = .failed(.unsupportedType)
                }
            } catch let error as HermesError {
                phase = Task.isCancelled
                    ? .ready
                    : .failed(FileOpenFailure.classify(error: error))
            } catch {
                phase = Task.isCancelled ? .ready : .failed(.other)
            }
        }
    }

    private func downloadAndShare() {
        downloadTask = Task {
            phase = .downloading
            do {
                let data = try await fetchBytes()
                if Task.isCancelled {
                    phase = .ready
                    return
                }
                shareItem = try FileShareItem.write(
                    data: data, name: target.name
                )
                phase = .ready
            } catch let error as HermesError {
                phase = Task.isCancelled
                    ? .ready
                    : .failed(FileOpenFailure.classify(error: error))
            } catch {
                phase = Task.isCancelled ? .ready : .failed(.other)
            }
        }
    }

    private func performSecondary(_ action: FileItemAction) {
        switch action {
        case .copyText:
            Task { await copyText() }
        case .exportPDF:
            Task { await exportPDF() }
        case .share, .download:
            downloadAndShare()
        case .preview, .delete, .pin, .unpin, .rename, .openInFiles:
            // readingActions 不含这几项（后四项由顶栏菜
            // 单 performMenu 分发），落到即策略表漂移
            // ——静默不执行（与阅读页同口径）
            break
        }
    }

    /// 顶栏菜单分发（§131）：打开页专属三件（置顶/
    /// 重命名/在文件页中打开）在本处落，通用件转
    /// performSecondary 与页内动作列共用执行体
    private func performMenu(_ action: FileItemAction) {
        switch action {
        case .pin, .unpin:
            let pinned = pinStore.toggle(path: target.path)
            notice = pinned
                ? L10n.string("已置顶")
                : L10n.string("已取消置顶")
        case .rename:
            renameDraft = target.name
            renamePresented = true
        case .openInFiles:
            // 回指文件页：先置定位请求、再切格、本页
            // 退场——DeliverablesView 消费后滚动高亮
            // （跨面通道口径见 AppState.fileRevealPath）
            appState.fileRevealPath = target.path
            appState.mainTabSwitchRequest = .files
            dismiss()
        case .copyText, .exportPDF, .share, .download:
            performSecondary(action)
        case .preview, .delete:
            // openPageActions 不出这两项
            break
        }
    }

    // MARK: - 改名（§131，D8：组合链，判定走 FileRenamePlan）

    /// 改名提交口：规整校验→无变化拦截→扩展名变更
    /// 先确认→才执行组合链
    private func requestRename() {
        guard let normalized = FileRenamePlan.normalizedName(renameDraft)
        else {
            notice = L10n.string("文件名不合法：不能为空，也不能带「/」。")
            Haptics.error()
            return
        }
        if normalized == target.name {
            notice = L10n.string("名字没有变化。")
            return
        }
        if !FileRenamePlan.keepsExtension(
            oldName: target.name, newName: normalized
        ) {
            pendingRenameName = normalized
            return
        }
        Task { await performRename(to: normalized) }
    }

    /// 改名组合链：服务端无改名端点（openapi 实查），
    /// 以既有原语组合——同名冲突预检（父目录列表）→
    /// 取原件字节→以新名上传（不覆盖）→回读校验新
    /// 条目在且字节一致→才删旧。任一步失败原件保持
    /// 不变并如实回告；只有删旧失败是例外：新名已确
    /// 认落好，呈现切新名、双份并存明示
    private func performRename(to newName: String) async {
        let oldPath = target.path
        let newPath = FileRenamePlan.targetPath(
            currentPath: oldPath, newName: newName
        )
        let parent = (oldPath as NSString).deletingLastPathComponent
        do {
            let listing = try await appState.performAdmin {
                client, config in
                try await client.files(config: config, path: parent)
            }
            if FileRenamePlan.conflicts(
                targetPath: newPath, currentPath: oldPath,
                siblingPaths: listing.entries.map(\.path)
            ) {
                notice = L10n.format(
                    "已存在同名文件「%@」，换个名字试试。", newName
                )
                Haptics.error()
                return
            }
            let data = try await fetchBytes()
            guard FileRenamePlan.isChainAllowed(byteCount: data.count)
            else {
                notice = L10n.string("文件太大，暂时不能在 App 里改名。")
                Haptics.error()
                return
            }
            try await appState.performAdmin { client, config in
                try await client.uploadFile(
                    config: config, path: newPath,
                    dataURL: FileBrowserLogic.makeDataURL(
                        data: data, fileName: newName
                    ),
                    overwrite: false
                )
            }
            let verify = try? await appState.performAdmin {
                client, config in
                try await client.files(config: config, path: parent)
            }
            guard let newEntry = verify?.entries.first(where: {
                      $0.path == newPath && !$0.isDirectory
                  }),
                  newEntry.size == Int64(data.count)
            else {
                notice = L10n.string(
                    "改名没完成：新文件没有确认成功，原文件保持不变。"
                )
                Haptics.error()
                return
            }
            var oldRemoved = true
            do {
                try await appState.performAdmin { client, config in
                    try await client.deleteFile(
                        config: config, path: oldPath, recursive: false
                    )
                }
            } catch {
                oldRemoved = false
            }
            // 本地账跟随新名：元数据缓存迁移、置顶迁
            // 移、文件页重聚合——不留旧名残影
            let now = Date()
            store.forget(path: oldPath)
            store.record(
                path: newPath, size: Int64(data.count), modifiedAt: now
            )
            pinStore.renamed(from: oldPath, to: newPath)
            currentTarget = FileOpenTarget(
                name: newName, path: newPath,
                size: Int64(data.count), modifiedAt: now,
                mimeType: target.mimeType, anchor: target.anchor
            )
            appState.fileLibraryRevision += 1
            if oldRemoved {
                notice = L10n.format("已改名为「%@」", newName)
                Haptics.success()
            } else {
                notice = L10n.string(
                    "新名字已生效，但原文件没能删掉，现在有两份相同内容的文件。"
                )
                Haptics.warning()
            }
        } catch {
            notice = (error as? HermesError)?.userMessage
                ?? L10n.string("改名失败，请稍后再试。")
            Haptics.error()
        }
    }

    private func performFailure(_ action: FileFailureAction) {
        switch action {
        case .retry:
            phase = .ready
            if let landingPrimary {
                runPrimary(landingPrimary)
            }
        case .download:
            downloadAndShare()
        case .dismiss:
            dismiss()
        }
    }

    private func copyText() async {
        do {
            let data = try await fetchBytes()
            if let text = FileTextExtractor.plainText(
                from: data, entry: entry
            ) {
                UIPasteboard.general.string = text
                notice = "已复制全文。"
                Haptics.success()
            } else {
                notice = "这个文件没能读出文字。"
            }
        } catch {
            notice = (error as? HermesError)?.userMessage
                ?? "下载失败，请稍后再试。"
        }
    }

    private func exportPDF() async {
        do {
            let data = try await fetchBytes()
            guard let kind = DocumentTextKind.kind(
                      forFileName: target.name
                  ),
                  let text = FileTextExtractor.plainText(
                      from: data, entry: entry
                  ),
                  let pdf = DocumentPDFExporter.pdfData(
                      title: DeliverableFileType.displayTitle(
                          forFileName: target.name
                      ),
                      blocks: DocumentReading.blocks(
                          for: text, kind: kind
                      )
                  )
            else {
                notice = "导出 PDF 失败，请稍后再试。"
                Haptics.error()
                return
            }
            shareItem = try FileShareItem.write(
                data: pdf,
                name: "\(DeliverableFileType.displayTitle(forFileName: target.name)).pdf"
            )
        } catch {
            notice = (error as? HermesError)?.userMessage
                ?? "下载失败，请稍后再试。"
        }
    }

    /// 取字节（已下载复用）：只取数不回填元数据缓
    /// 存——下载不兼任大小数据源（复杂度清理第 6
    /// 项砍下载回填；大小走发送记账与父目录回读两
    /// 路，见 FileMetadataStore）
    private func fetchBytes() async throws -> Data {
        if let downloadedData { return downloadedData }
        let data = try await appState.performAdmin {
            client, config in
            try await client.fileData(
                config: config, path: target.path
            )
        }
        downloadedData = data
        return data
    }
}

/// 页内 QL 承载（§125）：字节已由打开页取回并验过
/// 资格，本页只承载 QL 本体＋顶栏文件名与动作菜单
/// （与 Muse 失败页/预览页同形：不另起独立 sheet）
struct QuickLookHostView: View {
    @Environment(AppState.self) private var appState

    let entry: WorkspaceFileEntry
    let url: URL
    let data: Data?

    @State private var shareItem: FileShareItem?
    @State private var notice: String?

    var body: some View {
        QuickLookPreview(url: url)
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle(entry.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(
                            FileActionPolicy.readingActions(
                                for: entry
                            ),
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
                    .accessibilityLabel("文件操作")
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let notice {
                    Text(notice)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, OneDayMetrics.pageGutter)
                        .padding(.vertical, OneDayMetrics.spacingS)
                        .background(Palette.pageBG)
                }
            }
            .sheet(item: $shareItem) { item in
                FileShareSheet(url: item.url)
            }
    }

    private func perform(_ action: FileItemAction) {
        switch action {
        case .share, .download:
            if let data {
                shareItem = try? FileShareItem.write(
                    data: data, name: entry.name
                )
            }
        case .copyText:
            if let data,
               let text = FileTextExtractor.plainText(
                   from: data, entry: entry
               ) {
                UIPasteboard.general.string = text
                notice = "已复制全文。"
                Haptics.success()
            }
        case .exportPDF, .preview, .delete,
             .pin, .unpin, .rename, .openInFiles:
            // readingActions 不出这几项（后四项是打开
            // 页专属），落到即策略表漂移——静默不执行
            break
        }
    }
}

/// 文件详情（低频，顶栏「···」进）：原始路径/字节
/// 数/修改时间——文件头只给人话，机器口径收这里
struct FileOpenDetailsView: View {
    @Environment(\.dismiss) private var dismiss

    let target: FileOpenTarget
    let size: Int64?
    let modifiedAt: Date?

    var body: some View {
        NavigationStack {
            List {
                row("文件名", target.name)
                row("路径", target.path)
                row(
                    "大小",
                    size.map {
                        ByteCountFormatter.string(
                            fromByteCount: $0, countStyle: .file
                        )
                    } ?? "—"
                )
                row(
                    "修改时间",
                    modifiedAt.map { AdminFormat.short($0) } ?? "—"
                )
            }
            .navigationTitle("详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .foregroundStyle(Palette.inkSecondary)
            Spacer(minLength: OneDayMetrics.spacingM)
            Text(value)
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .font(.callout)
    }
}
