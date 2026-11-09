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

    private let client = OneDayBridgeClient()
    private var loadInFlight = false

    func goal(id: String) -> BridgeGoal? {
        goals.first { $0.id == id }
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
                "还没有粘贴数据桥钥匙。在设置里粘贴桥钥匙后，目标和点子就能用了。"
            )
        case .unauthorized:
            return .notConnected(
                "数据桥钥匙被拒绝了。请到设置里检查桥钥匙是否粘对。"
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
            return "数据桥未连接：还没有粘贴桥钥匙。"
        case .unauthorized:
            return "数据桥未连接：桥钥匙被拒绝。"
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
        milestoneTitles: [String]
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
            title: title, note: note, milestoneTitles: milestoneTitles
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
                notes[goalID] = "保存已发出，但回读时目标不见了，请刷新核对。"
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
            notes[goalID] = "保存已发出，但回读内容对不上，请刷新核对。"
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
}
