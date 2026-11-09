import Foundation
import OneDayCore

/// 会话派生标题解析器（0.6.1，用户真机点名）：服务端
/// 会话列表接口没有标题/预览字段、display_name 实测
/// 恒 null，行标题要落到内容上只能按需拉单会话消息
/// 取首条 user 消息。本解析器是全 App 唯一取数口：
/// 抽屉行与活动行共用同一份缓存与同一派生
/// （ServerSession.contentTitle），不许两处各拉各的。
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

    /// 为一批会话补齐派生标题素材：只处理无人话名、
    /// 未查过、不在飞的会话，至多 budget 条。
    func ensureTitles(
        for sessions: [ServerSession],
        appState: AppState,
        budget: Int = 8
    ) async {
        guard let config = appState.config else { return }
        let client = appState.client
        let batch = Array(sessions.filter {
            !$0.hasHumanName
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

    /// 行标题：派生（首条消息摘要）→ 人话名 → 未命名，
    /// 与活动行同源（ServerSession.contentTitle）
    func title(for session: ServerSession) -> String {
        session.contentTitle(
            firstUserMessage: firstUserMessages[session.id]
        )
    }
}
