import Foundation
import OneDayCore

/// 总览桥状态持有（0.6.0 一期）：ContentView 壳层持有，
/// 聊天页顶栏（状态行＋铃铛角标）与通知 sheet 共同消费。
/// 轮询节律冻结为前台 30 秒一轮（poll 由壳层以 scenePhase
/// 为 task id 驱动：回前台自动重启、退后台自动取消）；
/// 不学 OpenMuse 的 3 秒快照轮询。桥失败/无钥匙时
/// snapshot 置 nil、角标归 0——不拿上轮旧数冒充实时。
///
/// 0.7.0 通道口径修正（用户 16:05 真机截图坐实）：桥
/// 与 Hermes API 通道是两条独立链——每轮刷新除桥取数
/// 外另直探 Hermes /health（hermesChannelUp），状态行
/// 的「联系不上」只认通道探活（见 Core 的
/// OverviewStatusLine 新口径）；桥鉴权失败（未粘钥匙/
/// 401）只回写 AppState.overviewBridgeAuthFailed 供设
/// 置页露「桥未连接」，不许污染胶囊状态。
@MainActor
@Observable
final class OverviewBridgeStore {
    private(set) var snapshot: OverviewSnapshot?
    private(set) var notifications: [OverviewNotification] = []
    private(set) var notificationsLoaded = false
    private(set) var notificationsFailed = false
    /// Hermes API 通道探活（直探 /health，与桥独立）：
    /// nil＝尚未探到，状态行退回桥快照口径
    private(set) var hermesChannelUp: Bool?

    private let client = OverviewBridgeClient()
    private var isRefreshing = false

    var statusLine: String {
        OverviewStatusLine.resolve(
            snapshot: snapshot, hermesChannelUp: hermesChannelUp
        )
    }

    /// 状态点语气（0.19.0）：与 statusLine 同源（Core
    /// classify 一处判定），胶囊点色只认它，不许 App 层
    /// 再拿桥快照另立判定（旧色源与词两源分叉、词报
    /// 「在线」点落灰，用户 22:26 真机点名）
    var statusTone: OverviewStatusLine.Tone {
        OverviewStatusLine.tone(
            snapshot: snapshot, hermesChannelUp: hermesChannelUp
        )
    }

    var badgeCount: Int {
        OverviewBadge.count(snapshot: snapshot)
    }

    /// 前台轮询主循环：立即一轮，之后每 30 秒一轮；
    /// 任务取消（退后台/壳层消失）即停。
    func poll(appState: AppState) async {
        while !Task.isCancelled {
            await refresh(appState: appState)
            try? await Task.sleep(for: .seconds(30))
        }
    }

    func refresh(appState: AppState) async {
        guard !isRefreshing else { return }
        guard appState.phase == .connected, let config = appState.config else {
            snapshot = nil
            hermesChannelUp = nil
            appState.overviewBridgeAuthFailed = false
            return
        }
        if appState.isDemo {
            // 演示态不发网络请求：只给中性演示快照
            snapshot = OverviewSnapshot(
                hermesUp: true, activeSessions: 0, pendingApprovals: 0,
                unreadNotifications: 0,
                generatedAt: ISO8601DateFormatter().string(from: Date())
            )
            hermesChannelUp = true
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        // 通道探活与桥取数相互独立、互不等待结论：探活
        // 失败只落 hermesChannelUp，桥失败只落 snapshot
        do {
            _ = try await appState.client.health(config: config)
            hermesChannelUp = true
        } catch {
            hermesChannelUp = false
        }
        do {
            snapshot = try await client.overview(config: config)
            appState.overviewBridgeAuthFailed = false
        } catch let error as OverviewBridgeError {
            snapshot = nil
            // 只有钥匙类失败（未粘/被拒）才点「桥未连接」
            // 旗；网络类失败不归因于钥匙、旗保持原值
            if error == .noKey || error == .unauthorized {
                appState.overviewBridgeAuthFailed = true
            }
        } catch {
            snapshot = nil
        }
    }

    func loadNotifications(appState: AppState) async {
        notificationsFailed = false
        guard let config = appState.config else {
            notifications = []
            notificationsLoaded = true
            notificationsFailed = true
            return
        }
        if appState.isDemo {
            notifications = []
            notificationsLoaded = true
            return
        }
        do {
            notifications = try await client.notifications(config: config)
            notificationsLoaded = true
            appState.overviewBridgeAuthFailed = false
            // 0.36.5（联动 C 部）：本人裁决的回执一到
            // 即自动消账——按 refId 命中本人裁决集的
            // 未读回执逐条走既有 markRead 通道（桥确
            // 认后才改本地态、角标同步减一）；角标/
            // 通知列表/聊天回告卡读同一份状态、三处
            // 同消。桥未带 refId（未升级）时判定恒空、
            // 本段无动作
            for id in ApprovalResolution.receiptsToResolve(
                notifications: notifications,
                selfDecidedIDs: appState.selfDecidedApprovalIDs
            ) {
                await markRead(appState: appState, id: id)
            }
        } catch let error as OverviewBridgeError {
            notifications = []
            notificationsLoaded = true
            notificationsFailed = true
            if error == .noKey || error == .unauthorized {
                appState.overviewBridgeAuthFailed = true
            }
        } catch {
            notifications = []
            notificationsLoaded = true
            notificationsFailed = true
        }
    }

    /// 全部已读（0.36.7，规格 §3.5）：桥只有单条接
    /// 口，客户端对未读条目逐条顺序确认——只改确认
    /// 成功的本地态，返回是否全部成功；任一条失败
    /// 即 false、该条保持未读（不许假装全清），提
    /// 示文案归视图层按 S10 呈现。
    func markAllRead(appState: AppState) async -> Bool {
        let pending = notifications.filter { !$0.read }.map(\.id)
        var allSucceeded = true
        for id in pending {
            await markRead(appState: appState, id: id)
            let item = notifications.first(where: { $0.id == id })
            if let item, !item.read {
                allSucceeded = false
            }
        }
        return allSucceeded
    }

    /// 点开一条通知：先向桥确认已读，成功才改本地态与
    /// 角标（快照未读数同步减一）；失败保留未读，不假报。
    func markRead(appState: AppState, id: String) async {
        guard let config = appState.config,
              let index = notifications.firstIndex(where: { $0.id == id }),
              !notifications[index].read else { return }
        if appState.isDemo { return }
        do {
            let ok = try await client.markRead(config: config, id: id)
            guard ok else { return }
            notifications[index].read = true
            if var current = snapshot, current.unreadNotifications > 0 {
                current.unreadNotifications -= 1
                snapshot = current
            }
        } catch {
            // 已读没发出去：保持未读，下次点开重试
        }
    }
}
