import Foundation

/// 动态帖引用（§208，动态「讨论」引用化）：点「讨论」
/// 把帖子带进对话的载体——值快照，与 MessageQuote
/// 同哲学：不持原帖对象引用，帖被删/过期引用不悬
/// 挂。引用是发送舱的临时态、不是草稿：永不进
/// drafts 落盘，点 ✕ 即清、切线程作废、杀进程不恢
/// 复；发送后随消息行快照字段落盘（ChatEntry 的
/// feedPost* 四字段），回放拼装经本文件收口。
public struct FeedPostQuote: Equatable, Sendable {
    /// 帖 id（回跳锚＋失效判定，必填）
    public let postID: String
    /// 帖标题快照
    public let title: String
    /// 正文全文快照（Markdown 原文，不截断）
    public let body: String
    /// 来源呈现行（来源卡名 → 简报方向 → 首链域名
    /// 取一；全缺为空串，呈现与注入都跳过来源行）
    public let sourceLine: String
    /// 首图 URL（引用卡缩略图；无图为 nil、不占位）
    public let imageURL: String?
    /// 行首标识（帖的 displayEmoji 快照）
    public let mark: String

    public init(
        postID: String, title: String, body: String,
        sourceLine: String, imageURL: String? = nil,
        mark: String = ""
    ) {
        self.postID = postID
        self.title = title
        self.body = body
        self.sourceLine = sourceLine
        self.imageURL = imageURL
        self.mark = mark
    }

    /// 自桥帖组装：字段全走 BridgeFeedPost 现成来源，
    /// 不另立第二套帖数据口径
    public init(post: BridgeFeedPost) {
        self.init(
            postID: post.id,
            title: post.title,
            body: post.body,
            sourceLine: Self.sourceLine(for: post),
            imageURL: post.images.first?.url,
            mark: post.displayEmoji
        )
    }

    /// 来源行优先级（规格 §3.1）：来源卡名 → 所属
    /// 简报方向 → links 首条域名；全缺为空串
    public static func sourceLine(
        for post: BridgeFeedPost
    ) -> String {
        if let name = post.sourceCard?.name {
            let trimmed = name.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            if !trimmed.isEmpty { return trimmed }
        }
        if let direction = post.direction {
            let trimmed = direction.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            if !trimmed.isEmpty { return trimmed }
        }
        if let first = post.links.first {
            if let host = URL(string: first.url)?.host,
               !host.isEmpty {
                return host
            }
            return first.url
        }
        return ""
    }

    /// 一行摘要（呈现用）：与 MessageQuote.summary
    /// 同口径（折叠空白、截断加省略号），实现收口
    /// 在彼处、本处只转调（role 不参与摘要计算）
    public func summary(maxLength: Int = 60) -> String {
        MessageQuote(role: "", content: body)
            .summary(maxLength: maxLength)
    }

    /// 组装一条带动态引用的消息发往服务端的
    /// content：引用块在前（块头＋正文全文＋来源
    /// 行）、用户亲笔正文独立在后——身份分开，不
    /// 再冒充用户口吻（旧预填是系统代笔的第一人称
    /// 整段）；正文全文打包不截断（P-12 同口径，
    /// 见 MessageQuote.injectionText）；不新增 API
    /// 字段、走既有无状态重放链，分发收口在
    /// MessageQuote.outgoingContent 三参变体
    public static func outgoingContent(
        userText: String, feedQuote: FeedPostQuote?
    ) -> String {
        guard let feedQuote else { return userText }
        var block = "[引用动态：《\(feedQuote.title)》]"
        let body = feedQuote.body.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if !body.isEmpty {
            block += "\n" + feedQuote.body
        }
        if !feedQuote.sourceLine.isEmpty {
            block += "\n（来源：\(feedQuote.sourceLine)）"
        }
        guard !userText.isEmpty else { return block }
        return block + "\n\n" + userText
    }
}

/// 旧预填草稿的存量判定（§208 包 3）：一段草稿是
/// 否为 FeedDiscussPrefill.make 对某帖的机器输出
/// ——三语（简/繁/英）逐一再生、任一逐字相等才
/// 算；用户改过一字即不相等、清扫不动（判定从
/// 严）。消费点只有 SideChatStore 的存量清扫一
/// 处，清扫须拿原帖（标题＋正文）再生比对，不许
/// 凭结构特征猜测（改一字与原样在结构上同形，
/// 只有逐字再生能分开）
public enum FeedDiscussDraftCleanup {
    /// 预填的历史生成语言候选（三档显式语言；
    /// 「跟随系统」生成的实际语言同样落在这三档
    /// 的某一种里）
    public static let candidateLocales: [Locale] = [
        Locale(identifier: "zh-Hans"),
        Locale(identifier: "zh-Hant"),
        Locale(identifier: "en"),
    ]

    public static func isMachinePrefill(
        _ text: String, title: String, body: String
    ) -> Bool {
        candidateLocales.contains { locale in
            FeedDiscussPrefill.make(
                title: title, body: body, locale: locale
            ) == text
        }
    }
}
