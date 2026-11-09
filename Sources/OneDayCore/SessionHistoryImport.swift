import Foundation

/// 服务端会话历史 → 本地线程的导入口径（0.4.0，审计
/// §3.4）：点服务端会话进聊天页续聊时，GET
/// /api/sessions/{id}/messages 拉回的消息先过本过滤
/// 才落本地线程。
///
/// 口径：只取 user／assistant 且正文非空（去首尾空白
/// 后非空）的消息、保持服务端原序；工具／系统消息不
/// 进本地线程——它们既不作聊天气泡渲染、也不进发送
/// 时的上下文重放（原文查看走「会话信息」页的工具调用
/// 摘要行＋DisclosureGroup，不在此处落盘）。
public enum SessionHistoryImport {
    /// 一条可导入消息（角色／正文／服务端时间戳换算的日期）
    public struct Entry: Equatable, Sendable {
        public let role: String
        public let content: String
        public let date: Date?

        public init(role: String, content: String, date: Date?) {
            self.role = role
            self.content = content
            self.date = date
        }
    }

    public static func importableEntries(
        from messages: [SessionMessage]
    ) -> [Entry] {
        messages.compactMap { message in
            guard message.role == "user" || message.role == "assistant",
                  !message.content.trimmingCharacters(
                      in: .whitespacesAndNewlines
                  ).isEmpty
            else { return nil }
            return Entry(
                role: message.role,
                content: message.content,
                date: message.date
            )
        }
    }

    /// 导入线程的标题口径与会话详情同源：首条用户消息
    /// 摘要（ServerSession.contentTitle），无会话元信息
    /// 时回落「未命名会话」
    public static func threadTitle(
        session: ServerSession?,
        entries: [Entry]
    ) -> String {
        let firstUser = entries.first { $0.role == "user" }?.content
        guard let session else {
            return ServerSession.contentSummaryTitle(firstUser)
                ?? "未命名会话"
        }
        return session.contentTitle(firstUserMessage: firstUser)
    }
}
