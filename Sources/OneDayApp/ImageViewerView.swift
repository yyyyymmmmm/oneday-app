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
    @Environment(AppState.self) private var appState

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
        // §144 翻页预取：当前页 ±1 预取 2048、±2 预
        // 取 1080（规格 §5.3 查看器口径）——翻过去
        // 时图已在缓存，不再逐页冷开
        .task(id: state.index) { prefetchNeighbors() }
    }

    private func prefetchNeighbors() {
        for offset in [-2, -1, 1, 2] {
            let index = state.index + offset
            guard items.indices.contains(index) else { continue }
            let neighbor = items[index]
            guard case .remotePath(let path) = neighbor.source
            else { continue }
            let tier: ImageRenditionTier =
                abs(offset) == 1 ? .detail : .viewer
            RemoteImagePipeline.shared.prefetch(
                path: path, mtime: neighbor.mtime, tier: tier,
                config: appState.config
            ) {
                try? await appState.performAdmin {
                    client, config in
                    try await client.fileData(
                        config: config, path: path)
                }
            }
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

// MARK: - 聊天侧转场承载（UIKit zoom，§245.2 试点）

/// Zoom 源视图登记表（动效规矩包 §245.2 试点）：聊天
/// 缩略图是 SwiftUI 视图、无现成 UIView 句柄——入口以
/// ZoomSourceAnchor 在缩略图同位挂一枚透明 UIView 并
/// 按图片条目 id 登记于此，呈现时 ZoomHostingController
/// 的源提供者按 id 取回。弱引用持有：缩略图滚出屏/被
/// 列表回收后登记自动失效，提供者返回 nil、转场按
/// Core ZoomTransitionPolicy 回标准呈现，不假放大。
final class ZoomSourceRegistry {
    static let shared = ZoomSourceRegistry()

    private final class WeakView {
        weak var view: UIView?
        init(_ view: UIView) { self.view = view }
    }

    private var table: [String: WeakView] = [:]
    private let lock = NSLock()

    func register(id: String, view: UIView) {
        lock.lock()
        defer { lock.unlock() }
        table[id] = WeakView(view)
    }

    /// 只注销同一实例的登记（同 id 后登记者不被前者误撤）
    func unregister(id: String, view: UIView) {
        lock.lock()
        defer { lock.unlock() }
        if table[id]?.view === view {
            table.removeValue(forKey: id)
        }
    }

    func view(for id: String) -> UIView? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = table[id] else { return nil }
        if entry.view == nil {
            table.removeValue(forKey: id)
            return nil
        }
        return entry.view
    }
}

/// Zoom 源锚点：铺满宿主（缩略图）帧的透明 UIView，
/// 不拦命中（调用方再叠 .allowsHitTesting(false) 双
/// 保险），出现/更新即登记、拆解即注销。仅 §245.2 试
/// 点面（聊天消息流图片两主面）挂载，其余入口不挂、
/// 提供者回 nil 走标准呈现。
struct ZoomSourceAnchor: UIViewRepresentable {
    let sourceID: String

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        ZoomSourceRegistry.shared.register(id: sourceID, view: view)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        ZoomSourceRegistry.shared.register(id: sourceID, view: view)
    }

    // 无 dismantle 注销：登记为弱引用，视图随缩略图
    // 离树释放后登记自动失效（提供者查死登记即清表）。
}

/// 聊天页呈现承载（0.36.4；§245.2 试点改造）：聊天页
/// 当前无 NavigationStack，zoom 转场走 UIKit 系统机
/// 制——宿主 VC 设 preferredTransition＝.zoom。试点前
/// 源提供者恒返回 nil（无源降级形态未验）；试点后按
/// Core ZoomTransitionPolicy 裁决：Reduce Motion 开
/// 启不设 zoom（标准呈现）；否则提供者按 sourceID 查
/// ZoomSourceRegistry，查到真源才长出、查不到回 nil
/// 由系统标准降级。聊天栈化时并轨 matchedTransition-
/// Source（文件侧已用），本承载随之退役。
struct ZoomTransitionCover<Content: View>:
    UIViewControllerRepresentable {
    /// 本次呈现的起始图片条目 id（会话集合的初始页）；
    /// nil＝调用方未声明源，转场恒标准呈现
    var sourceID: String? = nil
    @ViewBuilder var content: () -> Content

    func makeUIViewController(
        context: Context
    ) -> UIHostingController<Content> {
        ZoomHostingController(
            rootView: content(), sourceID: sourceID
        )
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
    private let sourceID: String?

    init(rootView: Content, sourceID: String?) {
        self.sourceID = sourceID
        super.init(rootView: rootView)
    }

    required init?(coder aDecoder: NSCoder) {
        self.sourceID = nil
        super.init(coder: aDecoder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // 裁决在呈现定型时问一次 Core 策略：Reduce
        // Motion 时不设 zoom；源可用性由提供者在转场
        // 发生时实时查表（登记随滚动生灭，定型时快照
        // 会过期），查不到即 nil＝该次回标准呈现——与
        // 策略「无源不 zoom」在效果上等价（见 §245.2）。
        let decision = ZoomTransitionPolicy.decide(
            reduceMotion: UIAccessibility.isReduceMotionEnabled,
            sourceAvailable: sourceID != nil
        )
        guard decision == .zoom, let sourceID else { return }
        preferredTransition = .zoom(
            options: UIViewController.Transition.ZoomOptions(),
            sourceViewProvider: { _ in
                ZoomSourceRegistry.shared.view(for: sourceID)
            }
        )
    }
}

// MARK: - 单页（图面加载＋双态呈现）

/// 查看器单页（§144 递进链重做）：状态机在 Core
/// ViewerImageProgression，宿主只按它呈现——
/// - 首帧＝种子图（入口已到手的图经管线内存/磁盘
///   播种带入），不许出现「白屏＋转圈」第一帧；
/// - 递进 1080（到达换图、网络新到且有种子在显时
///   淡变）→ 2048（静默换）→ 原图（只在首次放大
///   越界时下）；档位只升不降由状态机钉死；
/// - 三态：有图不许菊花；真冷开 300ms 后仍无图才
///   许菊花；无图失败落失败态＋重试（旧实现无重
///   试、失败只能退出重进——「再点一次才出图」的
///   一半成因在此）。
/// 卡态按图宽高比成卡（fitted 尺寸走 Core 纯函
/// 数）、沉浸态全幅；缩放本体复用 ZoomableImage-
/// View（UIScrollView 1–4×、双击 2.5×、单击回调
/// 切双态——单击须等双击落空才触发，识别器在承
/// 载层配好失败依赖）。本地字节图（刚发送的消
/// 息）是原图本体、直解不降档。
private struct ImageViewerPage: View {
    let item: ChatImageViewerItem
    let mode: ImageViewerMode
    let zoomResetToken: Int
    let onToggleMode: () -> Void
    let onZoomChange: (Bool) -> Void
    let onImageLoaded: (UIImage) -> Void

    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progression = ViewerImageProgression()
    @State private var displayedImage: UIImage?
    /// 换图淡变位：与 displayedImage 同一遍渲染写入，
    /// 只对 1080 档网络新到置真（ZoomableImageView
    /// 在 updateUIView 据此交叉淡变）
    @State private var fadeSwap = false
    @State private var showSpinner = false
    @State private var isZoomed = false
    /// 失败重试令牌（递增重跑加载链后半段）
    @State private var loadToken = 0
    /// 原图每页只请求一次
    @State private var originalRequested = false

    var body: some View {
        Group {
            if let displayedImage {
                zoomSurface(displayedImage)
            } else if progression.phase == .failed {
                failureView
            } else {
                // 真冷开：先只给底色（卡态页面底/沉
                // 浸黑底由宿主底色承担），300ms 后仍
                // 无图才出菊花
                ZStack {
                    Color.clear
                    if showSpinner {
                        ProgressView()
                            .tint(
                                mode == .card
                                    ? Palette.inkSecondary : .white
                            )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: item.id) { await startFresh() }
        .task(id: loadToken) {
            guard loadToken > 0 else { return }
            await loadChain()
        }
        // 菊花延时门：300ms 内出图就不许它出现（重
        // 试同理，键含 loadToken）
        .task(id: "\(item.id)#\(loadToken)") {
            try? await Task.sleep(for: .milliseconds(300))
            if progression.phase == .empty {
                showSpinner = true
            }
        }
        .onChange(of: isZoomed) { _, zoomed in
            onZoomChange(zoomed)
            if zoomed {
                Task { await loadOriginalIfNeeded() }
            }
        }
    }

    private var failureView: some View {
        VStack(spacing: OneDayMetrics.spacingS) {
            Image(systemName: "photo")
                .font(.system(size: 26))
            Text("图片没加载出来")
                .font(.callout)
            Button {
                if progression.retry() {
                    loadToken += 1
                }
            } label: {
                Text("重试")
                    .font(.callout.weight(.medium))
            }
            .buttonStyle(.odPressable)
            .padding(.top, OneDayMetrics.spacingXS)
        }
        .foregroundStyle(
            mode == .card ? Palette.inkSecondary : Color.white
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    onSingleTap: onToggleMode,
                    crossfadeOnSwap: fadeSwap
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
                onSingleTap: onToggleMode,
                crossfadeOnSwap: fadeSwap
            )
        }
    }

    // MARK: - 加载链

    private func startFresh() async {
        progression = ViewerImageProgression()
        displayedImage = nil
        fadeSwap = false
        showSpinner = false
        originalRequested = false
        await loadChain()
    }

    private func loadChain() async {
        switch item.source {
        case .data(let data):
            if let decoded = UIImage(data: data) {
                apply(tier: .original, image: decoded, fade: false)
                onImageLoaded(decoded)
            } else {
                progression.tierFailed()
            }
        case .remotePath(let path):
            // 种子先行：第一帧有图（管线内存/磁盘里
            // 入口已到手的那张）
            if displayedImage == nil,
               let seed = RemoteImagePipeline.shared.seedImage(
                   path: path, mtime: item.mtime) {
                progression.seedArrived()
                displayedImage = seed
                fadeSwap = false
            }
            guard let viewer = await pipelineImage(
                path: path, tier: .viewer) else {
                progression.tierFailed()
                return
            }
            apply(
                tier: .viewer, image: viewer,
                fade: displayedImage != nil && !reduceMotion)
            onImageLoaded(viewer)
            // 2048 静默补齐：换图无淡变、不打扰
            if let detail = await pipelineImage(
                path: path, tier: .detail) {
                apply(tier: .detail, image: detail, fade: false)
                onImageLoaded(detail)
            } else {
                progression.tierFailed()
            }
        }
    }

    /// 原图：只在首次放大时下（档位覆盖不足以支撑放
    /// 大细看时才值得这笔流量）；触发点取「首次进入
    /// 放大态」——缩放回写只有 Bool 口径，精确像素比
    /// 判定不在本包（§144 记账）
    private func loadOriginalIfNeeded() async {
        guard case .remotePath(let path) = item.source,
              !originalRequested,
              (progression.displayedTier ?? .seed) < .original
        else { return }
        originalRequested = true
        if let original = await pipelineImage(
            path: path, tier: .original) {
            apply(tier: .original, image: original, fade: false)
            onImageLoaded(original)
        }
    }

    /// 换图唯一口：状态机判升档（只升不降），升成才
    /// 真换 displayedImage，淡变位同遍写入
    private func apply(
        tier: ImageRenditionTier, image: UIImage, fade: Bool
    ) {
        let before = progression.displayedTier
        progression.tierArrived(tier)
        guard progression.displayedTier != before else { return }
        fadeSwap = fade
        displayedImage = image
    }

    private func pipelineImage(
        path: String, tier: ImageRenditionTier
    ) async -> UIImage? {
        await RemoteImagePipeline.shared.image(
            path: path, mtime: item.mtime, tier: tier,
            config: appState.config
        ) {
            try? await appState.performAdmin { client, config in
                try await client.fileData(
                    config: config, path: path)
            }
        }
    }
}
