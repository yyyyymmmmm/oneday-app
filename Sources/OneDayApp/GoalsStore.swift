import Foundation
import OneDayCore

/// 目标数据中枢（P4，0.11.0）：oneday-bridge 目标仓的
/// 唯一状态面。口径（与 KanbanStore 同纪律）：
/// ①桥未连接/未开通如实露（noKey/401＝钥匙问题、
/// 集合 404＝桥未开通），绝不拿假数据顶；②写动作不
/// 许乐观假成功——PATCH/POST/DELETE 后一律回读列表，
/// 呈现态达到预期才算完成，未确认把人话留在行内
/// 提示；③已就绪时刷新失败保持旧数据不翻态。
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
    /// 详情面已拉过至少一次的目标（区分「还没拉」与
    /// 「拉过、确实为空」——空态不许靠猜）
    private(set) var detailLoadedIDs: Set<String> = []

    private let client = OneDayBridgeClient()
    private var loadInFlight = false

    func goal(id: String) -> BridgeGoal? {
        goals.first { $0.id == id }
    }

    func children(of goalID: String) -> [BridgeGoal] {
        GoalBoard.children(of: goalID, in: goals)
    }

    // MARK: - 加载

    func load(appState: AppState) async {
        guard !loadInFlight else { return }
        guard let config = appState.config else {
            loadState = .failed("尚未连接服务器。")
            return
        }
        loadInFlight = true
        defer { loadInFlight = false }
        do {
            goals = try await client.goals(config: config)
            loadState = .ready
        } catch let error as OneDayBridgeError {
            if loadState == .ready { return }
            loadState = Self.state(for: error)
        } catch {
            if loadState == .ready { return }
            loadState = .failed("目标读取失败，请稍后重试。")
        }
    }

    /// 静默回读（写动作确认专用）：失败不翻态、不动旧数
    private func refetch(appState: AppState) async {
        guard let config = appState.config else { return }
        if let fetched = try? await client.goals(config: config) {
            goals = fetched
        }
    }

    static func state(for error: OneDayBridgeError) -> LoadState {
        switch error {
        case .noKey:
            return .notConnected(
                "还没有可用的登录信息：目标和点子用的是你的 Hermes 登录。先到「设置」里确认已经连接并登录，就能用了。"
            )
        case .unauthorized:
            return .notConnected(
                "服务器拒绝了这次登录。请到「设置」里检查登录是否还有效。"
            )
        case .bridgeMissing:
            return .notConnected("服务器上的数据桥还没有开通。")
        case .recordGone:
            return .failed("这条记录已经不在了，请刷新后重试。")
        case .failed(let message):
            return .failed(message)
        }
    }

    static func message(for error: OneDayBridgeError) -> String {
        switch error {
        case .noKey:
            return "数据桥未连接：还没有可用的登录信息。"
        case .unauthorized:
            return "数据桥未连接：服务器拒绝了这次登录。"
        case .bridgeMissing:
            return "服务器上的数据桥还没有开通。"
        case .recordGone:
            return "这条记录已经不在了。"
        case .failed(let message):
            return message
        }
    }

    // MARK: - 新建（POST→回读确认出现才算完成）

    func create(
        appState: AppState, title: String, note: String,
        milestoneTitles: [String], parentId: String? = nil
    ) async -> Bool {
        guard !creating else { return false }
        guard let config = appState.config else {
            createError = "尚未连接服务器。"
            return false
        }
        creating = true
        createError = nil
        defer { creating = false }
        let request = BridgeGoalCreateRequest.make(
            title: title, note: note, milestoneTitles: milestoneTitles,
            parentId: parentId
        )
        do {
            let created = try await client.createGoal(
                config: config, request: request
            )
            await refetch(appState: appState)
            if goals.contains(where: { $0.id == created.id }) {
                return true
            }
            createError = "目标已提交，但还没有在列表里确认出现，请关闭后刷新核对。"
            return false
        } catch let error as OneDayBridgeError {
            createError = Self.message(for: error)
            return false
        } catch {
            createError = "目标创建失败，请稍后重试。"
            return false
        }
    }

    // MARK: - 编辑保存（PATCH 全量→回读确认字段一致）

    /// 勾选翻转与改标题/备注/增删里程碑共用此路：草稿
    /// 全量组装 PATCH 体（已有里程碑 id 原样带回、新条
    /// 不带 id），回读后逐项对账（标题/备注/里程碑
    /// id·标题·done 全等）才算保存成功
    func saveEdits(
        appState: AppState, goalID: String, title: String,
        note: String, milestones: [MilestoneDraftState]
    ) async -> Bool {
        guard !actingIDs.contains(goalID) else { return false }
        guard let config = appState.config else {
            notes[goalID] = "尚未连接服务器。"
            return false
        }
        actingIDs.insert(goalID)
        notes.removeValue(forKey: goalID)
        defer { actingIDs.remove(goalID) }
        let request = GoalPatchPlan.update(
            title: title, note: note, milestones: milestones
        )
        do {
            _ = try await client.patchGoal(
                config: config, id: goalID, request: request
            )
            await refetch(appState: appState)
            guard let current = goal(id: goalID) else {
                notes[goalID] = "保存已发出，但再确认时目标不见了，请刷新核对。"
                return false
            }
            let confirmed = current.title == request.title
                && current.note == request.note
                && current.milestones.count == request.milestones.count
                && zip(current.milestones, request.milestones)
                    .allSatisfy { server, sent in
                        server.title == sent.title
                            && server.done == sent.done
                            && (sent.id == nil || server.id == sent.id)
                    }
            if confirmed {
                return true
            }
            notes[goalID] = "保存已发出，但再确认时内容对不上，请刷新核对。"
            return false
        } catch let error as OneDayBridgeError {
            notes[goalID] = Self.message(for: error)
            return false
        } catch {
            notes[goalID] = "保存失败，请稍后重试。"
            return false
        }
    }

    // MARK: - 删除（DELETE→回读确认消失才算完成）

    func delete(appState: AppState, goalID: String) async -> Bool {
        guard !actingIDs.contains(goalID) else { return false }
        guard let config = appState.config else {
            notes[goalID] = "尚未连接服务器。"
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
            notes[goalID] = "删除已发出，但列表里还在，请刷新核对。"
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
            notes[goalID] = "删除失败，请稍后重试。"
            return false
        }
    }

    // MARK: - 状态流转（P2：PATCH {status}→回读确认）

    /// 标完成/重新打开：桥在流转时落 completedAt；回读
    /// 后状态与请求一致（完成时 completedAt 非空、重开
    /// 时为空）才算数，不一致把人话留在 notes
    func setStatus(
        appState: AppState, goalID: String, status: GoalStatus
    ) async -> Bool {
        guard !actingIDs.contains(goalID) else { return false }
        guard let config = appState.config else {
            notes[goalID] = "尚未连接服务器。"
            return false
        }
        actingIDs.insert(goalID)
        notes.removeValue(forKey: goalID)
        defer { actingIDs.remove(goalID) }
        do {
            _ = try await client.patchGoalStatus(
                config: config, id: goalID, status: status
            )
            await refetch(appState: appState)
            guard let current = goal(id: goalID) else {
                notes[goalID] = "状态已提交，但再确认时目标不见了，请刷新核对。"
                return false
            }
            let confirmed = current.status == status
                && (status == .completed
                    ? current.completedAt != nil
                    : current.completedAt == nil)
            if confirmed {
                return true
            }
            notes[goalID] = "状态已提交，但再确认时对不上，请刷新核对。"
            return false
        } catch let error as OneDayBridgeError {
            notes[goalID] = Self.message(for: error)
            return false
        } catch {
            notes[goalID] = "状态更新失败，请稍后重试。"
            return false
        }
    }

    /// 里程碑就地勾选（P2 呈现页）：走既有全量 PATCH＋
    /// 逐项对账的 saveEdits 口径，只是草稿取服务端现值
    /// 翻一项——不新开第二条写路
    func toggleMilestone(
        appState: AppState, goalID: String, milestoneID: String
    ) async -> Bool {
        guard let goal = goal(id: goalID) else { return false }
        let drafts = goal.milestones.map { milestone in
            MilestoneDraftState(
                id: milestone.id, title: milestone.title,
                done: milestone.id == milestoneID
                    ? !milestone.done : milestone.done
            )
        }
        return await saveEdits(
            appState: appState, goalID: goalID, title: goal.title,
            note: goal.note, milestones: drafts
        )
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
        let entries = try? await entriesFetch
        let briefings = try? await briefingsFetch
        if let entries {
            entriesByGoal[goalID] = entries
        }
        if let briefings {
            briefingsByGoal[goalID] = briefings
        }
        if entries != nil || briefings != nil {
            detailLoadedIDs.insert(goalID)
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

    /// 记一条进展（POST→回读确认新条目出现才算完成）
    func addEntry(
        appState: AppState, goalID: String, body: String
    ) async -> Bool {
        guard !actingIDs.contains(goalID) else { return false }
        guard let config = appState.config else {
            notes[goalID] = "尚未连接服务器。"
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
            notes[goalID] = "进展已提交，但还没有在记录里确认出现，请刷新核对。"
            return false
        } catch let error as OneDayBridgeError {
            notes[goalID] = Self.message(for: error)
            return false
        } catch {
            notes[goalID] = "记录进展失败，请稍后重试。"
            return false
        }
    }

    /// 删一条进展纠错（DELETE→回读确认消失才算完成）
    func deleteEntry(
        appState: AppState, goalID: String, entryID: String
    ) async -> Bool {
        guard !actingIDs.contains(goalID) else { return false }
        guard let config = appState.config else {
            notes[goalID] = "尚未连接服务器。"
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
            notes[goalID] = "删除已发出，但记录里还在，请刷新核对。"
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
            notes[goalID] = "删除进展失败，请稍后重试。"
            return false
        }
    }
}
