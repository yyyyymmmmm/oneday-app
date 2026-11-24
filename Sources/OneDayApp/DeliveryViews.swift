import OneDayCore
import OneDayDesign
import SwiftUI

/// 助手侧登记交付项（§146，规格 delivery-registry-
/// spec-20261111 §7 消费契约）：正文标记只是号，
/// 呈现以登记端点回读的 meta 为唯一依据。状态机：
/// - meta 未到（在查/网络类查失败）：不显——不露
///   标记原文、不占位造假卡（与 §136 未确证不出
///   图同口径）；查失败不落账，下次渲染重查；
/// - 查无此号（404）：标记按纯文本原样显示——
///   规格 §4.2/§7.3，查不到就是一行符号文本，
///   不成卡、不拼路径；
/// - status=gone：一行安静文本「<文件名>（文件
///   已删除）」，不可点；
/// - status=stale：照常渲染、不加警示（文件被
///   更新不是错误，规格 §7.3）；
/// - kind=image：§130 定高卡出图（登记快照
///   thumb→cover 递进，无快照回落原图管线）；
/// - 其余 kind：§125 白卡形态的封面卡（cover
///   有则封面区＋名＋类型·大小；无 cover 走 §32
///   客户端管线回落，再无落 C8 图标行）。
struct AssistantDeliveryItem: View {
    @Environment(AppState.self) private var appState

    let id: String
    let onOpenImage: (BridgeDelivery) -> Void
    let onOpenFile: (BridgeDelivery) -> Void

    private let client = OneDayBridgeClient()

    var body: some View {
        Group {
            switch DeliveryStore.shared.metaResult(for: id) {
            case .loaded(let meta):
                loadedBody(meta)
            case .notFound:
                Text(DeliveryMarker.markerText(for: id))
                    .font(.callout)
                    .foregroundStyle(Palette.inkSecondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case nil:
                EmptyView()
            }
        }
        .task(id: id) {
            await DeliveryStore.shared.loadMeta(
                id: id, client: client, appState: appState
            )
        }
    }

    @ViewBuilder
    private func loadedBody(_ meta: BridgeDelivery) -> some View {
        if meta.status == .gone {
            Text(L10n.format("%@（文件已删除）", meta.name))
                .font(.callout)
                .foregroundStyle(Palette.inkSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if meta.kind == "image" {
            DeliveryImageView(meta: meta, client: client) {
                onOpenImage(meta)
            }
        } else {
            DeliveryFileCard(meta: meta, client: client) {
                onOpenFile(meta)
            }
        }
    }
}

/// 登记图片的内联出图（§146）：卡形走 §130 定
/// 高卡（卡宽先按 meta 实测宽高算、图未到版式已
/// 定）；图源走登记快照递进——thumb（360）先
/// 到先显、cover（1080）到后换上；登记时无快
/// 照（cover 两档皆 false）或快照都取不到时，
/// 回落 §130 既有原图管线（ServerRemoteImage，
/// 自带占位/失败态）。点开/无障碍与 §136 图片
/// 行同口径（宿主回 ChatView 的查看器入口）。
struct DeliveryImageView: View {
    @Environment(AppState.self) private var appState

    let meta: BridgeDelivery
    let client: OneDayBridgeClient
    let onOpen: () -> Void

    @State private var thumb: UIImage?
    @State private var cover: UIImage?
    @State private var snapshotsSettled = false

    private var hasSnapshots: Bool {
        meta.cover.thumb || meta.cover.cover
    }

    private var displayImage: UIImage? { cover ?? thumb }

    var body: some View {
        // §379：原「点按手势＋自研按压修饰」迁原生
        // Button＋.odPressable（清点 #22 整件退役）；
        // 无障碍语义改由真 Button 承载
        Button {
            onOpen()
        } label: {
            Group {
                if !hasSnapshots
                    || (snapshotsSettled && displayImage == nil) {
                    // 无快照/快照全取不到：原图管线兜底
                    ServerRemoteImage(path: meta.path)
                } else if let displayImage {
                    let sizingBase = meta.imagePixelSize
                        ?? displayImage.size
                    let cardSize = ChatImageSizing.cardSize(
                        for: sizingBase
                    )
                    let fittedSize = ChatImageSizing.fittedSize(
                        for: displayImage.size,
                        in: cardSize
                    )
                    ZStack {
                        Image(uiImage: displayImage)
                            .resizable()
                            .frame(
                                width: fittedSize.width,
                                height: fittedSize.height
                            )
                    }
                    .frame(
                        width: cardSize.width,
                        height: cardSize.height
                    )
                    .background(
                        Palette.bubbleFill,
                        in: RoundedRectangle(
                            cornerRadius: OneDayMetrics.radiusCard
                        )
                    )
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: OneDayMetrics.radiusCard
                        )
                    )
                } else {
                    // 快照在路上：§130 占位卡同高，不跳动
                    RoundedRectangle(
                        cornerRadius: OneDayMetrics.radiusCard
                    )
                    .fill(Palette.bubbleFill)
                    .frame(
                        width: ChatImageSizing.placeholderCardSize.width,
                        height: ChatImageSizing.placeholderCardSize.height
                    )
                    .overlay { ProgressView() }
                }
            }
        }
        .buttonStyle(.odPressable)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            A11yText.imageLabel(fileName: meta.name)
        )
        .accessibilityHint(L10n.string("查看大图"))
        .task(id: meta.id) { await loadSnapshots() }
    }

    private func loadSnapshots() async {
        guard hasSnapshots else { return }
        if meta.cover.thumb, thumb == nil,
           let data = await DeliveryStore.shared.image(
               id: meta.id, variant: .thumb,
               client: client, appState: appState
           ) {
            thumb = UIImage(data: data)
        }
        if meta.cover.cover, cover == nil,
           let data = await DeliveryStore.shared.image(
               id: meta.id, variant: .cover,
               client: client, appState: appState
           ) {
            cover = UIImage(data: data)
        }
        snapshotsSettled = true
    }
}

/// 登记文件卡（§146；§452.3 换代）：登记封面在
/// 册＝成品块（气泡灰容器＋228 预览区＋元行，Muse
/// 聊天块式，取代 §125 白卡＋§407 的 148 封面）；
/// 不在册＝微信式文件卡（FileChip 同组件）。大小
/// 是登记时端点实测的真值（meta.size）。点开落点
/// 由宿主给（§452.6 聊天两路：QL 直达／兜底页）。
struct DeliveryFileCard: View {
    @Environment(AppState.self) private var appState

    let meta: BridgeDelivery
    let client: OneDayBridgeClient
    let onOpen: () -> Void

    @State private var coverImage: UIImage?
    /// 封面取数已穷尽（快照＋管线皆空）——占位面自
    /// 此落类型图标、不再挂菊花（§407 口径续）
    @State private var coverSettled = false
    @State private var shareItem: FileShareItem?
    @State private var deletePending = false
    @State private var notice: String?

    /// 合成条目：名/路径/大小全是登记实测，其余按
    /// 名称口径推导——与 FileChip 的合成条目同法
    private var entry: WorkspaceFileEntry {
        WorkspaceFileEntry(
            name: meta.name, path: meta.path, isDirectory: false,
            size: meta.size, mtime: nil, mimeType: meta.mime
        )
    }

    private var actions: [FileItemAction] {
        FileActionPolicy.menuActions(for: entry)
    }

    var body: some View {
        // §452.1/452.3 两形态：登记封面在册（①渲染
        // 类交付）→成品块；其余→微信式文件卡（与
        // FileChip 同组件，§452.2）
        if meta.cover.cover {
            blockBody
        } else {
            FileChip(path: meta.path, onOpen: onOpen)
        }
    }

    // MARK: 成品块（§452.3，Muse 聊天块式）

    private var blockBody: some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingXS) {
            ZStack(alignment: .bottomTrailing) {
                Button(action: onOpen) {
                    VStack(alignment: .leading, spacing: 0) {
                        previewArea
                        metaRow
                    }
                    .background(
                        Palette.bubbleFill,
                        in: RoundedRectangle(
                            cornerRadius: OneDayMetrics.radiusPreview
                        )
                    )
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: OneDayMetrics.radiusPreview
                        )
                    )
                    .contentShape(
                        RoundedRectangle(
                            cornerRadius: OneDayMetrics.radiusPreview
                        )
                    )
                }
                .buttonStyle(.odPressable)
                if !actions.isEmpty {
                    Menu {
                        actionItems
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: FrameworkIcon.cardGlyphSize, weight: .semibold))
                            .foregroundStyle(Palette.inkSecondary)
                            .frame(width: 40, height: 40)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("更多操作")
                    .padding(.trailing, OneDayMetrics.spacingMicro)
                    .padding(.bottom, 11)
                }
            }
            if let notice {
                Text(notice)
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
        .task(id: meta.id) { await loadCover() }
        .sheet(item: $shareItem) { item in
            FileShareSheet(url: item.url)
        }
        .confirmationDialog(
            "删除「\(meta.name)」？",
            isPresented: $deletePending,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                Haptics.impact(.heavy)
                Task { await deleteFile() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后无法恢复。")
        }
    }

    /// 预览区：内距 8、定高 228（§452.3；§407 定高
    /// 契约续——形态只认登记旗、图到只换图不换高）；
    /// 真图填充裁切，未到/无图占位面落居中类型图标
    private var previewArea: some View {
        Group {
            if let coverImage {
                Image(uiImage: coverImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(Palette.surface)
                    .overlay {
                        if coverSettled {
                            FileTypeIconView(
                                fileName: meta.name, height: 64
                            )
                        } else {
                            ProgressView()
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 228)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.top, OneDayMetrics.spacingS)
        .padding(.horizontal, OneDayMetrics.spacingS)
    }

    /// 元行：24 图标＋名（一行）＋类型标＋尾部菜单
    /// 占位（菜单钮以覆盖层同位落此行，§363 同式）
    private var metaRow: some View {
        HStack(spacing: OneDayMetrics.spacingS) {
            FileTypeIconView(fileName: meta.name, height: 24)
            VStack(
                alignment: .leading,
                spacing: OneDayMetrics.spacingMicro
            ) {
                Text(meta.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text(DeliverableFileType.label(forFileName: meta.name))
                    .font(.subheadline)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 40)
        }
        .padding(.horizontal, OneDayMetrics.spacingSM)
        .padding(.vertical, 10)
    }

    private func loadCover() async {
        // 取图只许填已预留的预览区——登记旗不在册
        // 时整路不跑（恒卡形态，§407 口径续）
        guard meta.cover.cover, coverImage == nil,
              !coverSettled
        else { return }
        if let data = await DeliveryStore.shared.image(
            id: meta.id, variant: .cover,
            client: client, appState: appState
        ),
           let image = UIImage(data: data) {
            coverImage = image
            return
        }
        // 登记快照取不到：§32 客户端管线回落填同
        // 一预留区（QL 首面/降采样）；再无则占位
        // 面落类型图标、形态不变
        coverImage = await FileThumbnailStore.shared.thumbnail(
            for: entry, targetPixelSize: 720
        ) {
            try? await appState.performAdmin { client, config in
                try await client.fileData(
                    config: config, path: meta.path
                )
            }
        }
        coverSettled = true
    }

    // MARK: 块菜单动作（与 FileChip 长按菜单同源同处理）

    @ViewBuilder
    private var actionItems: some View {
        ForEach(actions, id: \.self) { action in
            if action == .delete {
                Button(role: .destructive) {
                    deletePending = true
                } label: {
                    Label(action.label, systemImage: action.systemImage)
                }
            } else {
                Button {
                    perform(action)
                } label: {
                    Label(action.label, systemImage: action.systemImage)
                }
            }
        }
    }

    private func perform(_ action: FileItemAction) {
        notice = nil
        switch action {
        case .preview:
            onOpen()
        case .copyText:
            Task { await copyText() }
        case .exportPDF:
            Task { await exportPDF() }
        case .share, .download:
            Task { await downloadAndShare() }
        case .delete:
            deletePending = true
        case .pin, .unpin, .rename, .openInFiles:
            break
        }
    }

    private func fetchBytes() async throws -> Data {
        try await appState.performAdmin {
            client, config in
            try await client.fileData(
                config: config, path: meta.path
            )
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
            Haptics.error()
        }
    }

    private func exportPDF() async {
        do {
            let data = try await fetchBytes()
            guard let kind = DocumentTextKind.kind(
                      forFileName: meta.name
                  ),
                  let text = FileTextExtractor.plainText(
                      from: data, entry: entry
                  ),
                  let pdf = DocumentPDFExporter.pdfData(
                      title: DeliverableFileType.displayTitle(
                          forFileName: meta.name
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
                name: "\(DeliverableFileType.displayTitle(forFileName: meta.name)).pdf"
            )
        } catch {
            notice = (error as? HermesError)?.userMessage
                ?? "下载失败，请稍后再试。"
            Haptics.error()
        }
    }

    private func downloadAndShare() async {
        do {
            let data = try await fetchBytes()
            shareItem = try FileShareItem.write(
                data: data, name: meta.name
            )
        } catch {
            notice = (error as? HermesError)?.userMessage
                ?? "下载失败，请稍后再试。"
            Haptics.error()
        }
    }

    private func deleteFile() async {
        do {
            try await appState.performAdmin { client, config in
                try await client.deleteFile(
                    config: config, path: meta.path,
                    recursive: false
                )
            }
            // 回读核对（本仓纪律：删除以列表无此项为准）
            let parent = (meta.path as NSString)
                .deletingLastPathComponent
            let listing = try? await appState.performAdmin {
                client, config in
                try await client.files(config: config, path: parent)
            }
            if listing?.entries.contains(
                where: { $0.path == meta.path }
            ) == true {
                notice = "删除未生效，「\(meta.name)」仍在服务器上。"
                Haptics.warning()
            } else {
                FileMetadataStore.shared.forget(path: meta.path)
                FilePinStore.shared.removed(path: meta.path)
                notice = "已删除「\(meta.name)」。"
            }
        } catch {
            notice = (error as? HermesError)?.userMessage
                ?? "删除失败，请稍后再试。"
            Haptics.error()
        }
    }
}
