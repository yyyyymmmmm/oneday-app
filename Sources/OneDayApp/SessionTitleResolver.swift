import Foundation
import OneDayCore

/// 会话派生标题解析器（0.6.1 立、0.18.0 降为回落层）：
/// 0.6.1 的前提「列表接口没有标题字段」是客户端误
/// 判——列表行本就带 title/title_source（2026-11-09
/// 晚带登录态实拉坐实，26/28 条已有 llm 标题），客
/// 户端当时只解码 display_name。本解析器自 0.18.0
/// 只管回落层：服务端无标题的会话（如 Qwen 标题升
/// 级失败者）按需拉单会话消息取首条 user 消息作本
/// 地派生，喂统一管线 ServerSession.resolvedTitle。
/// 本解析器是全 App 唯一取数口：抽屉行与活动行共
/// 用同一份缓存与同一派生，不许两处各拉各的。
/// 纪律：请求有预算（单次 ensure 至多 budget 条）、
/// 有界并发（4 路）、查过的（含失败/无消息）记
/// resolved 不重复打——不许逐行无界拉取打爆服务端。
/// 直连 client 口径与 AgentHubStore.loadRuns 同例
/// （调用方在主拉取成功后调用、cookie 已新鲜；标题
/// 是补充数据，失败可降级为未命名）。
@MainActor
@Observable
final class SessionTitleResolver {
    /// sessionID → 首条 user 消息原文
    private(set) var firstUserMessages: [String: String] = [:]
    /// 已查毕的会话 id（有无结果都记，防止重复请求）
    private var resolvedIDs: Set<String> = []
    /// 正在拉取的会话 id（跨调用去重）
    private var inFlightIDs: Set<String> = []

    /// 为一批会话补齐派生标题素材：只处理无服务端
    /// 标题、无人话名、未查过、不在飞的会话（有服务
    /// 端标题者管线直接命中、不必拉消息），至多
    /// budget 条。
    func ensureTitles(
        for sessions: [ServerSession],
        appState: AppState,
        budget: Int = 8
    ) async {
        guard let config = appState.config else { return }
        let client = appState.client
        let batch = Array(sessions.filter {
            !$0.hasServerTitle
                && !$0.hasHumanName
                && !resolvedIDs.contains($0.id)
                && !inFlightIDs.contains($0.id)
        }.prefix(budget))
        guard !batch.isEmpty else { return }
        for session in batch { inFlightIDs.insert(session.id) }
        // 4 路一窗的滑动分块：窗内并发、窗间串行，总
        // 请求数仍受 budget 封顶
        for chunkStart in stride(from: 0, to: batch.count, by: 4) {
            let chunk = Array(batch[chunkStart..<min(chunkStart + 4, batch.count)])
            await withTaskGroup(of: (String, String?).self) { group in
                for session in chunk {
                    group.addTask {
                        let messages = try? await client.sessionMessages(
                            config: config, id: session.id
                        )
                        return (
                            session.id,
                            messages.flatMap {
                                ServerSession.firstUserMessage(in: $0)
                            }
                        )
                    }
                }
                for await (id, message) in group {
                    resolvedIDs.insert(id)
                    inFlightIDs.remove(id)
                    if let message {
                        firstUserMessages[id] = message
                    }
                }
            }
        }
    }

    /// 行标题：统一管线（服务端标题＞本地派生＞
    /// display_name 人话名＞未命名），与活动行、管理
    /// 页行同源（ServerSession.resolvedTitle）
    func title(for session: ServerSession) -> String {
        session.resolvedTitle(
            firstUserMessage: firstUserMessages[session.id]
        )
    }
}
