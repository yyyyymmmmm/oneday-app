import OneDayCore
import OneDayDesign
import SwiftUI

/// 轻量 Markdown 渲染（里程碑 1）：块级分代码块 / 标题 / 段落三类，
/// 行内走系统 AttributedString 的 markdown 解析（粗斜体、行内代码、
/// 链接）。流式中的半截代码围栏按代码块收尾，不炸版。
/// 完整 CommonMark（表格、嵌套列表）留待后续按需升级。
struct MarkdownText: View {
    let content: String
    @Environment(\.colorScheme) private var colorScheme

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
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingSM) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .paragraph(let text):
                    // 条 8（§14）：段落渲染前过断行整形
                    // （尾行孤字防护）
                    inline(
                        TextShaping.prettyWrapDocument(text),
                        strongFont: TypeScale.markdownStrong
                    )
                        .font(TypeScale.bubbleBody) // 0.3.8 第 29 条：气泡正文 17 regular 显式角色
                        .lineSpacing(5)
                        .foregroundStyle(Palette.ink)
                case .heading(let text, let level):
                    // 标题内粗体与标题同重（标题角色本身
                    // 即 semibold，strong 不再叠加）
                    inline(
                        text,
                        strongFont: level == 1
                            ? TypeScale.title(for: colorScheme)
                            : TypeScale.headline
                    )
                        .font(level == 1
                            ? TypeScale.title(for: colorScheme)
                            : TypeScale.headline)
                        .foregroundStyle(Palette.ink)
                case .code(let code):
                    Text(code)
                        .font(TypeScale.monoCode)
                        .foregroundStyle(Palette.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(OneDayMetrics.spacingSM)
                        .background(
                            Palette.fieldFill,
                            in: RoundedRectangle(
                                cornerRadius: OneDayMetrics.codeCorner
                            )
                        )
                        .textSelection(.enabled)
                        // 条 10（§14）：代码块复制钮——对勾
                        // 确认态 2.5s 自隐（CopyButton 共用件）
                        .overlay(alignment: .topTrailing) {
                            CopyButton(text: code)
                                .padding(2)
                        }
                }
            }
        }
    }

    /// 行内 markdown：解析失败回退纯文本，永不丢字。
    /// 0.3.3 字重收编：解析器给行内粗体打的是系统 bold
    /// （700），越过标题角色的 semibold（600）——层级倒
    /// 挂（用户点破「正文已粗、加粗无层级可走」的实处）。
    /// 按 InlinePresentationIntent.stronglyEmphasized 找
    /// 粗体段、重映射到 strongFont（正文语境＝TypeScale
    /// .markdownStrong，与正文恰差一档）；行内代码段
    /// （.code）不碰、斜体段在 strong 字体上叠 .italic
    private func inline(_ text: String, strongFont: Font) -> Text {
        guard var attributed = try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) else {
            return Text(text)
        }
        for run in attributed.runs {
            guard let intent = run.inlinePresentationIntent,
                  intent.contains(.stronglyEmphasized),
                  !intent.contains(.code) else { continue }
            var font = strongFont
            if intent.contains(.emphasized) {
                font = font.italic()
            }
            attributed[run.range].font = font
        }
        return Text(attributed)
    }
}
