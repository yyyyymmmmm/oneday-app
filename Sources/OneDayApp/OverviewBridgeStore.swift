import Foundation
import OneDayCore

/// 总览桥状态持有（0.6.0 一期）：ContentView 壳层持有，
/// 聊天页顶栏（状态行＋铃铛角标）与通知 sheet 共同消费。
/// 轮询节律冻结为前台 30 秒一轮（poll 由壳层以 scenePhase
/// 为 task id 驱动：回前台自动重启、退后台自动取消）；
/// 不学 OpenMuse 的 3 秒快照轮询。桥失败/无钥匙时
/// snapshot 置 nil，状态行据纯函数落「暂时联系不上」，
/// 角标归 0——不拿上轮旧数冒充实时。
@MainActor
@Observable
final class OverviewBridgeStore {
    private(set) var snapshot: OverviewSnapshot?
    private(set) var notifications: [OverviewNotification] = []
    private(set) var notificationsLoaded = false
    private(set) var notificationsFailed = false

    private let client = OverviewBridgeClient()
    private var isRefreshing = false

    var statusLine: String {
        OverviewStatusLine.resolve(snapshot: snapshot)
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
            return
        }
        if appState.isDemo {
            // 演示态不发网络请求：只给中性演示快照
            snapshot = OverviewSnapshot(
                hermesUp: true, activeSessions: 0, pendingApprovals: 0,
                unreadNotifications: 0,
                generatedAt: ISO8601DateFormatter().string(from: Date())
            )
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            snapshot = try await client.overview(config: config)
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
        } catch {
            notifications = []
            notificationsLoaded = true
            notificationsFailed = true
        }
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
