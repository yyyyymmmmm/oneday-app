import Foundation

/// 点子引用（§219，点子「开始吧/打开对话」引用化）：
/// 把点子带进对话的载体——值快照，与 FeedPostQuote
/// 同哲学：不持原点子对象引用，点子被删/过期引用
/// 不悬挂。引用是发送舱的临时态、不是草稿：永不
/// 进 drafts 落盘，点 ✕ 即清、切线程作废、杀进程
/// 不恢复；发送后随消息行快照字段落盘（ChatEntry
/// 的 ideaQuote* 三字段），回放拼装经本文件收口。
/// §219 前旧形是 IdeaChatPrefill 预填经 setDraft 直
/// 写草稿账（与亲笔同形、被防丢稿保活永久保护），
/// 与动态讨论同病，本包同型收口
public struct IdeaQuote: Equatable, Sendable {
    /// 点子 id（回跳锚＋失效判定，必填）
    public let ideaID: String
    /// 点子标题快照
    public let title: String
    /// 上下文载荷快照（说明／依据／包含的内容，
    /// 组装收口 IdeaChatContext.body；可为空串——
    /// 只有标题的点子引用块只剩题头）
    public let body: String
    /// 行首标识（点子的呈现 emoji 快照，口径
    /// IdeaEmoji.resolve；落盘不存、回放组装为空）
    public let mark: String

    public init(
        ideaID: String, title: String, body: String,
        mark: String = ""
    ) {
        self.ideaID = ideaID
        self.title = title
        self.body = body
        self.mark = mark
    }

    /// 自桥点子组装：字段全走 BridgeIdea 现成来
    /// 源，载荷组装与旧预填共用 IdeaChatContext
    /// 一口、不另立第二套拼装
    public init(
        idea: BridgeIdea, locale: Locale = AppLocale.uiLocale
    ) {
        self.init(
            ideaID: idea.id,
            title: idea.title,
            body: IdeaChatContext.body(idea: idea, locale: locale),
            mark: IdeaEmoji.resolve(emoji: idea.emoji)
        )
    }

    /// 一行摘要（呈现用）：与 FeedPostQuote.summary
    /// 同口径（经 MessageQuote.summary 收口）
    public func summary(maxLength: Int = 60) -> String {
        MessageQuote(role: "", content: body)
            .summary(maxLength: maxLength)
    }

    /// 组装一条带点子引用的消息发往服务端的
    /// content：引用块在前（块头＋载荷全文）、用
    /// 户亲笔正文独立在后——身份分开，不再冒充
    /// 用户口吻（旧预填的题头句「我们来聊聊这个
    /// 点子」是系统代笔的第一人称，本块头只作标
    /// 识、不带口吻）；不新增 API 字段、走既有无
    /// 状态重放链，分发收口在 MessageQuote 的来
    /// 源引用变体
    public static func outgoingContent(
        userText: String, ideaQuote: IdeaQuote?
    ) -> String {
        guard let ideaQuote else { return userText }
        var block = "[引用点子：《\(ideaQuote.title)》]"
        let body = ideaQuote.body.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if !body.isEmpty {
            block += "\n" + ideaQuote.body
        }
        guard !userText.isEmpty else { return block }
        return block + "\n\n" + userText
    }
}

/// 文件引用（§219，文件打开失败「让智能体重新发」
/// 引用化）：把打不开的文件带回对话的载体——值
/// 快照（文件名＋服务端原路径），与 FeedPostQuote
/// 同哲学。引用生命周期同族：发送舱临时态、永不
/// 进 drafts、✕ 即清、切线程作废、杀进程不恢复；
/// 发送后随消息行快照字段落盘（ChatEntry 的
/// fileQuote* 两字段）。§219 前旧形两路都是机器
/// 文直落亲笔面：无宿主路经 setDraft 直写草稿账、
/// 聊天宿主路直写输入舱 input（切线程时又被回存
/// 进草稿账）——同病两口，本包一并收口
public struct FileQuote: Equatable, Sendable {
    /// 文件名快照（呈现与块头）
    public let name: String
    /// 服务端原路径快照（智能体对账与重发的唯一
    /// 定位凭据；呈现只作次行小字）
    public let path: String

    public init(name: String, path: String) {
        self.name = name
        self.path = path
    }

    /// 自文件打开目标组装（FileOpenView 的现成入
    /// 口类型，不另立第二套文件标识）
    public init(target: FileOpenTarget) {
        self.init(name: target.name, path: target.path)
    }

    /// 回跳落点：引用块点按直接以本目标重开文件
    /// 页（ChatView 既有 fileOpenTarget 通道）
    public var target: FileOpenTarget {
        FileOpenTarget(name: name, path: path)
    }

    /// 一行摘要（呈现用）：路径折叠截断，与
    /// MessageQuote.summary 同口径收口
    public func summary(maxLength: Int = 60) -> String {
        MessageQuote(role: "", content: path)
            .summary(maxLength: maxLength)
    }

    /// 组装一条带文件引用的消息发往服务端的
    /// content：引用块在前——块头＋重发话术全文
    /// （FileResendPrefill 三要点逐字承接：哪个
    /// 文件打不开／原路径单独成行／确认存在后重
    /// 发，语义零丢失）、用户亲笔正文独立在后；
    /// 不新增 API 字段、走既有无状态重放链
    public static func outgoingContent(
        userText: String, fileQuote: FileQuote?
    ) -> String {
        guard let fileQuote else { return userText }
        var block = "[引用文件：《\(fileQuote.name)》]"
        block += "\n" + FileResendPrefill.make(
            name: fileQuote.name, path: fileQuote.path
        )
        guard !userText.isEmpty else { return block }
        return block + "\n\n" + userText
    }
}

/// 来源引用（§219）：发送舱引用槽位的统一载荷——
/// 一条用户消息至多带一种来源引用（动态／点子／
/// 文件），与消息引用（MessageQuote）同槽互斥。
/// §208 的动态引用是第一族；本枚举把槽位从 feed
/// 专用推广为三族共用。投递走按线程寻址直写（与
/// §210 feed 族同型，§219 适配定形）：feed 族沿
/// AppState.pendingFeedQuotesByThread、点子／文件
/// 两族走 AppState.pendingSourceQuotesByThread，
/// ChatView 一律按 currentThreadID 派生呈现——不
/// 经任何种子消费；新增来源族时只扩本枚举与呈
/// 现变体，不再新开平行状态
public enum SourceQuote: Equatable, Sendable {
    case feed(FeedPostQuote)
    case idea(IdeaQuote)
    case file(FileQuote)

    /// 本族的服务端 content 拼装（引用块在前、
    /// 亲笔在后，各族收口在其值类型上）
    public func outgoingContent(userText: String) -> String {
        switch self {
        case .feed(let quote):
            return FeedPostQuote.outgoingContent(
                userText: userText, feedQuote: quote
            )
        case .idea(let quote):
            return IdeaQuote.outgoingContent(
                userText: userText, ideaQuote: quote
            )
        case .file(let quote):
            return FileQuote.outgoingContent(
                userText: userText, fileQuote: quote
            )
        }
    }
}
