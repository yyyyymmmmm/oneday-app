import Foundation
import OneDayCore

/// 点子数据中枢（P5，0.11.0）：oneday-bridge 点子仓的
/// 状态面＋「一键转任务」的执行面。口径：
/// ①桥未连接/未开通与 GoalsStore 同分法（共用其静态
/// 映射，不另立一套说法）；②写动作回读确认才算完成；
/// ③转任务经 P3 KanbanStore 适配层落板——板未开通
/// 如实提示、不假成功，确认建卡出现后才落本地「已转」
/// 标记（冻结合约无此字段，只存本地 UserDefaults、
/// 不硬塞服务端）；④关联目标名只从同批拉到的目标
/// 列表解析，解析不到不显示、不编名（目标被删后服务
/// 端会把 goalId 置 null，回读即自愈）。
@MainActor
@Observable
final class IdeasStore {
    typealias LoadState = GoalsStore.LoadState

    private(set) var loadState: LoadState = .loading
    private(set) var ideas: [BridgeIdea] = []
    /// 关联目标解析与新建 picker 的数据源（拉不到只
    /// 降级这两处，点子本体照常）
    private(set) var goals: [BridgeGoal] = []
    /// 正在转任务/删除的点子 id
    private(set) var actingIDs: Set<String> = []
    /// 正在新建（表单防重复提交）
    private(set) var creating = false
    private(set) var createError: String?
    /// 卡内行内提示（转任务/删除的人话，不弹模态）
    private(set) var notes: [String: String] = [:]
    /// 已转任务的本地标记（点子 id 集）
    private(set) var convertedIDs: Set<String>

    private let client = OneDayBridgeClient()
    private var loadInFlight = false

    private static let marksKey = "convertedIdeaIDs"

    init() {
        convertedIDs = IdeaConversionMarks.decode(
            UserDefaults.standard.stringArray(forKey: Self.marksKey)
        )
    }

    func isConverted(_ idea: BridgeIdea) -> Bool {
        convertedIDs.contains(idea.id)
    }

    func goalTitle(for idea: BridgeIdea) -> String? {
        guard let goalId = idea.goalId else { return nil }
        return goals.first { $0.id == goalId }?.title
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
            ideas = try await client.ideas(config: config)
            loadState = .ready
        } catch let error as OneDayBridgeError {
            if loadState == .ready { return }
            loadState = GoalsStore.state(for: error)
        } catch {
            if loadState == .ready { return }
            loadState = .failed("点子读取失败，请稍后重试。")
        }
        // 目标列表是附带面：失败只降级关联显示/picker
        if let fetched = try? await client.goals(config: config) {
            goals = fetched
        }
    }

    /// 静默回读（写动作确认专用）：失败不翻态、不动旧数
    private func refetch(appState: AppState) async {
        guard let config = appState.config else { return }
        if let fetched = try? await client.ideas(config: config) {
            ideas = fetched
        }
        if let fetched = try? await client.goals(config: config) {
            goals = fetched
        }
    }

    // MARK: - 新建（POST→回读确认出现才算完成）

    func create(
        appState: AppState, title: String, detail: String,
        goalId: String?
    ) async -> Bool {
        guard !creating else { return false }
        guard let config = appState.config else {
            createError = "尚未连接服务器。"
            return false
        }
        creating = true
        createError = nil
        defer { creating = false }
        let request = BridgeIdeaCreateRequest.make(
            title: title, detail: detail, goalId: goalId
        )
        do {
            let created = try await client.createIdea(
                config: config, request: request
            )
            await refetch(appState: appState)
            if ideas.contains(where: { $0.id == created.id }) {
                return true
            }
            createError = "点子已提交，但还没有在列表里确认出现，请关闭后刷新核对。"
            return false
        } catch let error as OneDayBridgeError {
            createError = GoalsStore.message(for: error)
            return false
        } catch {
            createError = "点子创建失败，请稍后重试。"
            return false
        }
    }

    // MARK: - 删除（DELETE→回读确认消失才算完成）

    func delete(appState: AppState, idea: BridgeIdea) async {
        guard !actingIDs.contains(idea.id) else { return }
        guard let config = appState.config else {
            notes[idea.id] = "尚未连接服务器。"
            return
        }
        actingIDs.insert(idea.id)
        notes.removeValue(forKey: idea.id)
        defer { actingIDs.remove(idea.id) }
        do {
            try await client.deleteIdea(config: config, id: idea.id)
            await refetch(appState: appState)
            if !ideas.contains(where: { $0.id == idea.id }) {
                unmarkConverted(idea.id)
            } else {
                notes[idea.id] = "删除已发出，但列表里还在，请刷新核对。"
            }
        } catch let error as OneDayBridgeError {
            if case .recordGone = error {
                await refetch(appState: appState)
                if !ideas.contains(where: { $0.id == idea.id }) {
                    unmarkConverted(idea.id)
                    return
                }
            }
            notes[idea.id] = GoalsStore.message(for: error)
        } catch {
            notes[idea.id] = "删除失败，请稍后重试。"
        }
    }

    // MARK: - 一键转任务（经 P3 kanban 适配层）

    /// 流程：先让 KanbanStore 探板（未开通→如实提示、
    /// 不往下走）→ 按 IdeaTaskPlan 组装标题/正文 →
    /// createTask（建卡→催派→回板确认）→ 确认成功才
    /// 落本地已转标记。任一步不成都把人话留在卡内
    /// notes，点子本体不动、不假成功
    func convertToTask(
        appState: AppState, idea: BridgeIdea, kanban: KanbanStore
    ) async {
        guard !actingIDs.contains(idea.id) else { return }
        guard !isConverted(idea) else {
            notes[idea.id] = "这个点子已经转成任务了。"
            return
        }
        actingIDs.insert(idea.id)
        notes.removeValue(forKey: idea.id)
        defer { actingIDs.remove(idea.id) }

        await kanban.load(appState: appState)
        switch kanban.loadState {
        case .notProvisioned:
            notes[idea.id] = "任务板未开通，暂时不能把点子转成任务。"
            return
        case .failed(let message):
            notes[idea.id] = message
            return
        case .loading:
            notes[idea.id] = "任务板状态还没确认好，请稍后再试。"
            return
        case .ready:
            break
        }
        let plan = IdeaTaskPlan.make(
            idea: idea, goalTitle: goalTitle(for: idea)
        )
        let created = await kanban.createTask(
            appState: appState, title: plan.title, body: plan.body
        )
        if created {
            markConverted(idea.id)
        } else {
            notes[idea.id] = kanban.createError
                ?? "任务没有确认建成，请到活动页任务段核对。"
        }
    }

    // MARK: - 已转标记（本地持久化）

    private func markConverted(_ id: String) {
        convertedIDs.insert(id)
        UserDefaults.standard.set(
            IdeaConversionMarks.encode(convertedIDs), forKey: Self.marksKey
        )
    }

    private func unmarkConverted(_ id: String) {
        guard convertedIDs.contains(id) else { return }
        convertedIDs.remove(id)
        UserDefaults.standard.set(
            IdeaConversionMarks.encode(convertedIDs), forKey: Self.marksKey
        )
    }
}
