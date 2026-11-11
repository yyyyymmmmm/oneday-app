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

        public init(
            role: String, content: String, date: Date?,
            imagePaths: [String], toolCard: ToolCard?,
            fileRefs: [String] = []
        ) {
            self.role = role
            self.content = content
            self.date = date
            self.imagePaths = imagePaths
            self.toolCard = toolCard
            self.fileRefs = fileRefs
        }
    }

    /// user 消息规范化（0.46.1，§116 单点）：网关展开
    /// 块（AttachedContextRef）与图片标记（Attached
    /// ImageRef）一并剥离，还原（干净正文，图片路径，
    /// 文件路径）。导入、对账补缺、对账判同三处同走
    /// 本口径，不许各写一份
    public struct NormalizedUserContent: Equatable, Sendable {
        public let text: String
        public let imagePaths: [String]
        public let fileRefs: [String]

        public init(
            text: String, imagePaths: [String], fileRefs: [String]
        ) {
            self.text = text
            self.imagePaths = imagePaths
            self.fileRefs = fileRefs
        }

        /// 附件路径全集（图片＋文件）——判同的路径集口径
        public var allPaths: [String] { imagePaths + fileRefs }
    }

    public static func normalizedUserContent(
        _ content: String
    ) -> NormalizedUserContent {
        let attached = AttachedContextRef.parse(content)
        let imageParsed = AttachedImageRef.parse(attached.text)
        var imagePaths = attached.imagePaths
        for path in imageParsed.paths
        where !imagePaths.contains(path) {
            imagePaths.append(path)
        }
        return NormalizedUserContent(
            text: imageParsed.text, imagePaths: imagePaths,
            fileRefs: attached.fileRefs
        )
    }

    public static func richItems(
        from messages: [SessionMessage]
    ) -> [RichItem] {
        ToolCardBuilder.build(from: messages).compactMap { item in
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
                        message.content
                    )
                    guard !normalized.text.isEmpty
                            || !normalized.imagePaths.isEmpty
                            || !normalized.fileRefs.isEmpty
                    else { return nil }
                    return RichItem(
                        role: message.role,
                        content: normalized.text,
                        date: message.date,
                        imagePaths: normalized.imagePaths,
                        toolCard: nil,
                        fileRefs: normalized.fileRefs
                    )
                }
                let parsed = AttachedImageRef.parse(message.content)
                guard !parsed.text.isEmpty || !parsed.paths.isEmpty
                else { return nil }
                return RichItem(
                    role: message.role, content: parsed.text,
                    date: message.date, imagePaths: parsed.paths,
                    toolCard: nil
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
