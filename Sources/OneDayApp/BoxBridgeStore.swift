import Foundation
import OneDayCore

/// 盒桥状态持有（P2 浏览器面，枢纽浏览器段与应用格
/// 浏览器页共用一面、各自持有实例，轮询只在所属面
/// 可见时跑）：状态读盒桥 GET /status（不唤醒 Box），
/// 画面走 POST /screenshot（会唤醒——只在手动刷新、
/// 接管动作回图、或运行中轮询时取，休眠不自动唤醒
/// 烧额度）；接管走 POST /act 一动作一回图。
/// 桥鉴权失败（未粘钥匙/401）回写 AppState 的
/// overviewBridgeAuthFailed 旗（同一把钥匙、同一「桥
/// 未连接」口径，设置页露面），不许说成电脑离线。
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

    private let client = BoxBridgeClient()
    private var statusInFlight = false

    var status: BoxBridgeStatus? {
        if case .ready(let status) = hubState { return status }
        return nil
    }

    // MARK: - 状态

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
            appState.overviewBridgeAuthFailed = false
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
            appState.overviewBridgeAuthFailed = false
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
            appState.overviewBridgeAuthFailed = false
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
        case .noKey, .unauthorized:
            appState.overviewBridgeAuthFailed = true
            if target == .status {
                hubState = .bridgeUnavailable
            }
        case .failed:
            if target == .status {
                hubState = .failed
            }
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
