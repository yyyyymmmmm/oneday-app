import Foundation
import Observation
import OneDayCore

/// 想法状态店（棒 3，对位 #3/#35）：点子列表＋生成
/// 管道账面。采纳动作依赖任务板建卡链（枢纽看板
/// #58），棒 4 看板面落地后在此接通（见 adopt）。
@MainActor
@Observable
final class MacIdeasStore {
    private(set) var ideas: [BridgeIdea] = []
    private(set) var generation: BridgeGenerationInfo?
    private(set) var loading = false
    private(set) var loaded = false
    var loadError: String?
    var actionNote: String?

    var pendingIdeas: [BridgeIdea] {
        ideas.filter { $0.status == .pending }
    }

    var settledIdeas: [BridgeIdea] {
        ideas.filter { $0.status != .pending }
    }

    func refresh(session: SessionStore) async {
        guard !loading else { return }
        guard session.isConnected, let config = session.config,
              let key = session.apiKey else {
            ideas = []
            return
        }
        loading = true
        loadError = nil
        defer { loading = false }
        do {
            ideas = try await session.chatClient.ideas(
                config: config, apiKey: key
            )
        } catch let error as HermesError {
            loadError = error.userMessage
        } catch {
            loadError = "想法加载失败"
        }
        // 生成账面是降级项：旧桥无此端点时静默无数据
        generation = try? await session.chatClient.ideasGeneration(
            config: config, apiKey: key
        )
        loaded = true
    }

    /// 新建点子（用户手建）：成功后整表回读对齐
    func create(
        session: SessionStore, title: String, detail: String
    ) async -> Bool {
        guard let config = session.config, let key = session.apiKey
        else { return false }
        do {
            _ = try await session.chatClient.createIdea(
                config: config, apiKey: key,
                request: BridgeIdeaCreateRequest(
                    title: title,
                    detail: detail.isEmpty ? nil : detail,
                    goalId: nil
                )
            )
            await refresh(session: session)
            return true
        } catch let error as HermesError {
            actionNote = error.userMessage
            return false
        } catch {
            actionNote = "新建点子失败"
            return false
        }
    }

    /// 忽略：PATCH status=dismissed（桥侧状态机把关）
    func dismiss(session: SessionStore, idea: BridgeIdea) async {
        guard let config = session.config, let key = session.apiKey
        else { return }
        do {
            let settled = try await session.chatClient.patchIdea(
                config: config, apiKey: key, id: idea.id,
                request: BridgeIdeaPatchRequest(status: .dismissed)
            )
            replace(settled)
        } catch let error as HermesError {
            actionNote = error.userMessage
        } catch {
            actionNote = "忽略失败"
        }
    }

    /// 采纳（棒 4 接通，对位 #35）：看板建卡（幂等键
    /// 按想法 id 定，防重复点建双卡）→ 桥 PATCH 回
    /// 写 status=adopted＋taskId → 以回执整行替换为
    /// 终局（taskId 是「已转任务」的服务端真源）。
    /// 板清单为空/建卡无 id 时如实失败、不假装采纳
    func adopt(session: SessionStore, idea: BridgeIdea) async {
        guard let config = session.config, let key = session.apiKey
        else { return }
        do {
            let boardsRaw = try await session.chatClient
                .hubKanbanBoards(config: config, apiKey: key)
            let boards = boardsRaw.hubFirstList(["boards"])
                .compactMap { $0.stringValue }
            guard let board = boards.first ?? boardsRaw.hubList
                .compactMap({ $0.stringValue }).first
            else {
                actionNote = "采纳失败：服务端没有可用看板。"
                return
            }
            let receipt = try await session.chatClient
                .hubKanbanCreateTask(
                    config: config, apiKey: key, board: board,
                    title: idea.title, body: idea.detail,
                    idempotencyKey: "idea-adopt-\(idea.id)"
                )
            guard let taskID = receipt.hubFirstStr(
                ["id", "task_id", "taskId"]
            ) else {
                actionNote = "采纳失败：建卡回执里没有任务 id。"
                return
            }
            let settled = try await session.chatClient.patchIdea(
                config: config, apiKey: key, id: idea.id,
                request: BridgeIdeaPatchRequest(
                    status: .adopted, taskId: taskID
                )
            )
            replace(settled)
        } catch let error as HermesError {
            actionNote = error.userMessage
        } catch {
            actionNote = "采纳失败"
        }
    }

    /// 删除：服务端删净后本地摘行
    func delete(session: SessionStore, idea: BridgeIdea) async {
        guard let config = session.config, let key = session.apiKey
        else { return }
        do {
            try await session.chatClient.deleteIdea(
                config: config, apiKey: key, id: idea.id
            )
            ideas.removeAll { $0.id == idea.id }
        } catch let error as HermesError {
            actionNote = error.userMessage
        } catch {
            actionNote = "删除失败"
        }
    }

    private func replace(_ idea: BridgeIdea) {
        guard let index = ideas.firstIndex(where: { $0.id == idea.id })
        else { return }
        ideas[index] = idea
    }
}
