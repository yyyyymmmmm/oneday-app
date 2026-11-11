import Foundation
import OneDayCore

/// 任务数据中枢（P3，0.10.0）：活动格任务段自持——
/// 加载三步（版本探针→板清单→板快照）、控制动作按
/// Core 计划逐步执行＋回读确认、详情回读。口径：
/// ①专属板 oneday 不存在＝「任务板未开通」态，绝不
/// 拿假数据顶（建板是生产写操作、不在本包）；②写
/// 动作不许乐观假成功——服务端确认呈现态达到预期
/// 才算完成，未确认把人话留在卡内提示（AgentHub-
/// Store.decide 同口径）；③探针判枚举漂移→只读。
@MainActor
@Observable
final class KanbanStore {
    /// 加载态与错误映射走 Core 共用定义（§139，与
    /// LedgerStore 同一口）：未开通＝.unavailable(nil)
    /// （文案在呈现面固定），失败＝StoreLoadState 映射
    private(set) var loadState: StoreLoadState = .loading
    private(set) var snapshot: KanbanBoardSnapshot?
    /// 版本探针判漂移后的只读态（动作全闸，横幅明示）
    private(set) var readOnly = false
    /// 正在执行动作的任务 id（只禁用当前卡）
    private(set) var actingIDs: Set<String> = []
    /// 卡内行内提示（未确认/失败的人话，不弹模态）
    private(set) var notes: [String: String] = [:]
    private(set) var detail: KanbanTaskDetail?
    private(set) var detailLoading = false
    private(set) var creating = false
    private(set) var createError: String?

    private var probed = false
    private var loadInFlight = false

    var groups: [KanbanTaskGroup] {
        KanbanBoardGrouping.group(snapshot?.tasks ?? [])
    }

    // MARK: - 加载

    /// 首次加载/手动重试共用：探针只跑一次；板清单
    /// 取不到时不臆断未开通——直取板快照、404 才落
    /// 未开通态；清单明确无 oneday 才直接落未开通
    func load(appState: AppState) async {
        guard !loadInFlight else { return }
        guard appState.config != nil else {
            loadState = .notConnected
            return
        }
        loadInFlight = true
        defer { loadInFlight = false }

        if !probed {
            probed = true
            if let workflow = try? await appState.performAdmin(
                { client, config in
                    try await client.kanbanWorkflow(config: config)
                }
            ) {
                readOnly = KanbanProbe.isDrifted(workflow)
            }
        }

        let board = KanbanContract.boardSlug
        var provisioned: Bool?
        if let slugs = try? await appState.performAdmin(
            { client, config in
                try await client.kanbanBoards(config: config)
            }
        ) {
            provisioned = slugs.contains(board)
        }
        if provisioned == false {
            loadState = .unavailable(nil)
            return
        }
        await fetchBoard(
            appState: appState,
            missingMeansUnprovisioned: provisioned == nil
        )
    }

    /// 回板：已就绪时拉失败保持旧快照不翻态（轮询/
    /// 动作回读不许把整段打成失败页）；未就绪时才按
    /// 错误落态（404＋清单不可用→未开通，其余人话失败）
    private func fetchBoard(
        appState: AppState, missingMeansUnprovisioned: Bool
    ) async {
        do {
            let fetched = try await appState.performAdmin { client, config in
                try await client.kanbanBoard(
                    config: config, board: KanbanContract.boardSlug
                )
            }
            snapshot = fetched
            loadState = .ready
        } catch let error as HermesError {
            if loadState == .ready, snapshot != nil { return }
            if case .unexpectedStatus(_, let status) = error,
               status == 404, missingMeansUnprovisioned {
                loadState = .unavailable(nil)
            } else {
                loadState = StoreLoadState.failure(for: error)
            }
        } catch {
            if loadState == .ready, snapshot != nil { return }
            loadState = .failed(L10n.string("任务没读出来，可能是网络或服务暂时没响应"))
        }
    }

    /// 可见轮询（面 .task 驱动、消失即取消）：15 秒
    /// 一轮静默回板；动作/创建进行中不抢
    func runVisibleLoop(appState: AppState) async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(15))
            if Task.isCancelled { break }
            guard loadState == .ready,
                  actingIDs.isEmpty, !creating else { continue }
            await fetchBoard(
                appState: appState, missingMeansUnprovisioned: false
            )
        }
    }

    // MARK: - 详情

    func loadDetail(appState: AppState, id: String) async {
        detailLoading = true
        defer { detailLoading = false }
        detail = try? await appState.performAdmin { client, config in
            try await client.kanbanTaskDetail(
                config: config, board: KanbanContract.boardSlug, id: id
            )
        }
    }

    // MARK: - 新建（建卡→催派→回板确认）

    /// 三步全成才算完成：建卡回执 id 必须在回板快照
    /// 里出现，未确认不关表单、原因留在 createError。
    /// 催派失败不推翻建卡（gateway 自动 tick 亦会派）。
    /// 演示态按 DemoHermesClient 口径：写方法静默
    /// 成功、不落状态，确认步跳过
    func createTask(
        appState: AppState, title: String, body: String
    ) async -> Bool {
        await createTaskImpl(
            appState: appState, title: title, body: body
        ).success
    }

    /// 同 createTask 的全流程，确认落板时回任务 id
    /// （0.32.0 点子采纳回写桥 taskId 的数据源）；失败
    /// 回 nil、原因同样留在 createError
    func createTaskReturningID(
        appState: AppState, title: String, body: String
    ) async -> String? {
        let result = await createTaskImpl(
            appState: appState, title: title, body: body
        )
        return result.success ? result.taskID : nil
    }

    private func createTaskImpl(
        appState: AppState, title: String, body: String
    ) async -> (success: Bool, taskID: String?) {
        guard !creating else { return (false, nil) }
        creating = true
        createError = nil
        defer { creating = false }
        let key = UUID().uuidString
        do {
            let created = try await appState.performAdmin { client, config in
                try await client.kanbanCreateTask(
                    config: config, board: KanbanContract.boardSlug,
                    title: title, body: body, idempotencyKey: key
                )
            }
            _ = try? await appState.performAdmin { client, config in
                try await client.kanbanDispatch(
                    config: config, board: KanbanContract.boardSlug
                )
            }
            if appState.isDemo {
                return (true, created.id.isEmpty ? nil : created.id)
            }
            await fetchBoard(
                appState: appState, missingMeansUnprovisioned: false
            )
            if !created.id.isEmpty,
               snapshot?.tasks.contains(where: { $0.id == created.id })
                == true {
                return (true, created.id)
            }
            createError = L10n.string("任务已提交，但还没有在任务板上确认出现，请关闭后刷新核对。")
            return (false, nil)
        } catch let error as HermesError {
            createError = error.userMessage
            return (false, nil)
        } catch {
            createError = L10n.string("任务创建失败，请稍后再试。")
            return (false, nil)
        }
    }

    // MARK: - 控制动作（计划执行＋回读确认）

    /// 按 Core 计划逐步发动词 → 回板（详情打开着一并
    /// 回读）→ 呈现态对预期才算完成；闸门不过/发送
    /// 失败/未确认都把人话留在 notes[task.id]
    func perform(
        appState: AppState, task: KanbanTask,
        action: KanbanAction, answer: String? = nil
    ) async {
        guard !actingIDs.contains(task.id) else { return }
        let gate = KanbanActionPolicy.gate(
            action: action,
            takeoverActive: appState.boxTakeoverActive,
            readOnly: readOnly
        )
        guard gate.enabled else {
            notes[task.id] = gate.reason
            return
        }
        actingIDs.insert(task.id)
        notes.removeValue(forKey: task.id)
        defer { actingIDs.remove(task.id) }
        let steps = KanbanControlPlan.steps(action: action, task: task)
        do {
            for step in steps {
                try await execute(step, appState: appState, answer: answer)
            }
        } catch let error as HermesError {
            if action == .answer,
               case .cancelled = error {
                notes[task.id] = L10n.string("回答是空的，没有发出。")
            } else {
                notes[task.id] = error.userMessage
            }
            await fetchBoard(
                appState: appState, missingMeansUnprovisioned: false
            )
            return
        } catch {
            notes[task.id] = L10n.string("动作发送失败，请稍后再试。")
            await fetchBoard(
                appState: appState, missingMeansUnprovisioned: false
            )
            return
        }
        await fetchBoard(
            appState: appState, missingMeansUnprovisioned: false
        )
        if detail?.task.id == task.id {
            await loadDetail(appState: appState, id: task.id)
        }
        if !isConfirmed(action: action, taskID: task.id) {
            notes[task.id] = L10n.string("动作已发出，但状态还没有确认变化，请刷新核对。")
        }
    }

    private func execute(
        _ step: KanbanControlStep, appState: AppState, answer: String?
    ) async throws {
        let board = KanbanContract.boardSlug
        switch step {
        case .terminateRun(let runId):
            try await appState.performAdmin { client, config in
                try await client.kanbanTerminateRun(
                    config: config, board: board, runID: runId
                )
            }
        case .reclaim(let taskID):
            try await appState.performAdmin { client, config in
                try await client.kanbanReclaimTask(
                    config: config, board: board, id: taskID
                )
            }
        case .patchStatus(let taskID, let status):
            try await appState.performAdmin { client, config in
                try await client.kanbanPatchTaskStatus(
                    config: config, board: board, id: taskID,
                    status: status
                )
            }
        case .deleteTask(let taskID):
            try await appState.performAdmin { client, config in
                try await client.kanbanDeleteTask(
                    config: config, board: board, id: taskID
                )
            }
        case .comment(let taskID):
            guard let answer, !answer.isEmpty else {
                throw HermesError.cancelled
            }
            try await appState.performAdmin { client, config in
                try await client.kanbanComment(
                    config: config, board: board, id: taskID, body: answer
                )
            }
        case .dispatch:
            _ = try await appState.performAdmin { client, config in
                try await client.kanbanDispatch(
                    config: config, board: board
                )
            }
        }
    }

    /// 回读确认口径（以回板/回详情后的呈现态判）：
    /// 取消＝已消失；停止＝不再运行；继续/重试/打回
    /// ＝已回队列、已在跑、已排期或已完成；批准＝已
    /// 完成；答题＝已离开等答态
    private func isConfirmed(
        action: KanbanAction, taskID: String
    ) -> Bool {
        let current: KanbanTask?
        if detail?.task.id == taskID {
            current = detail?.task
        } else {
            current = snapshot?.tasks.first { $0.id == taskID }
        }
        switch action {
        case .cancel:
            return current == nil
        case .stop:
            guard let current else { return false }
            return current.presentation != .running
        case .resume, .retry, .requestChanges:
            guard let current else { return false }
            return [.queued, .running, .scheduled, .done]
                .contains(current.presentation)
        case .approve:
            return current?.presentation == .done
        case .answer:
            guard let current else { return false }
            return current.presentation != .needsInput
        case .create:
            return false
        }
    }
}
