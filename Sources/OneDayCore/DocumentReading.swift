import Foundation

/// 可进文档阅读页的文本类（0.36.31，资料库层）：阅读
/// 页只收能确定性读出文字的形态——Markdown 走 Core
/// 块解析、纯文本按空行分段、CSV 成表、JSON/YAML/XML
/// 按代码块整段呈现。HTML 不在此列：它的「阅读」是
/// 渲染成页（QuickLook 的活），不是读源文字；DOCX/
/// PDF 的文字提取另走宿主提取器（PDFKit 等），不冒充
/// 本表的纯文本路。
public enum DocumentTextKind: Sendable {
    case markdown
    case plain
    case csv
    case structured

    public static func kind(
        forFileName name: String
    ) -> DocumentTextKind? {
        switch (name as NSString).pathExtension.lowercased() {
        case "md", "markdown": return .markdown
        case "csv": return .csv
        case "json", "yaml", "yml", "xml": return .structured
        case "txt", "text", "log": return .plain
        default: return nil
        }
    }
}

/// 文档阅读页块模型（纯函数）：文本→[MarkdownBlock]，
/// 与聊天渲染共用同一块结构、呈现各走各的（聊天对标
/// Muse、阅读页对标飞书文档的块式呼吸感，见规格
/// 2026-11-11 附记）。
public enum DocumentReading {
    public static func blocks(
        for text: String, kind: DocumentTextKind
    ) -> [MarkdownBlock] {
        switch kind {
        case .markdown:
            return MarkdownParser.parse(text)
        case .plain:
            return plainBlocks(for: text)
        case .csv:
            return csvBlocks(for: text)
        case .structured:
            let trimmed = text.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            return trimmed.isEmpty
                ? [] : [.code(code: trimmed, language: nil)]
        }
    }

    /// 纯文本分段：空行分段、段内换行保留（与 Markdown
    /// 段落同口径）；全空白文本回空表（宿主据此判失败）
    public static func plainBlocks(for text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var current: [String] = []
        func flush() {
            let joined = current
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty {
                blocks.append(.paragraph(joined))
            }
            current = []
        }
        for line in text.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                flush()
            } else {
                current.append(line)
            }
        }
        flush()
        return blocks
    }

    /// CSV 成表：首行表头、余行按表头列数补齐/截断（与
    /// MarkdownParser 的表格归一同口径）；引号转义的高
    /// 级 CSV 不在此层处理（逗号直切），复杂表格回
    /// QuickLook 看原貌。空文本/只有空行回空表。
    public static func csvBlocks(for text: String) -> [MarkdownBlock] {
        let lines = text
            .components(separatedBy: "\n")
            .map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
        guard let headerLine = lines.first else { return [] }
        let header = splitCSVRow(headerLine)
        let rows = lines.dropFirst().map { line -> [String] in
            var cells = splitCSVRow(line)
            if cells.count > header.count {
                cells = Array(cells.prefix(header.count))
            }
            while cells.count < header.count {
                cells.append("")
            }
            return cells
        }
        return [
            .table(
                header: header,
                alignments: Array(
                    repeating: .left, count: header.count
                ),
                rows: rows
            ),
        ]
    }

    private static func splitCSVRow(_ line: String) -> [String] {
        line.components(separatedBy: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
    }

    /// 段落行段（§125 锚点定位）：plain 口径每段所占
    /// 的行段（1 起、含两端），与 plainBlocks 的段落
    /// 序一一对应——分段口径与 plainBlocks 逐字同
    /// 规（空行分段、段＝连续非空行），阅读页据此把
    /// `#L` 锚点落到具体段落高亮
    public static func plainParagraphLineRanges(
        for text: String
    ) -> [ClosedRange<Int>] {
        var ranges: [ClosedRange<Int>] = []
        var start: Int?
        let lines = text.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            let lineNumber = index + 1
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                if let currentStart = start {
                    ranges.append(currentStart...(lineNumber - 1))
                    start = nil
                }
            } else if start == nil {
                start = lineNumber
            }
        }
        if let start {
            ranges.append(start...lines.count)
        }
        return ranges
    }

    /// 锚点摘录（§125）：取行段原文，越界部分收敛到
    /// 文本实际行数；行段完全落在文本外回 nil（宿主
    /// 据此不摆摘录卡，不编造定位）
    public static func excerpt(
        for text: String, anchor: FileLineAnchor
    ) -> String? {
        let lines = text.components(separatedBy: "\n")
        guard anchor.startLine <= lines.count else { return nil }
        let end = min(anchor.endLine, lines.count)
        return lines[(anchor.startLine - 1)..<end]
            .joined(separator: "\n")
    }
}
