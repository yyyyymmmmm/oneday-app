import OneDayCore
import OneDayDesign
import QuickLook
import SwiftUI
import UIKit

/// 聊天富内容呈现（0.8.0，P1）：工具卡片、服务端图片、
/// 全屏图片查看器、文件 QuickLook 预览。形态按《设计
/// 标准》§5.5/§5.7：工具卡统一骨架（card 面、圆角 22、
/// 内边距 15、36×36 圆角 9 图标盒＋标题＋状态 chip）；
/// 文件牌 §125 起升卡（白卡＋类型图标盒＋大小副
/// 行）；图片圆角 12 缩略、点开全屏。
/// 卡片只呈现动作与结果，不写说明性文案（红线）。

// MARK: - 工具卡

/// 工具卡（0.36.10 按诊断 D3 重做）：卡面收敛为一
/// 行——图标盒＋人话标题＋一句话摘要＋状态字；参数
/// 原文与结果全文撤出卡面、点开卡进详情区（卡内展
/// 开）。状态是卡级的：只看本卡结果回没回（Core
/// ToolCardPresentation），整轮未落定不再把已完成
/// 的卡拖回「进行中」（诊断 D2 第一名）。旧形态（整
/// 卡平铺＋结果内联＋整轮 isLive）退役。
/// plain＝组内嵌模式：无自家卡面（组卡承接），行
/// 本体与详情展开同口径。
struct ToolCardView: View {
    let card: ToolCard
    var plain: Bool = false
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var state: ToolCardPresentation.State {
        ToolCardPresentation.state(of: card)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(
                    MotionTokens.resolved(
                        MotionTokens.swap, reduceMotion: reduceMotion
                    )
                ) {
                    expanded.toggle()
                }
            } label: {
                rowContent
            }
            .buttonStyle(.odPressable)
            .accessibilityLabel(
                "\(card.title)，\(ToolCardPresentation.statusLine(of: card))"
            )
            if expanded {
                Rectangle()
                    .fill(Palette.hairline)
                    .frame(height: 1)
                    .padding(.top, OneDayMetrics.spacingS)
                detailBody
                    .padding(.top, OneDayMetrics.spacingS)
            }
        }
        .padding(plain ? 0 : 15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if !plain {
                RoundedRectangle(
                    cornerRadius: OneDayMetrics.bubbleCorner
                )
                .fill(Palette.surface)
            }
        }
        .overlay {
            if !plain {
                RoundedRectangle(
                    cornerRadius: OneDayMetrics.bubbleCorner
                )
                .stroke(Palette.hairline, lineWidth: 1)
            }
        }
    }

    /// 一行本体：图标盒 36＋标题/摘要两行字＋状态字
    private var rowContent: some View {
        HStack(alignment: .center, spacing: OneDayMetrics.spacingS) {
            RoundedRectangle(cornerRadius: OneDayMetrics.radiusTile)
                .fill(card.category.tint)
                .frame(width: 36, height: 36)
                .overlay {
                    Image(systemName: card.category.symbol)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(Palette.ink)
                }
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                Text(card.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: OneDayMetrics.spacingS)
            statusMark
        }
        .contentShape(Rectangle())
    }

    /// 副行：参数摘要优先（浏览器卡用页面 URL，与旧
    /// 地址行口径同）；无摘要时成功无输出显「（无输
    /// 出）」、失败显原因首行（诊断 D3-7/D3-9）
    private var subtitle: String {
        if let pageLine = browserPageLine { return pageLine }
        if !card.summary.isEmpty { return card.summary }
        switch state {
        case .succeeded:
            return ToolResultUnwrap.isMeaningless(card.result ?? "")
                ? "（无输出）" : ""
        case .failed:
            return ToolCardPresentation.firstMeaningfulLine(
                of: card.result
            ) ?? ""
        case .running:
            return ""
        }
    }

    /// 状态字（卡级）：进行中＝转圈＋「进行中」（只
    /// 在本卡结果未回时）；失败＝失败徽标；其余＝展
    /// 开指示 chevron（可点必有指示，宪法 §9）
    @ViewBuilder
    private var statusMark: some View {
        switch state {
        case .running:
            HStack(spacing: OneDayMetrics.iconTextGap) {
                ProgressView()
                    .controlSize(.mini)
                Text("进行中")
                    .font(.badgeOnly)
                    .foregroundStyle(Palette.inkSecondary)
            }
        case .failed:
            Text("失败")
                .font(.badgeOnly.weight(.medium))
                .foregroundStyle(Palette.danger)
                .padding(.horizontal, 7)
                .padding(.vertical, OneDayMetrics.stackGap)
                .background(
                    Palette.errorSurface,
                    in: Capsule()
                )
        case .succeeded:
            Image(
                systemName: expanded ? "chevron.up" : "chevron.down"
            )
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Palette.inkSecondary)
            .accessibilityHidden(true)
        }
    }

    /// 详情区：参数原文＋结果全文＋工具原名（英文短
    /// 名只进这里，诊断 D3-3）。直播卡结果是 events
    /// 预览、落定后由 transcript 全文替换（呈现层不
    /// 标注两者区别，口径在 Core unwrap 归一）
    private var detailBody: some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
            if let arguments = card.arguments, !arguments.isEmpty {
                detailField(
                    "参数", text: Self.prettyArguments(arguments),
                    monospaced: true
                )
            } else if !card.summary.isEmpty {
                detailField("参数", text: card.summary, monospaced: false)
            }
            if let result = card.result {
                detailField(
                    "结果",
                    text: ToolResultUnwrap.isMeaningless(result)
                        ? "（无输出）" : result,
                    monospaced: card.category == .terminal
                )
            } else {
                detailField("结果", text: "进行中…", monospaced: false)
            }
            HStack(spacing: OneDayMetrics.iconTextGap) {
                Text("工具名")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Palette.inkSecondary)
                Text(
                    ToolCardClassifier.shortName(
                        forToolName: card.toolName
                    )
                )
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Palette.inkSecondary)
                .textSelection(.enabled)
            }
        }
    }

    private func detailField(
        _ label: String, text: String, monospaced: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(Palette.inkSecondary)
            Text(text)
                .font(
                    monospaced
                        ? .system(.caption, design: .monospaced)
                        : .caption
                )
                .foregroundStyle(Palette.bodyInk)
                .textSelection(.enabled)
        }
    }

    /// 参数详情排版：JSON 能解则美化（键序稳定），
    /// 解不出原文呈现——不丢内容
    private static func prettyArguments(_ raw: String) -> String {
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(
                  with: data
              ),
              let pretty = try? JSONSerialization.data(
                  withJSONObject: object,
                  options: [.prettyPrinted, .sortedKeys,
                            .withoutEscapingSlashes]
              ),
              let text = String(data: pretty, encoding: .utf8)
        else { return raw }
        return text
    }

    /// 浏览器导航结果首行形态（生产实查）：
    /// "Page: Example Domain (https://example.com/)" →
    /// 副行只出 URL（标题在结果正文里已有，不重复）
    private var browserPageLine: String? {
        guard card.category == .browser,
              let result = card.result,
              result.hasPrefix("Page: "),
              let open = result.firstIndex(of: "("),
              let close = result.firstIndex(of: ")"),
              open < close else { return nil }
        let url = String(result[result.index(after: open)..<close])
        return url.hasPrefix("http") ? url : nil
    }
}

/// 工具组（0.36.10，诊断 D3-8）：同轮连续 ≥2 张卡
/// 收成一组——组头一行（Core groupHeader：总数＋
/// 命运分布，失败不隐藏），默认收起；点开组逐卡一
/// 行（ToolCardView plain 模式），逐卡再点开各自详
/// 情。单卡轮次不走本组件、保持单行卡
struct ToolCardGroupView: View {
    let cards: [ToolCard]
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(
                    MotionTokens.resolved(
                        MotionTokens.swap, reduceMotion: reduceMotion
                    )
                ) {
                    expanded.toggle()
                }
            } label: {
                HStack(spacing: OneDayMetrics.spacingS) {
                    RoundedRectangle(cornerRadius: OneDayMetrics.radiusTile)
                        .fill(Palette.fieldFill)
                        .frame(width: 36, height: 36)
                        .overlay {
                            Image(
                                systemName: "wrench.and.screwdriver"
                            )
                            .font(
                                .system(size: 16, weight: .regular)
                            )
                            .foregroundStyle(Palette.ink)
                        }
                    Text(ToolCardPresentation.groupHeader(cards: cards))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Spacer(minLength: OneDayMetrics.spacingS)
                    if cards.contains(where: { $0.result == nil }) {
                        ProgressView()
                            .controlSize(.mini)
                    }
                    Image(
                        systemName: expanded
                            ? "chevron.up" : "chevron.down"
                    )
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.inkSecondary)
                    .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.odPressable)
            if expanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(cards.enumerated()), id: \.element.id) {
                        index, card in
                        if index > 0 {
                            Rectangle()
                                .fill(Palette.hairline)
                                .frame(height: 1)
                                .padding(
                                    .vertical, OneDayMetrics.spacingS
                                )
                        }
                        ToolCardView(card: card, plain: true)
                    }
                }
                .padding(.top, OneDayMetrics.spacingS)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Palette.surface,
            in: RoundedRectangle(
                cornerRadius: OneDayMetrics.bubbleCorner
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: OneDayMetrics.bubbleCorner
            )
            .stroke(Palette.hairline, lineWidth: 1)
        }
    }
}

extension ToolCardCategory {
    var symbol: String {
        switch self {
        case .browser: return "globe"
        case .desktop: return "desktopcomputer"
        case .search: return "magnifyingglass"
        case .file: return "doc"
        case .terminal: return "terminal"
        case .memory: return "brain"
        case .skill: return "puzzlepiece.extension"
        case .vision: return "eye"
        case .task: return "checklist"
        case .connection: return "cable.connector"
        case .device: return "iphone"
        case .other: return "wrench.and.screwdriver"
        }
    }

    var tint: Color {
        switch self {
        case .browser: return Palette.tintSky
        case .desktop: return Palette.bubbleFill
        case .search: return Palette.tintLavender
        case .file: return Palette.tintSky
        case .terminal: return Palette.tintOrange
        case .memory: return Palette.tintGreen
        case .skill: return Palette.tintLavender
        case .vision: return Palette.tintSky
        case .task: return Palette.tintGreen
        case .connection: return Palette.tintLavender
        case .device: return Palette.tintGreen
        case .other: return Palette.fieldFill
        }
    }
}

// MARK: - 服务端图片

/// 服务端图片字节的进程内缓存（同一路径只取一次）
@MainActor
final class ServerImageCache {
    static let shared = ServerImageCache()
    private var storage: [String: Data] = [:]

    func data(for path: String) -> Data? { storage[path] }
    func store(_ data: Data, for path: String) {
        storage[path] = data
    }
}

/// 历史消息里的服务端图片缩略：经既有文件下载通道取回
struct ServerRemoteImage: View {
    let path: String
    @Environment(AppState.self) private var appState
    @State private var data: Data?
    @State private var failed = false

    var body: some View {
        Group {
            if let data, let image = UIImage(data: data) {
                // §130：已发图固定高度卡（Core
                // ChatImageSizing）——卡高恒定 190、
                // 卡宽按比例钳制 [96, 260]，图居中完
                // 整显示不裁切、图窄于卡时两侧露
                // bubbleFill 底；本处一改同时覆盖用
                // 户与助手两侧的远端图。旧 0.36.19
                // 双封盒（220×240、呈现尺寸随图比例
                // 变）口径作废
                let cardSize = ChatImageSizing.cardSize(
                    for: image.size
                )
                let fittedSize = ChatImageSizing.fittedSize(
                    for: image.size,
                    in: cardSize
                )
                ZStack {
                    Image(uiImage: image)
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
            } else if failed {
                // §130：失败态同卡尺寸（占位卡口
                // 径 190 高），不再随文案宽高变
                ZStack {
                    HStack(spacing: OneDayMetrics.rowInnerGap) {
                        Image(systemName: "photo")
                        Text("图片加载失败")
                    }
                    .font(.caption)
                    // 0.23.0（审计 C4）：本字落在
                    // bubbleFill 填充面上——
                    // inkSecondary 在其上实算 4.29:1
                    // 压线下，换填充面专用加深档
                    // inkSecondaryOnFill（≈5.2:1）
                    .foregroundStyle(Palette.inkSecondaryOnFill)
                }
                .frame(
                    width: ChatImageSizing.placeholderCardSize.width,
                    height: ChatImageSizing.placeholderCardSize.height
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
                // §130：加载占位同卡高（190），消除
                // 旧 220×150 占位 → 实际高度的跳变；
                // 比例未知，卡宽取占位口径
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
        .task(id: path) { await load() }
    }

    private func load() async {
        if let hit = ServerImageCache.shared.data(for: path) {
            data = hit
            return
        }
        do {
            let fetched = try await appState.performAdmin {
                client, config in
                try await client.fileData(config: config, path: path)
            }
            ServerImageCache.shared.store(fetched, for: path)
            data = fetched
        } catch {
            failed = true
        }
    }
}

// MARK: - 全屏图片查看器

/// 全屏查看载荷：本地字节（刚发送的消息）或服务端路径
/// （历史消息，查看器内取回）。0.36.4 起它是集合元
/// 素（ImageViewerView 的 items）——单图呈现退役，
/// 单图场景即一条集合。
struct ChatImageViewerItem: Identifiable, Hashable {
    enum Source: Hashable {
        case data(Data)
        case remotePath(String)
    }

    let source: Source

    var id: String {
        switch source {
        case .data(let data):
            return "local-\(data.count)-\(data.hashValue)"
        case .remotePath(let path):
            return "remote-\(path)"
        }
    }
}

/// （ImageFullScreenView 已于 0.36.4 退役：单图黑
/// 底查看器被 ImageViewerView 取代——集合分页＋卡
/// 态/沉浸双态＋系统转场，见 ImageViewerView.swift。
/// 本段只留墓碑防后人误以为还有第二套查看器。）

/// UIScrollView 缩放承载：min 1×／max 4×，双击在点位
/// 放大到 2.5×、已放大则复原。0.36.4 增补两件（图
/// 片查看器双态用）：单击回调（须等双击落空才触
/// 发——识别器失败依赖在此配好，宿主不自理）与缩
/// 放复位令牌（令牌变化且正放大时拉回 1×，供卡
/// 态恒 1× 呈现）。
struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage
    @Binding var isZoomed: Bool
    var resetToken: Int = 0
    var onSingleTap: (() -> Void)? = nil

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 4
        scrollView.delegate = context.coordinator
        scrollView.backgroundColor = .clear
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        scrollView.addSubview(imageView)
        context.coordinator.imageView = imageView
        context.coordinator.lastResetToken = resetToken
        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
        let singleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleSingleTap(_:))
        )
        singleTap.require(toFail: doubleTap)
        scrollView.addGestureRecognizer(singleTap)
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.onSingleTap = onSingleTap
        if resetToken != context.coordinator.lastResetToken {
            context.coordinator.lastResetToken = resetToken
            if scrollView.zoomScale > 1.01 {
                scrollView.setZoomScale(1, animated: false)
                isZoomed = false
            }
        }
        guard let imageView = context.coordinator.imageView
        else { return }
        if scrollView.zoomScale <= 1.01 {
            imageView.frame = CGRect(
                origin: .zero, size: scrollView.bounds.size
            )
            scrollView.contentSize = scrollView.bounds.size
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isZoomed: $isZoomed)
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var imageView: UIImageView?
        var onSingleTap: (() -> Void)?
        var lastResetToken = 0
        private let isZoomed: Binding<Bool>

        init(isZoomed: Binding<Bool>) {
            self.isZoomed = isZoomed
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            isZoomed.wrappedValue = scrollView.zoomScale > 1.05
        }

        @objc func handleSingleTap(
            _ gesture: UITapGestureRecognizer
        ) {
            onSingleTap?()
        }

        @objc func handleDoubleTap(
            _ gesture: UITapGestureRecognizer
        ) {
            guard let scrollView = gesture.view as? UIScrollView,
                  let imageView else { return }
            if scrollView.zoomScale > 1.05 {
                scrollView.setZoomScale(1, animated: true)
                return
            }
            let point = gesture.location(in: imageView)
            let scale: CGFloat = 2.5
            let size = CGSize(
                width: scrollView.bounds.width / scale,
                height: scrollView.bounds.height / scale
            )
            let rect = CGRect(
                x: point.x - size.width / 2,
                y: point.y - size.height / 2,
                width: size.width, height: size.height
            )
            scrollView.zoom(to: rect, animated: true)
        }
    }
}

// MARK: - 文件牌与 QuickLook 预览

/// 文件卡（§125 升卡——设计标准 §5.5 FileChip 原式
/// 修订声明见 DESIGN §125：天蓝胶囊＋通用 doc 图标
/// 退役）：白卡（surface 底、圆角 16、内边距 12×10、
/// 随气泡宽，用户/助手两侧同形）＝40pt 类型图标盒
/// （FileIconBox 单源表）＋文件名（.body semibold、
/// 至多 2 行）＋副行「类型 · 大小」。大小只来自
/// FileMetadataStore 的实测回填（发送记账/下载回
/// 填/父目录列表回读），拿不到只显类型、不编造。
///
/// §131 翻案（用户 2026-11-11 15:13 拍板「对齐」，
/// §125「不设卡级按钮」口径作废）：卡右加「···」
/// 钮——卡级动作入口（对差表 D3），动作集与文件页
/// 行/长按同源同序（FileActionPolicy.menuActions
/// 单源，不另立第二套）；卡主体点击仍走 onOpen、
/// 长按仍沿用消息菜单，两路并存。大小回读改走
/// ensureSize（D1：可见即回读＋失败递增重试，不
/// 再等打开页才补）。
struct FileChip: View {
    @Environment(AppState.self) private var appState

    let path: String
    let onOpen: () -> Void

    @State private var shareItem: FileShareItem?
    @State private var deletePending = false
    @State private var notice: String?

    private var name: String {
        (path as NSString).lastPathComponent
    }

    /// 策略表用的合成条目：只有路径与（已回填的）大
    /// 小是实测，其余按名称口径推导——与 FileOpen-
    /// Target.workspaceEntry 同法，不冒充服务器回读
    private var entry: WorkspaceFileEntry {
        WorkspaceFileEntry(
            name: name, path: path, isDirectory: false,
            size: FileMetadataStore.shared.metadata(for: path)?.size,
            mtime: nil, mimeType: nil
        )
    }

    private var actions: [FileItemAction] {
        FileActionPolicy.menuActions(for: entry)
    }

    private var subtitle: String {
        let type = DeliverableFileType.label(forFileName: name)
        let sizeText = FileMetadataStore.shared
            .metadata(for: path)?.size
            .map {
                ByteCountFormatter.string(
                    fromByteCount: $0, countStyle: .file
                )
            }
        return [type, sizeText]
            .compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingXS) {
            HStack(spacing: 0) {
                Button(action: onOpen) {
                    HStack(spacing: OneDayMetrics.spacingSM) {
                        FileIconBox(name: name, size: 40)
                        VStack(
                            alignment: .leading,
                            spacing: OneDayMetrics.spacingXS
                        ) {
                            Text(name)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Palette.ink)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(Palette.inkSecondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.odPressable)
                if !actions.isEmpty {
                    Menu {
                        actionItems
                    } label: {
                        Image(systemName: "ellipsis")
                            .rotationEffect(.degrees(90))
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(Palette.inkSecondary)
                            // 命中域 44（与文件页行 ⋮ 同
                            // 口径，字形不变）
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("更多操作")
                }
            }
            .padding(.leading, OneDayMetrics.spacingSM)
            .padding(.vertical, 10)
            .background(
                Palette.surface,
                in: RoundedRectangle(
                    cornerRadius: OneDayMetrics.radiusPreview
                )
            )
            .contentShape(
                RoundedRectangle(
                    cornerRadius: OneDayMetrics.radiusPreview
                )
            )
            if let notice {
                Text(notice)
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
        .task(id: path) {
            await FileMetadataStore.shared.ensureSize(
                path: path, appState: appState
            )
        }
        .sheet(item: $shareItem) { item in
            FileShareSheet(url: item.url)
        }
        .confirmationDialog(
            "删除「\(name)」？",
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

    /// 菜单项与文件页行同源渲染：删除走确认框，其余
    /// 直达 perform（与 DeliverablesView.actionItems
    /// 同式）
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
            // menuActions 不出这四项（打开页专属，见
            // openPageActions），落到即策略表漂移——
            // 静默不执行（与打开页 performSecondary 同口径）
            break
        }
    }

    /// 取字节（与打开页 fetchBytes 同通道）：到手即
    /// 回填元数据缓存——卡面大小吃这份实测（回填路②）
    private func fetchBytes() async throws -> Data {
        let data = try await appState.performAdmin {
            client, config in
            try await client.fileData(config: config, path: path)
        }
        FileMetadataStore.shared.recordDownload(
            path: path, byteCount: data.count
        )
        return data
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
            guard let kind = DocumentTextKind.kind(forFileName: name),
                  let text = FileTextExtractor.plainText(
                      from: data, entry: entry
                  ),
                  let pdf = DocumentPDFExporter.pdfData(
                      title: DeliverableFileType.displayTitle(
                          forFileName: name
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
                name: "\(DeliverableFileType.displayTitle(forFileName: name)).pdf"
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
            shareItem = try FileShareItem.write(data: data, name: name)
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
                    config: config, path: path, recursive: false
                )
            }
            // 回读核对（本仓纪律：删除以列表无此项为准）
            let parent = (path as NSString).deletingLastPathComponent
            let listing = try? await appState.performAdmin {
                client, config in
                try await client.files(config: config, path: parent)
            }
            if listing?.entries.contains(where: { $0.path == path }) == true {
                notice = "删除未生效，「\(name)」仍在服务器上。"
                Haptics.warning()
            } else {
                FileMetadataStore.shared.forget(path: path)
                FilePinStore.shared.removed(path: path)
                notice = "已删除「\(name)」。"
            }
        } catch {
            notice = (error as? HermesError)?.userMessage
                ?? "删除失败，请稍后再试。"
            Haptics.error()
        }
    }
}

/// 助手侧文件牌的存在性门（§129）：正文探测来的
/// 路径没有登记背书（用户侧 @file: 登记制不走本
/// 门），渲染前先经 FileMetadataStore 校验——确
/// 证存在才出 FileChip；确证不在、还没查完、或
/// 校验没查成（网络类，只记 unverified 不下「不
/// 在」的结论），一律降为纯文本一行（路径原文照
/// 显、可选中，不假装是可点的文件）。校验是异步
/// 升级：消息先以文本落位，查实后原地换成牌，
/// 不阻塞整条消息渲染。历史消息同享此判定——存
/// 量坏牌不改数据、渲染层自动降级。
struct AssistantFileChip: View {
    @Environment(AppState.self) private var appState

    let path: String
    let onOpen: () -> Void

    var body: some View {
        Group {
            if FileMetadataStore.shared.existence(for: path)
                == .exists {
                FileChip(path: path, onOpen: onOpen)
            } else {
                Text(path)
                    .font(.callout)
                    .foregroundStyle(Palette.inkSecondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task(id: path) {
            await FileMetadataStore.shared.verifyExistence(
                path: path, appState: appState
            )
        }
    }
}

/// QuickLook 预览载荷：字节落临时目录后以 URL 呈现
struct ChatFilePreviewItem: Identifiable {
    let url: URL
    var id: String { url.path }

    static func write(
        data: Data, name: String
    ) throws -> ChatFilePreviewItem {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(name)
        try data.write(to: url)
        return ChatFilePreviewItem(url: url)
    }

    /// QL 预览资格（§121 题二 b）：不可预览类型
    /// （.ipa 等）硬呈 QLPreviewController 只剩空
    /// 白死页——呈现前先验资格，不过者由调用方改
    /// 落下载/分享档（通行做法，见 §121.5）
    var canPreview: Bool {
        // iOS 26 SDK 改名：canPreviewItem → canPreview(_:)
        QLPreviewController.canPreview(url as NSURL)
    }
}

/// 系统 QuickLook 单文件预览
struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(
        context: Context
    ) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(
        _ controller: QLPreviewController, context: Context
    ) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL

        init(url: URL) { self.url = url }

        func numberOfPreviewItems(
            in controller: QLPreviewController
        ) -> Int { 1 }

        func previewController(
            _ controller: QLPreviewController, previewItemAt index: Int
        ) -> QLPreviewItem {
            url as NSURL
        }
    }
}
