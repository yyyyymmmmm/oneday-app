import OneDayCore
import OneDayDesign
import QuickLook
import SwiftUI
import UIKit

/// 聊天富内容呈现（0.8.0，P1）：工具卡片、服务端图片、
/// 全屏图片查看器、文件 QuickLook 预览。形态按《设计
/// 标准》§5.5/§5.7：工具卡统一骨架（card 面、圆角 22、
/// 内边距 15、36×36 圆角 9 图标盒＋标题＋状态 chip）；
/// 文件牌 sky 底圆角 16；图片圆角 12 缩略、点开全屏。
/// 卡片只呈现动作与结果，不写说明性文案（红线）。

// MARK: - 工具卡

struct ToolCardView: View {
    let card: ToolCard
    /// 流式进行中（结果未回）：标题行右侧出「进行中」
    var isLive: Bool = false
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let collapseLimit = 280

    var body: some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
            HStack(alignment: .top, spacing: OneDayMetrics.spacingS) {
                RoundedRectangle(cornerRadius: 9)
                    .fill(card.category.tint)
                    .frame(width: 36, height: 36)
                    .overlay {
                        Image(systemName: card.category.symbol)
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(Palette.ink)
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Palette.ink)
                    if !card.summary.isEmpty {
                        Text(card.summary)
                            .font(.caption)
                            .foregroundStyle(Palette.inkSecondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: OneDayMetrics.spacingS)
                if card.resultFailed {
                    Text("失败")
                        // 0.23.0（审计 G6）：徽标文字升角色
                        // badgeOnly（caption 12；旧 caption2
                        // 11 退出文字位）
                        .font(.badgeOnly.weight(.medium))
                        .foregroundStyle(Palette.danger)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Palette.errorSurface,
                            in: Capsule()
                        )
                } else if isLive {
                    HStack(spacing: 5) {
                        ProgressView()
                            .controlSize(.mini)
                        Text("进行中")
                            // 0.23.0（审计 G6/G1）：状态小字升
                            // badgeOnly（12）＋inkSecondary
                            .font(.badgeOnly)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }
            }
            if let pageLine = browserPageLine {
                HStack(spacing: 5) {
                    Image(systemName: "link")
                    Text(pageLine)
                        .lineLimit(1)
                }
                // 0.23.0（审计 G6）：11pt 字形字面量清零
                // ——字形随行文字走 caption 档（12）同缩
                .font(.caption)
                .foregroundStyle(Palette.inkSecondary)
            }
            if let result = card.result, !result.isEmpty {
                Rectangle()
                    .fill(Palette.hairline)
                    .frame(height: 1)
                resultBody(result)
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

    /// 浏览器导航结果首行形态（生产实查）：
    /// "Page: Example Domain (https://example.com/)" →
    /// 地址行只出 URL（标题在结果正文里已有，不重复）
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

    @ViewBuilder
    private func resultBody(_ result: String) -> some View {
        let needsCollapse = result.count > Self.collapseLimit
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingXS) {
            Text(
                needsCollapse && !expanded
                    ? String(result.prefix(Self.collapseLimit)) + "…"
                    : result
            )
            .font(
                card.category == .terminal
                    ? .system(.caption, design: .monospaced)
                    : .caption
            )
            .foregroundStyle(Palette.bodyInk)
            .textSelection(.enabled)
            if needsCollapse {
                Button(expanded ? "收起" : "展开结果") {
                    // 0.25.0（动效专包）：展开/收起原为无
                    // 动画硬切（卡高跳变）——走 swap 令牌
                    // （令牌册自注 swap 含折叠展开）＋
                    // resolved 出口，卡高平滑过渡
                    withAnimation(
                        MotionTokens.resolved(
                            MotionTokens.swap, reduceMotion: reduceMotion
                        )
                    ) {
                        expanded.toggle()
                    }
                }
                .font(.caption)
                .foregroundStyle(Palette.primary)
                .buttonStyle(.odPressable)
                // 0.23.0（审计 C2 同批）：展开钮命中域补
                // 到 44 高（视觉字形不变、行内左对齐）
                .frame(minHeight: OneDayMetrics.minTapTarget)
                .contentShape(Rectangle())
            }
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
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 220)
            } else if failed {
                HStack(spacing: 6) {
                    Image(systemName: "photo")
                    Text("图片加载失败")
                }
                .font(.caption)
                // 0.23.0（审计 C4）：本字落在 bubbleFill
                // 填充面上——inkSecondary 在其上实算
                // 4.29:1 压线下，换填充面专用加深档
                // inkSecondaryOnFill（≈5.2:1）
                .foregroundStyle(Palette.inkSecondaryOnFill)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    Palette.bubbleFill,
                    in: RoundedRectangle(cornerRadius: 12)
                )
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Palette.bubbleFill)
                    .frame(width: 220, height: 150)
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

/// 文件牌（设计标准 §5.5 原式）：sky 底、圆角 16、
/// 内边距 11×8、文件名＋doc 图标
struct FileChip: View {
    let path: String
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 6) {
                Image(systemName: "doc")
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.primary)
                Text((path as NSString).lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(Palette.bodyInk)
                    .lineLimit(1)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(
                Palette.tintSky,
                in: RoundedRectangle(cornerRadius: 16)
            )
        }
        .buttonStyle(.odPressable)
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
