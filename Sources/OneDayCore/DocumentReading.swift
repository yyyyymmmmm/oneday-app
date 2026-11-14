import Foundation

/// 文本类判定（0.36.31，资料库层）：能确定性读出
/// 文字的形态——Markdown 走 Core 块解析、纯文本按
/// 空行分段、CSV 成表、JSON/YAML/XML 按代码块整
/// 段呈现。本表供文件分类（FileActionPolicy .text
/// 档）与导出 PDF 的块模型输入；§259 起文件预览
/// 一律走 QuickLook，本表不再是预览分流依据。
/// HTML 不在此列：它渲染成页是 QuickLook 的活；
/// DOCX/PDF 的文字提取另走宿主提取器（PDFKit
/// 等），不冒充本表的纯文本路。
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

/// 文本块模型（纯函数）：文本→[MarkdownBlock]，
/// 与聊天渲染共用同一块结构。§259 后唯一消费方是
/// 导出 PDF（块→A4 文本 PDF 排版）；原文档阅读页
/// 呈现已随双轨合一退役。
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
}
