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

    /// 人话称呼：助手为产品内智能体名（缺省 Hermes、
    /// 0.36.22 起呈现层传档案显示名跟随改名），用户
    /// 为「我」；未知角色回落「对方」
    public static func speakerName(for role: String) -> String {
        speakerName(for: role, assistantName: AgentName.fallback)
    }

    /// 人话称呼（带智能体显示名）：引用条/回复状态文
    /// 案是露脸面，助手称呼跟随本地档案显示名，与页
    /// 头/胶囊同源（0.36.22 档案收敛）
    public static func speakerName(
        for role: String, assistantName: String
    ) -> String {
        switch role {
        case "assistant": return assistantName
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

    /// 引用块正文（注入用）：**全文原样**，不设上限、不
    /// 拼任何标记（0.36.19 定版，错题本 P-12）。旧口径
    /// （0.4.1）曾以 1000 字为上限截断并拼「…（以下省
    /// 略）」明示——2026-11-11 真机定案：打包给模型的
    /// 用户内容被砍残、编辑标记还进了模型正文，Hermes
    /// 拿到半截引用反问用户。口径改照 Muse 全文打
    /// 包：被引内容本就在会话内、每轮重放已有尾 20 条
    /// 管总盘，单条引用不再设备级截断。引用条/引用块
    /// 的视觉摘要另走 summary（更短），与注入不同源
    public var injectionText: String { content }

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

    /// outgoingContent 的逆运算（收敛包，2026-11-24）：
    /// 把线格式「[引用 {称呼} 的消息]\n{引用正文}\n\n
    /// {正文}」拆回（引用，正文）；纯引用块形（正文为
    /// 空的发送）拆得正文为空串。历史导入/回补靠本函
    /// 数把落进服务端历史的引用块还原成槽位（见
    /// SessionHistoryImport.normalizedUserContent），
    /// 不再让线格式原文直进气泡。
    ///
    /// 角色由称呼反推：「我」→ user，其余一律
    /// assistant——引用只许指向 user/assistant 两类
    /// 消息，助手称呼是档案显示名、无从反查角色，归
    /// assistant 是唯一自洽解。同族块头（[引用动态：
    /// 《…》] 等）不以「 的消息]」收尾，天然不命中。
    ///
    /// 切分歧义：引用正文与正文都可含空行，单凭分隔
    /// 形无唯一解。knownQuoteTexts 给出候选全集（同
    /// 批消息的呈现正文集）时，优先取「引用正文恰等
    /// 于某条已知消息」的切法；无命中时取最后一个空
    /// 行界——引用助手长文（Markdown 段落空行是常
    /// 态）保全优先，正文多为短句。指纹不依赖切分精
    /// 度：两侧都经 outgoingContent 从（正文，引用）
    /// 重组线格式，任何切法拼回去都是同一线格式
    /// （SessionHistorySync 指纹口径），切错只伤呈
    /// 现不伤判同。
    ///
    /// 已知边界：用户亲笔正文若恰以同形块头起笔会被
    /// 误拆——线格式无转义层，此为格式固有歧义（与
    /// AttachedContext 标记同性质）；且本地亲笔条目
    /// 恒带槽位、回补判同走重组不走本函数，误拆只可
    /// 能发生在导入外来历史时。
    public static func parse(
        wireContent: String, knownQuoteTexts: Set<String> = []
    ) -> (quote: MessageQuote, body: String)? {
        guard let firstNewline = wireContent.firstIndex(of: "\n")
        else { return nil }
        let header = wireContent[..<firstNewline]
        let headerPrefix = "[引用 "
        let headerSuffix = " 的消息]"
        guard header.hasPrefix(headerPrefix),
              header.hasSuffix(headerSuffix)
        else { return nil }
        let name = String(
            header.dropFirst(headerPrefix.count)
                .dropLast(headerSuffix.count)
        )
        guard !name.isEmpty else { return nil }
        let role = name == "我" ? "user" : "assistant"
        let rest = String(
            wireContent[wireContent.index(after: firstNewline)...]
        )
        var splits: [(quote: String, body: String)] = []
        var searchStart = rest.startIndex
        while let range = rest.range(
            of: "\n\n", range: searchStart..<rest.endIndex
        ) {
            splits.append((
                quote: String(rest[..<range.lowerBound]),
                body: String(rest[range.upperBound...])
            ))
            searchStart = range.upperBound
        }
        guard let fallback = splits.last else {
            return (MessageQuote(role: role, content: rest), "")
        }
        if !knownQuoteTexts.isEmpty,
           let hit = splits.first(where: {
               knownQuoteTexts.contains($0.quote)
           }) {
            return (
                MessageQuote(role: role, content: hit.quote),
                hit.body
            )
        }
        return (
            MessageQuote(role: role, content: fallback.quote),
            fallback.body
        )
    }

    /// 引用分发收口（§208）：一条用户消息至多带一
    /// 种引用——消息引用与动态引用在发送舱共用同
    /// 一槽位、落盘互斥（ChatEntry 的 quote 两字段
    /// 与 feedPost 四字段不同时有值）。动态引用在
    /// 场走 FeedPostQuote 变体，否则走消息引用原
    /// 口径。发送组装与同 key 重演组装共用本函数，
    /// 口径全仓一处
    public static func outgoingContent(
        userText: String, quote: MessageQuote?,
        feedQuote: FeedPostQuote?
    ) -> String {
        if let feedQuote {
            return FeedPostQuote.outgoingContent(
                userText: userText, feedQuote: feedQuote
            )
        }
        return outgoingContent(userText: userText, quote: quote)
    }

    /// 引用分发收口·来源引用变体（§219，推广
    /// §208 的 feed 专用三参变体）：来源引用（动
    /// 态／点子／文件，SourceQuote 统一载荷）在
    /// 场时优先于消息引用——一条用户消息至多带
    /// 一种引用、槽位单一在场（发送舱互斥纪律）。
    /// 发送组装与杀进程重演组装共用本函数，两处
    /// 拼装口径不许分叉；上之三参变体保留（Core
    /// 既有钉测与回放兼容面），新调用点一律走本
    /// 变体
    public static func outgoingContent(
        userText: String, quote: MessageQuote?,
        sourceQuote: SourceQuote?
    ) -> String {
        if let sourceQuote {
            return sourceQuote.outgoingContent(
                userText: userText
            )
        }
        return outgoingContent(userText: userText, quote: quote)
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
    /// H2-a（台账 159）：助手消息「朗读／停止朗读」
    public static let speak = "speaker.wave.2"
    public static let speakStop = "stop.circle"
    /// 台账 154（DESIGN §342）：发件箱三项——未发
    /// 送条目动作面的重新发送／编辑／撤回
    public static let resend = "arrow.clockwise"
    public static let editUnsent = "pencil"
    public static let withdrawUnsent = "trash"
    /// D3（DESIGN §352）：已发消息「编辑」——与未发
    /// 编辑同名同图符（两项互斥在席、永不并存）
    public static let editSent = "pencil"
    /// D2（DESIGN §352）：末轮回答「重新生成」
    public static let regenerate = "arrow.counterclockwise"
    /// 0.50.80 热修：长按菜单「添加反应」子菜单图符
    public static let react = "face.smiling"
    /// D1（台账 5）：播放条主钮——暂停/继续
    public static let speakPause = "pause.fill"
    public static let speakResume = "play.fill"

    public static let all = [
        reply, copy, select, share, fork, speak, speakStop,
        speakPause, speakResume, react,
        resend, editUnsent, withdrawUnsent,
        editSent, regenerate,
    ]
}
