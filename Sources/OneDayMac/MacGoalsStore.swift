import Foundation
import Observation
import OneDayCore

/// 目标状态店（棒 3，对位 #4/#36）：目标 CRUD＋详情
/// 三件（进展条目/简报信件）。写口全走桥现行契约，
/// 回执全形替换本地行，不本地拼装。
@MainActor
@Observable
final class MacGoalsStore {
    private(set) var goals: [BridgeGoal] = []
    private(set) var loading = false
    private(set) var loaded = false
    var loadError: String?
    var actionNote: String?

    // 详情态（随选中目标装载）
    private(set) var detailGoalID: String?
    private(set) var entries: [BridgeGoalEntry] = []
    private(set) var briefings: [BridgeBriefing] = []
    private(set) var detailLoading = false

    var activeGoals: [BridgeGoal] {
        goals.filter { $0.status == .active }
    }

    var completedGoals: [BridgeGoal] {
        goals.filter { $0.status == .completed }
    }

    func refresh(session: SessionStore) async {
        guard !loading else { return }
        guard session.isConnected, let config = session.config,
              let key = session.apiKey else {
            goals = []
            return
        }
        loading = true
        loadError = nil
        defer { loading = false }
        do {
            goals = try await session.chatClient.goals(
                config: config, apiKey: key
            )
        } catch let error as HermesError {
            loadError = error.userMessage
        } catch {
            loadError = "目标加载失败"
        }
        loaded = true
    }

    /// 新建目标（表单口径与 iOS 同：标题/备注去首尾空白）
    func create(
        session: SessionStore, title: String, note: String,
        parentId: String? = nil
    ) async -> BridgeGoal? {
        guard let config = session.config, let key = session.apiKey
        else { return nil }
        do {
            let created = try await session.chatClient.createGoal(
                config: config, apiKey: key,
                request: .make(
                    title: title, note: note, parentId: parentId
                )
            )
            await refresh(session: session)
            return created
        } catch let error as HermesError {
            actionNote = error.userMessage
            return nil
        } catch {
            actionNote = "新建目标失败"
            return nil
        }
    }

    /// 编辑标题/备注：回执整行替换
    func patch(
        session: SessionStore, goal: BridgeGoal,
        title: String, note: String
    ) async {
        guard let config = session.config, let key = session.apiKey
        else { return }
        do {
            let settled = try await session.chatClient.patchGoal(
                config: config, apiKey: key, id: goal.id,
                request: .edited(title: title, note: note)
            )
            replace(settled)
        } catch let error as HermesError {
            actionNote = error.userMessage
        } catch {
            actionNote = "保存目标失败"
        }
    }

    /// 状态流转：完成/重新打开
    func setStatus(
        session: SessionStore, goal: BridgeGoal, status: GoalStatus
    ) async {
        guard let config = session.config, let key = session.apiKey
        else { return }
        do {
            let settled = try await session.chatClient
                .patchGoalStatus(
                    config: config, apiKey: key, id: goal.id,
                    status: status
                )
            replace(settled)
        } catch let error as HermesError {
            actionNote = error.userMessage
        } catch {
            actionNote = "状态更新失败"
        }
    }

    /// 删除目标：服务端删净后本地摘行
    func delete(session: SessionStore, goal: BridgeGoal) async {
        guard let config = session.config, let key = session.apiKey
        else { return }
        do {
            try await session.chatClient.deleteGoal(
                config: config, apiKey: key, id: goal.id
            )
            goals.removeAll { $0.id == goal.id }
            if detailGoalID == goal.id {
                detailGoalID = nil
                entries = []
                briefings = []
            }
        } catch let error as HermesError {
            actionNote = error.userMessage
        } catch {
            actionNote = "删除目标失败"
        }
    }

    // MARK: - 详情（进展＋简报）

    func loadDetail(session: SessionStore, goalID: String) async {
        detailGoalID = goalID
        entries = []
        briefings = []
        guard let config = session.config, let key = session.apiKey
        else { return }
        detailLoading = true
        defer { detailLoading = false }
        if let fetched = try? await session.chatClient.goalEntries(
            config: config, apiKey: key, goalID: goalID
        ), detailGoalID == goalID {
            entries = fetched
        }
        if let fetched = try? await session.chatClient.goalBriefings(
            config: config, apiKey: key, goalID: goalID
        ), detailGoalID == goalID {
            briefings = fetched
        }
    }

    /// 追加一条手记进展：成功以条目流回读出现为准
    func addEntry(
        session: SessionStore, goalID: String, text: String
    ) async {
        guard let config = session.config, let key = session.apiKey
        else { return }
        do {
            _ = try await session.chatClient.createGoalEntry(
                config: config, apiKey: key, goalID: goalID,
                request: .userNote(text)
            )
            if let fetched = try? await session.chatClient
                .goalEntries(
                    config: config, apiKey: key, goalID: goalID
                ) {
                entries = fetched
            }
        } catch let error as HermesError {
            actionNote = error.userMessage
        } catch {
            actionNote = "记录进展失败"
        }
    }

    /// 删单条进展（纠错）
    func deleteEntry(
        session: SessionStore, goalID: String,
        entry: BridgeGoalEntry
    ) async {
        guard let config = session.config, let key = session.apiKey
        else { return }
        do {
            try await session.chatClient.deleteGoalEntry(
                config: config, apiKey: key, goalID: goalID,
                entryID: entry.id
            )
            entries.removeAll { $0.id == entry.id }
        } catch let error as HermesError {
            actionNote = error.userMessage
        } catch {
            actionNote = "删除进展失败"
        }
    }

    /// 打开简报信件：桥侧记打开时刻，回执替换本地行
    func openBriefing(
        session: SessionStore, briefing: BridgeBriefing
    ) async {
        guard let config = session.config, let key = session.apiKey
        else { return }
        if let settled = try? await session.chatClient
            .markBriefingOpened(
                config: config, apiKey: key,
                goalID: briefing.goalId, briefingID: briefing.id
            ),
           let index = briefings.firstIndex(
               where: { $0.id == settled.id }
           ) {
            briefings[index] = settled
        }
    }

    private func replace(_ goal: BridgeGoal) {
        guard let index = goals.firstIndex(where: { $0.id == goal.id })
        else { return }
        goals[index] = goal
    }
}
