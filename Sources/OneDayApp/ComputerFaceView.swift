import OneDayCore
import OneDayDesign
import SwiftUI
import UIKit
import WebKit

/// 电脑面（P9，0.15.0 转正；§493 归位中枢）：智能
/// 体的云电脑（Simular Box）完整一面——状态头＋三
/// 段：桌面（截图/接管）、文件、终端。
struct ComputerFaceView: View {
    @Environment(AppState.self) private var appState
    @State private var store = BoxBridgeStore()
    @State private var segment: Segment = .desktop
    @State private var takeoverTarget: CloudComputerTarget?

    private enum Segment: String, CaseIterable, Identifiable {
        case desktop = "桌面"
        case files = "文件"
        case terminal = "终端"

        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: OneDayMetrics.spacingM) {
            statusHeader
            Picker("电脑分段", selection: $segment) {
                ForEach(Segment.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, OneDayMetrics.pageGutter)
            segmentContent
        }
        .padding(.top, OneDayMetrics.spacingM)
        .background(Palette.pageBG)
        .task { await runLoop() }
        .onDisappear {
            if store.takeover {
                store.takeover = false
                appState.boxTakeoverActive = false
            }
        }
        .fullScreenCover(item: $takeoverTarget) { target in
            CloudComputerTakeoverSheet(
                target: target,
                store: store,
                onHandBackToAI: nil
            )
        }
    }

    @ViewBuilder
    private var segmentContent: some View {
        switch segment {
        case .desktop:
            BrowserFaceView(
                store: store, managesLoop: false, showsStatusCard: false
            )
        case .files:
            BoxFilesView()
        case .terminal:
            BoxTerminalView()
        }
    }

    private func runLoop() async {
        while !Task.isCancelled {
            await store.refreshStatus(appState: appState)
            if segment == .desktop,
               store.status?.isRunning == true, !store.takeover {
                await store.refreshScreenshot(appState: appState)
            }
            try? await Task.sleep(for: .seconds(10))
        }
    }

    private var statusHeader: some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
            HStack(spacing: OneDayMetrics.spacingS) {
                Circle()
                    .fill(
                        store.status?.isRunning == true
                            ? Palette.success : Palette.inkMuted
                    )
                    .frame(width: 9, height: 9)
                Text(store.hubState.statusLine)
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                Spacer()
                Button {
                    Task { await store.refreshStatus(appState: appState) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: FrameworkIcon.inlineGlyphSize, weight: .medium))
                        .frame(
                            width: OneDayMetrics.minTapTarget,
                            height: OneDayMetrics.minTapTarget
                        )
                        .contentShape(Rectangle())
                        .padding(-(OneDayMetrics.minTapTarget - 14) / 2)
                }
                .buttonStyle(.odPressable)
                .foregroundStyle(Palette.inkSecondary)
                .accessibilityLabel("刷新状态")
            }
            switch store.hubState {
            case .ready(let status):
                readyDetails(status)
            case .bridgeUnavailable:
                Text("云电脑还没连上：先到「设置 → 云电脑与远程主机」里配置密钥，再回来刷新状态。")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
            case .failed:
                Button("重试") {
                    Task { await store.refreshStatus(appState: appState) }
                }
                .buttonStyle(.bordered)
            case .loading:
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OneDayMetrics.cardPadding)
        .background(
            Palette.surface,
            in: RoundedRectangle(cornerRadius: OneDayMetrics.containerCorner,
                    style: .continuous)
        )
        .padding(.horizontal, OneDayMetrics.pageGutter)
    }

    @ViewBuilder
    private func readyDetails(_ status: BoxBridgeStatus) -> some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
            Text(status.pageTitleText)
                .font(.body)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
            let meta = status.pageMetaText()
            if !meta.isEmpty {
                Text(meta)
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(2)
            }
        }
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingXS) {
            if let name = status.name, !name.isEmpty {
                detailRow("名称", name)
            }
            if let imageLine = status.imageLine {
                detailRow("系统", imageLine)
            }
            if let saved = status.lastSavedAt {
                detailRow("最后保存", BoxTimeText.dateTime(saved))
            }
            if let creditsLine = status.creditsLine {
                detailRow("额度", creditsLine)
            }
        }
        HStack(spacing: OneDayMetrics.spacingS) {
            if !status.isRunning {
                Button("唤醒并查看") { wake() }
                    .buttonStyle(.bordered)
            }
            Button {
                takeoverTarget = CloudComputerTarget(
                    id: status.boxId ?? "live-box",
                    boxID: status.boxId,
                    liveURL: status.viewUrl ?? ""
                )
            } label: {
                Label("全屏接管控制", systemImage: "hand.tap.fill")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: OneDayMetrics.spacingS) {
            Text(label)
                .font(.footnote)
                .foregroundStyle(Palette.inkSecondary)
                .frame(width: 56, alignment: .leading)
            Text(value)
                .font(.footnote)
                .foregroundStyle(Palette.ink)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
    }

    private func wake() {
        segment = .desktop
        Task {
            await store.refreshScreenshot(appState: appState)
            await store.refreshStatus(appState: appState)
        }
    }
}

// MARK: - 聊天页大厂级云电脑预览卡（对标 Manus / OpenAI Operator）

/// 聊天流内联云电脑实时预览卡：
/// 彻底取代 AI 消息里裸露的操作网址，展示桌面缩略预览、在线状态与页面标题，
/// 点击卡片或「接管控制」按钮直接弹出全屏沉浸式接管页。
struct CloudComputerChatPreviewCard: View {
    let target: CloudComputerTarget
    let onTakeover: () -> Void

    @Environment(AppState.self) private var appState
    @State private var store = BoxBridgeStore()

    var body: some View {
        Button(action: onTakeover) {
            VStack(alignment: .leading, spacing: 0) {
                // 顶部状态条
                HStack(spacing: 8) {
                    Circle()
                        .fill(store.status?.isRunning == true ? Palette.success : Palette.primary)
                        .frame(width: 8, height: 8)
                    Text(headerTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    HStack(spacing: 4) {
                        Image(systemName: "hand.tap.fill")
                            .font(.caption.weight(.semibold))
                        Text("接管控制")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Palette.primary, in: Capsule())
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                // 桌面缩略图预览区
                ZStack {
                    Color(white: 0.09)
                    if let data = store.screenshot?.imageData,
                       let image = UIImage(data: data) {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 158)
                            .clipped()
                    } else {
                        VStack(spacing: 8) {
                            if store.screenshotLoading {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "desktopcomputer")
                                    .font(.system(size: 30, weight: .light))
                                    .foregroundStyle(Color.white.opacity(0.85))
                            }
                            Text(store.status?.isRunning == false ? "云电脑休眠中 · 点击唤醒并接管" : "点击进入全屏实时桌面")
                                .font(.caption)
                                .foregroundStyle(Color.white.opacity(0.75))
                        }
                    }

                    // 左下角实时画面角标
                    VStack {
                        Spacer()
                        HStack {
                            HStack(spacing: 4) {
                                Image(systemName: "play.rectangle.fill")
                                    .font(.caption2)
                                Text(subtitleText)
                                    .font(.caption2.weight(.medium))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.58), in: Capsule())
                            Spacer()
                        }
                        .padding(8)
                    }
                }
                .frame(height: 158)
                .clipped()
            }
            .background(Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: OneDayMetrics.radiusCard, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: OneDayMetrics.radiusCard, style: .continuous)
                    .strokeBorder(Palette.hairline, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: OneDayMetrics.radiusCard, style: .continuous))
        }
        .buttonStyle(.odPressable)
        .task(id: target.id) {
            await store.refreshStatus(appState: appState)
            if store.status?.isRunning == true {
                await store.refreshScreenshot(appState: appState)
            }
        }
    }

    private var headerTitle: String {
        if let status = store.status {
            return "云电脑 · \(status.stateText)"
        }
        return "云电脑 · 实时画面"
    }

    private var subtitleText: String {
        if let page = store.status?.page ?? store.status?.lastKnownPage, !page.titleText.isEmpty {
            return page.titleText
        }
        return "点击即可直接操作"
    }
}

// MARK: - 全屏沉浸式云电脑接管页（实时流 + 免登直控双模 + 横屏 + 交还给 AI 闭环）

struct CloudComputerTakeoverSheet: View {
    let target: CloudComputerTarget
    @State var store: BoxBridgeStore
    let onHandBackToAI: (() -> Void)?

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    enum ControlMode: String, CaseIterable, Identifiable {
        case liveStream = "实时流"
        case directControl = "免登直控"
        var id: String { rawValue }
    }

    @State private var mode: ControlMode = .liveStream
    @State private var isLandscape = false
    @State private var zoomScale: CGFloat = 1.0
    @State private var lastZoomScale: CGFloat = 1.0
    @State private var urlInput = ""
    @State private var textInput = ""
    @State private var showKeyboardBar = false
    @State private var webViewReloadToken = UUID()

    init(
        target: CloudComputerTarget,
        store: BoxBridgeStore? = nil,
        onHandBackToAI: (() -> Void)? = nil
    ) {
        self.target = target
        _store = State(initialValue: store ?? BoxBridgeStore())
        self.onHandBackToAI = onHandBackToAI
    }

    private var resolvedLiveURL: URL? {
        if !target.liveURL.isEmpty, let u = URL(string: target.liveURL) {
            return u
        }
        if let raw = store.status?.viewUrl, let u = URL(string: raw) {
            return u
        }
        return nil
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                topHUD
                if mode == .liveStream, let url = resolvedLiveURL {
                    LiveStreamWebView(url: url, reloadToken: webViewReloadToken)
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    directControlSurface
                }
            }
        }
        .statusBarHidden(isLandscape)
        .onAppear {
            store.takeover = true
            appState.boxTakeoverActive = true
        }
        .onDisappear {
            store.takeover = false
            appState.boxTakeoverActive = false
            if isLandscape {
                setOrientation(.portrait)
            }
        }
        .task {
            await store.refreshStatus(appState: appState)
            if resolvedLiveURL == nil {
                mode = .directControl
            }
            if mode == .directControl || store.screenshot == nil {
                await store.refreshScreenshot(appState: appState)
            }
        }
    }

    // MARK: 顶部悬浮控制栏

    private var topHUD: some View {
        HStack(spacing: 10) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.16), in: Circle())
            }
            .accessibilityLabel("关闭")

            Picker("控制模式", selection: $mode) {
                ForEach(ControlMode.allCases) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 180)
            .colorScheme(.dark)
            .onChange(of: mode) { _, newMode in
                if newMode == .directControl {
                    Task { await store.refreshScreenshot(appState: appState) }
                }
            }

            Spacer(minLength: 4)

            if mode == .liveStream {
                Button {
                    webViewReloadToken = UUID()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.16), in: Circle())
                }
                .accessibilityLabel("刷新实时流")
            }

            Button {
                toggleOrientation()
            } label: {
                Image(systemName: isLandscape ? "rectangle.portrait" : "rectangle.landscape")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.16), in: Circle())
            }
            .accessibilityLabel(isLandscape ? "切回竖屏" : "切换横屏")

            Button {
                handBack()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption.weight(.bold))
                    Text("交还给 AI")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Palette.success, in: Capsule())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.88))
    }

    // MARK: 免登直控面（支持缩放、单击/双击/长按右键、滚轮、快捷键、输入文字）

    private var directControlSurface: some View {
        VStack(spacing: 0) {
            ZStack {
                Color(white: 0.08)
                if let data = store.screenshot?.imageData,
                   let image = UIImage(data: data) {
                    GeometryReader { proxy in
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .scaleEffect(zoomScale)
                            .contentShape(Rectangle())
                            .gesture(
                                MagnificationGesture()
                                    .onChanged { value in
                                        zoomScale = min(max(lastZoomScale * value, 1.0), 3.5)
                                    }
                                    .onEnded { _ in
                                        lastZoomScale = zoomScale
                                    }
                            )
                            .simultaneousGesture(
                                SpatialTapGesture(count: 2).onEnded { value in
                                    performTap(at: value.location, in: proxy.size, doubleClick: true)
                                }
                            )
                            .simultaneousGesture(
                                SpatialTapGesture(count: 1).onEnded { value in
                                    performTap(at: value.location, in: proxy.size, doubleClick: false)
                                }
                            )
                    }
                } else {
                    VStack(spacing: 12) {
                        if store.screenshotLoading {
                            ProgressView().tint(.white)
                            Text("正在连接云电脑画面…")
                                .font(.footnote)
                                .foregroundStyle(.white.opacity(0.75))
                        } else {
                            Image(systemName: "desktopcomputer")
                                .font(.system(size: 36))
                                .foregroundStyle(.white.opacity(0.6))
                            Button("唤醒并获取画面") {
                                Task { await store.refreshScreenshot(appState: appState) }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }

                if store.acting {
                    VStack {
                        HStack(spacing: 6) {
                            ProgressView().tint(.white).controlSize(.small)
                            Text("执行中…")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.7), in: Capsule())
                        .padding(.top, 10)
                        Spacer()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            directControlDock
        }
    }

    private var directControlDock: some View {
        VStack(spacing: 8) {
            if let note = store.actNote {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(Palette.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if showKeyboardBar {
                HStack(spacing: 8) {
                    TextField("输入要打到电脑上的文字或密码", text: $textInput)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .submitLabel(.send)
                        .onSubmit { sendTypedText() }
                    Button("发送") { sendTypedText() }
                        .buttonStyle(.borderedProminent)
                        .disabled(store.acting || textInput.isEmpty)
                }
                HStack(spacing: 8) {
                    TextField("打开网址（如 accounts.google.com）", text: $urlInput)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    Button("前往") {
                        guard let u = BoxAddressText.normalize(urlInput) else { return }
                        urlInput = ""
                        Task { await store.perform(appState: appState, .navigate(u)) }
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.acting || urlInput.isEmpty)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    dockButton(showKeyboardBar ? "收起输入" : "输入/网址", icon: "keyboard") {
                        withAnimation(.snappy(duration: 0.2)) {
                            showKeyboardBar.toggle()
                        }
                    }
                    dockButton("刷新", icon: "arrow.clockwise") {
                        Task { await store.refreshScreenshot(appState: appState) }
                    }
                    dockButton("上滑", icon: "chevron.up") {
                        performCenterScroll(deltaY: -360)
                    }
                    dockButton("下滑", icon: "chevron.down") {
                        performCenterScroll(deltaY: 360)
                    }
                    dockButton("回车", icon: "return") {
                        Task { await store.perform(appState: appState, .key("Enter")) }
                    }
                    dockButton("Tab", icon: "arrow.right.to.line") {
                        Task { await store.perform(appState: appState, .key("Tab")) }
                    }
                    dockButton("退格", icon: "delete.left") {
                        Task { await store.perform(appState: appState, .key("Backspace")) }
                    }
                    dockButton("Esc", icon: "escape") {
                        Task { await store.perform(appState: appState, .key("Escape")) }
                    }
                    if zoomScale > 1.05 {
                        dockButton("重置缩放", icon: "arrow.down.right.and.arrow.up.left") {
                            zoomScale = 1.0
                            lastZoomScale = 1.0
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(white: 0.12))
    }

    private func dockButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                Text(title)
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.14), in: Capsule())
        }
        .disabled(store.acting)
    }

    private func sendTypedText() {
        let text = textInput
        guard !text.isEmpty else { return }
        textInput = ""
        Task { await store.perform(appState: appState, .type(text)) }
    }

    private func performTap(at point: CGPoint, in size: CGSize, doubleClick: Bool) {
        guard let shot = store.screenshot else { return }
        let imageSize = CGSize(width: shot.width, height: shot.height)
        guard let pixel = BoxCoordinateMapper.imagePoint(
            viewPoint: point, container: size, image: imageSize
        ) else { return }
        Haptics.impact(.light)
        Task {
            await store.perform(
                appState: appState,
                doubleClick ? .doubleClick(x: pixel.x, y: pixel.y) : .click(x: pixel.x, y: pixel.y)
            )
        }
    }

    private func performCenterScroll(deltaY: Int) {
        let w = store.screenshot?.width ?? 1024
        let h = store.screenshot?.height ?? 640
        Task {
            await store.perform(
                appState: appState,
                .scroll(x: w / 2, y: h / 2, deltaY: deltaY)
            )
        }
    }

    private func toggleOrientation() {
        isLandscape.toggle()
        setOrientation(isLandscape ? .landscapeRight : .portrait)
    }

    private func setOrientation(_ mask: UIInterfaceOrientationMask) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
    }

    private func handBack() {
        store.takeover = false
        appState.boxTakeoverActive = false
        if isLandscape {
            setOrientation(.portrait)
        }
        dismiss()
        if let onHandBackToAI {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                onHandBackToAI()
            }
        }
    }
}

/// 持久 Cookie 的实时流 WKWebView：首次登录一次云电脑厂商账号后自动保持登录态，
/// 支持 60fps 实时拖动、滚轮、键盘直输。
private struct LiveStreamWebView: UIViewRepresentable {
    let url: URL
    let reloadToken: UUID

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        context.coordinator.lastToken = reloadToken
        context.coordinator.lastURL = url
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if context.coordinator.lastToken != reloadToken || context.coordinator.lastURL != url {
            context.coordinator.lastToken = reloadToken
            context.coordinator.lastURL = url
            webView.load(URLRequest(url: url))
        }
    }

    final class Coordinator {
        var lastToken: UUID?
        var lastURL: URL?
    }
}
