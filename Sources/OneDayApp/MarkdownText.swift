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
                        strongFont: .callout.weight(.bold)
                    )
                        // 0.4.4（§29）：正文字号 17→16——
                        // 量测 Muse 正文覆盖 14.8% vs 本
                        // 页 20.7%，取 16 落覆盖率；语义载
                        // 体走 .callout（HIG 字体表 Callout
                        // ＝16 regular），守 DesignTokens
                        // 「不许 Font.system(size:) 写死」
                        // 纪律。0.3.8 第 29 条的 17 regular
                        // 角色与 0.4.1 第 9 修的行高口径
                        // （回系统默认 leading、不自调）不
                        // 变，只是基准样式由 Body 换 Callout
                        .font(.callout)
                        // 0.4.4（§29）：正文墨换 bodyInk
                        // （#262626 炭灰、笔芯量测 ≈38），
                        // 不再用 Color.primary 近纯黑
                        .foregroundStyle(Palette.bodyInk)
                case .heading(let text, let level):
                    // 0.4.1 第 9 修（细化第 6 修）：标题从
                    // body regular 基准派生——HIG 字体规
                    // 范表里 Body 之上、字重仍为 regular
                    // 的语义样式只有 Title2（22 regular）；
                    // Headline（17 semibold）/Title3（20
                    // semibold）沾 semibold 即显粗、禁用。
                    // 一级标题走 .title2（层级由字号承
                    // 担），二级以下回 .body 基准（层级由
                    // 块间距承担）；标题内 strong 与正文
                    // 同规则——只对应内容本身的 **、映射
                    // 同字号 bold 一档，不再有「标题角色
                    // 自带 semibold」的旧口径
                    inline(
                        text,
                        strongFont: level == 1
                            ? .title2.weight(.bold)
                            : .callout.weight(.bold)
                    )
                        // 0.4.4（§29）：二级以下标题的字
                        // 号基准随正文 17→16（.body→
                        // .callout）、墨随正文换 bodyInk；
                        // 一级标题 .title2 尺寸不动、只换墨
                        .font(level == 1
                            ? .title2
                            : .callout)
                        .foregroundStyle(Palette.bodyInk)
                case .code(let code):
                    Text(code)
                        .font(.system(.footnote, design: .monospaced))
                        // 0.4.4（§29）：代码块在助手泡内、
                        // 墨随正文换 bodyInk（字号字体不动）
                        .foregroundStyle(Palette.bodyInk)
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
    /// 字重口径（0.3.3 收编、0.4.1 第 9 修定版）：strong
    /// 只对应内容本身的 **——按 InlinePresentation-
    /// Intent.stronglyEmphasized 找粗体段、重映射到
    /// strongFont（正文/标题语境一律同字号 .weight
    /// (.bold)，与 regular 基准恰差一档）；标题角色自
    /// 带 semibold 的旧口径已随第 9 修废止（标题回
    /// regular 基准，见 heading 分支）；行内代码段
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
