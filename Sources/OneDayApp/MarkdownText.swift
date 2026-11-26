import Nuke
import NukeUI
import OneDayCore
import OneDayDesign
import SwiftUI
import UIKit

/// Markdown 渲染（0.36.25 渲染补全）：块级解析在 Core
/// MarkdownParser（可测层），本视图只按结构呈现——段
/// 落／标题 1–6 级／代码块（语言标＋轻量高亮）／引用
/// 块／列表（嵌套＋任务清单）／表格（横滑）／分割线／
/// 内联图片（base64 data URL、https URL、服务端路径）。
struct MarkdownText: View {
    let content: String
    let onSelectionChange: ((Bool) -> Void)?
    let allowsDirectSelection: Bool
    let segmentProducts: [Int: NSAttributedString]?
    let searchHighlightQuery: String?
    let onOpenImageGallery: ((ImageViewerSession) -> Void)?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.legibilityWeight) private var legibilityWeight

    init(
        _ content: String,
        onSelectionChange: ((Bool) -> Void)? = nil,
        segmentProducts: [Int: NSAttributedString]? = nil,
        allowsDirectSelection: Bool = true,
        searchHighlightQuery: String? = nil,
        onOpenImageGallery: ((ImageViewerSession) -> Void)? = nil
    ) {
        self.content = content
        self.onSelectionChange = onSelectionChange
        self.segmentProducts = segmentProducts
        self.allowsDirectSelection = allowsDirectSelection
        self.searchHighlightQuery = searchHighlightQuery
        self.onOpenImageGallery = onOpenImageGallery
    }

    private var extractedMedia: (cleanedText: String, images: [MarkdownInlineImage]) {
        Self.extractInlineImages(from: content)
    }

    private var blocks: [MarkdownBlock] {
        MarkdownParser.parse(extractedMedia.cleanedText)
    }

    /// §168：呈现段（Core 装配）——连续散文合并成
    /// 一段 prose 进单个文本视图；结构块各自成段
    private var segments: [MarkdownMessageSegment] {
        MarkdownMessageAssembler.segments(from: blocks)
    }

    var body: some View {
        let media = extractedMedia
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingSM) {
            if !media.images.isEmpty {
                ForEach(media.images) { img in
                    MarkdownInlineImageView(
                        image: img,
                        onOpen: onOpenImageGallery.map { present in
                            {
                                var seen: Set<String> = []
                                let items = media.images.map(\.viewerItem).filter {
                                    seen.insert($0.id).inserted
                                }
                                let selectedID = img.viewerItem.id
                                guard let index = items.firstIndex(where: {
                                    $0.id == selectedID
                                }) else { return }
                                present(ImageViewerSession(items: items, initialIndex: index))
                            }
                        }
                    )
                }
            }
            ForEach(Array(segments.enumerated()), id: \.offset) { offset, segment in
                switch segment {
                case .prose(let paragraphs):
                    proseView(
                        paragraphs,
                        product: media.images.isEmpty ? segmentProducts?[offset] : nil
                    )
                case .quote(let lines):
                    blockquoteView(
                        lines,
                        product: media.images.isEmpty ? segmentProducts?[offset] : nil
                    )
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

    private static let inlineImageRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"!\[([^\]]*)\]\(([^)\s]+)\)"#,
        options: []
    )

    private static func extractInlineImages(
        from raw: String
    ) -> (cleanedText: String, images: [MarkdownInlineImage]) {
        guard raw.contains("!["), let regex = inlineImageRegex else {
            return (raw, [])
        }
        let ns = raw as NSString
        let matches = regex.matches(
            in: raw,
            range: NSRange(location: 0, length: ns.length)
        )
        guard !matches.isEmpty else { return (raw, []) }
        var images: [MarkdownInlineImage] = []
        var cleaned = raw
        for (idx, match) in matches.enumerated().reversed() {
            let alt = ns.substring(with: match.range(at: 1))
            let src = ns.substring(with: match.range(at: 2))
            if let item = MarkdownInlineImage.make(id: "\(idx)-\(src.hashValue)", alt: alt, source: src) {
                images.insert(item, at: 0)
                if let range = Range(match.range, in: cleaned) {
                    cleaned.removeSubrange(range)
                }
            }
        }
        return (cleaned.trimmingCharacters(in: .whitespacesAndNewlines), images)
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
        _ paragraphs: [MarkdownProseParagraph],
        product: NSAttributedString? = nil
    ) -> some View {
        SelectableInlineText(
            paragraphs: Self.proseParagraphs(paragraphs),
            textStyle: .body,
            foreground: Palette.bodyInk,
            onSelectionChange: onSelectionChange,
            allowsDirectSelection: allowsDirectSelection,
            prebuiltAttributed: product,
            searchHighlightQuery: searchHighlightQuery
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
                    : OneDayMetrics.paragraphSpacing)
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
                Text(
                    findHighlighted(
                        highlighted(code, language: language),
                        code: code
                    )
                )
                .textSelection(.enabled)
            }
            // 右滑引用排除区（0.36.26 §95）：本区横
            // 滑归代码横滚，起始点落在此不触发本行
            // 右滑引用（SwipeReplyModifier 同款）
            .swipeReplyExcluded()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OneDayMetrics.spacingSM)
        // §334（台账 191）：块面改 codeFill 次档——
        // 正文进泡后本块是「泡中块」：fieldFill 暗档
        // 与泡面同值 #2C2C2E、块界会整块消失；
        // codeFill 本是在册代码面令牌（浅 #E2E4E7／
        // 暗 secondarySystemFill 压泡面合成 ≈(68,68,
        // 72)），且高亮三色对比账正以它为基面实算
        .background(
            Palette.codeFill,
            in: RoundedRectangle(
                cornerRadius: OneDayMetrics.codeCorner
            )
        )
    }

    /// §503：代码块查找着色——词法拼装的属性串字
    /// 符序与代码原文恒等（tokens 是原文的一个划
    /// 分），按字符偏移把命中区间映射回属性串加底；
    /// 无查询/无命中时原样返回
    private func findHighlighted(
        _ attributed: AttributedString, code: String
    ) -> AttributedString {
        guard let query = searchHighlightQuery,
              ChatFind.normalizedQuery(query) != nil
        else { return attributed }
        let ranges = ChatFind.occurrenceRanges(
            in: code, query: query
        )
        guard !ranges.isEmpty else { return attributed }
        var result = attributed
        for nsRange in ranges {
            guard let stringRange = Range(nsRange, in: code)
            else { continue }
            let lower = result.index(
                result.startIndex,
                offsetByCharacters: code.distance(
                    from: code.startIndex,
                    to: stringRange.lowerBound
                )
            )
            let upper = result.index(
                result.startIndex,
                offsetByCharacters: code.distance(
                    from: code.startIndex,
                    to: stringRange.upperBound
                )
            )
            result[lower..<upper].backgroundColor =
                Palette.findMatchFill
        }
        return result
    }

    /// 高亮拼装（Phase 2.5）：优先走 Highlightr 185+ 语言引擎（暗/浅色主题同步），
    /// 回退到等宽 footnote 词法高亮——关键词紫／字符串绿／数字蓝／注释次墨／普通正文墨
    private func highlighted(
        _ code: String, language: String?
    ) -> AttributedString {
        #if canImport(Highlightr)
        let theme = colorScheme == .dark ? "atom-one-dark" : "atom-one-light"
        if let nsAttributed = CodeHighlight.attributedString(
            code: code,
            language: language,
            theme: theme
        ), var rich = try? AttributedString(nsAttributed, including: \.uiKit) {
            rich.font = .system(.footnote, design: .monospaced)
            return rich
        }
        #endif
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
        _ lines: [MarkdownQuoteLine],
        product: NSAttributedString? = nil
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
                textStyle: .body,
                foreground: Palette.inkSecondaryOnFill,
                onSelectionChange: onSelectionChange,
                allowsDirectSelection: allowsDirectSelection,
                prebuiltAttributed: product,
                searchHighlightQuery: searchHighlightQuery
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
        let category = dynamicTypeSize.contentSizeCategory
        let isBold = legibilityWeight == .bold
        return VStack(alignment: .leading, spacing: OneDayMetrics.spacingXS) {
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
                        textStyle: .body,
                        foreground: Palette.bodyInk,
                        onSelectionChange: onSelectionChange,
                        allowsDirectSelection: allowsDirectSelection,
                        searchHighlightQuery: searchHighlightQuery
                    )
                    .alignmentGuide(.firstTextBaseline) { _ in
                        InlineTextFonts.firstBaseline(
                            textStyle: .body,
                            category: category,
                            boldText: isBold
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

    /// 表格分流（§271，第 72 条；口径单源在 Core
    /// MarkdownTablePresentation）：≤4 列走 Grid
    /// （列宽封顶＋单元格折行、整体仍横向可滚）；
    /// >4 列降级列表（逐行「表头标签＋值」，气泡
    /// 宽内读全、不横拖）。表头 bold＋发丝线与行
    /// 分隔（全 App 同一种分隔几何：整行贯通发丝
    /// 线）；列对齐来自分隔行的 : 标记
    @ViewBuilder
    private func tableView(
        header: [String],
        alignments: [MarkdownTableAlignment],
        rows: [[String]]
    ) -> some View {
        Group {
            if MarkdownTablePresentation.mode(
                columnCount: header.count
            ) == .list {
                tableListView(header: header, rows: rows)
            } else {
                tableGridView(
                    header: header,
                    alignments: alignments,
                    rows: rows
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // 右滑引用排除区（0.36.26 §95）：本区横滑归
        // 表格横滚／列表纵滚，起始点落在此不触发本
        // 行右滑引用
        .swipeReplyExcluded()
    }

    /// Grid 形态：列宽封顶（Core maxColumnWidth）后
    /// 单元格在列内折行——旧形态按内容理想宽定列、
    /// 长文本单元格整行不折、3 列长文表也要横拖才
    /// 看得全（格式显示诊断 §四）；封顶后宽表先折
    /// 行、横滑只剩多列总宽仍超气泡宽时的余量
    /// §396 落码：SwiftUI Grid 无列宽设定 API、格上
    /// frame(maxWidth:) 不构成列宽约束（§329 校准
    /// 拟合实证：列按自然宽、整行不折）——列宽改由
    /// MarkdownTableGridLayout 按与量测同源的拼装
    /// 算定（逐列自然宽封顶）后以显式宽喂格，呈现
    /// 与行高合成器共用同一列宽单源
    private func tableGridView(
        header: [String],
        alignments: [MarkdownTableAlignment],
        rows: [[String]]
    ) -> some View {
        let columnWidths = MarkdownTableGridLayout
            .columnWidths(
                header: header, rows: rows,
                category: dynamicTypeSize
                    .contentSizeCategory,
                boldText: legibilityWeight == .bold
            )
        return ScrollView(.horizontal, showsIndicators: false) {
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
                            width: columnWidths[column],
                            alignment: Self.frameAlignment(
                                alignments[column]
                            )
                        )
                        .fixedSize(
                            horizontal: false, vertical: true
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
                                width: columnWidths[column],
                                alignment: Self.frameAlignment(
                                    alignments[column]
                                )
                            )
                            .fixedSize(
                                horizontal: false,
                                vertical: true
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
    }

    /// 列表降级形态（>4 列）：逐数据行成组、组内逐
    /// 列一行「标签（表头，次墨小字）＋值」，组间发
    /// 丝线分隔——与 Grid 形态同一分隔几何；值走同
    /// 一行内渲染（粗体等标记同口径）、可选择
    private func tableListView(
        header: [String], rows: [[String]]
    ) -> some View {
        let entries = MarkdownTablePresentation.listEntries(
            header: header, rows: rows
        )
        return VStack(
            alignment: .leading,
            spacing: OneDayMetrics.spacingSM
        ) {
            ForEach(
                Array(entries.enumerated()), id: \.offset
            ) { rowIndex, row in
                if rowIndex > 0 {
                    GroupDivider()
                }
                VStack(
                    alignment: .leading,
                    spacing: OneDayMetrics.spacingXS
                ) {
                    ForEach(
                        Array(row.enumerated()), id: \.offset
                    ) { _, entry in
                        HStack(
                            alignment: .firstTextBaseline,
                            spacing: OneDayMetrics.spacingS
                        ) {
                            Text(entry.label)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(
                                    Palette.inkSecondaryOnFill
                                )
                            inline(
                                entry.value,
                                strongFont: .callout.weight(.bold)
                            )
                            .font(.callout)
                            .foregroundStyle(Palette.bodyInk)
                            .textSelection(.enabled)
                        }
                    }
                }
            }
        }
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

    /// 行内渲染（表格格专用）：格文本经 Core
    /// InlineRunBuilder 单源解析产语义 run、本视图
    /// 只做呈现映射——行内语义的读法（哪些段算
    /// strong／code／link／删线）自 §392 起全仓只
    /// 在 Core 一处，App 层不再自带系统行内解析
    private func inline(_ text: String, strongFont: Font) -> Text {
        Text(Self.cellAttributed(text, strongFont: strongFont))
    }

    /// run→SwiftUI 属性串呈现映射（§392）：intent
    /// 按 run 旗标回填（SwiftUI 据 intent 渲粗斜体
    /// 与代码档、与系统解析产物同路）；字重口径与
    /// 旧 inlineAttributed 逐项同——strong 只对应
    /// 内容本身的 **、重映射到 strongFont（同字号
    /// .weight(.bold)），斜体段在 strong 字体上叠
    /// .italic；行内代码段（.code）字重与删线都不
    /// 碰；删线取 run 旗标（Core 分段已并入）；链
    /// 接透传。解析失败降级在 builder 内（整段普
    /// 通 run、永不丢字）
    nonisolated static func cellAttributed(
        _ text: String, strongFont: Font
    ) -> AttributedString {
        var result = AttributedString()
        for run in InlineRunBuilder.runs(for: text) {
            var piece = AttributedString(run.text)
            var intent = InlinePresentationIntent()
            if run.strong {
                intent.insert(.stronglyEmphasized)
            }
            if run.emphasis {
                intent.insert(.emphasized)
            }
            if run.code {
                intent.insert(.code)
            }
            if !intent.isEmpty {
                piece.inlinePresentationIntent = intent
            }
            if run.strong, !run.code {
                var font = strongFont
                if run.emphasis {
                    font = font.italic()
                }
                piece.font = font
            }
            if run.strikethrough, !run.code {
                piece.strikethroughStyle = .single
            }
            if let link = run.link {
                piece.link = link
            }
            result.append(piece)
        }
        return result
    }
}

private struct MarkdownInlineImage: Identifiable {
    static let previewLongEdge = 1200
    enum Source {
        case base64(Data)
        case remoteURL(URL)
        case serverPath(String)
    }

    let id: String
    let alt: String
    let source: Source

    var viewerItem: ChatImageViewerItem {
        switch source {
        case .base64(let data):
            ChatImageViewerItem(source: .data(data))
        case .remoteURL(let url):
            ChatImageViewerItem(source: .publicURL(url, previewLongEdge: Self.previewLongEdge))
        case .serverPath(let path):
            ChatImageViewerItem(source: .remotePath(path))
        }
    }

    static func make(id: String, alt: String, source: String) -> MarkdownInlineImage? {
        if source.hasPrefix("data:image/"),
           let comma = source.firstIndex(of: ",") {
            let b64 = String(source[source.index(after: comma)...])
            if let data = Data(base64Encoded: b64, options: .ignoreUnknownCharacters) {
                return MarkdownInlineImage(id: id, alt: alt, source: .base64(data))
            }
            return nil
        }
        if source.hasPrefix("https://") || source.hasPrefix("http://"),
           let url = URL(string: source) {
            return MarkdownInlineImage(id: id, alt: alt, source: .remoteURL(url))
        }
        if source.hasPrefix("/"), FileRefDetector.isInDownloadRoot(source) {
            return MarkdownInlineImage(id: id, alt: alt, source: .serverPath(source))
        }
        return nil
    }
}

private struct MarkdownInlineImageView: View {
    let image: MarkdownInlineImage
    var onOpen: (() -> Void)?

    var body: some View {
        switch image.source {
        case .base64(let data):
            if let uiImage = UIImage(data: data) {
                let cardSize = ChatImageSizing.cardSize(for: uiImage.size)
                previewButton {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: cardSize.width, height: cardSize.height)
                        .background(
                            Palette.bubbleFill,
                            in: RoundedRectangle(cornerRadius: OneDayMetrics.radiusCard)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: OneDayMetrics.radiusCard))
                }
            }
        case .remoteURL(let url):
            let request = onOpen == nil ? ImageRequest(url: url)
                : RemoteImageRequestFactory.publicRequest(
                    url: url, longEdgeCap: MarkdownInlineImage.previewLongEdge
                )
            LazyImage(request: request) { state in
                if let loaded = state.image {
                    previewButton {
                        loaded
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 260, maxHeight: 220)
                            .clipShape(RoundedRectangle(cornerRadius: OneDayMetrics.radiusCard))
                    }
                } else if state.error != nil {
                    HStack(spacing: OneDayMetrics.spacingXS) {
                        Image(systemName: "photo")
                        Text(image.alt.isEmpty ? "图片加载失败" : image.alt)
                    }
                    .font(.caption)
                    .foregroundStyle(Palette.inkSecondaryOnFill)
                    .padding(OneDayMetrics.spacingM)
                    .background(
                        Palette.bubbleFill,
                        in: RoundedRectangle(cornerRadius: OneDayMetrics.radiusCard)
                    )
                } else {
                    RoundedRectangle(cornerRadius: OneDayMetrics.radiusCard)
                        .fill(Palette.bubbleFill)
                        .frame(
                            width: ChatImageSizing.placeholderCardSize.width,
                            height: ChatImageSizing.placeholderCardSize.height
                        )
                        .overlay { ProgressView() }
                }
            }
            .pipeline(onOpen == nil ? .shared : OneDayImagePipelines.remote)
        case .serverPath(let path):
            ServerRemoteImage(path: path, onOpen: onOpen)
        }
    }

    @ViewBuilder
    private func previewButton<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if let onOpen {
            Button(action: onOpen) {
                content().contentShape(Rectangle())
            }
            .buttonStyle(.odPressable)
            .accessibilityLabel(image.alt.isEmpty ? L10n.string("图片") : image.alt)
            .accessibilityHint(L10n.string("查看大图"))
        } else {
            content()
        }
    }
}

