import Foundation
import OneDayCore
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
    /// 0.4.1：本条消息引用了哪条消息（长按「回复」）——
    /// 只在发送时由用户消息携带，存被引消息的角色与正文
    /// 原文两字段；摘要与注入拼装读时经 MessageQuote
    /// 生成（可选＋默认 nil、SwiftData 轻量迁移）
    var quoteRole: String? = nil
    var quoteContent: String? = nil
    /// 0.5.1：助手回复的思考原文（reasoning 通道落盘，
    /// §32）——只作折叠单元展示、不回灌请求上下文；
    /// reasoningSeconds 为流内实测思考耗时（首个思考增
    /// 量→首个正文增量或流结束），无思考或无数据为 nil
    /// （可选＋默认 nil、SwiftData 轻量迁移）
    var reasoning: String? = nil
    var reasoningSeconds: Double? = nil
    /// 0.8.0（P1 富内容）：工具调用卡的 JSON 编码 payload
    /// （OneDayCore.ToolCard）——非 nil 即本条是工具卡
    /// （role 恒 "tool"），不作气泡渲染、不进发送上下文
    /// （上下文组装只取 user/assistant，见 ChatView.send）
    var toolCardData: Data? = nil
    /// 0.8.0：历史导入消息里服务端图片路径的 JSON 编码
    /// （[String]）——图片本体在服务器，呈现时经文件
    /// 下载通道取回；本地发送消息的图片仍走 imageData
    var remoteImagePathsData: Data? = nil
    var createdAt: Date
    var thread: ChatThread?

    init(role: String, content: String, thread: ChatThread? = nil, imageData: Data? = nil, quote: MessageQuote? = nil, reasoning: String? = nil, reasoningSeconds: Double? = nil, toolCard: ToolCard? = nil, remoteImagePaths: [String] = []) {
        id = UUID()
        self.role = role
        self.content = content
        self.imageData = imageData
        quoteRole = quote?.role
        quoteContent = quote?.content
        self.reasoning = reasoning
        self.reasoningSeconds = reasoningSeconds
        toolCardData = toolCard.flatMap {
            try? JSONEncoder().encode($0)
        }
        remoteImagePathsData = remoteImagePaths.isEmpty
            ? nil
            : try? JSONEncoder().encode(remoteImagePaths)
        createdAt = Date()
        self.thread = thread
    }

    /// 工具卡 payload 解码（无或损坏为 nil）
    var toolCard: ToolCard? {
        guard let toolCardData else { return nil }
        return try? JSONDecoder().decode(
            ToolCard.self, from: toolCardData
        )
    }

    /// 服务端图片路径（历史导入消息用）
    var remoteImagePaths: [String] {
        guard let remoteImagePathsData else { return [] }
        return (try? JSONDecoder().decode(
            [String].self, from: remoteImagePathsData
        )) ?? []
    }

    /// 落盘两字段 → 引用值对象（任一缺失即无引用）
    var quote: MessageQuote? {
        guard let quoteRole, let quoteContent else { return nil }
        return MessageQuote(role: quoteRole, content: quoteContent)
    }
}
