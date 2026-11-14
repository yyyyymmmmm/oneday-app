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

    /// 在线判定迟滞（0.36.20，§86.2，治审计 R1）：探
    /// 活成败先过 Core ConnectionLiveness 记账——连失
    /// 3 次才许把 hermesChannelUp 写 false，阈值前保持
    /// 上一结论（静默期不出断开文案）；任一成功（探
    /// 活或业务，见 noteBusinessSuccess）立即清零回写
    private var liveness = ConnectionLiveness()

    private let client = OverviewBridgeClient()
    private var isRefreshing = false

    /// 回告本机存档（§241 留存）：桥窗口只有最近 50
    /// 条且随桥易失——凡本机见过的通知都落进本档，
    /// 已读只翻标记、记录不清。通知面板的历史面读
    /// 本档与现行合并（ReportCardHistory），聊天页回
    /// 告卡仍只读现行未读，两面分工不混
    @ObservationIgnored private var archive: [OverviewNotification] = []
    @ObservationIgnored private var archiveLoaded = false
    /// 演示态不读存档、不露真实历史（演示分支置位）
    @ObservationIgnored private var demoMode = false

    /// 历史面数据源：现行 ∪ 存档（现行优先），演示
    /// 态退回现行（恒空）。通知面板列表/计数/详情取
    /// 数走本面；角标与回告卡不走本面
    var historyNotifications: [OverviewNotification] {
        guard !demoMode else { return notifications }
        loadArchiveIfNeeded()
        return ReportCardHistory.merge(
            live: notifications, archived: archive)
    }

    private static var archiveFileURL: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0]
        let dir = base.appendingPathComponent(
            "ReportCards", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("archive.json")
    }

    private func loadArchiveIfNeeded() {
        guard !archiveLoaded else { return }
        archiveLoaded = true
        guard let data = try? Data(contentsOf: Self.archiveFileURL),
              let items = try? JSONDecoder().decode(
                [OverviewNotification].self, from: data)
        else { return }
        archive = items
    }

    private func persistArchive() {
        guard let data = try? JSONEncoder().encode(archive)
        else { return }
        try? data.write(to: Self.archiveFileURL, options: .atomic)
    }

    /// 把一轮现行通知吸收进存档（加载成功即调用）：
    /// 合并后存档即历史全集，已读态以现行为准
    private func absorbIntoArchive(
        _ items: [OverviewNotification]
    ) {
        loadArchiveIfNeeded()
        archive = ReportCardHistory.merge(
            live: items, archived: archive)
        persistArchive()
    }

    /// 存档侧已读回写：现行标已读成功后同翻存档副本；
    /// 条目已滑出桥窗口（现行查无）时，存档副本就是
    /// 唯一记录面，直接翻本档
    private func markArchiveRead(id: String) {
        loadArchiveIfNeeded()
        guard let index = archive.firstIndex(where: { $0.id == id }),
              !archive[index].read else { return }
        archive[index].read = true
        persistArchive()
    }

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
            liveness = ConnectionLiveness()
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
            liveness.recordSuccess()
            hermesChannelUp = true
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        // 通道探活与桥取数相互独立、互不等待结论：探活
        // 失败只落 hermesChannelUp，桥失败只落 snapshot
        await probeChannel(appState: appState, config: config)
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

    /// 通道探活一轮（0.36.20，§86.2）：失败不立即翻脸
    /// ——先按 Core RetryBackoff 在轮内快速重探，连失
    /// 满阈值（3 次）才把 hermesChannelUp 写 false；任
    /// 一次成功即清零回写 true。任务取消（退后台）不
    /// 记账：取消不是失败，别让场景切换冒充断网
    private func probeChannel(
        appState: AppState, config: ServerConfig
    ) async {
        var failuresThisRound = 0
        while true {
            do {
                let health = try await appState.client.health(
                    config: config
                )
                // 通道判活经全仓统一派生（第 9 项）：
                // 此前只看「不抛错」——回执 status 非
                // ok 也算活；自此与连接页硬门同判词，
                // 非 ok 按失败进退避重探
                guard ServiceHealth.from(health: health) == .up else {
                    throw HermesError.healthCheckFailed(status: 200)
                }
                liveness.recordSuccess()
                hermesChannelUp = true
                return
            } catch {
                if Task.isCancelled { return }
                failuresThisRound += 1
                let verdict = liveness.recordFailure()
                if verdict == false {
                    hermesChannelUp = false
                    return
                }
                // 未达阈值：轮内快速重探（全抖动退避，
                // base 1.0/cap 4.0——与链接步同源策略、
                // 量级更小，静默期算式见 §86.5）
                let wait = RetryBackoff.delay(
                    afterFailure: failuresThisRound,
                    base: 1.0, cap: 4.0,
                    jitterUnit: Double.random(in: 0...1)
                )
                if wait > 0 {
                    try? await Task.sleep(for: .seconds(wait))
                }
                if Task.isCancelled { return }
            }
        }
    }

    /// 业务成功回写（0.36.20，§86.2）：Hermes 通道上任
    /// 一真实业务收到响应即算通道活证——计数清零、状
    /// 态立即回「在线」，不等下一轮探活（治审计 R4：
    /// 聊天明明刚收发成功、胶囊还挂着旧探活失败的
    /// 「联系不上」最长约 30 秒）
    func noteBusinessSuccess() {
        liveness.recordSuccess()
        if hermesChannelUp != true {
            hermesChannelUp = true
        }
    }

    func loadNotifications(appState: AppState) async {
        notificationsFailed = false
        demoMode = appState.isDemo
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
            installLoadedNotifications(
                try await client.notifications(config: config)
            )
            notificationsLoaded = true
            appState.overviewBridgeAuthFailed = false
            // §241 留存：先吸收进存档再走自动消账——被
            // 消账的回执也已在历史里，不因已读而丢记录
            absorbIntoArchive(notifications)
            // 0.36.5（联动 C 部）：本人裁决的回执一到
            // 即自动消账——按 refId 命中本人裁决集的
            // 未读回执逐条走既有 markRead 通道（§233
            // 起本地先落已读、角标同步减一，再向桥确
            // 认）；角标/
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

    /// 全部已读（0.36.7，规格 §3.5；§233 改本地先行）：
    /// 桥只有单条接口——**本地先把未读条目全标已读
    /// （角标同步清）**，再逐条向桥确认；返回值＝桥
    /// 确认是否全部成功，任一条没确认上即 false（本
    /// 地已读态不回滚，下轮名单以服务端为准纠正），
    /// 视图层据此给一句同步未成的提示
    func markAllRead(appState: AppState) async -> Bool {
        let pending = notifications.filter { !$0.read }.map(\.id)
        for id in pending { applyLocalRead(id: id) }
        guard let config = appState.config, !appState.isDemo
        else { return true }
        var allSucceeded = true
        for id in pending {
            let ok = (try? await client.markRead(
                config: config, id: id
            )) ?? false
            if !ok { allSucceeded = false }
        }
        return allSucceeded
    }

    /// 本地先落已读（§233 同步落点）：目标条换已读＋
    /// 快照未读数即时减一（封底 0）；条不在名单/已读
    /// 时返回 false 不动。通知已读是纯呈现态，先行不
    /// 等桥确认
    @discardableResult
    func applyLocalRead(id: String) -> Bool {
        guard let index = notifications.firstIndex(
                  where: { $0.id == id }
              ),
              !notifications[index].read else { return false }
        notifications[index].read = true
        if var current = snapshot, current.unreadNotifications > 0 {
            current.unreadNotifications -= 1
            snapshot = current
        }
        return true
    }

    /// 名单装载收口（load/测试共用一个落点）
    func installLoadedNotifications(
        _ loaded: [OverviewNotification]
    ) {
        notifications = loaded
    }

    /// 点开一条通知：**本地先落已读＋角标先减**，再向
    /// 桥确认（§233）；确认失败静默保留本地已读（纯
    /// 呈现态，下轮名单以服务端为准纠正，不打扰用
    /// 户），桥回执不成功同理
    func markRead(appState: AppState, id: String) async {
        guard applyLocalRead(id: id) else {
            // §241：条目已滑出桥窗口时存档是唯一记录
            // 面——桥无可确认，直接翻本档副本
            if !appState.isDemo { markArchiveRead(id: id) }
            return
        }
        guard let config = appState.config else { return }
        if appState.isDemo { return }
        // §241：本地已读同拍翻存档副本（存档＝历史
        // 面，与本地呈现态同源；桥确认仍走 §233 纪律）
        markArchiveRead(id: id)
        _ = try? await client.markRead(config: config, id: id)
    }
}
