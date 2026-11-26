import Foundation
import Observation
import OneDayCore

/// 想法状态店（棒 3，对位 #3/#35）：点子列表＋生成
/// 管道账面。采纳动作依赖任务板建卡链（枢纽看板
/// #58，归枢纽棒），本店只做新建/忽略/删除，采纳在
/// 详情面明示未落、不假装。
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
