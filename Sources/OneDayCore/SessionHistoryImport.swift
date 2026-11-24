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

    /// 富内容导入项（0.8.0，P1）：普通消息（正文已剥
    /// 图片附件标记、路径单列）与工具卡（role="tool"）
    /// 按服务端原序混排；过滤门与旧口径同：正文空且无
    /// 图的消息不进线程（其工具调用已成卡，不丢）
    public struct RichItem: Sendable {
        public let role: String
        public let content: String
        public let date: Date?
        public let imagePaths: [String]
        public let toolCard: ToolCard?
        /// 0.46.1（§116）：user 消息展开块里剥出的非图
        /// 片附件路径（呈现走用户气泡文件牌）；助手消
        /// 息恒空（其文件引用由正文探测出牌，旧口径）
        public let fileRefs: [String]
        /// 台账 187：服务端行 id（SessionMessage.id 的
        /// 整数形）——落盘钉进 ChatEntry.serverRowID
        /// 作反应寻址坐标；工具卡项与异常 id 恒 nil。
        /// 不进回补指纹（指纹口径一字不动）
        public let serverRowID: Int?
        /// 台账 187：服务端反应全集——落盘覆写条目
        /// 镜像（服务端唯一真源）；工具卡项恒空
        public let reactions: [MessageReaction]
        /// 总表 203／§441：选择框载荷——不进条目本
        /// 体（v1 瞬态覆盖层口径），由导入侧按尾位规
        /// 则播种覆盖层；工具卡项恒 nil
        public let options: MessageOptions?
        /// 收敛包（2026-11-24，P3-1）：user 消息正文
        /// 首引用块拆出的引用槽位——落盘回填 Chat-
        /// Entry.quoteRole/quoteContent，正文只存干
        /// 净正文；非 user 项与无引用项恒 nil
        public let quote: MessageQuote?

        public init(
            role: String, content: String, date: Date?,
            imagePaths: [String], toolCard: ToolCard?,
            fileRefs: [String] = [],
            serverRowID: Int? = nil,
            reactions: [MessageReaction] = [],
            options: MessageOptions? = nil,
            quote: MessageQuote? = nil
        ) {
            self.role = role
            self.content = content
            self.date = date
            self.imagePaths = imagePaths
            self.toolCard = toolCard
            self.fileRefs = fileRefs
            self.serverRowID = serverRowID
            self.reactions = reactions
            self.options = options
            self.quote = quote
        }
    }

    /// user 消息规范化（0.46.1，§116 单点）：网关展开
    /// 块（AttachedContextRef）与图片标记（Attached
    /// ImageRef）一并剥离，还原（干净正文，图片路径，
    /// 文件路径）。收敛包（2026-11-24）补第三种剥离：
    /// 正文首的引用块（MessageQuote 线格式）拆回引用
    /// 槽位（quote），不再混在正文里。导入、对账补
    /// 缺、对账判同三处同走本口径，不许各写一份
    public struct NormalizedUserContent: Equatable, Sendable {
        public let text: String
        public let imagePaths: [String]
        public let fileRefs: [String]
        /// 收敛包（2026-11-24，P3-1）：正文首引用块
        /// 拆出的引用槽位——与正文分开走，不再让
        /// 「[引用 …]」线格式原文混进正文；无引用
        /// 恒 nil
        public let quote: MessageQuote?

        public init(
            text: String, imagePaths: [String], fileRefs: [String],
            quote: MessageQuote? = nil
        ) {
            self.text = text
            self.imagePaths = imagePaths
            self.fileRefs = fileRefs
            self.quote = quote
        }

        /// 附件路径全集（图片＋文件）——判同的路径集口径
        public var allPaths: [String] { imagePaths + fileRefs }
    }

    public static func normalizedUserContent(
        _ content: String, knownQuoteTexts: Set<String> = []
    ) -> NormalizedUserContent {
        let attached = AttachedContextRef.parse(content)
        let imageParsed = AttachedImageRef.parse(attached.text)
        var imagePaths = attached.imagePaths
        for path in imageParsed.paths
        where !imagePaths.contains(path) {
            imagePaths.append(path)
        }
        // 收敛包（2026-11-24，P3-1）：引用块是第三种
        // 脚手架——发送时由 MessageQuote.outgoing-
        // Content 拼在线格式首、落服务端历史后随回
        // 流进来；在此拆回（正文，引用槽位），不许
        // 再让线格式原文混进正文直进气泡
        let parsed = MessageQuote.parse(
            wireContent: imageParsed.text,
            knownQuoteTexts: knownQuoteTexts
        )
        return NormalizedUserContent(
            text: parsed?.body ?? imageParsed.text,
            imagePaths: imagePaths,
            fileRefs: attached.fileRefs,
            quote: parsed?.quote
        )
    }

    /// 服务端行 id 的整数形（台账 187）：id 是 JSON 数
    /// （Double 承载）——整数且为正才成钉桩；0/负/小数
    /// 是异常数据，宁可不钉（不可反应）也不钉错行
    private static func serverRowID(
        of message: SessionMessage
    ) -> Int? {
        guard message.id > 0 else { return nil }
        return Int(exactly: message.id)
    }

    public static func richItems(
        from messages: [SessionMessage]
    ) -> [RichItem] {
        // 收敛包：引用拆解的校验集＝本批消息的呈现正
        // 文集——被引消息多半同批在场，拆解可据实校
        // 验切点（MessageQuote.parse 的歧义口径）
        let knownQuoteTexts = Set(messages.map { message in
            message.role == "user"
                ? normalizedUserContent(message.content).text
                : AttachedImageRef.parse(message.content).text
        })
        return ToolCardBuilder.build(from: messages).compactMap { item in
            switch item {
            case .toolCard(let card, let date):
                return RichItem(
                    role: "tool", content: "", date: date,
                    imagePaths: [], toolCard: card
                )
            case .message(let message):
                // 0.46.1（§116）：user 消息先过规范化
                // ——网关展开块还原成正文＋文件牌路径，
                // 不再把给模型的英文脚手架当用户原话
                // 渲染；assistant 维持图片标记旧口径
                if message.role == "user" {
                    let normalized = normalizedUserContent(
                        message.content,
                        knownQuoteTexts: knownQuoteTexts
                    )
                    // 收敛包：纯引用发送（正文空、只有引
                    // 用块）拆后正文为空——引用在位即算可
                    // 导入，不许被空正文门吞掉整条
                    guard !normalized.text.isEmpty
                            || !normalized.imagePaths.isEmpty
                            || !normalized.fileRefs.isEmpty
                            || normalized.quote != nil
                    else { return nil }
                    return RichItem(
                        role: message.role,
                        content: normalized.text,
                        date: message.date,
                        imagePaths: normalized.imagePaths,
                        toolCard: nil,
                        fileRefs: normalized.fileRefs,
                        serverRowID: Self.serverRowID(
                            of: message
                        ),
                        reactions: message.reactions,
                        options: message.options,
                        quote: normalized.quote
                    )
                }
                let parsed = AttachedImageRef.parse(message.content)
                guard !parsed.text.isEmpty || !parsed.paths.isEmpty
                else { return nil }
                return RichItem(
                    role: message.role, content: parsed.text,
                    date: message.date, imagePaths: parsed.paths,
                    toolCard: nil,
                    serverRowID: Self.serverRowID(of: message),
                    reactions: message.reactions,
                        options: message.options
                )
            }
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
