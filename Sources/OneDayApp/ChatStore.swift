import Foundation
import SwiftData

/// 本地会话（里程碑 1 存储从简：SwiftData 两表）。
/// 0.4.0（审计 §3.4）：服务端会话与本地线程的映射打通
/// ——续聊导入时把服务端会话 id 落在 serverSessionID，
/// 再点同一条服务端会话按 id 找回本线程、不重复导入。
@Model
final class ChatThread {
    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    /// 侧边栏置顶（0.3.6，§21；默认 false、SwiftData
    /// 轻量迁移，置顶组口径见 SidebarGrouping）
    var isPinned: Bool = false
    /// 关联的服务端会话 id（/api/sessions/{id}）：本机
    /// 发起的会话为 nil；从服务端会话导入续聊的线程非
    /// nil（可选＋默认 nil、SwiftData 轻量迁移）
    var serverSessionID: String? = nil

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
    /// 0.2.1：随消息发送的首张图片（JPEG 数据），气泡回显用；
    /// 多图发送时其余图片不落盘（只走当次请求）
    var imageData: Data?
    var createdAt: Date
    var thread: ChatThread?

    init(role: String, content: String, thread: ChatThread? = nil, imageData: Data? = nil) {
        id = UUID()
        self.role = role
        self.content = content
        self.imageData = imageData
        createdAt = Date()
        self.thread = thread
    }
}
