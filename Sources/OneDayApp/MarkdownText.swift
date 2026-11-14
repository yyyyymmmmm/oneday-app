import OneDayCore
import OneDayDesign
import SwiftUI
import UIKit

/// Markdown 渲染（0.36.25 渲染补全）：块级解析在 Core
/// MarkdownParser（可测层），本视图只按结构呈现——段
/// 落／标题 1–6 级／代码块（语言标＋轻量高亮）／引用
/// 块／列表（嵌套＋任务清单）／表格（横滑）／分割线。
/// 行内走系统 AttributedString 解析（粗斜体、行内代
/// 码、链接），删除线由 Core MarkdownInline 分段补齐
/// （系统行内解析不消费 ~~，审计 §1.2 实证）。流式半
/// 截的降级口径在 Core 解析层（未闭合围栏续渲、半截
/// 表格不成表、未闭合行内标记字面呈现），本视图对任
/// 意中间态文本渲染结果确定、不跳版。
struct MarkdownText: View {
    let content: String
    /// §149：选区活动回报（聊天页据此在选字期间关
    /// 本行右滑引用）；其他消费面不传＝不回报
    let onSelectionChange: ((Bool) -> Void)?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.legibilityWeight) private var legibilityWeight

    init(
        _ content: String,
        onSelectionChange: ((Bool) -> Void)? = nil
    ) {
        self.content = content
        self.onSelectionChange = onSelectionChange
    }

    private var blocks: [MarkdownBlock] {
        MarkdownParser.parse(content)
    }

    /// §168：呈现段（Core 装配）——连续散文合并成
    /// 一段 prose 进单个文本视图；结构块各自成段
    private var segments: [MarkdownMessageSegment] {
        MarkdownMessageAssembler.segments(from: blocks)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingSM) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .prose(let paragraphs):
                    proseView(paragraphs)
                case .quote(let lines):
                    blockquoteView(lines)
                case .code(let code, let language):
                    codeView(code, language: language)
                case .table(let header, let alignments, let rows):
                    tableView(
                        header: header,
                        alignments: alignments,
                        rows: rows
                    )
                case .taskList(let items):
                    listView(items)
                case .divider:
                    GroupDivider()
                }
            }
        }
    }

    // MARK: - 段落与标题

    /// 合并散文段（§168）：整段散文（段落＋标题＋普
    /// 通列表）同住一个 SelectableInlineText＝一个
    /// UITextView 的同一文本存储——双击选词／手柄
    /// 拖扩／跨段扩选在段内连续成立（苹果选择体系
    /// 的前提，诊断报告 chat-text-selection-
    /// diagnosis-20261111）。段间几何与旧逐块呈现同
    /// 值：块间段后距 spacingSM、列表项间 spacingXS、
    /// 末段归零（段间由外层 VStack 的 spacingSM 接）
    private func proseView(
        _ paragraphs: [MarkdownProseParagraph]
    ) -> some View {
        SelectableInlineText(
            paragraphs: Self.proseParagraphs(paragraphs),
            textStyle: .callout,
            foreground: Palette.bodyInk,
            onSelectionChange: onSelectionChange
        )
    }

    /// §251：散文段落映射单源——呈现（proseView）
    /// 与排版产物层（LayoutProductService）共用本
    /// 函数拼装段落，两处永不分家（产物与呈现同源
    /// 是影子对拍成立的前提）；口径改版时同步升
    /// Core LayoutStyleKey.paragraphVersion
    nonisolated static func proseParagraphs(
        _ paragraphs: [MarkdownProseParagraph]
    ) -> [InlineTextParagraph] {
        paragraphs.enumerated().map { index, paragraph in
            var result = InlineTextParagraph(runs: paragraph.runs)
            result.spaceAfter = index == paragraphs.count - 1
                ? 0
                : (paragraph.tightAfter
                    ? OneDayMetrics.spacingXS
                    : OneDayMetrics.spacingSM)
            switch paragraph.kind {
            case .body:
                break
            case .heading(let level):
                result.textStyleOverride =
                    Self.headingTextStyle(level)
                result.dimmed = level >= 6
            case .listItem(let level, let marker):
                result.listMarker = InlineListMarker(
                    text: Self.markerText(
                        marker: marker, level: level
                    ),
                    levelIndent: CGFloat(level)
                        * OneDayMetrics.spacingM,
                    columnWidth: 22,
                    textGap: OneDayMetrics.spacingS
                )
            }
            return result
        }
    }

    /// 列表标记文字（与旧 markerView 同字同档）：
    /// 无序按 level 换字形、有序用序号。task 不会到
    /// 达这里（Core 装配已把含任务项的列表整块分
    /// 流），兜底字形只为不丢标记
    nonisolated private static func markerText(
        marker: MarkdownListItem.Marker, level: Int
    ) -> String {
        switch marker {
        case .bullet:
            return level == 0 ? "•" : (level == 1 ? "◦" : "▪")
        case .ordered(let number):
            return "\(number)."
        case .task(let checked):
            return checked ? "☑" : "☐"
        }
    }

    // 标题分级口径（0.36.25 补 4–6 级）：字阶梯
    // 22／20／17／15／13／13——H1 .title2、H2
    // .title3、H3 .body（17，比正文 16 大一档）、
    // H4 .subheadline、H5/H6 .footnote（H6 再降墨
    // 色分档），任何一级都不与正文同大。§168 起标
    // 题不再独立成视图，字阶经段级覆盖进合并散文
    // 段（proseView），本表仍是唯一映射源

    /// 标题字阶的 UIKit 档（§149）：与 headingFont
    /// 的 SwiftUI 梯逐级同档（title2／title3／
    /// body／subheadline／footnote）
    nonisolated private static func headingTextStyle(
        _ level: Int
    ) -> UIFont.TextStyle {
        switch level {
        case 1: return .title2
        case 2: return .title3
        case 3: return .body
        case 4: return .subheadline
        default: return .footnote
        }
    }

    // MARK: - 代码块

    /// 代码块：头行左语言标（小字次墨，无标不占位）＋
    /// 右复制钮；正文轻量高亮（Core CodeHighlight 五
    /// 类词法），横向可滚（长行不折行撑版），文字可选
    private func codeView(_ code: String, language: String?) -> some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingXS) {
            HStack(alignment: .center) {
                if let language {
                    Text(language)
                        .font(.meta)
                        .foregroundStyle(Palette.inkSecondaryOnFill)
                }
                Spacer(minLength: 0)
                CopyButton(text: code)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                Text(highlighted(code, language: language))
                    .textSelection(.enabled)
            }
            // 右滑引用排除区（0.36.26 §95）：本区横
            // 滑归代码横滚，起始点落在此不触发本行
            // 右滑引用（SwipeReplyModifier 同款）
            .swipeReplyExcluded()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OneDayMetrics.spacingSM)
        .background(
            Palette.fieldFill,
            in: RoundedRectangle(
                cornerRadius: OneDayMetrics.codeCorner
            )
        )
    }

    /// 高亮拼装：等宽 footnote 为底，类色映射——关键
    /// 词紫／字符串绿／数字蓝／注释次墨／普通正文墨
    private func highlighted(
        _ code: String, language: String?
    ) -> AttributedString {
        var result = AttributedString()
        for token in CodeHighlight.tokens(
            code: code, language: language
        ) {
            var piece = AttributedString(token.text)
            piece.font = .system(.footnote, design: .monospaced)
            piece.foregroundColor = Self.color(for: token.kind)
            result.append(piece)
        }
        return result
    }

    private static func color(for kind: CodeTokenKind) -> Color {
        switch kind {
        case .plain: return Palette.bodyInk
        case .keyword: return Palette.codeKeyword
        case .string: return Palette.codeString
        case .comment: return Palette.inkSecondaryOnFill
        case .number: return Palette.codeNumber
        }
    }

    /// §251：引用段落映射单源（同 proseParagraphs
    /// 口径：呈现与产物层共用）；引用文本的可用宽
    /// ＝气泡文本宽 −（竖条 3＋间距 spacingS），宽
    /// 度折算在消费方（产物层 builder）
    nonisolated static func quoteParagraphs(
        _ lines: [MarkdownQuoteLine]
    ) -> [InlineTextParagraph] {
        lines.enumerated().map { index, line in
            InlineTextParagraph(
                runs: InlineRunBuilder.runs(for: line.text),
                headIndent: CGFloat(max(0, line.depth - 1))
                    * OneDayMetrics.spacingM,
                spaceAfter: index == lines.count - 1
                    ? 0 : OneDayMetrics.spacingXS
            )
        }
    }

    // MARK: - 引用块

    /// 引用块（对标 Muse：左竖条＋弱化文字）：竖条走
    /// 装饰弱墨（非文字用途合规），正文用填充面次墨；
    /// depth ≥2 逐级再缩进一档
    private func blockquoteView(
        _ lines: [MarkdownQuoteLine]
    ) -> some View {
        HStack(alignment: .top, spacing: OneDayMetrics.spacingS) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Palette.inkMuted)
                .frame(width: 3)
            // §149：整块合一走单个可选文本（逐行一
            // 段：depth 缩进走段级 headIndent、行间
            // 距走段后距 spacingXS——与旧逐行
            // VStack 的几何同值），整块内任意选段
            SelectableInlineText(
                paragraphs: Self.quoteParagraphs(lines),
                textStyle: .callout,
                foreground: Palette.inkSecondaryOnFill,
                onSelectionChange: onSelectionChange
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 列表

    /// 任务清单（§168 分流后本视图只剩此用途）：勾
    /// 选框是 SF Symbol 图形标记、进不了文本存储，
    /// 含任务项的列表整块留旧呈现——标记列固定宽右
    /// 对齐（序号不跳列），嵌套按 level 逐级缩进；
    /// 任务项呈勾选框形态（只读，呈现非控件），项
    /// 正文仍逐项可选（§149）。普通列表已进合并散
    /// 文段（proseView），不在此渲染
    private func listView(_ items: [MarkdownListItem]) -> some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingXS) {
            ForEach(
                Array(items.enumerated()), id: \.offset
            ) { _, item in
                HStack(
                    alignment: .firstTextBaseline,
                    spacing: OneDayMetrics.spacingS
                ) {
                    markerView(item)
                        .frame(width: 22, alignment: .trailing)
                    // §149：项正文改可选文本；基线以
                    // alignmentGuide 钉到基字体
                    // ascender（inset 归零后的首行
                    // 基线），与标记列保持首行对齐
                    SelectableInlineText(
                        paragraphs: [.markdown(item.text)],
                        textStyle: .callout,
                        foreground: Palette.bodyInk,
                        onSelectionChange: onSelectionChange
                    )
                    .alignmentGuide(.firstTextBaseline) { _ in
                        InlineTextFonts.firstBaseline(
                            textStyle: .callout,
                            category: dynamicTypeSize
                                .contentSizeCategory,
                            boldText: legibilityWeight == .bold
                        )
                    }
                }
                .padding(
                    .leading,
                    CGFloat(item.level) * OneDayMetrics.spacingM
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func markerView(_ item: MarkdownListItem) -> some View {
        switch item.marker {
        case .task(let checked):
            Image(
                systemName: checked
                    ? "checkmark.square.fill" : "square"
            )
            .font(.footnote)
            .foregroundStyle(
                checked ? Palette.success : Palette.inkSecondary
            )
        case .ordered(let number):
            Text("\(number).")
                .font(.callout)
                .foregroundStyle(Palette.inkSecondaryOnFill)
        case .bullet:
            Text(item.level == 0 ? "•" : (item.level == 1 ? "◦" : "▪"))
                .font(.callout)
                .foregroundStyle(Palette.inkSecondaryOnFill)
        }
    }

    // MARK: - 表格

    /// 表格：Grid 按内容定列宽，整体横向可滚（宽表不
    /// 挤字）；表头 bold＋发丝线与行分隔（全 App 同一
    /// 种分隔几何：整行贯通发丝线）；列对齐来自分隔
    /// 行的 : 标记
    private func tableView(
        header: [String],
        alignments: [MarkdownTableAlignment],
        rows: [[String]]
    ) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(
                alignment: .leading,
                horizontalSpacing: OneDayMetrics.spacingM,
                verticalSpacing: OneDayMetrics.spacingXS
            ) {
                GridRow {
                    ForEach(
                        Array(header.enumerated()), id: \.offset
                    ) { column, cell in
                        inline(
                            cell,
                            strongFont: .callout.weight(.bold)
                        )
                        .font(.callout)
                        .foregroundStyle(Palette.bodyInk)
                        // §149 次档（DESIGN §149.3 第
                        // 3 条）：单元格留 SwiftUI
                        // Text＋可选——整格菜单（iOS
                        // 27 起格内选段），不冒充同档
                        .textSelection(.enabled)
                        .frame(
                            maxWidth: .infinity,
                            alignment: Self.frameAlignment(
                                alignments[column]
                            )
                        )
                        .multilineTextAlignment(
                            Self.textAlignment(alignments[column])
                        )
                    }
                }
                GridRow {
                    GroupDivider()
                        .gridCellColumns(header.count)
                }
                ForEach(
                    Array(rows.enumerated()), id: \.offset
                ) { _, row in
                    GridRow {
                        ForEach(
                            Array(row.enumerated()), id: \.offset
                        ) { column, cell in
                            inline(
                                cell,
                                strongFont: .callout.weight(.bold)
                            )
                            .font(.callout)
                            .foregroundStyle(Palette.bodyInk)
                            .textSelection(.enabled)
                            .frame(
                                maxWidth: .infinity,
                                alignment: Self.frameAlignment(
                                    alignments[column]
                                )
                            )
                            .multilineTextAlignment(
                                Self.textAlignment(
                                    alignments[column]
                                )
                            )
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // 右滑引用排除区（0.36.26 §95）：本区横滑归
        // 表格横滚，起始点落在此不触发本行右滑引用
        .swipeReplyExcluded()
    }

    private static func frameAlignment(
        _ alignment: MarkdownTableAlignment
    ) -> Alignment {
        switch alignment {
        case .left: return .leading
        case .center: return .center
        case .right: return .trailing
        }
    }

    private static func textAlignment(
        _ alignment: MarkdownTableAlignment
    ) -> TextAlignment {
        switch alignment {
        case .left: return .leading
        case .center: return .center
        case .right: return .trailing
        }
    }

    // MARK: - 行内

    /// 行内渲染：先经 Core MarkdownInline 切删除线段，
    /// 每段再走系统行内解析；删除线段整段加删线（其
    /// 中的行内代码段除外——代码不许被划）
    private func inline(_ text: String, strongFont: Font) -> Text {
        MarkdownInline.segments(text).reduce(Text("")) { partial, segment in
            partial + Text(inlineAttributed(
                segment.text,
                strongFont: strongFont,
                strikethrough: segment.strikethrough
            ))
        }
    }

    /// 行内 markdown：解析失败回退纯文本，永不丢字。
    /// 字重口径（0.3.3 收编、0.4.1 第 9 修定版）：strong
    /// 只对应内容本身的 **——按 InlinePresentation-
    /// Intent.stronglyEmphasized 找粗体段、重映射到
    /// strongFont（同字号 .weight(.bold)，与 regular
    /// 基准恰差一档）；斜体段在 strong 字体上叠
    /// .italic；行内代码段（.code）字重与删线都不碰
    private func inlineAttributed(
        _ text: String,
        strongFont: Font,
        strikethrough: Bool
    ) -> AttributedString {
        guard var attributed = try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) else {
            var fallback = AttributedString(text)
            if strikethrough {
                fallback.strikethroughStyle = .single
            }
            return fallback
        }
        for run in Array(attributed.runs) {
            let intent = run.inlinePresentationIntent
            let isCode = intent?.contains(.code) ?? false
            if let intent,
               intent.contains(.stronglyEmphasized), !isCode {
                var font = strongFont
                if intent.contains(.emphasized) {
                    font = font.italic()
                }
                attributed[run.range].font = font
            }
            if strikethrough, !isCode {
                attributed[run.range].strikethroughStyle = .single
            }
        }
        return attributed
    }
}
