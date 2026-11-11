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
    /// 关联的服务端会话 id（/api/sessions/{id}）：从
    /// 服务端会话导入续聊的线程导入时落；App 内新建
    /// 旁聊 0.21.0 起首发即建真会话落 id（此前恒
    /// nil——无状态重放不建会话，是标题断环的根）；
    /// 建会话失败的线程暂为 nil、下次发送再试（可
    /// 选＋默认 nil、SwiftData 轻量迁移）
    var serverSessionID: String? = nil
    /// 标题是否用户手改（0.20.0）：抽屉/管理页本地改名
    /// 时置 true——手改名永不被服务端 AI 标题覆盖
    /// （DrawerThreadTitle 解析口径；默认 false、Swift-
    /// Data 轻量迁移。此前本地存储无此标记，标题回流
    /// 无从分辨手改与派生，是 0.20.0 第三条的补环）
    var titleIsManual: Bool = false
    /// 旁聊链接失败留痕（0.21.0）：App 内旁聊首发建
    /// 服务端会话失败的累计次数与最近一次原因——
    /// 失败不挡消息（回退无状态重放）、不静默，下
    /// 次发送再试链接；链接成功即清零（状态机见
    /// OneDayCore.SideChatLink；默认值、SwiftData
    /// 轻量迁移）
    var linkFailureCount: Int = 0
    var linkLastError: String? = nil
    /// 本线程链接时锁定的模型（0.21.0）：建会话以
    /// require_model_lock 落锁时记下（＝建时胶囊所
    /// 选）；此后胶囊改选与记录不一致才推一次会话
    /// 内切换（POST /api/sessions/{id}/model）。导
    /// 入线程为 nil——锁非我方所设、永不代推（可
    /// 选＋默认 nil、SwiftData 轻量迁移）
    var linkedModel: String? = nil
    /// 服务端种子已落位（0.27.0）：本线程的历史已
    /// 经导入导入其自有 oneday- 会话（或线程出生即
    /// 带服务端历史——续聊导入线程落盘时直接置
    /// true）。自有会话未种子前不许进会话模式发送
    /// （发送计划见 SideChatLink.sendPlan）；合并桶
    /// 解绑重链时随新绑定重新种子（默认 false、
    /// SwiftData 轻量迁移）
    var serverSeeded: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \ChatEntry.thread)
    var entries: [ChatEntry] = []

    init(title: String = L10n.string("新会话")) {
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
    /// 0.46.1（§116）：历史导入/对账补缺的 user 消息
    /// 里网关展开块剥出的非图片附件路径（JSON 编码，
    /// 与 remoteImagePathsData 同形态）——呈现走用户
    /// 气泡文件牌、点开同走文件下载通道
    var remoteFilePathsData: Data? = nil
    var createdAt: Date
    var thread: ChatThread?

    init(role: String, content: String, thread: ChatThread? = nil, imageData: Data? = nil, quote: MessageQuote? = nil, reasoning: String? = nil, reasoningSeconds: Double? = nil, toolCard: ToolCard? = nil, remoteImagePaths: [String] = [], remoteFilePaths: [String] = []) {
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
        remoteFilePathsData = remoteFilePaths.isEmpty
            ? nil
            : try? JSONEncoder().encode(remoteFilePaths)
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

    /// 服务端文件路径（历史导入/对账补缺的用户附件用）
    var remoteFilePaths: [String] {
        guard let remoteFilePathsData else { return [] }
        return (try? JSONDecoder().decode(
            [String].self, from: remoteFilePathsData
        )) ?? []
    }

    /// 落盘两字段 → 引用值对象（任一缺失即无引用）
    var quote: MessageQuote? {
        guard let quoteRole, let quoteContent else { return nil }
        return MessageQuote(role: quoteRole, content: quoteContent)
    }
}
