import SwiftUI
import OneDayCore
import OneDayDesign

/// Markdown 呈现（棒 1，对位 #13）：块级结构走 Core
/// MarkdownParser（与 iOS 同一解析口径），行内格式
/// 走系统 AttributedString markdown 解析；代码块走
/// Core CodeHighlight 分词着色（关键词紫／字符串
/// 绿／注释灰／数字蓝，呈现映射与 Core 注释同口径），
/// 横向滚动＋一键复制；表格走 Grid 等宽对齐。
struct MacMarkdownView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(
                Array(MarkdownParser.parse(text).enumerated()),
                id: \.offset
            ) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .paragraph(let raw):
            inlineText(raw)
                .font(.body)
                .textSelection(.enabled)
        case .heading(let raw, let level):
            inlineText(raw)
                .font(headingFont(level))
                .textSelection(.enabled)
        case .code(let code, let language):
            MacCodeBlockView(code: code, language: language)
        case .blockquote(let lines):
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Palette.inkMuted)
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(
                        Array(lines.enumerated()), id: \.offset
                    ) { _, line in
                        inlineText(line.text)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .padding(
                                .leading,
                                CGFloat(max(0, line.depth - 1)) * 12
                            )
                    }
                }
            }
        case .list(let items):
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(items.enumerated()), id: \.offset) {
                    _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(markerText(item.marker))
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 16, alignment: .trailing)
                        inlineText(item.text)
                            .font(.body)
                            .textSelection(.enabled)
                    }
                    .padding(.leading, CGFloat(item.level) * 16)
                }
            }
        case .table(let header, let alignments, let rows):
            tableView(header: header, alignments: alignments, rows: rows)
        case .divider:
            Divider()
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title2.weight(.bold)
        case 2: return .title3.weight(.bold)
        case 3: return .headline
        default: return .body.weight(.semibold)
        }
    }

    private func markerText(_ marker: MarkdownListItem.Marker) -> String {
        switch marker {
        case .bullet: return "•"
        case .ordered(let number): return "\(number)."
        case .task(let checked): return checked ? "☑" : "☐"
        }
    }

    /// 行内格式：系统 markdown 行内解析（粗/斜/行内
    /// 码/链接/删除线），解析失败回落原文不丢字
    private func inlineText(_ raw: String) -> Text {
        let segments = MarkdownInline.segments(raw)
        var result = Text("")
        for segment in segments {
            var attributed = (try? AttributedString(
                markdown: segment.text,
                options: AttributedString.MarkdownParsingOptions(
                    interpretedSyntax: .inlineOnlyPreservingWhitespace
                )
            )) ?? AttributedString(segment.text)
            if segment.strikethrough {
                attributed.strikethroughStyle = .single
            }
            result = result + Text(attributed)
        }
        return result
    }

    private func tableView(
        header: [String],
        alignments: [MarkdownTableAlignment],
        rows: [[String]]
    ) -> some View {
        Grid(
            alignment: .leading, horizontalSpacing: 14,
            verticalSpacing: 4
        ) {
            GridRow {
                ForEach(Array(header.enumerated()), id: \.offset) {
                    index, cell in
                    inlineText(cell)
                        .font(.callout.weight(.semibold))
                        .gridColumnAlignment(
                            gridAlignment(alignments, index)
                        )
                }
            }
            Divider()
            ForEach(Array(rows.enumerated()), id: \.offset) {
                _, row in
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) {
                        index, cell in
                        inlineText(cell)
                            .font(.callout)
                            .gridColumnAlignment(
                                gridAlignment(alignments, index)
                            )
                    }
                }
            }
        }
        .textSelection(.enabled)
        .padding(8)
        .background(
            Palette.surface, in: RoundedRectangle(cornerRadius: 8)
        )
    }

    private func gridAlignment(
        _ alignments: [MarkdownTableAlignment], _ index: Int
    ) -> HorizontalAlignment {
        guard alignments.indices.contains(index) else { return .leading }
        switch alignments[index] {
        case .left: return .leading
        case .center: return .center
        case .right: return .trailing
        }
    }
}

/// 代码块：语言标＋复制钮＋横向滚动的高亮代码面
struct MacCodeBlockView: View {
    let code: String
    let language: String?
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(
                    CodeHighlight.normalizeLanguage(language) ?? "code"
                )
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(
                        code, forType: .string
                    )
                    copied = true
                } label: {
                    Label(
                        copied ? "已复制" : "复制",
                        systemImage: copied ? "checkmark" : "doc.on.doc"
                    )
                    .font(.caption)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            ScrollView(.horizontal, showsIndicators: true) {
                Text(highlighted)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(
            Palette.surface, in: RoundedRectangle(cornerRadius: 8)
        )
    }

    private var highlighted: AttributedString {
        var result = AttributedString()
        for token in CodeHighlight.tokens(
            code: code, language: language
        ) {
            var part = AttributedString(token.text)
            switch token.kind {
            case .plain:
                break
            case .keyword:
                part.foregroundColor = .purple
            case .string:
                part.foregroundColor = .green
            case .comment:
                part.foregroundColor = .gray
            case .number:
                part.foregroundColor = .blue
            }
            result += part
        }
        return result
    }
}
