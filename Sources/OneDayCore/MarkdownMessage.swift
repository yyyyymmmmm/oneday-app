import Foundation

/// 消息级段落装配（§161 聊天文本选择修复包）：把
/// MarkdownParser 的块序列重组为「呈现段」——连续的
/// 散文块（段落／标题／普通列表）合并成一段 prose，
/// 由 App 层装进**单个** UITextView 的同一文本存储。
///
/// 为什么必须合并（外部核查，诊断报告
/// chat-text-selection-diagnosis-20261111）：苹果自家
/// Messages／Notes 的选择体系（双击选词／手柄跨行扩
/// 选）建立在整段内容同处一个文本存储的前提上；
/// SwiftUI .textSelection 与逐块独立文本视图都给不出
/// 跨块选区。§149 已把每个块各自装进一个 UITextView，
/// 块内可选、跨块不可扩，且真机双击不达标——本装配
/// 把「一块一视图」改成「一消息一段一视图」。
///
/// 分流口径（逐项记账、非静默绕过）：
/// - 引用块：左竖条是独立装饰视图、跨不了文本存储，
///   整块独立成段（块内多行仍同处一个视图，§149 既有
///   形态）；与前后散文之间的跨界选择不提供。
/// - 任务清单：勾选框是 SF Symbol 图形标记、不是文
///   字，含任务项的列表整块独立成段走旧呈现（项内
///   文本仍可选）；普通列表的标记（•／◦／▪／序号）
///   是文字，进合并段由段落制表位排悬挂缩进。
/// - 代码块：横向滚动＋复制钮是独立表面，独立成段
///   （块内选择口径见 DESIGN §161.4）。
/// - 表格：Grid 布局＋横滑，独立成段（单元格次档
///   选择维持 §149 口径）。
/// - 分割线：无字，独立成段。
public enum MarkdownMessageSegment: Equatable {
    /// 合并散文段：一份文本存储的全部段落
    case prose([MarkdownProseParagraph])
    /// 引用块整段（行结构与解析层同源）
    case quote([MarkdownQuoteLine])
    /// 代码块整段
    case code(code: String, language: String?)
    /// 表格整段
    case table(
        header: [String],
        alignments: [MarkdownTableAlignment],
        rows: [[String]]
    )
    /// 含任务项的列表整块（旧呈现）
    case taskList([MarkdownListItem])
    /// 分割线
    case divider
}

/// 合并散文段内的一段：语义 run 已由 InlineRunBuilder
/// 产出（与 §149 逐块路径同一拼装口径），App 层只做
/// 字体／颜色／标记的呈现映射，不再解析 markdown。
public struct MarkdownProseParagraph: Equatable {
    public enum Kind: Equatable {
        case body
        case heading(level: Int)
        /// 普通列表项：level 为嵌套层，marker 为
        /// bullet／ordered（task 已在装配层分流，
        /// 不会到达这里；类型上保留以与解析层同源）
        case listItem(level: Int, marker: MarkdownListItem.Marker)
    }

    public var kind: Kind
    public var runs: [InlineRun]
    /// 段后距档：true＝同块行间（列表项与项之间，
    /// App 映射 spacingXS）；false＝块间（App 映射
    /// spacingSM）。段序列最后一项的段后距由呈现层
    /// 归零，本标记不生效
    public var tightAfter: Bool

    public init(
        kind: Kind, runs: [InlineRun], tightAfter: Bool = false
    ) {
        self.kind = kind
        self.runs = runs
        self.tightAfter = tightAfter
    }
}

public enum MarkdownMessageAssembler {
    /// 块序列 → 呈现段序列（顺序与原文一致，空输入
    /// 产空序列）
    public static func segments(
        from blocks: [MarkdownBlock]
    ) -> [MarkdownMessageSegment] {
        var result: [MarkdownMessageSegment] = []
        var prose: [MarkdownProseParagraph] = []

        func flushProse() {
            guard !prose.isEmpty else { return }
            result.append(.prose(prose))
            prose = []
        }

        for block in blocks {
            switch block {
            case .paragraph(let text):
                // 段落整形与 §149 逐块路径同口径：仅
                // 段落过 prettyWrapDocument（标题／列
                // 表／引用不整形，旧路径如此）
                prose.append(MarkdownProseParagraph(
                    kind: .body,
                    runs: InlineRunBuilder.runs(
                        for: TextShaping.prettyWrapDocument(text)
                    )
                ))
            case .heading(let text, let level):
                prose.append(MarkdownProseParagraph(
                    kind: .heading(level: level),
                    runs: InlineRunBuilder.runs(for: text)
                ))
            case .list(let items):
                if items.contains(where: {
                    if case .task = $0.marker { return true }
                    return false
                }) {
                    flushProse()
                    result.append(.taskList(items))
                } else {
                    for (index, item) in items.enumerated() {
                        prose.append(MarkdownProseParagraph(
                            kind: .listItem(
                                level: item.level,
                                marker: item.marker
                            ),
                            runs: InlineRunBuilder.runs(
                                for: item.text
                            ),
                            tightAfter: index < items.count - 1
                        ))
                    }
                }
            case .blockquote(let lines):
                flushProse()
                result.append(.quote(lines))
            case .code(let code, let language):
                flushProse()
                result.append(.code(code: code, language: language))
            case .table(let header, let alignments, let rows):
                flushProse()
                result.append(.table(
                    header: header,
                    alignments: alignments,
                    rows: rows
                ))
            case .divider:
                flushProse()
                result.append(.divider)
            }
        }
        flushProse()
        return result
    }

    /// 便捷入口：原文 → 呈现段（解析＋装配）
    public static func segments(
        for content: String
    ) -> [MarkdownMessageSegment] {
        segments(from: MarkdownParser.parse(content))
    }
}
