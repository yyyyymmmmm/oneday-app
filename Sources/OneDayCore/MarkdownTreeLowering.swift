import Foundation
import Markdown

/// §417（#13 Markdown 换底，施工图 swap-md-image-
/// prep-20261123.md 第一部 Path B）：swift-markdown
/// （cmark-gfm）解析树 → 现行块模型 MarkdownBlock
/// 与行内 InlineRun 的降解层。本层是新核唯一落
/// 点：MarkdownParser.parse 与 InlineRunBuilder.
/// runs(for:) 的签名与备忘入口不变、内部经
/// MarkdownEngine 分派到此，消费面零改动。
///
/// 降解口径（与旧状态机逐项对齐，差分语料
/// MarkdownEngineDifferentialTests＋签收表
/// md-swap-diff-signoff-20261123.md 把守）：
/// - 段落／标题／列表项／引用行／表格单元格仍持
///   「行内 markdown 原文」——由树行内节点序列化
///   重组为规范形（**／*／~~／`／[]()），与旧解析
///   器逐字原文的差异只剩定界符写法归一（__→**、
///   实体与转义解开），可见呈现与 runs 逐项同果。
/// - runs 由同一访问器从树直产：代码段不升
///   strong/emphasis 是树上的结构事实，不再靠
///   InlinePresentationIntent 猜。
enum MarkdownTreeParsing {

    // MARK: - 块级降解

    static func blocks(from content: String) -> [MarkdownBlock] {
        // disableSmartOpts 必开：智能标点会把 --- 改
        // 成 —、引号改弯引号，污染「块持规范形原文、
        // 下游按原文再解析」的契约（差分实证）
        let document = Document(
            parsing: content, options: [.disableSmartOpts]
        )
        let sourceLines = content.components(separatedBy: "\n")
        var result: [MarkdownBlock] = []
        // HTMLBlock 与相邻段落在旧口径里同属一段落
        // 累积（HTML 行只是普通段落行）：树上是独立
        // 块，靠源行相邻（无空行间隔）折回一段
        var previousRange: SourceRange?
        var previousWasHTML = false
        // 一次解析两件产物（性能门实证）：降解时把
        // 每块的 runs 从同一棵树直产、种进 runs 备
        // 忘盒，装配层查表命中、不再逐块重解析；
        // 含 ~~ 的块不种（删除线分段口径只在原文
        // 路完备，见 inlineRuns 注）
        let seedBox = RunSeedBox()
        for child in document.children {
            let lowered = lowerBlock(
                child, sourceLines: sourceLines, seeds: seedBox
            )
            let isHTML = child is HTMLBlock
            var didFold = false
            if let first = lowered.first,
               case .paragraph(let text) = first,
               let last = result.last,
               case .paragraph(let previous) = last,
               isHTML || previousWasHTML,
               let previousR = previousRange,
               let currentR = child.range,
               currentR.lowerBound.line - previousR.upperBound.line <= 1 {
                result[result.count - 1] = .paragraph(
                    previous + "\n" + text
                )
                result.append(contentsOf: lowered.dropFirst())
                didFold = true
            } else {
                result.append(contentsOf: lowered)
            }
            if let last = result.last, case .paragraph = last {
                previousWasHTML = didFold
                    ? (previousWasHTML || isHTML)
                    : isHTML
            } else {
                previousWasHTML = false
            }
            if let range = child.range {
                previousRange = range
            }
        }
        for entry in seedBox.entries {
            MarkdownParseMemos.runs.seed(
                entry.runs, for: entry.key
            )
        }
        return mergeAdjacentLists(result)
    }

    /// runs 种入收集盒（见 blocks(from:) 注）
    final class RunSeedBox {
        var entries: [(key: String, runs: [InlineRun])] = []
    }

    /// 从树直产一块的 runs 并登记种入：键＝块持原
    /// 文（与 InlineRunBuilder 查表键同串）；含 ~~
    /// 的文本不种——删除线在「被删段含粗斜体」时
    /// 树上无节点、只有原文分段路能完备处理，种入
    /// 会与原文路产物分叉
    private static func collectSeed(
        _ box: RunSeedBox?, key: String,
        children: some Sequence<Markup>
    ) {
        guard let box, !key.isEmpty, !key.contains("~~")
        else { return }
        var runs: [InlineRun] = []
        for child in children {
            collectInline(
                child, context: InlineContext(), into: &runs
            )
        }
        guard !runs.isEmpty else { return }
        box.entries.append((key: key, runs: runs))
    }

    /// 引用段落逐行种入：装配按行（MarkdownQuote-
    /// Line.text）求 runs——按断行节点把树 runs 切
    /// 成行段、键＝行文。只种行文无首尾空白的行
    ///（trim 后键与树 runs 文本须逐字对应）、含
    /// ~~ 的行不种（同 collectSeed 口径）
    private static func seedQuoteLines(
        paragraph: Paragraph, rawLines: [String],
        seeds: RunSeedBox?
    ) {
        guard let seeds else { return }
        var segments: [[Markup]] = [[]]
        for child in paragraph.children {
            if child is SoftBreak || child is LineBreak {
                segments.append([])
            } else {
                segments[segments.count - 1].append(child)
            }
        }
        guard segments.count == rawLines.count else { return }
        for (segment, rawLine) in zip(segments, rawLines) {
            let key = rawLine.trimmingCharacters(
                in: .whitespaces
            )
            guard key == rawLine, !key.isEmpty,
                  !key.contains("~~") else { continue }
            var runs: [InlineRun] = []
            for node in segment {
                collectInline(
                    node, context: InlineContext(), into: &runs
                )
            }
            if !runs.isEmpty {
                seeds.entries.append((key: key, runs: runs))
            }
        }
    }

    private static func lowerBlock(
        _ markup: Markup, sourceLines: [String],
        seeds: RunSeedBox? = nil
    ) -> [MarkdownBlock] {
        switch markup {
        case let paragraph as Paragraph:
            let text = serializeInline(
                paragraph.children, softBreak: "\n"
            )
            collectSeed(seeds, key: text, children: paragraph.children)
            return [.paragraph(text)]
        case let heading as Heading:
            if let setext = lowerSetextHeading(
                heading, sourceLines: sourceLines
            ) {
                return setext
            }
            let headingText = serializeInline(
                heading.children, softBreak: "\n"
            )
            if headingText.isEmpty {
                // 空标题（"#" 单行）：旧口径不成标
                // 题、整行按段落留原样——补齐（签收
                // 表同类项）
                return [.paragraph(sourceText(
                    of: heading, sourceLines: sourceLines
                ))]
            }
            collectSeed(
                seeds, key: headingText,
                children: heading.children
            )
            return [.heading(
                text: headingText,
                level: heading.level
            )]
        case let codeBlock as CodeBlock:
            return [.code(
                code: stripOneTrailingNewline(codeBlock.code),
                language: normalizedLanguage(codeBlock.language)
            )]
        case let quote as BlockQuote:
            return [.blockquote(lines: flattenQuote(
                quote, depth: 1, sourceLines: sourceLines,
                seeds: seeds
            ))]
        case is UnorderedList, is OrderedList:
            return flattenList(
                markup, level: 0, sourceLines: sourceLines,
                seeds: seeds
            )
        case let table as Table:
            return [lowerTable(table, seeds: seeds)]
        case is ThematicBreak:
            return [.divider]
        case let html as HTMLBlock:
            // HTMLBlock 节点不暴露原文，靠源行区间照收
            return [.paragraph(sourceText(
                of: html, sourceLines: sourceLines
            ))]
        default:
            // 其余容器（解析选项未开 block directives，
            // 不应出现）：递归降解子块兜底
            return markup.children.flatMap {
                lowerBlock(
                    $0, sourceLines: sourceLines, seeds: seeds
                )
            }
        }
    }

    /// Setext 集合标题（===／--- 下划线式）：新树认
    /// H1/H2，旧解析器不认。签收口径（签收表 D3）：
    /// 两形都按旧口径补齐——--- 形在 Hermes 输出里
    /// 压倒性是分割线意图（段落＋.divider 还原），
    /// === 形是普通段落行（原文照收）。识别靠源行：
    /// 标题区间跨行且末行是纯 =／- 串
    private static func lowerSetextHeading(
        _ heading: Heading, sourceLines: [String]
    ) -> [MarkdownBlock]? {
        guard let range = heading.range,
              range.upperBound.line > range.lowerBound.line
        else { return nil }
        // 下划线行不能信 range 尾行：探针实测 Setext
        // 标题的 range 尾行会越界一行（指到下一块尾）
        // ——按标题文本行数推：首行＋文本行数-1 的下
        // 一行即下划线行
        let textLineCount = serializeInline(
            heading.children, softBreak: "\n"
        ).components(separatedBy: "\n").count
        let underlineIndex =
            (range.lowerBound.line - 1) + textLineCount
        guard sourceLines.indices.contains(underlineIndex)
        else { return nil }
        let underlineRaw = sourceLines[underlineIndex]
        let compact = underlineRaw.filter {
            $0 != " " && $0 != "\t"
        }
        guard !compact.isEmpty,
              let first = compact.first,
              first == "-" || first == "=",
              compact.allSatisfy({ $0 == first })
        else { return nil }
        let text = serializeInline(
            heading.children, softBreak: "\n"
        )
        if first == "-" {
            return [.paragraph(text), .divider]
        }
        return [.paragraph(text + "\n" + underlineRaw)]
    }

    /// 相邻列表块合并：旧累积器不分标记类型、连续
    /// 列表行恒同块（空行后续项亦然）；新树按列表
    /// 类型／松紧切块，降解后把相邻 .list 折回一块
    ///（中间隔着溢出段落的不合并，与旧分块同界）
    private static func mergeAdjacentLists(
        _ blocks: [MarkdownBlock]
    ) -> [MarkdownBlock] {
        var result: [MarkdownBlock] = []
        for block in blocks {
            if case .list(let newItems) = block,
               let last = result.last,
               case .list(let existing) = last {
                result[result.count - 1] = .list(
                    items: existing + newItems
                )
            } else {
                result.append(block)
            }
        }
        return result
    }

    // MARK: - 引用摊平

    /// 引用块递归摊平为行（现行模型是扁平行＋
    /// depth）：嵌套引用 depth 递增；引用内列表摊
    /// 为带标记文本行、代码摊为围栏原文行——与旧
    /// 解析器「> 行整行收为文本行」等价。子块之间
    /// 的空行只在源文确有间隔行（空 > 行）时才补：
    /// 以相邻子块的源行距判定（差分实证：无条件补
    /// 空行会在嵌套／标题＋正文间多出幽灵空行）
    private static func flattenQuote(
        _ quote: BlockQuote, depth: Int,
        sourceLines: [String], seeds: RunSeedBox? = nil
    ) -> [MarkdownQuoteLine] {
        var lines: [MarkdownQuoteLine] = []
        var previousEndLine: Int?
        for child in quote.children {
            if let previousEnd = previousEndLine,
               let range = child.range,
               range.lowerBound.line - previousEnd >= 2 {
                lines.append(MarkdownQuoteLine(
                    depth: depth, text: ""
                ))
            }
            lines.append(contentsOf: quoteLines(
                for: child, depth: depth,
                sourceLines: sourceLines, seeds: seeds
            ))
            if let range = child.range {
                previousEndLine = range.upperBound.line
            }
        }
        return lines
    }

    private static func quoteLines(
        for markup: Markup, depth: Int,
        sourceLines: [String], seeds: RunSeedBox? = nil
    ) -> [MarkdownQuoteLine] {
        switch markup {
        case let paragraph as Paragraph:
            let rawLines = serializeInline(
                paragraph.children, softBreak: "\n"
            ).components(separatedBy: "\n")
            seedQuoteLines(
                paragraph: paragraph, rawLines: rawLines,
                seeds: seeds
            )
            return rawLines.map {
                MarkdownQuoteLine(
                    depth: depth,
                    text: $0.trimmingCharacters(
                        in: .whitespaces
                    )
                )
            }
        case let nested as BlockQuote:
            return flattenQuote(
                nested, depth: depth + 1,
                sourceLines: sourceLines, seeds: seeds
            )
        case let heading as Heading:
            let hashes = String(
                repeating: "#", count: heading.level
            )
            return [MarkdownQuoteLine(
                depth: depth,
                text: hashes + " " + serializeInline(
                    heading.children, softBreak: "\n"
                )
            )]
        case is UnorderedList, is OrderedList:
            return flattenList(
                markup, level: 0, sourceLines: sourceLines
            ).flatMap { block -> [MarkdownQuoteLine] in
                switch block {
                case .list(let items):
                    return items.map {
                        MarkdownQuoteLine(
                            depth: depth,
                            text: quoteMarkerPrefix($0.marker)
                                + $0.text
                        )
                    }
                case .paragraph(let text):
                    return text
                        .components(separatedBy: "\n")
                        .map {
                            MarkdownQuoteLine(
                                depth: depth, text: $0
                            )
                        }
                case .code(let code, let language):
                    var texts = ["```" + (language ?? "")]
                    texts.append(contentsOf: code
                        .components(separatedBy: "\n"))
                    texts.append("```")
                    return texts.map {
                        MarkdownQuoteLine(depth: depth, text: $0)
                    }
                default:
                    return []
                }
            }
        case let codeBlock as CodeBlock:
            var texts = ["```" + (codeBlock.language ?? "")]
            texts.append(contentsOf: stripOneTrailingNewline(
                codeBlock.code
            ).components(separatedBy: "\n"))
            texts.append("```")
            return texts.map {
                MarkdownQuoteLine(depth: depth, text: $0)
            }
        default:
            // 表格等其余块：源文逐行照收（旧口径同形
            // 态），但须先剥本层引用标记——源行带 >，
            // 旧解析器收的是剥标记后的行文
            return sourceText(of: markup, sourceLines: sourceLines)
                .components(separatedBy: "\n")
                .map {
                    MarkdownQuoteLine(
                        depth: depth,
                        text: stripQuoteMarkers(
                            $0, depth: depth
                        ).trimmingCharacters(in: .whitespaces)
                    )
                }
        }
    }

    /// 剥源行首的引用标记（按 depth 层）：每层剥
    /// 一个 > 与其后至多一个空格
    private static func stripQuoteMarkers(
        _ line: String, depth: Int
    ) -> String {
        var rest = line
        for _ in 0..<depth {
            rest = rest.trimmingCharacters(
                in: .whitespaces
            )
            guard rest.hasPrefix(">") else { break }
            rest = String(rest.dropFirst())
            if rest.hasPrefix(" ") {
                rest = String(rest.dropFirst())
            }
        }
        return rest
    }

    private static func quoteMarkerPrefix(
        _ marker: MarkdownListItem.Marker
    ) -> String {
        switch marker {
        case .bullet:
            return "- "
        case .ordered(let number):
            return "\(number). "
        case .task(let checked):
            return checked ? "- [x] " : "- [ ] "
        }
    }

    // MARK: - 列表摊平

    private static func flattenList(
        _ list: Markup, level: Int, sourceLines: [String],
        seeds: RunSeedBox? = nil
    ) -> [MarkdownBlock] {
        var flattener = ListFlattener(
            sourceLines: sourceLines, seeds: seeds
        )
        flattener.walk(list: list, level: level)
        return flattener.finish()
    }

    /// 列表递归摊平器：层级＝嵌套深度（封顶 6，与
    /// 旧 indent/2 同顶）；有序序号以源行字面数字
    /// 为准（旧口径逐行读数字，start＋序号只作兜
    /// 底）；多段落项的后段与项内代码按旧口径溢
    /// 出——列表在此收尾、后段独立成块，其后列表
    /// 项另起一块（旧累积器在空行处 flush 同果）
    private struct ListFlattener {
        let sourceLines: [String]
        var seeds: RunSeedBox?
        var blocks: [MarkdownBlock] = []
        var items: [MarkdownListItem] = []

        mutating func flush() {
            guard !items.isEmpty else { return }
            blocks.append(.list(items: items))
            items = []
        }

        mutating func finish() -> [MarkdownBlock] {
            flush()
            return blocks
        }

        mutating func walk(list: Markup, level: Int) {
            let ordered = list is OrderedList
            let startIndex = (list as? OrderedList)?.startIndex ?? 1
            var ordinal = 0
            for child in list.children {
                guard let item = child as? ListItem
                else { continue }
                let marker: MarkdownListItem.Marker
                if let checkbox = item.checkbox {
                    marker = .task(checked: checkbox == .checked)
                } else if ordered {
                    marker = .ordered(
                        number: recoveredOrderedNumber(item: item)
                            ?? Int(startIndex) + ordinal
                    )
                } else {
                    marker = .bullet
                }
                ordinal += 1
                var text = ""
                var consumedFirstParagraph = false
                var pendingChildren: [Markup] = []
                for itemChild in item.children {
                    if !consumedFirstParagraph,
                       let paragraph = itemChild as? Paragraph {
                        text = serializeInline(
                            paragraph.children, softBreak: " "
                        )
                        collectSeed(
                            seeds, key: text,
                            children: paragraph.children
                        )
                        consumedFirstParagraph = true
                    } else {
                        pendingChildren.append(itemChild)
                    }
                }
                items.append(MarkdownListItem(
                    level: min(level, 6),
                    marker: marker,
                    text: text
                ))
                for itemChild in pendingChildren {
                    switch itemChild {
                    case is UnorderedList, is OrderedList:
                        walk(list: itemChild, level: level + 1)
                    case let paragraph as Paragraph:
                        flush()
                        let spillText = serializeInline(
                            paragraph.children, softBreak: "\n"
                        )
                        collectSeed(
                            seeds, key: spillText,
                            children: paragraph.children
                        )
                        blocks.append(.paragraph(spillText))
                    case let codeBlock as CodeBlock:
                        flush()
                        blocks.append(.code(
                            code: stripOneTrailingNewline(
                                codeBlock.code
                            ),
                            language: normalizedLanguage(
                                codeBlock.language
                            )
                        ))
                    default:
                        // 引用等其余块不许吞：收尾后按
                        // 顶层口径独立成块（旧口径：引
                        // 用行退出列表另起引用块）
                        flush()
                        blocks.append(contentsOf: lowerBlock(
                            itemChild,
                            sourceLines: sourceLines,
                            seeds: seeds
                        ))
                    }
                }
            }
        }

        /// 有序序号源行回收：项区间首行剥缩进后读
        /// 字面数字（「3.」起手、乱序编号都以源文
        /// 为准，与旧 parseListItem 逐行读数同口径）
        func recoveredOrderedNumber(item: ListItem) -> Int? {
            guard let range = item.range else { return nil }
            let lineIndex = range.lowerBound.line - 1
            guard sourceLines.indices.contains(lineIndex)
            else { return nil }
            let line = sourceLines[lineIndex]
                .drop(while: { $0 == " " || $0 == "\t" })
            var digits = ""
            for character in line {
                if character.isNumber {
                    digits.append(character)
                } else {
                    break
                }
            }
            guard !digits.isEmpty, digits.count <= 9
            else { return nil }
            return Int(digits)
        }
    }

    // MARK: - 表格

    private static func lowerTable(
        _ table: Table, seeds: RunSeedBox? = nil
    ) -> MarkdownBlock {
        // 树形实测（探针）：Head 的子节点直接是
        // Cell；Body 的子节点是 Row、Row 下才是 Cell
        func cellText(_ cell: Table.Cell) -> String {
            let text = serializeInline(
                cell.children, softBreak: " "
            )
            collectSeed(seeds, key: text, children: cell.children)
            return text
        }
        var header: [String] = []
        var rows: [[String]] = []
        for child in table.children {
            if let head = child as? Table.Head {
                header = head.children.compactMap {
                    ($0 as? Table.Cell).map { cellText($0) }
                }
            } else if let body = child as? Table.Body {
                for row in body.children {
                    guard let tableRow = row as? Table.Row
                    else { continue }
                    rows.append(tableRow.children.compactMap {
                        ($0 as? Table.Cell).map { cellText($0) }
                    })
                }
            }
        }
        let alignments: [MarkdownTableAlignment] =
            header.indices.map { index in
                guard index < table.columnAlignments.count,
                      let alignment =
                        table.columnAlignments[index]
                else { return .left }
                switch alignment {
                case .left: return .left
                case .center: return .center
                case .right: return .right
                }
            }
        return .table(
            header: header,
            alignments: alignments,
            rows: rows.map {
                normalizeRow($0, count: header.count)
            }
        )
    }

    /// 行单元格按表头列数补齐／截断（旧归一口径同式）
    private static func normalizeRow(
        _ cells: [String], count: Int
    ) -> [String] {
        if cells.count == count { return cells }
        if cells.count < count {
            return cells + Array(
                repeating: "", count: count - cells.count
            )
        }
        return Array(cells.prefix(count))
    }

    // MARK: - 行内序列化（树 → 规范形原文）

    static func serializeInline(
        _ children: some Sequence<Markup>, softBreak: String
    ) -> String {
        var output = ""
        for child in children {
            output += serializeInlineNode(
                child, softBreak: softBreak
            )
        }
        return output
    }

    private static func serializeInlineNode(
        _ markup: Markup, softBreak: String
    ) -> String {
        switch markup {
        case let text as Text:
            return escapeLiteralText(text.string)
        case let code as InlineCode:
            return serializeCodeSpan(code.code)
        case let strong as Strong:
            return "**" + serializeInline(
                strong.children, softBreak: softBreak
            ) + "**"
        case let emphasis as Emphasis:
            return "*" + serializeInline(
                emphasis.children, softBreak: softBreak
            ) + "*"
        case let strike as Strikethrough:
            return "~~" + serializeInline(
                strike.children, softBreak: softBreak
            ) + "~~"
        case let link as Link:
            var result = "[" + serializeInline(
                link.children, softBreak: softBreak
            ) + "]("
            result += link.destination ?? ""
            if let title = link.title {
                result += " \"\(title)\""
            }
            return result + ")"
        case let image as Image:
            var result = "![" + serializeInline(
                image.children, softBreak: softBreak
            ) + "]("
            result += image.source ?? ""
            if let title = image.title {
                result += " \"\(title)\""
            }
            return result + ")"
        case is SoftBreak:
            return softBreak
        case is LineBreak:
            return "\n"
        case let html as InlineHTML:
            return html.rawHTML
        default:
            if markup.childCount > 0 {
                return serializeInline(
                    markup.children, softBreak: softBreak
                )
            }
            return plainText(of: markup)
        }
    }

    /// 字面文本序列化转义：块持的规范形原文会被下
    /// 游（InlineRunBuilder）按 markdown 再解析，
    /// 树上已定型的字面字符若带标记形（\* \` \[
    /// 等），再解析会翻义——只对「可能成标记」的
    /// 位置回加反斜杠：反斜杠与反引号恒转义；[ 恒
    /// 转义（防链接成形）；< 仅标签形（后随字母／
    /// !?）转义；* 任一侧非空白即转义（词内亦可
    /// 成斜体）；_ 仅非词内位置转义（词内 _ 在
    /// CommonMark 里永不成斜体、保原文）。转义后
    /// 的文本再解析与树产物逐字等价
    private static func escapeLiteralText(
        _ text: String
    ) -> String {
        // 快退（性能）：无任一特殊字符的纯文本（绝
        // 大多数节点）原样返回，免逐字数组化
        guard text.contains(where: {
            $0 == "\\" || $0 == "`" || $0 == "["
                || $0 == "<" || $0 == "*" || $0 == "_"
        }) else { return text }
        let characters = Array(text)
        var output = ""
        for index in characters.indices {
            let character = characters[index]
            let previous: Character? =
                index > 0 ? characters[index - 1] : nil
            let next: Character? =
                index + 1 < characters.count
                    ? characters[index + 1] : nil
            switch character {
            case "\\", "`", "[":
                output += "\\"
            case "<":
                if let next,
                   next.isLetter || next == "/"
                    || next == "!" || next == "?" {
                    output += "\\"
                }
            case "*":
                let prevBlank = previous.map {
                    $0.isWhitespace
                } ?? true
                let nextBlank = next.map {
                    $0.isWhitespace
                } ?? true
                if !prevBlank || !nextBlank {
                    output += "\\"
                }
            case "_":
                // 词内（两侧都是字词字符）永不成斜
                // 体、不转义；其余位置都可能成标记
                let prevWord = previous.map {
                    $0.isLetter || $0.isNumber
                } ?? false
                let nextWord = next.map {
                    $0.isLetter || $0.isNumber
                } ?? false
                if !(prevWord && nextWord) {
                    output += "\\"
                }
            default:
                break
            }
            output.append(character)
        }
        return output
    }

    /// 行内代码序列化：内容含反引号时按 CommonMark
    /// 口径加长围栏（旧原文照收的等价规范形）
    private static func serializeCodeSpan(
        _ code: String
    ) -> String {
        guard code.contains("`") else { return "`" + code + "`" }
        var longest = 0
        var run = 0
        for character in code {
            run = character == "`" ? run + 1 : 0
            longest = max(longest, run)
        }
        let fence = String(repeating: "`", count: longest + 1)
        let needsPadding = code.hasPrefix("`")
            || code.hasSuffix("`")
            || code.hasPrefix(" ")
            || code.hasSuffix(" ")
        return needsPadding
            ? fence + " " + code + " " + fence
            : fence + code + fence
    }

    // MARK: - 行内 runs（树 → InlineRun）

    private struct InlineContext {
        var strong = false
        var emphasis = false
        var strikethrough = false
        var link: URL?
    }

    /// 片段行内解析：入参按契约是行内文本（段落／
    /// 标题／列表项／引用行的原文）。处理链＝行首
    /// 防护 → 删除线分段 → 段内树解析（见下注）
    static func inlineRuns(for text: String) -> [InlineRun] {
        guard !text.isEmpty else { return [] }
        // 删除线分段层（MarkdownInline，现行既有件）：
        // cmark-gfm 的删除线在「被删段含粗斜体」时不
        // 成节点（探针实证：~~删掉**这段**~~ 只出
        // Text＋Strong），整段吞标记——先按既有分段
        // 口径切开（代码段内的 ~~ 不触发、未闭合不
        // 成段，与旧路同一步），段内再走树，删除线
        // 标记由分段层赋予整段 runs
        // 无 ~~ 的片段（绝大多数）分段层必回单段未
        // 删——直通省一遍逐字扫（口径与 segments 全
        // 扫等价：无标记即无段界）
        let segments: [MarkdownInline.Segment] =
            text.contains("~~")
                ? MarkdownInline.segments(
                    guardFragmentLineStarts(text)
                )
                : [MarkdownInline.Segment(
                    text: guardFragmentLineStarts(text),
                    strikethrough: false
                )]
        var runs: [InlineRun] = []
        for segment in segments {
            let segmentRuns = treeInlineRuns(
                for: segment.text,
                strikethrough: segment.strikethrough
            )
            for run in segmentRuns {
                appendRun(run, to: &runs)
            }
        }
        return runs
    }

    /// 段内树解析：整篇解析后取块内行内产物；多块
    /// 片段以 \n 连接（旧系统行内解析对整串同果）
    private static func treeInlineRuns(
        for text: String, strikethrough: Bool
    ) -> [InlineRun] {
        guard !text.isEmpty else { return [] }
        let document = Document(
            parsing: text, options: [.disableSmartOpts]
        )
        var runs: [InlineRun] = []
        var isFirstBlock = true
        for child in document.children {
            if !isFirstBlock {
                appendRun(InlineRun(
                    text: "\n", strikethrough: strikethrough
                ), to: &runs)
            }
            isFirstBlock = false
            collectRuns(
                from: child,
                context: InlineContext(
                    strikethrough: strikethrough
                ),
                into: &runs
            )
        }
        return runs
    }

    private static func collectRuns(
        from markup: Markup, context: InlineContext,
        into runs: inout [InlineRun]
    ) {
        switch markup {
        case let paragraph as Paragraph:
            for child in paragraph.children {
                collectInline(
                    child, context: context, into: &runs
                )
            }
        case let heading as Heading:
            for child in heading.children {
                collectInline(
                    child, context: context, into: &runs
                )
            }
        default:
            // 片段入参按契约不该出现整块形态；防御性
            // 递归子节点，不丢字
            for child in markup.children {
                collectRuns(
                    from: child, context: context, into: &runs
                )
            }
        }
    }

    private static func collectInline(
        _ markup: Markup, context: InlineContext,
        into runs: inout [InlineRun]
    ) {
        switch markup {
        case let text as Text:
            if context.link == nil {
                // 裸链接补位：swift-markdown 0.6 未挂
                // autolink 扩展，旧系统行内解析却会把
                // 裸 URL／www.／邮箱提成链接 run——用
                // 平台 NSDataDetector 对纯文本段补同
                // 口径（原生件，非自造解析）
                appendTextWithAutolinks(
                    text.string, context: context, into: &runs
                )
            } else {
                appendRun(InlineRun(
                    text: text.string,
                    strong: context.strong,
                    emphasis: context.emphasis,
                    link: context.link,
                    strikethrough: context.strikethrough
                ), to: &runs)
            }
        case let strong as Strong:
            var inner = context
            inner.strong = true
            for child in strong.children {
                collectInline(child, context: inner, into: &runs)
            }
        case let emphasis as Emphasis:
            var inner = context
            inner.emphasis = true
            for child in emphasis.children {
                collectInline(
                    child, context: inner, into: &runs
                )
            }
        case let strike as Strikethrough:
            var inner = context
            inner.strikethrough = true
            for child in strike.children {
                collectInline(child, context: inner, into: &runs)
            }
        case let code as InlineCode:
            // 代码不升 strong、不叠斜体（树上结构事
            // 实）；删除线与链接随外层（旧分段口径同果）
            appendRun(InlineRun(
                text: code.code,
                code: true,
                link: context.link,
                strikethrough: context.strikethrough
            ), to: &runs)
        case let link as Link:
            var inner = context
            if let destination = link.destination,
               !destination.isEmpty {
                inner.link = URL(string: destination)
            } else {
                inner.link = nil
            }
            for child in link.children {
                collectInline(child, context: inner, into: &runs)
            }
        case let image as Image:
            // 语义差二（签收表 D2）：行内图片在旧系统
            // 行内解析下的实测行为＝替代文本作普通
            // run（聊天路径的图片另由 InlineImage-
            // Candidate 预提取成图卡、不经本路）；新核
            // 同口径：只取替代文本子节点、不带链接
            for child in image.children {
                collectInline(child, context: context, into: &runs)
            }
        case is SoftBreak:
            appendRun(InlineRun(
                text: "\n",
                strong: context.strong,
                emphasis: context.emphasis,
                link: context.link,
                strikethrough: context.strikethrough
            ), to: &runs)
        case is LineBreak:
            appendRun(InlineRun(
                text: "\n",
                strong: context.strong,
                emphasis: context.emphasis,
                link: context.link,
                strikethrough: context.strikethrough
            ), to: &runs)
        case let html as InlineHTML:
            appendRun(InlineRun(
                text: html.rawHTML,
                strong: context.strong,
                emphasis: context.emphasis,
                link: context.link,
                strikethrough: context.strikethrough
            ), to: &runs)
        default:
            if markup.childCount > 0 {
                for child in markup.children {
                    collectInline(
                        child, context: context, into: &runs
                    )
                }
            } else if !plainText(of: markup).isEmpty {
                appendRun(InlineRun(
                    text: plainText(of: markup),
                    strong: context.strong,
                    emphasis: context.emphasis,
                    link: context.link,
                    strikethrough: context.strikethrough
                ), to: &runs)
            }
        }
    }

    private static let linkDetector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.link.rawValue
    )

    /// 链接候选预检：见 appendTextWithAutolinks 注
    private static func hasLinkCandidate(
        _ text: String
    ) -> Bool {
        if text.contains("://") || text.contains("www.")
            || text.contains("@") {
            return true
        }
        // 「.」两侧皆字词字符（域名形）：在 UTF-8
        // 视图上零分配扫（前后字节皆 ASCII 字词字
        // 符即成立，多字节字符字节 ≥0x80 自动落选
        // ——域名标签本就只由 ASCII 组成，口径等价）
        let bytes = text.utf8
        var previous: UInt8 = 0
        var iterator = bytes.makeIterator()
        while let byte = iterator.next() {
            if byte == 0x2E,
               previous.isASCIIWordByte {
                var lookahead = iterator
                if let next = lookahead.next(),
                   next.isASCIIWordByte {
                    return true
                }
            }
            previous = byte
        }
        return false
    }

    /// 纯文本段的裸链接提升：检测器命中的 URL／邮
    /// 箱拆成链接 run（www. 命中补 http:// 协议头，
    /// 与旧系统行内解析的产物同形），其余照原样
    private static func appendTextWithAutolinks(
        _ text: String, context: InlineContext,
        into runs: inout [InlineRun]
    ) {
        func plainRun(_ slice: String) -> InlineRun {
            InlineRun(
                text: slice,
                strong: context.strong,
                emphasis: context.emphasis,
                strikethrough: context.strikethrough
            )
        }
        // 候选预检（性能门实证：检测器全量扫描是全
        // 链热点）：链接命中必含「://」／「www.」／
        // 「@」／两侧皆字词字符的「.」之一，无候选
        // 的纯文本段（绝大多数）直通、产物不变
        guard hasLinkCandidate(text),
              let detector = linkDetector else {
            appendRun(plainRun(text), to: &runs)
            return
        }
        let fullRange = NSRange(
            text.startIndex..<text.endIndex, in: text
        )
        let matches = detector.matches(
            in: text, range: fullRange
        ).filter { match in
            // 命中口径与旧系统行内解析对齐（差分实
            // 证）：带协议的 URL、www. 开头、邮箱才
            // 提升；裸域名（example.com）旧系统不提
            // 升、检测器会多提，必须滤掉
            guard match.resultType == .link,
                  let url = match.url,
                  let range = Range(match.range, in: text)
            else { return false }
            let matched = text[range].lowercased()
            return url.scheme == "mailto"
                || matched.contains("://")
                || matched.hasPrefix("www.")
        }
        guard !matches.isEmpty else {
            appendRun(plainRun(text), to: &runs)
            return
        }
        var cursor = text.startIndex
        for match in matches {
            guard let range = Range(match.range, in: text),
                  let detected = match.url
            else { continue }
            if cursor < range.lowerBound {
                appendRun(
                    plainRun(String(text[cursor..<range.lowerBound])),
                    to: &runs
                )
            }
            let matchedText = String(text[range])
            var url = detected
            if url.scheme == nil {
                url = URL(string: "http://" + matchedText) ?? url
            }
            appendRun(InlineRun(
                text: matchedText,
                strong: context.strong,
                emphasis: context.emphasis,
                link: url,
                strikethrough: context.strikethrough
            ), to: &runs)
            cursor = range.upperBound
        }
        if cursor < text.endIndex {
            appendRun(
                plainRun(String(text[cursor..<text.endIndex])),
                to: &runs
            )
        }
    }

    /// 片段行首防护：runs 入参按契约是行内文本，
    /// 但整篇解析会把行首的 #／-／>／围栏／HTML
    /// 等读成块结构、吞掉标记字面——旧系统行内解
    /// 析（inlineOnly）恒按字面收。逐行把行首块标
    /// 记的首字符转义成字面，产物 runs 文本逐字不
    /// 变、结构恒为行内
    private static func guardFragmentLineStarts(
        _ text: String
    ) -> String {
        text.components(separatedBy: "\n")
            .map(guardFragmentLine)
            .joined(separator: "\n")
    }

    private static func guardFragmentLine(
        _ line: String
    ) -> String {
        let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
        guard let first = trimmed.first else { return line }
        let indent = line.prefix(line.count - trimmed.count)
        let rest = String(trimmed)
        func escaped(_ charCount: Int = 1) -> String {
            indent + "\\" + rest.prefix(charCount)
                + rest.dropFirst(charCount)
        }
        switch first {
        case "#", ">":
            return escaped()
        case "<":
            let second = rest.dropFirst().first
            if let second, second.isLetter || second == "/"
                || second == "!" {
                return escaped()
            }
            return line
        case "`", "~":
            if rest.hasPrefix("```") || rest.hasPrefix("~~~") {
                return escaped()
            }
            return line
        case "-", "+", "*":
            if rest.dropFirst().first == " " {
                return escaped()
            }
            let markers = rest.filter {
                $0 == "-" || $0 == "*" || $0 == "_" || $0 == " "
            }
            if markers.count == rest.count, rest.count >= 3 {
                return escaped()
            }
            return line
        case "=":
            if rest.allSatisfy({ $0 == "=" }) {
                return escaped()
            }
            return line
        default:
            if first.isNumber {
                var index = rest.startIndex
                while index < rest.endIndex,
                      rest[index].isNumber {
                    index = rest.index(after: index)
                }
                if index < rest.endIndex,
                   rest[index] == "." || rest[index] == ")",
                   rest.index(after: index) < rest.endIndex,
                   rest[rest.index(after: index)] == " " {
                    let digitCount = rest.distance(
                        from: rest.startIndex, to: index
                    )
                    return indent + rest.prefix(digitCount)
                        + "\\" + String(rest[index...])
                }
            }
            return line
        }
    }

    /// 相邻同标记合并（与 InlineRunBuilder 旧口径同
    /// 式：只减 run 数、不改呈现）
    private static func appendRun(
        _ run: InlineRun, to runs: inout [InlineRun]
    ) {
        guard !run.text.isEmpty else { return }
        if var last = runs.last,
           last.strong == run.strong,
           last.emphasis == run.emphasis,
           last.code == run.code,
           last.link == run.link,
           last.strikethrough == run.strikethrough {
            last.text += run.text
            runs[runs.count - 1] = last
            return
        }
        runs.append(run)
    }

    // MARK: - 共用小件

    /// 代码块语言口径与旧解析器逐字一致：信息串首
    /// 词 → CodeHighlight.normalizeLanguage
    private static func normalizedLanguage(
        _ language: String?
    ) -> String? {
        CodeHighlight.normalizeLanguage(
            language?.components(separatedBy: .whitespaces).first
        )
    }

    /// cmark 代码字面以 \n 收尾，旧状态机按行 join
    /// 无尾行：剥恰一枚尾 \n
    private static func stripOneTrailingNewline(
        _ code: String
    ) -> String {
        code.hasSuffix("\n") ? String(code.dropLast()) : code
    }

    /// 节点源文（HTMLBlock 等不暴露原文的节点靠源
    /// 行区间照收，与旧「整行收为段落行」同果）
    private static func sourceText(
        of markup: Markup, sourceLines: [String]
    ) -> String {
        guard let range = markup.range else {
            return plainText(of: markup)
        }
        let start = max(range.lowerBound.line - 1, 0)
        let end = min(
            range.upperBound.line - 1, sourceLines.count - 1
        )
        guard start <= end else { return plainText(of: markup) }
        return sourceLines[start...end].joined(separator: "\n")
    }

    /// 协议层无 plainText：按叶节点递归拼纯文本
    ///（兜底口径：文本叶取原文、代码叶取码、断行
    /// 折为空格、容器递归子节点）
    private static func plainText(of markup: Markup) -> String {
        switch markup {
        case let text as Text:
            return text.string
        case let code as InlineCode:
            return code.code
        case is SoftBreak, is LineBreak:
            return " "
        default:
            return markup.children
                .map { plainText(of: $0) }
                .joined()
        }
    }
}

private extension UInt8 {
    /// ASCII 字词字节（字母／数字）：链接候选预检
    /// 的域名标签口径
    var isASCIIWordByte: Bool {
        (self >= 0x30 && self <= 0x39)
            || (self >= 0x41 && self <= 0x5A)
            || (self >= 0x61 && self <= 0x7A)
    }
}
