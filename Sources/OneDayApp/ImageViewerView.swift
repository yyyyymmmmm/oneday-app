import OneDayCore
import OneDayDesign
import Photos
import SwiftUI
import UIKit

/// 查看器呈现载荷（0.36.4）：集合＋起始页。四入口
/// （聊天图/文件行/影音网格/Box 图）统一经它进查
/// 看器——旧单图 item 模型（进查看器即孤岛、无翻
/// 页）退役。
struct ImageViewerSession: Identifiable, Hashable {
    let items: [ChatImageViewerItem]
    let initialIndex: Int

    var id: String {
        items.indices.contains(initialIndex)
            ? items[initialIndex].id : "viewer-empty"
    }
}

/// 图片查看器（0.36.4，体验三件规格 §3 全面重做）：
/// 收敛四入口，替代旧 ImageFullScreenView 单图版。
///
/// - 双态（状态机在 Core ImageViewerState）：默认
///   卡态——页面底、图按自身宽高比成卡（边距/圆角
///   走 ImageViewerSpec 落值）、chrome 在场；点图
///   切沉浸态——纯黑底全幅、chrome 全隐，再点切回。
/// - 翻页：系统分页滚动（ScrollView＋paging 行为＋
///   scrollPosition 与状态机索引双向同步）；放大态
///   经状态机 pagingEnabled 关外层滚动（scroll-
///   Disabled 只作用外层、内层图面平移不受影响——
///   这是选分页 ScrollView 而非 TabView(.page) 的
///   原因：后者的 disabled 会连内层手势一并封死）。
/// - chrome：左上关闭圆钮 44、右上玻璃胶囊（下载
///   ＋•••菜单：复制/分享/删除）——玻璃走系统
///   glassEffect（导航层材质，与顶栏钮同语言）；
///   删除项只在宿主提供 onDeleteItem 时出现。
/// - 保存走相册（权限文案 NSPhotoLibraryAddUsage-
///   Description 已在 Project.swift 声明；只在用户
///   点「下载」时申请 addOnly）。
/// - 触感：打开/关闭/翻页/切态全无（规格 §2.3 页
///   面切换类）；保存/复制成功 success、失败 error、
///   删除落锤 impact heavy——结果事件口径与全 App
///   矩阵一致。
struct ImageViewerView: View {
    let items: [ChatImageViewerItem]
    let initialIndex: Int
    /// 删除动作（文件面提供；聊天/Box/浏览器不传，
    /// 菜单不出现删除项）
    var onDeleteItem: ((ChatImageViewerItem) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var state: ImageViewerState
    /// 卡态复位令牌：切回卡态时递增，各页的缩放承
    /// 载据此把 zoomScale 拉回 1（卡面恒 1× 呈现）
    @State private var cardResetToken = 0
    /// 已加载图面（按 item.id）：chrome 动作（保存/
    /// 复制/分享）作用于当前页已加载的图
    @State private var loadedImages: [String: UIImage] = [:]
    @State private var shareItem: FileShareItem?
    @State private var notice: String?
    /// 下拉关闭的跟手位移（0.36.4 追加验收项，用户
    /// 点名「下拉返回不了」）：未放大时纵拖写入、整
    /// 面跟随＋渐隐，过阈值松手 dismiss、未过弹簧
    /// 回位（dragSpring 令牌）；放大态不接管（图面
    /// 平移优先）
    @State private var dragOffset: CGFloat = 0

    init(
        items: [ChatImageViewerItem],
        initialIndex: Int,
        onDeleteItem: ((ChatImageViewerItem) -> Void)? = nil
    ) {
        self.items = items
        self.initialIndex = initialIndex
        self.onDeleteItem = onDeleteItem
        _state = State(
            initialValue: ImageViewerState(
                count: items.count, initialIndex: initialIndex
            )
        )
    }

    var body: some View {
        ZStack {
            // 底：卡态＝页面底、沉浸态＝纯黑（规格
            // §3.5）；双态切换底色交叉走 swap 令牌
            (state.mode == .card ? Palette.pageBG : Color.black)
                .ignoresSafeArea()
            if state.hasContent {
                pagingScroll
            } else {
                Text("没有可显示的图片。")
                    .font(.callout)
                    .foregroundStyle(
                        state.mode == .card
                            ? Palette.inkSecondary : Color.white
                    )
            }
            if state.chromeVisible {
                chromeOverlay
                    .transition(.opacity)
            }
            if let notice {
                noticeOverlay(notice)
            }
        }
        .animation(
            MotionTokens.resolved(
                MotionTokens.swap, reduceMotion: reduceMotion
            ),
            value: state.mode
        )
        // 下拉关闭（跟手层）：整面随纵拖位移、背景
        // 渐隐露出底下内容；与分页横滚以方向判定分
        // 流（纵向主导才接管），单击/双击/按钮点按
        // 不受影响（拖动手势与点按天然分家）
        .offset(y: dragOffset)
        .opacity(1 - Double(min(dragOffset / 320, 1)) * 0.35)
        .simultaneousGesture(dragDismissGesture)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .sheet(item: $shareItem) { item in
            FileShareSheet(url: item.url)
        }
    }

    // MARK: - 下拉关闭手势

    /// 下拉关闭（0.36.4 追加验收项）：纵向主导才接
    /// 管（横拖归分页）、只跟下行、放大态不接管；
    /// 过 110pt 松手 dismiss（系统转场逆向收尾），
    /// 未过走拖拽弹簧令牌回位。阈值沿旧查看器实证
    /// 值 110（0.8.0 起在产），不另立新数。
    private var dragDismissGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard !state.isZoomed else { return }
                let dy = value.translation.height
                if dy > 0,
                   abs(dy) > abs(value.translation.width) {
                    dragOffset = dy
                }
            }
            .onEnded { value in
                let dy = value.translation.height
                let shouldDismiss = !state.isZoomed
                    && dy > 110
                    && abs(dy) > abs(value.translation.width)
                if shouldDismiss {
                    dismiss()
                } else {
                    withAnimation(
                        MotionTokens.resolved(
                            MotionTokens.dragSpring,
                            reduceMotion: reduceMotion
                        )
                    ) {
                        dragOffset = 0
                    }
                }
            }
    }

    // MARK: - 分页面

    /// 分页索引双向绑定：读＝状态机当前页，写＝翻
    /// 页落定回写状态机（夹紧/清缩放在状态机内）
    private var pageBinding: Binding<Int?> {
        Binding(
            get: { state.index },
            set: { newValue in
                if let newValue {
                    state.select(index: newValue)
                }
            }
        )
    }

    private var pagingScroll: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 0) {
                ForEach(items.indices, id: \.self) { index in
                    page(index)
                        .containerRelativeFrame(.horizontal)
                        .id(index)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: pageBinding)
        .scrollDisabled(!state.pagingEnabled)
        .ignoresSafeArea()
    }

    private func page(_ index: Int) -> some View {
        ImageViewerPage(
            item: items[index],
            mode: state.mode,
            zoomResetToken: cardResetToken,
            onToggleMode: toggleMode,
            onZoomChange: { zoomed in
                // 只认当前页的缩放回写（翻页过渡中
                // 邻页的回写不许污染状态机）
                if index == state.index {
                    state.setZoomed(zoomed)
                }
            },
            onImageLoaded: { image in
                loadedImages[items[index].id] = image
            }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "图片 \(index + 1)，共 \(items.count) 张"
        )
        .accessibilityHint("点按在卡片与全屏之间切换")
    }

    private func toggleMode() {
        state.toggleMode()
        if state.mode == .card {
            cardResetToken += 1
        }
    }

    // MARK: - chrome（卡态）

    private var chromeOverlay: some View {
        VStack {
            HStack(alignment: .top) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .frame(
                            width: ImageViewerSpec.closeButtonDiameter,
                            height: ImageViewerSpec.closeButtonDiameter
                        )
                        .glassEffect(.regular, in: Circle())
                }
                .buttonStyle(.odPressable)
                .accessibilityLabel("关闭")
                Spacer()
                HStack(spacing: 0) {
                    Button {
                        Task { await saveCurrent() }
                    } label: {
                        Image(systemName: "arrow.down.to.line")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Palette.ink)
                            .frame(
                                width: ImageViewerSpec.chromeButtonWidth,
                                height: ImageViewerSpec.chromeCapsuleHeight
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.odPressable)
                    .accessibilityLabel("保存到相册")
                    Menu {
                        Button {
                            copyCurrent()
                        } label: {
                            Label("复制", systemImage: "doc.on.doc")
                        }
                        Button {
                            shareCurrent()
                        } label: {
                            Label(
                                "分享",
                                systemImage: "square.and.arrow.up"
                            )
                        }
                        if onDeleteItem != nil {
                            Divider()
                            Button(role: .destructive) {
                                deleteCurrent()
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Palette.ink)
                            .frame(
                                width: ImageViewerSpec.chromeButtonWidth,
                                height: ImageViewerSpec.chromeCapsuleHeight
                            )
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("更多操作")
                }
                .glassEffect(.regular, in: Capsule())
            }
            .padding(.horizontal, OneDayMetrics.spacingM)
            .padding(.top, OneDayMetrics.spacingS)
            Spacer()
        }
    }

    private func noticeOverlay(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text)
                .font(.footnote)
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, OneDayMetrics.spacingM)
                .padding(.vertical, OneDayMetrics.spacingS)
                .glassEffect(.regular, in: Capsule())
                .padding(.bottom, OneDayMetrics.spacingXXL)
        }
        .allowsHitTesting(false)
        .task(id: text) {
            try? await Task.sleep(for: .seconds(2.5))
            if notice == text { notice = nil }
        }
    }

    // MARK: - chrome 动作（作用于当前页）

    private var currentItem: ChatImageViewerItem? {
        items.indices.contains(state.index)
            ? items[state.index] : nil
    }

    private var currentImage: UIImage? {
        currentItem.flatMap { loadedImages[$0.id] }
    }

    private func saveCurrent() async {
        guard let image = currentImage else {
            notice = "图片还没加载完，请稍后再试。"
            return
        }
        let status = await PHPhotoLibrary.requestAuthorization(
            for: .addOnly
        )
        guard status == .authorized || status == .limited else {
            notice = "没有相册保存权限，请在系统设置里允许后再试。"
            Haptics.error()
            return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.creationRequestForAsset(
                    from: image
                )
            }
            notice = "已保存到相册。"
            Haptics.success()
        } catch {
            notice = "保存失败，请稍后再试。"
            Haptics.error()
        }
    }

    private func copyCurrent() {
        guard let image = currentImage else {
            notice = "图片还没加载完，请稍后再试。"
            return
        }
        UIPasteboard.general.image = image
        notice = "已复制。"
        Haptics.success()
    }

    private func shareCurrent() {
        guard let image = currentImage,
              let data = image.pngData() else {
            notice = "图片还没加载完，请稍后再试。"
            return
        }
        // 分享临时文件名：远端图沿原文件名（分享单
        // 标题即它），本地图用通用名——不编造来源
        let name: String
        if let item = currentItem,
           case .remotePath(let path) = item.source {
            name = (path as NSString).lastPathComponent
        } else {
            name = "OneDay图片.png"
        }
        if let item = try? FileShareItem.write(data: data, name: name) {
            shareItem = item
        } else {
            notice = "分享准备失败，请稍后再试。"
            Haptics.error()
        }
    }

    private func deleteCurrent() {
        guard let item = currentItem, let onDeleteItem else { return }
        // 删除落锤（规格 §2.3）：菜单点删除即确认
        // 动作、只震一次；删除本体与回读归宿主
        Haptics.impact(.heavy)
        onDeleteItem(item)
        dismiss()
    }
}

// MARK: - 聊天侧转场承载（UIKit zoom）

/// 聊天页呈现承载（0.36.4）：聊天页当前无 Naviga-
/// tionStack，zoom 转场走 UIKit 系统机制——宿主
/// VC 设 preferredTransition＝.zoom（规格 §3.4 过
/// 渡方案）。源视图提供者暂缺（聊天缩略是 SwiftUI
/// 视图、无现成 UIView 句柄可交），系统在无源时
/// 的确切降级形态真机待验、不在此断言；聊天栈化
/// 时并轨 matchedTransitionSource（文件侧已用）。
struct ZoomTransitionCover<Content: View>:
    UIViewControllerRepresentable {
    @ViewBuilder var content: () -> Content

    func makeUIViewController(
        context: Context
    ) -> UIHostingController<Content> {
        ZoomHostingController(rootView: content())
    }

    func updateUIViewController(
        _ controller: UIHostingController<Content>,
        context: Context
    ) {
        controller.rootView = content()
    }
}

private final class ZoomHostingController<Content: View>:
    UIHostingController<Content> {
    override func viewDidLoad() {
        super.viewDidLoad()
        preferredTransition = .zoom(
            options: UIViewController.Transition.ZoomOptions(),
            sourceViewProvider: { _ in nil }
        )
    }
}

// MARK: - 单页（图面加载＋双态呈现）

/// 查看器单页：图面经既有通道加载（本地字节直解、
/// 远端走文件下载＋进程内缓存，与缩略同通道）；
/// 卡态按图宽高比成卡（ fitted 尺寸走 Core 纯函
/// 数）、沉浸态全幅；缩放本体复用 ZoomableImage-
/// View（UIScrollView 1–4×、双击 2.5×、单击回调
/// 切双态——单击须等双击落空才触发，识别器在承
/// 载层配好失败依赖）。
private struct ImageViewerPage: View {
    let item: ChatImageViewerItem
    let mode: ImageViewerMode
    let zoomResetToken: Int
    let onToggleMode: () -> Void
    let onZoomChange: (Bool) -> Void
    let onImageLoaded: (UIImage) -> Void

    @Environment(AppState.self) private var appState
    @State private var image: UIImage?
    @State private var loadFailed = false
    @State private var isZoomed = false

    var body: some View {
        Group {
            if let image {
                zoomSurface(image)
            } else if loadFailed {
                VStack(spacing: OneDayMetrics.spacingS) {
                    Image(systemName: "photo")
                        .font(.system(size: 26))
                    Text("图片没加载出来")
                        .font(.callout)
                }
                .foregroundStyle(
                    mode == .card ? Palette.inkSecondary : Color.white
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView()
                    .tint(mode == .card ? Palette.inkSecondary : .white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: item.id) { await load() }
        .onChange(of: isZoomed) { _, zoomed in
            onZoomChange(zoomed)
        }
    }

    @ViewBuilder
    private func zoomSurface(_ image: UIImage) -> some View {
        if mode == .card {
            GeometryReader { proxy in
                let fitted = ImageViewerLayout.fittedSize(
                    imageWidth: image.size.width,
                    imageHeight: image.size.height,
                    maxWidth: proxy.size.width
                        - 2 * ImageViewerSpec.cardHorizontalMargin,
                    maxHeight: proxy.size.height * 0.68
                )
                ZoomableImageView(
                    image: image,
                    isZoomed: $isZoomed,
                    resetToken: zoomResetToken,
                    onSingleTap: onToggleMode
                )
                .frame(width: fitted.width, height: fitted.height)
                .background(
                    Palette.surface,
                    in: RoundedRectangle(
                        cornerRadius: ImageViewerSpec.cardCorner
                    )
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: ImageViewerSpec.cardCorner
                    )
                )
                .frame(
                    maxWidth: .infinity, maxHeight: .infinity,
                    alignment: .top
                )
                .padding(.top, proxy.size.height * 0.10)
            }
        } else {
            ZoomableImageView(
                image: image,
                isZoomed: $isZoomed,
                resetToken: zoomResetToken,
                onSingleTap: onToggleMode
            )
        }
    }

    private func load() async {
        switch item.source {
        case .data(let data):
            image = UIImage(data: data)
            if let image {
                onImageLoaded(image)
            } else {
                loadFailed = true
            }
        case .remotePath(let path):
            if let hit = ServerImageCache.shared.data(for: path),
               let cached = UIImage(data: hit) {
                image = cached
                onImageLoaded(cached)
                return
            }
            do {
                let fetched = try await appState.performAdmin {
                    client, config in
                    try await client.fileData(
                        config: config, path: path
                    )
                }
                ServerImageCache.shared.store(fetched, for: path)
                image = UIImage(data: fetched)
                if let image {
                    onImageLoaded(image)
                } else {
                    loadFailed = true
                }
            } catch {
                loadFailed = true
            }
        }
    }
}
