import Foundation

/// 消息引用（0.4.1，聊天页长按「回复」）：引用状态与
/// 发送上下文注入的纯逻辑，与视图层分离、单测把守。
///
/// 口径：
/// - 引用是值快照（角色＋正文），不持 SwiftData 对象
///   引用——被引消息所在线程被删/切换都不悬挂。
/// - 落盘只存角色与正文两字段（ChatEntry.quoteRole /
///   quoteContent），正文存原文；摘要与注入拼装都在
///   读时经本文件函数生成，口径全仓一处。
/// - 注入走现有无状态重放发送链：引用不新增 API 字段，
///   只在组装本轮上下文时把引用块拼进对应 user 消息的
///   content（历史消息回放同口径，见 outgoingContent）。
public struct MessageQuote: Equatable, Sendable {
    /// "user" / "assistant"（与 ChatMessage.role 同口径）
    public let role: String
    /// 被引消息正文原文
    public let content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }

    /// 注入上下文时引用正文的字符上限：长回复全文引用
    /// 会把每轮重放的上下文撑爆，截断并明示省略；引用
    /// 条/引用块的视觉摘要另走 summary（更短）
    public static let injectionCharacterLimit = 1000

    /// 人话称呼：助手恒为 Hermes（产品内智能体名），
    /// 用户为「我」；未知角色回落「对方」
    public static func speakerName(for role: String) -> String {
        switch role {
        case "assistant": return "Hermes"
        case "user": return "我"
        default: return "对方"
        }
    }

    /// 一行摘要：折叠全部空白（含换行）为单空格、去首尾，
    /// 超长截断加省略号。引用条（发送舱上方）与引用块
    /// （已发送消息顶部）共用，保证两处口径一致
    public func summary(maxLength: Int = 60) -> String {
        let collapsed = content
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard collapsed.count > maxLength else { return collapsed }
        return String(collapsed.prefix(maxLength)) + "…"
    }

    /// 引用块正文（注入用）：超 injectionCharacterLimit
    /// 截断并以「…（以下省略）」明示，不静默截断
    public var injectionText: String {
        guard content.count > Self.injectionCharacterLimit else {
            return content
        }
        return String(content.prefix(Self.injectionCharacterLimit))
            + "\n…（以下省略）"
    }

    /// 组装一条消息发往服务端的 content：无引用原样
    /// 返回；有引用时在正文前拼引用块——
    /// 「[引用 {称呼} 的消息]\n{引用正文}\n\n{正文}」。
    /// 正文为空（纯图片发送带引用）时只发引用块本身。
    /// 发送链的历史回放映射与本轮新消息共用本函数，
    /// 引用在后续轮次里持续在场、口径一致
    public static func outgoingContent(
        userText: String, quote: MessageQuote?
    ) -> String {
        guard let quote else { return userText }
        let block = "[引用 \(speakerName(for: quote.role)) 的消息]\n"
            + quote.injectionText
        guard !userText.isEmpty else { return block }
        return block + "\n\n" + userText
    }
}

/// 长按菜单四项的 SF Symbol 名（0.4.1）：符号名收敛在
/// 此一处，视图层不散写字符串；存在性由单测以
/// UIImage(systemName:) 逐个钉死，写错名 CI 当场红
public enum MessageActionSymbols {
    public static let reply = "arrowshape.turn.up.left"
    public static let copy = "doc.on.doc"
    public static let select = "text.viewfinder"
    public static let share = "square.and.arrow.up"
    /// 0.7.0（M4 分流动作）：「在旁聊里接着问」
    public static let fork = "arrow.triangle.branch"

    public static let all = [reply, copy, select, share, fork]
}
