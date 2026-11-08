import OneDayDesign
import SwiftUI

/// 轻量 Markdown 渲染（里程碑 1）：块级分代码块 / 标题 / 段落三类，
/// 行内走系统 AttributedString 的 markdown 解析（粗斜体、行内代码、
/// 链接）。流式中的半截代码围栏按代码块收尾，不炸版。
/// 完整 CommonMark（表格、嵌套列表）留待后续按需升级。
struct MarkdownText: View {
    let content: String

    init(_ content: String) {
        self.content = content
    }

    private enum Block {
        case paragraph(String)
        case heading(String, Int)
        case code(String)
    }

    private var blocks: [Block] {
        var result: [Block] = []
        var paragraph: [String] = []
        var code: [String]?
        func flushParagraph() {
            if !paragraph.isEmpty {
                result.append(.paragraph(paragraph.joined(separator: "\n")))
                paragraph = []
            }
        }
        for rawLine in content.components(separatedBy: "\n") {
            let line = rawLine
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if let existing = code {
                    result.append(.code(existing.joined(separator: "\n")))
                    code = nil
                } else {
                    flushParagraph()
                    code = []
                }
                continue
            }
            if code != nil {
                code?.append(line)
                continue
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                flushParagraph()
                continue
            }
            if trimmed.hasPrefix("### ") {
                flushParagraph()
                result.append(.heading(String(trimmed.dropFirst(4)), 3))
            } else if trimmed.hasPrefix("## ") {
                flushParagraph()
                result.append(.heading(String(trimmed.dropFirst(3)), 2))
            } else if trimmed.hasPrefix("# ") {
                flushParagraph()
                result.append(.heading(String(trimmed.dropFirst(2)), 1))
            } else {
                paragraph.append(line)
            }
        }
        flushParagraph()
        if let code {
            result.append(.code(code.joined(separator: "\n")))
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .paragraph(let text):
                    inline(text)
                        .font(.body)
                        .foregroundStyle(Palette.ink)
                case .heading(let text, let level):
                    inline(text)
                        .font(level == 1 ? .title3.weight(.bold) : .headline)
                        .foregroundStyle(Palette.ink)
                case .code(let code):
                    Text(code)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(Palette.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(OneDayMetrics.spacingSM)
                        .background(
                            Palette.pageBG,
                            in: RoundedRectangle(
                                cornerRadius: OneDayMetrics.controlCorner
                            )
                        )
                        .textSelection(.enabled)
                }
            }
        }
    }

    /// 行内 markdown：解析失败回退纯文本，永不丢字
    private func inline(_ text: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) {
            return Text(attributed)
        }
        return Text(text)
    }
}
