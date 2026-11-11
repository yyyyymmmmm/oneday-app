import Foundation

/// Markdown 块级结构（0.36.25，对话渲染补全包）：聊天正文
/// 的块级解析从 MarkdownText 视图层抽到 Core 可测层——
/// 解析只产结构、不碰呈现；视图按结构渲染。补全对照
/// chat-rendering-gap-audit-20261110 的 17 项矩阵：引用
/// 块／列表（含嵌套与任务清单）／表格／分割线／标题 4–6
/// 级在此落结构，删除线走 MarkdownInline 分段，代码块
/// 语言标随 .code 的 language 字段带出。
///
/// 流式半截口径（落定渲染前的部分文本喂进来也必须稳）：
/// - 未闭合围栏：按已开围栏续渲成代码块直到文末（与
///   0.5.1 旧口径一致，不炸版、不吞字）
/// - 半截表格：只有「表头行＋完整分隔行」成对出现才认
///   表格；分隔行没写完／列数对不上时整段按段落原文降
///   级，分隔行写完的下一帧才成表——不预判、不半渲
/// - 未闭合行内标记（**／~~／`）：解析层不处理，原文
///   交给行内层按既有降级（不成对即字面）呈现
public enum MarkdownBlock: Equatable {
    /// 段落：行内 markdown 原文（多行以 \n 连接）
    case paragraph(String)
    /// 标题：level 1–6
    case heading(text: String, level: Int)
    /// 代码块：language 为围栏信息串首词小写，无标为 nil
    case code(code: String, language: String?)
    /// 引用块：连续 > 行合并，depth 为引用层级（1 起）
    case blockquote(lines: [MarkdownQuoteLine])
    /// 列表：连续列表行合并（含任务项），level 为嵌套层
    case list(items: [MarkdownListItem])
    /// 表格：header／alignments 同长，rows 已按 header
    /// 列数补齐／截断
    case table(
        header: [String],
        alignments: [MarkdownTableAlignment],
        rows: [[String]]
    )
    /// 分割线（---／***／___）
    case divider
}

/// 引用块一行：depth 1＝一层 >，2＝>>，余类推
public struct MarkdownQuoteLine: Equatable {
    public var depth: Int
    public var text: String

    public init(depth: Int, text: String) {
        self.depth = depth
        self.text = text
    }
}

/// 列表一项：marker 决定呈现（圆点／序号／勾选框）
public struct MarkdownListItem: Equatable {
    public enum Marker: Equatable {
        case bullet
        case ordered(number: Int)
        case task(checked: Bool)
    }

    public var level: Int
    public var marker: Marker
    public var text: String

    public init(level: Int, marker: Marker, text: String) {
        self.level = level
        self.marker = marker
        self.text = text
    }
}

/// 表格列对齐（来自分隔行的 : 位置）
public enum MarkdownTableAlignment: Equatable {
    case left
    case center
    case right
}

/// 块级解析器：逐行状态机，无状态残留，可对任意文本
/// （含流式半截）反复调用得确定结果
public enum MarkdownParser {
    /// §157（2026-11-11）：入口先过解析记忆——同文再
    /// 算即查表（MarkdownParseMemo），纯函数同文同
    /// 果、输出逐字不变；未命中才走 parseUncached
    public static func parse(_ content: String) -> [MarkdownBlock] {
        MarkdownParseMemos.blocks.value(for: content) {
            parseUncached(content)
        }
    }

    private static func parseUncached(_ content: String) -> [MarkdownBlock] {
        let lines = content.components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var code: [String]?
        var codeLanguage: String?
        var quote: [MarkdownQuoteLine] = []
        var list: [MarkdownListItem] = []

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(paragraph.joined(separator: "\n")))
            paragraph = []
        }
        func flushQuote() {
            guard !quote.isEmpty else { return }
            blocks.append(.blockquote(lines: quote))
            quote = []
        }
        func flushList() {
            guard !list.isEmpty else { return }
            blocks.append(.list(items: list))
            list = []
        }
        func flushAll() {
            flushParagraph()
            flushQuote()
            flushList()
        }

        var index = 0
        while index < lines.count {
            let rawLine = lines[index]
            let trimmed = rawLine
                .trimmingCharacters(in: .whitespaces)

            // —— 围栏：开关行（信息串只在开栏时取） ——
            if trimmed.hasPrefix("```") {
                if code != nil {
                    blocks.append(.code(
                        code: (code ?? []).joined(separator: "\n"),
                        language: codeLanguage
                    ))
                    code = nil
                    codeLanguage = nil
                } else {
                    flushAll()
                    code = []
                    let info = trimmed.dropFirst(3)
                        .trimmingCharacters(in: .whitespaces)
                    codeLanguage = CodeHighlight.normalizeLanguage(
                        info.components(separatedBy: .whitespaces).first
                    )
                }
                index += 1
                continue
            }
            if code != nil {
                code?.append(rawLine)
                index += 1
                continue
            }

            // —— 空行：一切块收尾；列表先看后文是否续项 ——
            if trimmed.isEmpty {
                if !list.isEmpty {
                    var lookahead = index + 1
                    while lookahead < lines.count,
                          lines[lookahead]
                            .trimmingCharacters(in: .whitespaces)
                            .isEmpty {
                        lookahead += 1
                    }
                    if lookahead < lines.count,
                       parseListItem(lines[lookahead]) != nil {
                        index = lookahead
                        continue
                    }
                }
                flushAll()
                index += 1
                continue
            }

            // —— 表格：表头＋分隔行成对才认 ——
            if trimmed.contains("|"), index + 1 < lines.count,
               let table = parseTable(
                    headerLine: rawLine,
                    delimiterLine: lines[index + 1]
               ) {
                flushAll()
                var rows: [[String]] = []
                var rowIndex = index + 2
                while rowIndex < lines.count {
                    let rowTrimmed = lines[rowIndex]
                        .trimmingCharacters(in: .whitespaces)
                    guard !rowTrimmed.isEmpty,
                          rowTrimmed.contains("|"),
                          !rowTrimmed.hasPrefix("```")
                    else { break }
                    rows.append(normalizeRow(
                        splitCells(lines[rowIndex]),
                        count: table.header.count
                    ))
                    rowIndex += 1
                }
                blocks.append(.table(
                    header: table.header,
                    alignments: table.alignments,
                    rows: rows
                ))
                index = rowIndex
                continue
            }

            // —— 标题（# 后必须带空格，1–6 级） ——
            if let heading = parseHeading(trimmed) {
                flushAll()
                blocks.append(heading)
                index += 1
                continue
            }

            // —— 分割线 ——
            if isHorizontalRule(trimmed) {
                flushAll()
                blocks.append(.divider)
                index += 1
                continue
            }

            // —— 引用块 ——
            if let quoteLine = parseQuoteLine(trimmed) {
                flushParagraph()
                flushList()
                quote.append(quoteLine)
                index += 1
                continue
            }

            // —— 列表项 ——
            if let item = parseListItem(rawLine) {
                // 有序列表打断段落只认 1. 起手（CommonMark
                // 同款防误伤：「2024. 是…」不许变列表）
                let interruptsParagraph: Bool
                switch item.marker {
                case .ordered(let number):
                    interruptsParagraph = paragraph.isEmpty
                        || number == 1
                default:
                    interruptsParagraph = true
                }
                if interruptsParagraph {
                    flushParagraph()
                    flushQuote()
                    list.append(item)
                    index += 1
                    continue
                }
            }

            // —— 列表续行：缩进 ≥2 的普通行并入末项 ——
            if !list.isEmpty,
               leadingIndent(rawLine) >= 2,
               parseListItem(rawLine) == nil {
                let last = list.count - 1
                let extra = trimmed
                list[last].text = list[last].text.isEmpty
                    ? extra
                    : list[last].text + " " + extra
                index += 1
                continue
            }

            // —— 段落行 ——
            flushQuote()
            flushList()
            paragraph.append(rawLine)
            index += 1
        }
        flushAll()
        if let code {
            // 未闭合围栏：按代码块收尾（流式半截口径）
            blocks.append(.code(
                code: code.joined(separator: "\n"),
                language: codeLanguage
            ))
        }
        return blocks
    }

    // MARK: - 行级判定

    private static func parseHeading(_ trimmed: String) -> MarkdownBlock? {
        var level = 0
        for char in trimmed {
            if char == "#" { level += 1 } else { break }
        }
        guard level >= 1, level <= 6 else { return nil }
        let rest = trimmed.dropFirst(level)
        guard rest.hasPrefix(" ") else { return nil }
        var text = rest.trimmingCharacters(in: .whitespaces)
        // CommonMark 收尾式：文末空格后的 # 串是闭合标记
        if let range = text.range(
            of: #"\s+#+$"#, options: .regularExpression
        ) {
            text = String(text[..<range.lowerBound])
        }
        guard !text.isEmpty else { return nil }
        return .heading(text: text, level: level)
    }

    private static func isHorizontalRule(_ trimmed: String) -> Bool {
        let compact = trimmed.filter { $0 != " " && $0 != "\t" }
        guard compact.count >= 3 else { return false }
        guard let first = compact.first,
              first == "-" || first == "*" || first == "_"
        else { return false }
        return compact.allSatisfy { $0 == first }
    }

    private static func parseQuoteLine(
        _ trimmed: String
    ) -> MarkdownQuoteLine? {
        guard trimmed.hasPrefix(">") else { return nil }
        var depth = 0
        var rest = trimmed[...]
        while rest.hasPrefix(">") {
            depth += 1
            rest = rest.dropFirst()
            if rest.hasPrefix(" ") { rest = rest.dropFirst() }
        }
        return MarkdownQuoteLine(
            depth: depth,
            text: String(rest)
                .trimmingCharacters(in: .whitespaces)
        )
    }

    private static func leadingIndent(_ line: String) -> Int {
        var indent = 0
        for char in line {
            if char == " " { indent += 1 }
            else if char == "\t" { indent += 4 }
            else { break }
        }
        return indent
    }

    private static func parseListItem(
        _ rawLine: String
    ) -> MarkdownListItem? {
        let indent = leadingIndent(rawLine)
        let body = rawLine.dropFirst(min(indent, rawLine.count))
        guard let first = body.first else { return nil }
        var marker: MarkdownListItem.Marker
        var rest: Substring
        if first == "-" || first == "*" || first == "+" {
            let after = body.dropFirst()
            guard after.hasPrefix(" ") || after.hasPrefix("\t")
                || after.isEmpty
            else { return nil }
            marker = .bullet
            rest = after
                .drop(while: { $0 == " " || $0 == "\t" })
            // 任务清单：- [ ] / - [x]（只认无序标记后）
            if rest.hasPrefix("[ ] ") || rest.hasPrefix("[ ]\t") {
                marker = .task(checked: false)
                rest = rest.dropFirst(4)
            } else if rest.hasPrefix("[x] ") || rest.hasPrefix("[X] ")
                || rest.hasPrefix("[x]\t") || rest.hasPrefix("[X]\t") {
                marker = .task(checked: true)
                rest = rest.dropFirst(4)
            } else if rest == "[ ]" {
                marker = .task(checked: false)
                rest = rest.dropFirst(3)
            } else if rest == "[x]" || rest == "[X]" {
                marker = .task(checked: true)
                rest = rest.dropFirst(3)
            }
        } else if first.isNumber {
            var digits = ""
            var cursor = body.startIndex
            while cursor < body.endIndex, body[cursor].isNumber {
                digits.append(body[cursor])
                cursor = body.index(after: cursor)
            }
            guard digits.count <= 9,
                  cursor < body.endIndex,
                  body[cursor] == "." || body[cursor] == ")"
            else { return nil }
            let after = body[body.index(after: cursor)...]
            guard after.hasPrefix(" ") || after.hasPrefix("\t")
            else { return nil }
            guard let number = Int(digits) else { return nil }
            marker = .ordered(number: number)
            rest = after
                .drop(while: { $0 == " " || $0 == "\t" })
        } else {
            return nil
        }
        return MarkdownListItem(
            level: min(indent / 2, 6),
            marker: marker,
            text: String(rest)
                .trimmingCharacters(in: .whitespaces)
        )
    }

    // MARK: - 表格

    private static func parseTable(
        headerLine: String, delimiterLine: String
    ) -> (
        header: [String], alignments: [MarkdownTableAlignment]
    )? {
        let delimiterTrimmed = delimiterLine
            .trimmingCharacters(in: .whitespaces)
        guard delimiterTrimmed.contains("|")
            || delimiterTrimmed.contains("-")
        else { return nil }
        let header = splitCells(headerLine)
        let delimiters = splitCells(delimiterLine)
        guard !header.isEmpty, delimiters.count == header.count
        else { return nil }
        var alignments: [MarkdownTableAlignment] = []
        for cell in delimiters {
            let value = cell.trimmingCharacters(in: .whitespaces)
            let core = value.filter { $0 == "-" }
            guard !core.isEmpty,
                  value.allSatisfy({ $0 == "-" || $0 == ":" })
            else { return nil }
            let left = value.hasPrefix(":")
            let right = value.hasSuffix(":")
            alignments.append(
                left && right ? .center : (right ? .right : .left)
            )
        }
        return (header, alignments)
    }

    /// 拆单元格：首尾竖线各剥一根，\| 转义不作分隔
    private static func splitCells(_ line: String) -> [String] {
        let placeholder = "\u{1}"
        var text = line.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "\\|", with: placeholder)
        if text.hasPrefix("|") { text.removeFirst() }
        if text.hasSuffix("|") { text.removeLast() }
        return text.components(separatedBy: "|").map {
            $0.trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: placeholder, with: "|")
        }
    }

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
}

/// 行内删除线分段（0.36.25）：系统行内解析不消费 ~~，
/// 渲染层先按本分段切开——成对 ~~ 之间的段带删除线标
/// 记，段内其余行内语法（粗斜体／行内码／链接）仍交
/// 系统解析。降级口径：未闭合的 ~~ 不成段、按字面留
/// 在普通段内（与系统对未闭合 ** 的处理一致）；行内
/// 代码段内的 ~~ 不触发（先认代码段再认 ~~）。
public enum MarkdownInline {
    public struct Segment: Equatable {
        public var text: String
        public var strikethrough: Bool

        public init(text: String, strikethrough: Bool) {
            self.text = text
            self.strikethrough = strikethrough
        }
    }

    public static func segments(_ text: String) -> [Segment] {
        var result: [Segment] = []
        var buffer = ""
        var inStrike = false
        let chars = Array(text)
        var index = 0

        func flush() {
            guard !buffer.isEmpty else { return }
            result.append(Segment(
                text: buffer, strikethrough: inStrike
            ))
            buffer = ""
        }

        while index < chars.count {
            let char = chars[index]
            // 代码段：整段原样进当前段，内部 ~~ 不触发
            if char == "`" {
                var runLength = 0
                var probe = index
                while probe < chars.count, chars[probe] == "`" {
                    runLength += 1
                    probe += 1
                }
                if let close = findBacktickRun(
                    in: chars, from: probe, length: runLength
                ) {
                    buffer += String(chars[index...close])
                    index = close + 1
                } else {
                    buffer += String(chars[index..<probe])
                    index = probe
                }
                continue
            }
            // ~~：开段须后文有闭合，闭段直接收
            if char == "~",
               index + 1 < chars.count, chars[index + 1] == "~" {
                if inStrike {
                    flush()
                    inStrike = false
                    index += 2
                    continue
                }
                if hasClosingStrike(
                    in: chars, from: index + 2
                ) {
                    flush()
                    inStrike = true
                    index += 2
                    continue
                }
                buffer += "~~"
                index += 2
                continue
            }
            buffer.append(char)
            index += 1
        }
        flush()
        return result
    }

    private static func findBacktickRun(
        in chars: [Character], from start: Int, length: Int
    ) -> Int? {
        var index = start
        while index < chars.count {
            if chars[index] == "`" {
                var runLength = 0
                var probe = index
                while probe < chars.count, chars[probe] == "`" {
                    runLength += 1
                    probe += 1
                }
                if runLength == length { return probe - 1 }
                index = probe
            } else {
                index += 1
            }
        }
        return nil
    }

    private static func hasClosingStrike(
        in chars: [Character], from start: Int
    ) -> Bool {
        var index = start
        while index < chars.count {
            if chars[index] == "`" {
                var runLength = 0
                var probe = index
                while probe < chars.count, chars[probe] == "`" {
                    runLength += 1
                    probe += 1
                }
                if let close = findBacktickRun(
                    in: chars, from: probe, length: runLength
                ) {
                    index = close + 1
                } else {
                    index = probe
                }
                continue
            }
            if chars[index] == "~",
               index + 1 < chars.count, chars[index + 1] == "~" {
                return true
            }
            index += 1
        }
        return false
    }
}
