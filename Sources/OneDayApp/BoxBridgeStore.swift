import Foundation
import OneDayCore

/// 盒桥状态持有（P2 浏览器面，枢纽浏览器段与应用格
/// 浏览器页共用一面、各自持有实例，轮询只在所属面
/// 可见时跑）：状态读盒桥 GET /status（不唤醒 Box），
/// 画面走 POST /screenshot（会唤醒——只在手动刷新、
/// 接管动作回图、或运行中轮询时取，休眠不自动唤醒
/// 烧额度）；接管走 POST /act 一动作一回图。
/// 桥鉴权失败（未粘钥匙/401）只落本面状态
/// （bridgeUnavailable），不许说成电脑离线；旧
/// AppState.overviewBridgeAuthFailed 旗全仓无读者，
/// 已随 §259 单源化退役，本面不再回写。
@MainActor
@Observable
final class BoxBridgeStore {
    private(set) var hubState: BoxBridgeHubState = .loading
    /// 最新截图（桥原图字节＋尺寸＋时刻）
    private(set) var screenshot: BoxScreenshot?
    private(set) var screenshotLoading = false
    private(set) var screenshotFailed = false
    /// 接管态（产品层互斥：单桌面无锁原语——接管中
    /// 停自动轮询、界面明示智能体已暂停；任务派发层
    /// 的真暂停随 P3 任务桥联动，本面先立呈现与通道）
    var takeover = false
    private(set) var acting = false
    /// 接管动作/导航的最近一次失败（人话，视图行内露）
    private(set) var actNote: String?
    /// 带鉴权票据的实时流地址（由 box_view_token 现取，避免 WKWebView 撞登录墙）
    private(set) var liveStreamURL: URL?
    private(set) var liveStreamLoading = false
    private(set) var liveStreamError: String?

    private let client = BoxBridgeClient()
    private var statusInFlight = false

    var status: BoxBridgeStatus? {
        if case .ready(let status) = hubState { return status }
        return nil
    }

    // MARK: - 实时流票据与交还上下文

    /// 拉取带鉴权票据的实时桌面流地址；若厂商未返回票据则回落到可用 viewUrl
    func refreshLiveStreamURL(appState: AppState, fallbackRawURL: String? = nil) async {
        guard !liveStreamLoading else { return }
        if appState.isDemo {
            if let raw = fallbackRawURL, let u = URL(string: raw) {
                liveStreamURL = u
            }
            return
        }
        guard let config = appState.config else {
            if let raw = fallbackRawURL ?? status?.viewUrl, let u = URL(string: raw) {
                liveStreamURL = u
            }
            return
        }
        liveStreamLoading = true
        liveStreamError = nil
        defer { liveStreamLoading = false }
        do {
            let tokenResult = try await client.viewToken(config: config)
            if let url = tokenResult.url {
                liveStreamURL = url
                return
            }
        } catch let error as BoxBridgeError {
            if case .failed(let msg) = error {
                liveStreamError = msg
            }
        } catch {
            liveStreamError = L10n.string("实时流票据获取失败，已尝试使用默认地址。")
        }
        let fallback = [fallbackRawURL, status?.viewUrl]
            .compactMap { $0 }
            .first { !$0.isEmpty }
        if let fallback, let u = URL(string: fallback) {
            liveStreamURL = u
        }
    }

    /// 交还给 AI 前刷新最新桌面状态与截图，拼出结构化交还摘要让智能体知道用户做了什么
    func prepareHandbackSummary(appState: AppState) async -> String {
        await refreshStatus(appState: appState)
        if status?.isRunning == true {
            await refreshScreenshot(appState: appState)
        }
        if let page = status?.page ?? status?.lastKnownPage,
           (!page.titleText.isEmpty || !page.url.isEmpty) {
            let titlePart = page.titleText.isEmpty ? "当前页面" : page.titleText
            let urlPart = page.url.isEmpty ? "" : " (\(page.url))"
            return "我已完成云电脑接管操作，请继续。\n当前页面：\(titlePart)\(urlPart)"
        }
        return "我已完成云电脑接管操作，请继续。"
    }

    // MARK: - 状态

/// §416 新鲜度普查豁免：显式刷新口——状态/截图按需现拉（判定表见 DESIGN §416）
    func refreshStatus(appState: AppState) async {
        guard !statusInFlight else { return }
        guard appState.phase == .connected, let config = appState.config else {
            hubState = .failed
            return
        }
        if appState.isDemo {
            hubState = .ready(Self.demoStatus)
            return
        }
        statusInFlight = true
        defer { statusInFlight = false }
        do {
            let fetched = try await client.status(config: config)
            hubState = .ready(fetched)
        } catch let error as BoxBridgeError {
            apply(error: error, appState: appState, target: .status)
        } catch {
            hubState = .failed
        }
    }

    // MARK: - 截图

    /// 取一张最新截图：Box 睡眠时桥会先唤醒（耗时较
    /// 长），调用方负责在 UI 上给等待态
    func refreshScreenshot(appState: AppState) async {
        guard !screenshotLoading, !acting else { return }
        guard let config = appState.config else { return }
        if appState.isDemo { return }
        screenshotLoading = true
        screenshotFailed = false
        defer { screenshotLoading = false }
        await fetchScreenshot(appState: appState, config: config)
    }

    /// 截图实取（无防重入 guard）：perform 在 acting
    /// 期间补截回图也走这里，guard 只守外部入口
    private func fetchScreenshot(
        appState: AppState, config: ServerConfig
    ) async {
        do {
            screenshot = try await client.screenshot(config: config)
        } catch let error as BoxBridgeError {
            screenshotFailed = true
            apply(error: error, appState: appState, target: .screenshot)
        } catch {
            screenshotFailed = true
        }
    }

    // MARK: - 接管动作

    /// 发一个接管动作：成功以回图换新画面（回图缺失
    /// 时补截一张）；失败把桥的人话错误留在 actNote，
    /// 画面保持上一张不许变黑
    func perform(appState: AppState, _ request: BoxActRequest) async {
        guard !acting, !screenshotLoading else { return }
        guard let config = appState.config else { return }
        if appState.isDemo {
            actNote = L10n.string("演示态不执行接管动作。")
            return
        }
        acting = true
        actNote = nil
        defer { acting = false }
        do {
            let response = try await client.act(
                config: config, request: request
            )
            if let shot = response.screenshot {
                screenshot = shot
            } else if let config = appState.config {
                await fetchScreenshot(appState: appState, config: config)
            }
            // 导航类动作回带新页面：顺手刷状态让标题/
            // 网址跟上（状态读不唤醒、成本低）
            if response.page != nil {
                await refreshStatus(appState: appState)
            }
        } catch let error as BoxBridgeError {
            switch error {
            case .noKey, .unauthorized:
                apply(error: error, appState: appState, target: .status)
                actNote = L10n.string("还没连上，这次操作没有发出去。")
            case .failed(let message):
                actNote = message
            }
        } catch {
            actNote = L10n.string("接管动作发送失败。")
        }
    }

    func clearActNote() {
        actNote = nil
    }

    // MARK: - 可见轮询

    /// 面可见期间的轮询主循环（视图 .task 驱动、面消
    /// 失即取消）：10 秒一轮状态；运行中且非接管态时
    /// 顺带刷新截图（休眠不自动唤醒、接管中不抢图）
    func runVisibleLoop(appState: AppState) async {
        while !Task.isCancelled {
            await refreshStatus(appState: appState)
            if status?.isRunning == true, !takeover {
                await refreshScreenshot(appState: appState)
            }
            try? await Task.sleep(for: .seconds(10))
        }
    }

    // MARK: - 错误归因

    private enum ErrorTarget { case status, screenshot }

    private func apply(
        error: BoxBridgeError, appState: AppState, target: ErrorTarget
    ) {
        switch error {
        case .noKey:
            if target == .status {
                hubState = .notConfigured
            }
        case .unauthorized:
            if target == .status {
                hubState = .bridgeUnavailable
            }
            // screenshot 目标也需要记录 noKey 状态，让 UI 能区分「缺钥匙」vs「网络失败」
            screenshotFailed = true
        case .failed:
            if target == .status {
                hubState = .failed
            }
            // screenshot 失败已在 fetchScreenshot 里置位，此处无需重复
        }
    }

    // MARK: - 演示态

    private static var demoStatus: BoxBridgeStatus {
        BoxBridgeStatus(
            state: "running", name: "main",
            page: BoxPageRef(
                title: "Example Domain", url: "https://example.com/"
            ),
            lastKnownPage: BoxPageRef(
                title: "Example Domain", url: "https://example.com/"
            )
        )
    }
}
