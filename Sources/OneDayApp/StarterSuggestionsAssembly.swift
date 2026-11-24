import Foundation
import OneDayCore

/// §455 空态建议装配（App 侧）：把 AppState 已同步的
/// 真数据装成 Core 引擎的快照，并管已用/已弃记账的本
/// 地落盘。引擎只认快照（StarterSuggestions.swift），
/// 本层只管取数与记账，不新造服务端接口、不另拉数据。
@MainActor
enum StarterSuggestionsAssembly {

    // MARK: - 现算现排

    static func currentSuggestions(
        appState: AppState
    ) -> [StarterSuggestion] {
        StarterSuggestionsEngine.suggestions(
            context: currentContext(appState: appState)
        )
    }

    static func currentContext(
        appState: AppState, now: Date = Date()
    ) -> StarterContext {
        let suppressed = StarterSuggestionMarks.suppressedKeys(now: now)
        let hub = appState.sharedHubStore()
        let goalsStore = appState.sharedGoalsStore()
        let cronStore = appState.sharedCronStore()
        let libraryStore = appState.sharedLibraryListStore()

        // 冷启判定：任一数据源已就绪才算上下文成立；
        // 都没同步过时 hour 也传 nil，整面回落冷启三
        // 条（与旧形态首帧一致），数据到达后现算升级
        var approvalsReady = false
        if case .ready = hub.approvalState { approvalsReady = true }
        let anyReady = approvalsReady
            || goalsStore.loadState == .ready
            || cronStore.hasLoaded
            || libraryStore.deliverables != nil
        guard anyReady else {
            return StarterContext(suppressedKeys: suppressed)
        }

        // 待批（Hub 审核段 /pending 回读，与天内审批卡
        // 同一份数据）：指纹＝条数＋首尾 id，新待批到
        // 达或旧待批消解都会换指纹、旧抑制自动失效
        var pending: StarterContext.PendingApprovals?
        if case .ready(let records) = hub.approvalState,
           !records.isEmpty {
            pending = .init(
                count: records.count,
                token: "\(records.count)"
                    + "|\(records.first?.id ?? "")"
                    + "|\(records.last?.id ?? "")"
            )
        }

        // 目标：卡住的（blocked 或有失败任务）取最近活
        // 动一条进一级；在办的（running/waiting）取最
        // 近活动一条进二级，与卡住的那条不重复
        let activeGoals = goalsStore.goals.filter { $0.status == .active }
        let blocked = activeGoals
            .filter { goal in
                guard let activity = goal.activity else { return false }
                return activity.state == .blocked
                    || activity.failedCount > 0
            }
            .max {
                ($0.activity?.lastActivityAt ?? 0)
                    < ($1.activity?.lastActivityAt ?? 0)
            }
        var blockedContext: StarterContext.BlockedGoal?
        if let blocked {
            let activity = blocked.activity
            blockedContext = .init(
                id: blocked.id,
                title: blocked.title,
                token: "\(activity?.since ?? activity?.lastActivityAt ?? blocked.updatedAt)"
            )
        }
        let active = activeGoals
            .filter { goal in
                goal.id != blocked?.id
                    && (goal.activity?.state == .running
                        || goal.activity?.state == .waiting)
            }
            .max {
                ($0.activity?.lastActivityAt ?? 0)
                    < ($1.activity?.lastActivityAt ?? 0)
            }
        let activeContext = active.map {
            StarterContext.ActiveGoal(id: $0.id, title: $0.title)
        }

        // 定时：最近异常＝enabled 且 last_error 非空，
        // 取最近一次运行的那条；将跑＝24 小时内有
        // next_run_at 的个数
        let failed = cronStore.jobs
            .filter { $0.enabled && !($0.lastError ?? "").isEmpty }
            .max {
                (AdminFormat.iso($0.lastRunAt) ?? .distantPast)
                    < (AdminFormat.iso($1.lastRunAt) ?? .distantPast)
            }
        let failedContext = failed.map {
            StarterContext.FailedCronJob(
                id: $0.id,
                name: $0.name ?? $0.scheduleText,
                token: $0.lastRunAt ?? ""
            )
        }
        let upcomingCount = cronStore.jobs.filter { job in
            guard job.enabled,
                  let next = AdminFormat.iso(job.nextRunAt)
            else { return false }
            return next >= now
                && next <= now.addingTimeInterval(24 * 3600)
        }.count

        // 资源库：只读已同步/快照播种的交付物（该店刷
        // 新口要呈现面喂 fetch 闭包，聊天侧不新拉）；
        // 48 小时内的算「最近交付」
        var deliveryContext: StarterContext.RecentDelivery?
        if let deliverables = libraryStore.deliverables {
            let nowEpoch = now.timeIntervalSince1970
            let fresh = deliverables
                .filter { !$0.entry.isDirectory }
                .filter { item in
                    guard let mtime = item.entry.mtime else { return false }
                    return mtime <= nowEpoch + 3600
                        && nowEpoch - mtime <= 48 * 3600
                }
                .sorted {
                    ($0.entry.mtime ?? 0) > ($1.entry.mtime ?? 0)
                }
            if let newest = fresh.first {
                deliveryContext = .init(
                    newestName: newest.entry.name,
                    extraCount: fresh.count - 1,
                    token: "\(newest.entry.path)|\(newest.entry.mtime ?? 0)"
                )
            }
        }

        return StarterContext(
            pendingApprovals: pending,
            failedCronJob: failedContext,
            blockedGoal: blockedContext,
            activeGoal: activeContext,
            recentDelivery: deliveryContext,
            upcomingCronCount: upcomingCount,
            hour: Calendar.current.component(.hour, from: now),
            suppressedKeys: suppressed
        )
    }

    // MARK: - 加载触发（空态出现时调；各店自带懒加载
    // 与新鲜度门，重复调零请求或直接返回）

    static func loadContextIfNeeded(appState: AppState) async {
        await appState.sharedHubStore().loadApproval()
        await appState.sharedCronStore().loadIfNeeded()
        await appState.sharedGoalsStore().loadIfNeeded(appState: appState)
    }

    // MARK: - 记账

    static func markUsed(_ suggestion: StarterSuggestion) {
        StarterSuggestionMarks.markUsed(suggestion)
    }
}

/// 已用/已弃记账的本地落盘（UserDefaults 一份 JSON）：
/// 点过一条即记账，抑制窗内不再出；状态类建议的 key
/// 带状态指纹，状态变了自然重装，不靠窗长兜底。
@MainActor
enum StarterSuggestionMarks {
    private static let defaultsKey = "starterSuggestionMarks.v1"
    private static var cached: StarterSuggestionMarkBook?

    private static var book: StarterSuggestionMarkBook {
        if let cached { return cached }
        let loaded: StarterSuggestionMarkBook
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode(
               StarterSuggestionMarkBook.self, from: data
           ) {
            loaded = decoded
        } else {
            loaded = StarterSuggestionMarkBook()
        }
        cached = loaded
        return loaded
    }

    static func suppressedKeys(now: Date) -> Set<String> {
        book.suppressedKeys(now: now)
    }

    static func markUsed(
        _ suggestion: StarterSuggestion, now: Date = Date()
    ) {
        var updated = book
        updated.markUsed(
            key: suggestion.key, tier: suggestion.tier, at: now
        )
        updated.prune(now: now)
        cached = updated
        if let data = try? JSONEncoder().encode(updated) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}
