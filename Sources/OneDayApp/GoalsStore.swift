import Foundation
import OneDayCore

/// 目标数据中枢（P4，0.11.0）：oneday-bridge 目标仓的
/// 唯一状态面。口径（与 KanbanStore 同纪律）：
/// ①桥未连接/未开通如实露（noKey/401＝钥匙问题、
/// 集合 404＝桥未开通），绝不拿假数据顶；②写动作分
/// 档（§233）：表单保存/创建/删除等确认类仍回读对
/// 账才算完成；**轻动作（完成态流转）改乐观**——先
/// 翻本地呈现、后台保存，失败恢复原状＋行内提示；
/// ③已就绪时刷新失败保持旧数据不翻态。
@MainActor
@Observable
final class GoalsStore {
    enum LoadState: Equatable {
        case loading
        /// 桥未连接/未开通（消息说清是哪一种）
        case notConnected(String)
        case failed(String)
        case ready
    }

    private(set) var loadState: LoadState = .loading
    private(set) var goals: [BridgeGoal] = []
    /// 正在执行写动作的目标 id（只禁用当前行）
    private(set) var actingIDs: Set<String> = []
    /// 行内提示（未确认/失败的人话，不弹模态）
    private(set) var notes: [String: String] = [:]
    private(set) var creating = false
    private(set) var createError: String?
    /// 详情面数据（P2）：按目标 id 分仓的条目流与简报，
    /// 只在进详情时拉、写后回读刷新——呈现读的永远是
    /// 桥的现值，本地不另立账（审计 R 档口径）
    private(set) var entriesByGoal: [String: [BridgeGoalEntry]] = [:]
    private(set) var briefingsByGoal: [String: [BridgeBriefing]] = [:]
    /// 详情面关联任务实时行（GD-2 读面一）：桥把任务的
    /// goalId 字段与任务板现况拼好的行，与条目/简报同
    /// 纪律进详情时拉、写后回读刷新，本地不另立账；
    /// §308 起关联判定只读行自带的 goalId（单轨真值），
    /// 回响物化与关联段呈现都读这一面
    private(set) var goalTasksByGoal:
        [String: [BridgeGoalTask]] = [:]
    /// 未归类任务（GD-2 读面二）：用户发起类（点子
    /// 采纳/对话派发）且未归任何目标的任务，随列表
    /// load 一并拉；失败保持旧值、不翻主 loadState
    private(set) var ungroupedTasks: [BridgeUngroupedTask] = []
    /// 未归类区的人话提示（归组失败时任务原样留在
    /// 面上，这行说明发生了什么）
    private(set) var ungroupedNote: String?
    /// 详情面已拉过至少一次的目标（区分「还没拉」与
    /// 「拉过、确实为空」——空态不许靠猜）
    private(set) var detailLoadedIDs: Set<String> = []

    private let client: OneDayBridgeClientProtocol
    private var loadInFlight = false
    /// 新鲜度门（§367）：读触发先过门，TTL 内零请求
    private var freshness = FreshnessGate(
        ttl: FreshnessGate.standardListTTL
    )

    init(client: OneDayBridgeClientProtocol = OneDayBridgeClient()) {
        self.client = client
    }

    func goal(id: String) -> BridgeGoal? {
        goals.first { $0.id == id }
    }

    func children(of goalID: String) -> [BridgeGoal] {
        GoalBoard.children(of: goalID, in: goals)
    }

    // MARK: - 加载

    /// 读触发入口（§367 新鲜度门）：TTL 内且配置没变
    /// 直接用已载数据、零请求；首载/过期/换服务器才
    /// 走 load 全量。下拉刷新与错误态重试不经此门、
    /// 恒走 load 强制
    func loadIfNeeded(appState: AppState) async {
        await loadIfNeeded(appState: appState, now: Date())
    }

    /// 时刻注入的门控本体（钉测用：推进时刻验过期）
    func loadIfNeeded(appState: AppState, now: Date) async {
        guard !freshness.isFresh(
            configKey: appState.config?.baseString, now: now
        ) else { return }
        await load(appState: appState, now: now)
    }

    func load(appState: AppState, now: Date = Date()) async {
        guard !loadInFlight else { return }
        guard let config = appState.config else {
            loadState = .failed(L10n.string("尚未连接服务器。"))
            return
        }
        loadInFlight = true
        defer { loadInFlight = false }
        do {
            installLoadedGoals(
                try await client.goals(config: config)
            )
            loadState = .ready
            freshness.stamp(configKey: config.baseString, now: now)
            await refreshUngrouped(appState: appState)
        } catch let error as OneDayBridgeError {
            if loadState == .ready { return }
            loadState = Self.state(for: error)
        } catch {
            if loadState == .ready { return }
            loadState = .failed(L10n.string("目标没读出来，可能是网络或服务暂时没响应"))
        }
    }

    /// 静默回读（写动作确认专用）：失败不翻态、不动旧数
    private func refetch(appState: AppState) async {
        guard let config = appState.config else { return }
        if let fetched = try? await client.goals(config: config) {
            installLoadedGoals(fetched)
            // 写后回读即全量现值：落账新鲜度（回读本身
            // 不经门、不许被门跳过，§367.4）
            freshness.stamp(
                configKey: config.baseString, now: Date()
            )
        }
    }

    /// 名单装载收口（load/回读/测试共用一个落点）
    func installLoadedGoals(_ loaded: [BridgeGoal]) {
        goals = loaded
        goalFingerprints = Dictionary(
            uniqueKeysWithValues: loaded.map {
                ($0.id, $0.entriesFingerprint ?? "")
            }
        )
    }

    /// 上次装载名单的条目指纹集（G-3a 在面重验的比对底）
    private(set) var goalFingerprints: [String: String] = [:]

    /// G-3a（2026-11-24）在面指纹重验：目标面可见期间
    /// 视图每 30 秒调一次——拉一遍目标列表与指纹集比
    /// 对，全等则什么都不做（零呈现扰动）；有变才装
    /// 载新名单，并给「详情已打开过且指纹变了」的目标
    /// 回拉条目流（智能体新记的进展、看板回声不用退
    /// 出重进就能看见）。失败静默保持现值（与刷新失
    /// 败同纪律）
    func revalidateFingerprints(appState: AppState) async {
        guard loadState == .ready,
              let config = appState.config else { return }
        guard let fetched = try? await client.goals(
            config: config
        ) else { return }
        let newMap = Dictionary(
            uniqueKeysWithValues: fetched.map {
                ($0.id, $0.entriesFingerprint ?? "")
            }
        )
        guard newMap != goalFingerprints else { return }
        let changedIDs = fetched
            .filter {
                goalFingerprints[$0.id] != ($0.entriesFingerprint ?? "")
            }
            .map(\.id)
        installLoadedGoals(fetched)
        for gid in changedIDs where detailLoadedIDs.contains(gid) {
            await refetchEntries(appState: appState, goalID: gid)
        }
    }

    /// 乐观呈现落点（§233）：以同 id 副本整行替换本
    /// 地呈现（勾选/状态流转的即时翻面与失败恢复共
    /// 用）；名单里没有该 id 时不动
    func applyGoal(_ goal: BridgeGoal) {
        goals = goals.map { $0.id == goal.id ? goal : $0 }
    }

    static func state(for error: OneDayBridgeError) -> LoadState {
        switch error {
        case .noKey:
            return .notConnected(
                L10n.string("还没有可用的登录信息：目标和点子用的是你的 Hermes 登录。先到「设置」里确认已经连接并登录，就能用了。")
            )
        case .unauthorized:
            return .notConnected(
                L10n.string("服务器拒绝了这次登录。请到「设置」里检查登录是否还有效。")
            )
        case .bridgeMissing:
            return .notConnected(L10n.string("服务器上这项服务还没有开通。"))
        case .recordGone:
            return .failed(L10n.string("这条记录已经不在了，请刷新后重试。"))
        case .failed(let message):
            return .failed(message)
        }
    }

    static func message(for error: OneDayBridgeError) -> String {
        switch error {
        case .noKey:
            return L10n.string("还没连上你的服务：还没有可用的登录信息。")
        case .unauthorized:
            return L10n.string("还没连上你的服务：服务器拒绝了这次登录。")
        case .bridgeMissing:
            return L10n.string("服务器上这项服务还没有开通。")
        case .recordGone:
            return L10n.string("这条记录已经不在了。")
        case .failed(let message):
            return message
        }
    }

    // MARK: - 新建（POST→回读确认出现才算完成）

    func create(
        appState: AppState, title: String, note: String,
        parentId: String? = nil,
        category: GoalCategory? = nil
    ) async -> Bool {
        guard !creating else { return false }
        guard let config = appState.config else {
            createError = L10n.string("尚未连接服务器。")
            return false
        }
        creating = true
        createError = nil
        defer { creating = false }
        let request = BridgeGoalCreateRequest.make(
            title: title, note: note,
            parentId: parentId, category: category
        )
        do {
            let created = try await client.createGoal(
                config: config, request: request
            )
            await refetch(appState: appState)
            if goals.contains(where: { $0.id == created.id }) {
                return true
            }
            createError = L10n.string("目标已提交，但还没有在列表里确认出现，请关闭后刷新核对。")
            return false
        } catch let error as OneDayBridgeError {
            createError = Self.message(for: error)
            return false
        } catch {
            createError = L10n.string("目标创建失败，请稍后再试。")
            return false
        }
    }

    // MARK: - 编辑保存（PATCH 全量→回读确认字段一致）

    /// 改标题/备注走此路：PATCH 体只带标题/备注
    /// （G-6 里程碑移除后编辑面无第三项），回读后对账
    /// （标题/备注全等）才算保存成功
    func saveEdits(
        appState: AppState, goalID: String, title: String,
        note: String
    ) async -> Bool {
        guard !actingIDs.contains(goalID) else { return false }
        guard let config = appState.config else {
            notes[goalID] = L10n.string("尚未连接服务器。")
            return false
        }
        actingIDs.insert(goalID)
        notes.removeValue(forKey: goalID)
        defer { actingIDs.remove(goalID) }
        let request = BridgeGoalPatchRequest.edited(
            title: title, note: note
        )
        do {
            _ = try await client.patchGoal(
                config: config, id: goalID, request: request
            )
            await refetch(appState: appState)
            guard let current = goal(id: goalID) else {
                notes[goalID] = L10n.string("保存已发出，但再确认时目标不见了，请刷新核对。")
                return false
            }
            let confirmed = current.title == request.title
                && current.note == request.note
            if confirmed {
                return true
            }
            notes[goalID] = L10n.string("保存已发出，但再确认时内容对不上，请刷新核对。")
            return false
        } catch let error as OneDayBridgeError {
            notes[goalID] = Self.message(for: error)
            return false
        } catch {
            notes[goalID] = L10n.string("保存失败，请稍后再试。")
            return false
        }
    }

    // MARK: - 删除（DELETE→回读确认消失才算完成）

    func delete(appState: AppState, goalID: String) async -> Bool {
        guard !actingIDs.contains(goalID) else { return false }
        guard let config = appState.config else {
            notes[goalID] = L10n.string("尚未连接服务器。")
            return false
        }
        actingIDs.insert(goalID)
        notes.removeValue(forKey: goalID)
        defer { actingIDs.remove(goalID) }
        do {
            try await client.deleteGoal(config: config, id: goalID)
            await refetch(appState: appState)
            if goal(id: goalID) == nil {
                return true
            }
            notes[goalID] = L10n.string("删除已发出，但列表里还在，请刷新核对。")
            return false
        } catch let error as OneDayBridgeError {
            // 记录本就已不在＝删除目的已达（回读同口径）
            if case .recordGone = error {
                await refetch(appState: appState)
                return goal(id: goalID) == nil
            }
            notes[goalID] = Self.message(for: error)
            return false
        } catch {
            notes[goalID] = L10n.string("删除失败，请稍后再试。")
            return false
        }
    }

    // MARK: - 状态流转（§233 乐观：先翻呈现，后台 PATCH＋回读对账）

    /// 标完成/重新打开：**调用当拍先翻本地状态**（完
    /// 成态与 completedAt 本地占位），后台 PATCH 后
    /// 回读对账（状态一致、完成时 completedAt 非空、
    /// 重开时为空）才算落定；网络失败恢复原状＋行内
    /// 提示，回读对不上时呈现已随回读回到服务端现值、
    /// 只留提示
    func setStatus(
        appState: AppState, goalID: String, status: GoalStatus
    ) async -> Bool {
        guard !actingIDs.contains(goalID) else { return false }
        guard let original = goal(id: goalID) else { return false }
        guard let config = appState.config else {
            notes[goalID] = L10n.string("尚未连接服务器。")
            return false
        }
        actingIDs.insert(goalID)
        notes.removeValue(forKey: goalID)
        defer { actingIDs.remove(goalID) }
        applyGoal(original.withStatus(
            status,
            completedAt: status == .completed
                ? Date().timeIntervalSince1970 : nil
        ))
        do {
            _ = try await client.patchGoalStatus(
                config: config, id: goalID, status: status
            )
            await refetch(appState: appState)
            guard let current = goal(id: goalID) else {
                notes[goalID] = L10n.string("状态已提交，但再确认时目标不见了，请刷新核对。")
                return false
            }
            let confirmed = current.status == status
                && (status == .completed
                    ? current.completedAt != nil
                    : current.completedAt == nil)
            if confirmed {
                return true
            }
            notes[goalID] = L10n.string("状态已提交，但再确认时对不上，请刷新核对。")
            return false
        } catch let error as OneDayBridgeError {
            applyGoal(original)
            notes[goalID] = Self.message(for: error)
            return false
        } catch {
            applyGoal(original)
            notes[goalID] = L10n.string("状态更新失败，请稍后再试。")
            return false
        }
    }

    // MARK: - 分类变更（0.40.0：PATCH {category}→回读确认）

    /// 改/清分类：分类是独立动作（编辑 sheet 里改），走
    /// 专用小体 PATCH、不混全量编辑；回读后分类与请求
    /// 一致才算数。存量目标补分类也走这里（用户自选，
    /// 系统不推断）
    func setCategory(
        appState: AppState, goalID: String,
        category: GoalCategory?
    ) async -> Bool {
        guard !actingIDs.contains(goalID) else { return false }
        guard let config = appState.config else {
            notes[goalID] = L10n.string("尚未连接服务器。")
            return false
        }
        actingIDs.insert(goalID)
        notes.removeValue(forKey: goalID)
        defer { actingIDs.remove(goalID) }
        do {
            _ = try await client.patchGoalCategory(
                config: config, id: goalID, category: category
            )
            await refetch(appState: appState)
            guard let current = goal(id: goalID) else {
                notes[goalID] = L10n.string("分类已提交，但再确认时目标不见了，请刷新核对。")
                return false
            }
            if current.category == category {
                return true
            }
            notes[goalID] = L10n.string("分类已提交，但再确认时对不上，请刷新核对。")
            return false
        } catch let error as OneDayBridgeError {
            notes[goalID] = Self.message(for: error)
            return false
        } catch {
            notes[goalID] = L10n.string("分类更新失败，请稍后再试。")
            return false
        }
    }

    // MARK: - 详情面（P2：条目流＋简报）

    /// 进详情拉条目与简报：失败保持旧缓存不翻空
    /// （与列表同纪律）；目标已不在时如实记 notes
    func loadDetail(appState: AppState, goalID: String) async {
        guard let config = appState.config else { return }
        async let entriesFetch = client.goalEntries(
            config: config, goalID: goalID
        )
        async let briefingsFetch = client.goalBriefings(
            config: config, goalID: goalID
        )
        async let tasksFetch = client.goalTasks(
            config: config, goalID: goalID
        )
        let entries = try? await entriesFetch
        let briefings = try? await briefingsFetch
        let tasks = try? await tasksFetch
        if let entries {
            entriesByGoal[goalID] = entries
        }
        if let briefings {
            briefingsByGoal[goalID] = briefings
        }
        if let tasks {
            goalTasksByGoal[goalID] = tasks
        }
        if entries != nil || briefings != nil {
            detailLoadedIDs.insert(goalID)
        }
    }

    private func refetchGoalTasks(
        appState: AppState, goalID: String
    ) async {
        guard let config = appState.config else { return }
        if let fetched = try? await client.goalTasks(
            config: config, goalID: goalID
        ) {
            goalTasksByGoal[goalID] = fetched
        }
    }

    private func refetchEntries(
        appState: AppState, goalID: String
    ) async {
        guard let config = appState.config else { return }
        if let fetched = try? await client.goalEntries(
            config: config, goalID: goalID
        ) {
            entriesByGoal[goalID] = fetched
            detailLoadedIDs.insert(goalID)
        }
    }

    // MARK: - GD-3 打开记录 / GD-2 归组

    /// 打开一封简报时记下打开时刻（GD-3）：只供台账
    /// 看「写了没看」，不是用户写动作——失败静默、
    /// 不打扰；成功后以桥的回执整行替换本地这封信
    /// （lastOpenedAt 就此在本地可见）
    func markBriefingOpened(
        appState: AppState, goalID: String, briefingID: String
    ) async {
        guard let config = appState.config else { return }
        guard let updated = try? await client.markBriefingOpened(
            config: config, goalID: goalID, briefingID: briefingID
        ) else { return }
        if var list = briefingsByGoal[goalID],
           let idx = list.firstIndex(where: { $0.id == briefingID }) {
            list[idx] = updated
            briefingsByGoal[goalID] = list
        }
    }

    /// 未归类面静默刷新：失败保持旧值（与 load 同纪律，
    /// 附属读面不翻主状态）
    private func refreshUngrouped(appState: AppState) async {
        guard let config = appState.config else { return }
        if let response = try? await client.ungroupedTasks(
            config: config
        ) {
            installUngroupedTasks(response.items)
        }
    }

    /// 未归类面装载收口（刷新/测试共用一个落点）
    func installUngroupedTasks(_ items: [BridgeUngroupedTask]) {
        ungroupedTasks = items
    }

    /// 归组乐观落点：行同步先从未归类面摘下（接缝，
    /// 单测钉死）；面上没有该行时返回 nil 不动
    @discardableResult
    func applyOptimisticUngroup(taskID: String) -> BridgeUngroupedTask? {
        guard let row = ungroupedTasks.first(where: {
            $0.taskId == taskID
        }) else { return nil }
        ungroupedTasks.removeAll { $0.taskId == taskID }
        return row
    }

    /// 归组失败恢复落点：原行整行放回（按 createdAt
    /// 降序归位，与桥下发序一致）；已在面上不重复放
    func restoreUngrouped(_ row: BridgeUngroupedTask) {
        guard !ungroupedTasks.contains(where: {
            $0.taskId == row.taskId
        }) else { return }
        ungroupedTasks.append(row)
        ungroupedTasks.sort { $0.createdAt > $1.createdAt }
    }

    /// 一键归组（GD-2）：乐观先行——行先从未归类面
    /// 摘下，后台写归属字段；失败把行原样放回＋人话提示
    /// （总纲时序口径）。成功后静默回读两面收口真值
    func assignUngroupedTask(
        appState: AppState, taskID: String, toGoalID goalID: String
    ) async {
        guard ungroupedTasks.contains(where: {
            $0.taskId == taskID
        }) else { return }
        guard let config = appState.config else {
            ungroupedNote = L10n.string("尚未连接服务器。")
            return
        }
        ungroupedNote = nil
        guard let row = applyOptimisticUngroup(taskID: taskID)
        else { return }
        do {
            _ = try await client.setTaskGoal(
                config: config, taskID: taskID,
                request: BridgeTaskGoalWrite(goalId: goalID)
            )
            await refreshUngrouped(appState: appState)
            await refetchGoalTasks(appState: appState, goalID: goalID)
        } catch let error as OneDayBridgeError {
            restoreUngrouped(row)
            ungroupedNote = Self.message(for: error)
        } catch {
            restoreUngrouped(row)
            ungroupedNote = L10n.string("没归上组，任务还在未归类里，请稍后再试。")
        }
    }

    /// 记一条进展（POST→回读确认新条目出现才算完成）
    func addEntry(
        appState: AppState, goalID: String, body: String
    ) async -> Bool {
        guard !actingIDs.contains(goalID) else { return false }
        guard let config = appState.config else {
            notes[goalID] = L10n.string("尚未连接服务器。")
            return false
        }
        actingIDs.insert(goalID)
        notes.removeValue(forKey: goalID)
        defer { actingIDs.remove(goalID) }
        do {
            let created = try await client.createGoalEntry(
                config: config, goalID: goalID,
                request: .userNote(body)
            )
            await refetchEntries(appState: appState, goalID: goalID)
            // 条目流与目标视图的 latestEntry 是同一份事实
            // 的两面：列表摘要靠 goals 回读，一并刷新
            await refetch(appState: appState)
            if entriesByGoal[goalID]?.contains(
                where: { $0.id == created.id }
            ) == true {
                return true
            }
            notes[goalID] = L10n.string("进展已提交，但还没有在记录里确认出现，请刷新核对。")
            return false
        } catch let error as OneDayBridgeError {
            notes[goalID] = Self.message(for: error)
            return false
        } catch {
            notes[goalID] = L10n.string("记录进展失败，请稍后再试。")
            return false
        }
    }

    // MARK: - 委派「安排一件事」（0.40.0，§308 单轨改形）

    /// §308 前是两步两账：App 直连任务板建卡、再回桥补
    /// 关联，中途失败就留「卡在、关联不在」的半成品。
    /// 现在一次调用走完：桥的 delegate 在同一操作里建卡
    /// ＋写任务的 goalId 字段（桥是目标域属主、补 API
    /// 不加桥），App 回读目标任务面确认新行出现才算
    /// 完成；失败桥侧不落归属，如实留 notes，不假成功
    func delegateTask(
        appState: AppState, goalID: String, title: String
    ) async -> Bool {
        guard !actingIDs.contains(goalID) else { return false }
        guard let config = appState.config else {
            notes[goalID] = L10n.string("尚未连接服务器。")
            return false
        }
        actingIDs.insert(goalID)
        notes.removeValue(forKey: goalID)
        defer { actingIDs.remove(goalID) }
        do {
            let created = try await client.delegateGoalTask(
                config: config, goalID: goalID,
                request: BridgeGoalDelegateRequest(
                    title: title.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ),
                    idempotencyKey: UUID().uuidString
                )
            )
            await refetchGoalTasks(appState: appState, goalID: goalID)
            if goalTasksByGoal[goalID]?.contains(
                where: { $0.taskId == created.taskId }
            ) == true {
                return true
            }
            notes[goalID] = L10n.string("任务没有确认建成，请到枢纽任务段核对（聊天页点顶部胶囊打开）。")
            return false
        } catch let error as OneDayBridgeError {
            notes[goalID] = Self.message(for: error)
            return false
        } catch {
            notes[goalID] = L10n.string("安排失败，请稍后再试。")
            return false
        }
    }

    /// 删一条进展纠错（DELETE→回读确认消失才算完成）
    func deleteEntry(
        appState: AppState, goalID: String, entryID: String
    ) async -> Bool {
        guard !actingIDs.contains(goalID) else { return false }
        guard let config = appState.config else {
            notes[goalID] = L10n.string("尚未连接服务器。")
            return false
        }
        actingIDs.insert(goalID)
        notes.removeValue(forKey: goalID)
        defer { actingIDs.remove(goalID) }
        do {
            try await client.deleteGoalEntry(
                config: config, goalID: goalID, entryID: entryID
            )
            await refetchEntries(appState: appState, goalID: goalID)
            await refetch(appState: appState)
            if entriesByGoal[goalID]?.contains(
                where: { $0.id == entryID }
            ) != true {
                return true
            }
            notes[goalID] = L10n.string("删除已发出，但记录里还在，请刷新核对。")
            return false
        } catch let error as OneDayBridgeError {
            if case .recordGone = error {
                await refetchEntries(appState: appState, goalID: goalID)
                return entriesByGoal[goalID]?.contains(
                    where: { $0.id == entryID }
                ) != true
            }
            notes[goalID] = Self.message(for: error)
            return false
        } catch {
            notes[goalID] = L10n.string("删除进展失败，请稍后再试。")
            return false
        }
    }
}
