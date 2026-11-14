import OneDayCore
import OneDayDesign
import SwiftUI
import UIKit

/// 浏览器面（P2 打通，0.9.0）：枢纽浏览器段与电脑面
/// （P9）桌面段共用同一面（施工图 §4.3）。三件事：
/// 状态读盒桥（不再读 9119 computer-use 错位源）、
/// 画面是盒桥回的云电脑真实截图、接管走盒桥一动作
/// 一回图。视觉按设计标准 §5.7/§7-P2：整屏预览
/// aspect 1.6、圆角 12；接管态顶条 ink 底白字。
struct BrowserFaceView: View {
    @Environment(AppState.self) private var appState
    @State private var store: BoxBridgeStore
    /// 轮询归属：独立面（枢纽浏览器段）自跑可见轮询；
    /// 电脑面（P9）由 ComputerView 统一驱动并注入同一
    /// store，这里关掉防双轮询
    private let managesLoop: Bool
    /// 状态卡归属：独立面自带状态卡；电脑面由其状态头
    /// 统一呈现（同一 store、同一口径），这里关掉防两套
    private let showsStatusCard: Bool
    @State private var viewerItem: ChatImageViewerItem?
    @State private var urlText = ""
    @State private var typeText = ""

    init(
        store: BoxBridgeStore? = nil,
        managesLoop: Bool = true,
        showsStatusCard: Bool = true
    ) {
        _store = State(initialValue: store ?? BoxBridgeStore())
        self.managesLoop = managesLoop
        self.showsStatusCard = showsStatusCard
    }

    var body: some View {
        ScrollView {
            VStack(spacing: OneDayMetrics.spacingM) {
                if store.takeover {
                    takeoverStrip
                }
                if showsStatusCard {
                    statusCard
                }
                screenCard
                controlArea
            }
            .padding(.horizontal, OneDayMetrics.pageGutter)
            .padding(.vertical, OneDayMetrics.spacingM)
        }
        .background(Palette.pageBG)
        .task {
            if managesLoop {
                await store.runVisibleLoop(appState: appState)
            }
        }
        // 接管态回写全局旗（0.10.0）：任务段的派发互斥
        // 读 AppState.boxTakeoverActive（P3 客户端半边）；
        // onAppear 只许置真不许清零——另一实例的面出现
        // 不能把正在接管的态冲掉，清零只走开关变化
        .onAppear {
            if store.takeover {
                appState.boxTakeoverActive = true
            }
        }
        .onChange(of: store.takeover) { _, newValue in
            appState.boxTakeoverActive = newValue
        }
        .fullScreenCover(item: $viewerItem) { item in
            // 0.36.4：截图查看并入统一查看器（单图集合）
            ImageViewerView(items: [item], initialIndex: 0)
        }
    }

    // MARK: - 接管顶条（设计标准 §7-P2 定式）

    private var takeoverStrip: some View {
        HStack(spacing: OneDayMetrics.spacingS) {
            Image(systemName: "hand.tap")
                .font(.system(size: 13, weight: .semibold))
            Text("接管中 · 智能体已暂停")
                .font(.subheadline.weight(.semibold))
            Spacer()
            Button("交还") {
                store.takeover = false
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.bordered)
            .tint(.white)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, OneDayMetrics.spacingM)
        .padding(.vertical, OneDayMetrics.spacingS)
        .background(
            Palette.ink, in: RoundedRectangle(cornerRadius: OneDayMetrics.radiusCard)
        )
    }

    // MARK: - 状态卡

    private var statusCard: some View {
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
                        .font(.system(size: 14, weight: .medium))
                }
                .buttonStyle(.odPressable)
                .foregroundStyle(Palette.inkSecondary)
                .accessibilityLabel("刷新状态")
            }
            switch store.hubState {
            case .ready(let status):
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
                    if let creditsLine = status.creditsLine {
                        Text(creditsLine)
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }
            case .bridgeUnavailable:
                Text("云电脑还没连上：先到「设置」里确认已经连接并登录，再回来刷新状态。")
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
    }

    // MARK: - 画面卡

    private var screenCard: some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
            screenPreview
            HStack(spacing: OneDayMetrics.spacingS) {
                if let captured = store.screenshot?.capturedAt {
                    Text("截于 \(BoxTimeText.hhmmss(captured))")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                }
                Spacer()
                if store.screenshotLoading || store.acting {
                    ProgressView()
                        .controlSize(.small)
                }
                Button {
                    Task { await store.refreshScreenshot(appState: appState) }
                } label: {
                    Label("刷新画面", systemImage: "arrow.clockwise")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .disabled(store.screenshotLoading || store.acting)
            }
            if store.screenshotFailed, store.screenshot != nil {
                Text("画面刷新失败，显示的是上一张截图。")
                    .font(.footnote)
                    .foregroundStyle(Palette.danger)
            }
        }
        .padding(OneDayMetrics.cardPadding)
        .background(
            Palette.surface,
            in: RoundedRectangle(cornerRadius: OneDayMetrics.containerCorner,
                        style: .continuous)
        )
    }

    @ViewBuilder
    private var screenPreview: some View {
        let aspect = store.screenshot?.aspect ?? 1.6
        ZStack {
            RoundedRectangle(cornerRadius: OneDayMetrics.radiusCard, style: .continuous)
                .fill(Color.white)
            if let data = store.screenshot?.imageData,
               let image = UIImage(data: data) {
                GeometryReader { proxy in
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(
                            width: proxy.size.width,
                            height: proxy.size.height
                        )
                        .contentShape(Rectangle())
                        .gesture(
                            SpatialTapGesture().onEnded { value in
                                handleScreenTap(
                                    at: value.location, in: proxy.size
                                )
                            }
                        )
                }
            } else if store.screenshotLoading {
                VStack(spacing: OneDayMetrics.spacingS) {
                    ProgressView()
                    Text("正在取画面…")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                }
            } else if store.screenshot != nil {
                Text("画面数据无法显示，请刷新。")
                    .font(.footnote)
                    .foregroundStyle(Palette.danger)
            } else if store.status?.isRunning == false {
                VStack(spacing: OneDayMetrics.spacingS) {
                    Image(systemName: "moon.zzz")
                        .font(.system(size: 22))
                        .foregroundStyle(Palette.inkMuted)
                    Text("云电脑休眠中")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                    Button("唤醒并查看") {
                        Task {
                            await store.refreshScreenshot(
                                appState: appState
                            )
                        }
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                Button("获取最新画面") {
                    Task {
                        await store.refreshScreenshot(appState: appState)
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .aspectRatio(aspect, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: OneDayMetrics.radiusCard, style: .continuous))
    }

    /// 画面点按分流：接管态＝按坐标换算发点击动作；
    /// 只读态＝打开全屏查看（复用 0.8.0 全屏查看件）
    private func handleScreenTap(at point: CGPoint, in size: CGSize) {
        guard let shot = store.screenshot,
              let data = shot.imageData else { return }
        if store.takeover {
            let imageSize = CGSize(
                width: shot.width, height: shot.height
            )
            guard let pixel = BoxCoordinateMapper.imagePoint(
                viewPoint: point, container: size, image: imageSize
            ) else { return }
            Task {
                await store.perform(
                    appState: appState, .click(x: pixel.x, y: pixel.y)
                )
            }
        } else {
            viewerItem = ChatImageViewerItem(source: .data(data))
        }
    }

    // MARK: - 控制区

    @ViewBuilder
    private var controlArea: some View {
        if store.takeover {
            takeoverControls
        } else {
            VStack(spacing: OneDayMetrics.spacingS) {
                Button {
                    store.takeover = true
                } label: {
                    Label("接管操作", systemImage: "hand.tap")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(store.status == nil || store.acting)
                if let note = store.actNote {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(Palette.danger)
                }
            }
        }
    }

    private var takeoverControls: some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingSM) {
            HStack(spacing: OneDayMetrics.spacingS) {
                TextField("输入网址", text: $urlText)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                Button("前往") {
                    guard let url = BoxAddressText.normalize(urlText)
                    else { return }
                    Task {
                        await store.perform(
                            appState: appState, .navigate(url)
                        )
                    }
                }
                .buttonStyle(.bordered)
                .disabled(store.acting)
            }
            HStack(spacing: OneDayMetrics.spacingS) {
                TextField("输入文字", text: $typeText)
                    .textFieldStyle(.roundedBorder)
                Button("输入") {
                    let text = typeText
                    guard !text.isEmpty else { return }
                    typeText = ""
                    Task {
                        await store.perform(
                            appState: appState, .type(text)
                        )
                    }
                }
                .buttonStyle(.bordered)
                .disabled(store.acting || typeText.isEmpty)
            }
            HStack(spacing: OneDayMetrics.spacingS) {
                keyButton("回车", key: "Enter")
                keyButton("退格", key: "Backspace")
                keyButton("Esc", key: "Escape")
                Spacer()
                if store.acting {
                    ProgressView().controlSize(.small)
                }
            }
            Text("点按画面即点击对应位置。")
                .font(.footnote)
                .foregroundStyle(Palette.inkSecondary)
            if let note = store.actNote {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(Palette.danger)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OneDayMetrics.cardPadding)
        .background(
            Palette.surface,
            in: RoundedRectangle(cornerRadius: OneDayMetrics.containerCorner,
                        style: .continuous)
        )
    }

    private func keyButton(_ title: String, key: String) -> some View {
        Button(title) {
            Task {
                await store.perform(appState: appState, .key(key))
            }
        }
        .buttonStyle(.bordered)
        .disabled(store.acting)
    }
}
