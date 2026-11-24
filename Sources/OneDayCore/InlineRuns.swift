import Foundation

/// 行内富文本 run（§149 聊天文本可选包）：气泡正文的
/// 行内拼装从「SwiftUI AttributedString 直渲」改成
/// 「Core 产语义 run、App 层映射 NSAttributedString
/// 喂 UITextView」——选段能力在 iOS 26 上只有
/// UITextView 有（外部核查见 DESIGN §149.2），而
/// markdown 的读法（哪些段算 strong／code／link）
/// 必须与旧渲染逐项同口径、且可测，故下沉本层。
///
/// run 只持语义标记、不碰字体颜色：字号字重颜色全
/// 在 App 层按角色（段落／标题／引用／用户泡）映射，
/// 与 MarkdownText 旧口径（strong 只对应内容本身
/// 的 **）一一对应。
public struct InlineRun: Equatable, Sendable {
    public var text: String
    public var strong: Bool
    public var emphasis: Bool
    public var code: Bool
    public var link: URL?
    public var strikethrough: Bool

    public init(
        text: String,
        strong: Bool = false,
        emphasis: Bool = false,
        code: Bool = false,
        link: URL? = nil,
        strikethrough: Bool = false
    ) {
        self.text = text
        self.strong = strong
        self.emphasis = emphasis
        self.code = code
        self.link = link
        self.strikethrough = strikethrough
    }
}

public enum InlineRunBuilder {
    /// 行内 markdown → run 序列。§417 起默认路由
    /// swift-markdown 树行内 Visitor 直产（强弱／
    /// 代码／链接／删除线都是树结构事实）；回滚位
    /// （MarkdownEngine）走旧路：先经 Markdown-
    /// Inline 切删除线段，段内再走系统行内解析读
    /// InlinePresentationIntent。两路同口径：代码
    /// 不升 strong、不叠斜体；链接取目标；未闭合
    /// 标记字面保留（永不丢字）。相邻同标记 run
    /// 合并，输出确定性与输入顺序一致
    /// §167（2026-11-11）：入口先过解析记忆——段内含
    /// AttributedString(markdown:) 全量解析、是三处入
    /// 口里最贵的一处；同文再算即查表（Markdown-
    /// ParseMemo），纯函数同文同果、输出逐字不变
    public static func runs(for markdownText: String) -> [InlineRun] {
        guard !markdownText.isEmpty else { return [] }
        return MarkdownParseMemos.runs.value(for: markdownText) {
            runsUncached(for: markdownText)
        }
    }

    private static func runsUncached(for markdownText: String) -> [InlineRun] {
        // §417（2026-11-23）：默认路改走树行内
        // Visitor（MarkdownTreeParsing.inlineRuns，
        // swift-markdown 树直产 runs）；旧路（分段＋
        // 系统解析）降为回滚位，见 legacyRunsUncached
        if MarkdownEngine.usesLegacyParser {
            return legacyRunsUncached(for: markdownText)
        }
        return MarkdownTreeParsing.inlineRuns(for: markdownText)
    }

    /// 旧行内路（回滚位）：MarkdownInline 分段＋系统
    /// AttributedString 解析。§417 起仅 Markdown-
    /// Engine 回滚位消费；删除条件与旧块解析器同
    /// 批（见 MarkdownEngine）
    private static func legacyRunsUncached(for markdownText: String) -> [InlineRun] {
        var result: [InlineRun] = []
        for segment in MarkdownInline.segments(markdownText) {
            guard let attributed = try? AttributedString(
                markdown: segment.text,
                options: AttributedString.MarkdownParsingOptions(
                    interpretedSyntax: .inlineOnlyPreservingWhitespace
                )
            ) else {
                append(
                    InlineRun(
                        text: segment.text,
                        strikethrough: segment.strikethrough
                    ),
                    to: &result
                )
                continue
            }
            for run in attributed.runs {
                let intent = run.inlinePresentationIntent
                let isCode = intent?.contains(.code) ?? false
                append(
                    InlineRun(
                        text: String(
                            attributed[run.range].characters
                        ),
                        strong: !isCode
                            && (intent?.contains(.stronglyEmphasized)
                                ?? false),
                        emphasis: !isCode
                            && (intent?.contains(.emphasized)
                                ?? false),
                        code: isCode,
                        link: run.link,
                        strikethrough: segment.strikethrough
                    ),
                    to: &result
                )
            }
        }
        return result
    }

    /// 纯文本 run（用户气泡／整条选择 sheet）：整串
    /// 一个普通 run、绝不解析 markdown——用户原文
    /// 里的 `**`／`~~` 保持字面，与旧裸 Text 呈现
    /// 逐字一致
    public static func plainRuns(_ text: String) -> [InlineRun] {
        text.isEmpty ? [] : [InlineRun(text: text)]
    }

    /// 相邻同标记合并：拼装层按 run 逐个上属性，同
    /// 标记相邻段合一不改变任何呈现、只减 run 数
    private static func append(
        _ run: InlineRun, to result: inout [InlineRun]
    ) {
        guard !run.text.isEmpty else { return }
        if var last = result.last,
           last.strong == run.strong,
           last.emphasis == run.emphasis,
           last.code == run.code,
           last.link == run.link,
           last.strikethrough == run.strikethrough {
            last.text += run.text
            result[result.count - 1] = last
            return
        }
        result.append(run)
    }
}
