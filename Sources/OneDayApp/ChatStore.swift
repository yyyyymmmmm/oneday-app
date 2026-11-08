import Foundation
import SwiftData

/// 本地会话（里程碑 1 存储从简：SwiftData 两表）。
/// 服务端会话（/api/sessions）与本地会话的对应关系留待
/// 里程碑 2 会话管理时打通，此处只存本机聊天记录。
@Model
final class ChatThread {
    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \ChatEntry.thread)
    var entries: [ChatEntry] = []

    init(title: String = "新会话") {
        id = UUID()
        self.title = title
        createdAt = Date()
        updatedAt = Date()
    }

    /// 按时间排序的消息（视图层统一走它，不散落 sort）
    var sortedEntries: [ChatEntry] {
        entries.sorted { $0.createdAt < $1.createdAt }
    }
}

@Model
final class ChatEntry {
    var id: UUID
    /// "user" / "assistant"（与 ChatMessage.role 同口径）
    var role: String
    var content: String
    var createdAt: Date
    var thread: ChatThread?

    init(role: String, content: String, thread: ChatThread? = nil) {
        id = UUID()
        self.role = role
        self.content = content
        createdAt = Date()
        self.thread = thread
    }
}
