import OneDayCore
import OneDayDesign
import SwiftUI
import WebKit

/// 电脑面（P9，0.15.0 转正）：应用格「电脑」行的落点，
/// 把智能体的云电脑（Simular Box）做成完整一面——
/// 状态头＋三段：桌面（截图/接管）、文件、终端。
/// 单一事实源纪律：本面持有一份 BoxBridgeStore 并注入
/// 桌面段（BrowserFaceView 关掉自带轮询与状态卡），
/// 状态只在本面的状态头呈现一处；文件段就是文件格
/// 「电脑」段共用的同一个 BoxFilesView 组件。两处入口
/// （应用格行、文件格电脑段）不出现两套状态口径。
/// 轮询由本面统一驱动：状态 10 秒一轮；截图只在桌面
/// 段在场且电脑运行中时顺带刷新（休眠不自动唤醒烧
/// 额度，文件/终端段不为看不见的画面取图）。
/// 唤醒只走手动入口：状态头与桌面段的「唤醒并查看」
/// （桥在截图时才唤醒，状态读永不唤醒）。
struct ComputerView: View {
    var onBackToApps: (() -> Void)? = nil

    @Environment(AppState.self) private var appState
    @State private var store = BoxBridgeStore()
    @State private var segment: Segment = .desktop
    @State private var liveItem: LiveViewItem?

    private enum Segment: String, CaseIterable, Identifiable {
        case desktop = "桌面"
        case files = "文件"
        case terminal = "终端"

        var id: String { rawValue }
    }

    private struct LiveViewItem: Identifiable {
        let id = UUID()
        let url: URL
    }

    var body: some View {
        NavigationStack {
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
            .navigationTitle("电脑")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let onBackToApps {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: onBackToApps) {
                            Label("返回", systemImage: "chevron.left")
                        }
                    }
                }
            }
            .task { await runLoop() }
            // 离面收尾：接管旗由本面负责清零——接管中
            // 离开电脑面不得把「智能体已暂停」永久挂在
            // 任务派发上（store.takeover 的 onChange 在
            // 桌面段内回写，桌面段随本面一同卸载时补清）
            .onDisappear {
                if store.takeover {
                    store.takeover = false
                    appState.boxTakeoverActive = false
                }
            }
            .sheet(item: $liveItem) { item in
                liveSheet(item)
            }
        }
    }

    // MARK: - 分段内容

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

    // MARK: - 统一轮询

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

    // MARK: - 状态头（Box 状态面：状态/页面/镜像/保存/额度全真数据）

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
                        .font(.system(size: 14, weight: .medium))
                }
                .buttonStyle(.odPressable)
                .foregroundStyle(Palette.inkSecondary)
                .accessibilityLabel("刷新状态")
            }
            switch store.hubState {
            case .ready(let status):
                readyDetails(status)
            case .bridgeUnavailable:
                Text("云电脑走桥钥匙的云电脑分项（未配时回退旧共用钥），在「设置 · 桥钥匙」粘贴或导入后生效。")
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
            in: RoundedRectangle(cornerRadius: 23, style: .continuous)
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
                detailRow("镜像", imageLine)
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
            if let raw = status.viewUrl, let url = URL(string: raw) {
                Button("实时视图") {
                    liveItem = LiveViewItem(url: url)
                }
                .buttonStyle(.bordered)
            }
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

    /// 手动唤醒：切到桌面段并取一张截图（桥在截图时
    /// 才唤醒 Box）；唤醒后顺手刷一次状态让状态头跟上。
    /// 状态读本身永不唤醒——这里走的是截图通道。
    private func wake() {
        segment = .desktop
        Task {
            await store.refreshScreenshot(appState: appState)
            await store.refreshStatus(appState: appState)
        }
    }

    // MARK: - 厂商实时视图（通道 A：状态里的 viewUrl 直开）

    private func liveSheet(_ item: LiveViewItem) -> some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text("厂商实时画面（与网页端同一个桌面）。首次打开可能需要登录你的 Simular 账号；连续操作（拖动、滚动）在这里做，回合制接管在「桌面」段。")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, OneDayMetrics.pageGutter)
                    .padding(.vertical, OneDayMetrics.spacingS)
                VendorWebView(url: item.url)
            }
            .background(Palette.pageBG)
            .navigationTitle("实时视图")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { liveItem = nil }
                }
            }
        }
    }
}

/// 厂商实时视图的 WKWebView 薄包装：只装载状态回的
/// viewUrl，不注入脚本、不读页面内容
private struct VendorWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}
