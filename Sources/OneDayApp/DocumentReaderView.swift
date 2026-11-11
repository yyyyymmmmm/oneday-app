import CoreText
import OneDayCore
import OneDayDesign
import PDFKit
import SwiftUI
import UIKit

/// 文件文字提取（阅读页/复制文字共用）：PDF 走 PDFKit
/// （系统件、真提取），其余按 UTF-8 解、失败退 UTF-16；
/// 读不出回 nil——调用方据此如实报错，不编造内容。
enum FileTextExtractor {
    static func plainText(
        from data: Data, entry: WorkspaceFileEntry
    ) -> String? {
        if FileActionPolicy.category(of: entry) == .pdf {
            return PDFDocument(data: data)?.string
        }
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        return String(data: data, encoding: .unicode)
    }
}

/// 文档阅读页（0.36.31，资料库层·条目文档化）：可读
/// 文本类条目（md/txt/csv/json 等，Core DocumentText-
/// Kind 判定）不再落 QuickLook 看源文件，而是进本页
/// 按块读——内部排版学飞书文档（规格 2026-11-11 附
/// 记）：块间呼吸（块距 16、标题前额外留白）、引用块
/// 升高亮块（浅底＋左 accent 条）、表格带框线与列宽
/// （按内容估宽、超屏横滚）、代码块底面＋横滚。工具
/// 栏按类型出项（FileActionPolicy.readingActions）：
/// 复制文字/导出 PDF/分享/下载，失败页按类型给动作
/// （failureActions），不摆一套打天下。
struct DocumentReaderView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let entry: WorkspaceFileEntry

    @State private var blocks: [MarkdownBlock]?
    @State private var rawText: String?
    @State private var rawData: Data?
    @State private var loadError: String?
    @State private var shareItem: FileShareItem?
    @State private var notice: String?

    private var displayTitle: String {
        DeliverableFileType.displayTitle(forFileName: entry.name)
    }

    var body: some View {
        Group {
            if let blocks {
                if blocks.isEmpty {
                    ContentUnavailableView(
                        "文件是空的",
                        systemImage: "doc.text",
                        description: Text("这个文件没有可读的正文。")
                    )
                } else {
                    readerBody(blocks)
                }
            } else if let loadError {
                failureView(loadError)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Palette.pageBG)
        .navigationTitle(displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ForEach(
                        FileActionPolicy.readingActions(for: entry),
                        id: \.self
                    ) { action in
                        Button {
                            perform(action)
                        } label: {
                            Label(action.label,
                                  systemImage: action.systemImage)
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("文件操作")
            }
        }
        .sheet(item: $shareItem) { item in
            FileShareSheet(url: item.url)
        }
        .task { await load() }
    }

    // MARK: - 正文（飞书式块排版）

    private func readerBody(_ blocks: [MarkdownBlock]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingM) {
                if let notice {
                    Text(notice)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                }
                ForEach(
                    Array(blocks.enumerated()), id: \.offset
                ) { index, block in
                    blockView(block)
                        .padding(.top, topGap(for: block, at: index))
                }
            }
            .padding(.horizontal, OneDayMetrics.pageGutter)
            .padding(.vertical, OneDayMetrics.spacingL)
        }
    }

    /// 标题前额外留白（块式呼吸感的一半来源）：一级/
    /// 二级标题前 +8、三级起 +4，首块不加
    private func topGap(for block: MarkdownBlock, at index: Int) -> CGFloat {
        guard index > 0 else { return 0 }
        if case .heading(_, let level) = block {
            return level <= 2
                ? OneDayMetrics.spacingS : OneDayMetrics.spacingXS
        }
        return 0
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .paragraph(let text):
            inlineText(TextShaping.prettyWrapDocument(text))
                .font(.bodyText)
                .lineSpacing(7)
                .foregroundStyle(Palette.bodyInk)
        case .heading(let text, let level):
            inlineText(text)
                .font(Self.headingFont(level))
                .foregroundStyle(Palette.bodyInk)
        case .code(let code, let language):
            codeView(code, language: language)
        case .blockquote(let lines):
            highlightBlock(lines)
        case .list(let items):
            listView(items)
        case .table(let header, let alignments, let rows):
            tableView(
                header: header, alignments: alignments, rows: rows
            )
        case .divider:
            GroupDivider()
        }
    }

    private static func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title2.weight(.semibold)
        case 2: return .title3.weight(.semibold)
        case 3: return .body.weight(.semibold)
        case 4: return .subheadline.weight(.semibold)
        default: return .footnote.weight(.semibold)
        }
    }

    /// 高亮块（飞书 callout 形态）：浅底圆角＋左 accent
    /// 条＋内边距，引用文字不再弱化成次墨——它是被特
    /// 意标出的内容，不是附注
    private func highlightBlock(
        _ lines: [MarkdownQuoteLine]
    ) -> some View {
        HStack(alignment: .top, spacing: OneDayMetrics.spacingSM) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Palette.primary)
                .frame(width: 4)
            VStack(
                alignment: .leading, spacing: OneDayMetrics.spacingXS
            ) {
                ForEach(
                    Array(lines.enumerated()), id: \.offset
                ) { _, line in
                    inlineText(line.text)
                        .font(.bodyText)
                        .lineSpacing(5)
                        .foregroundStyle(Palette.bodyInk)
                        .padding(
                            .leading,
                            CGFloat(max(0, line.depth - 1))
                                * OneDayMetrics.spacingM
                        )
                }
            }
        }
        .padding(OneDayMetrics.spacingSM)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Palette.primaryPale,
            in: RoundedRectangle(cornerRadius: OneDayMetrics.radiusThumb)
        )
    }

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
                Text(code)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(Palette.bodyInk)
                    .textSelection(.enabled)
            }
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

    private func listView(_ items: [MarkdownListItem]) -> some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
            ForEach(
                Array(items.enumerated()), id: \.offset
            ) { _, item in
                HStack(
                    alignment: .firstTextBaseline,
                    spacing: OneDayMetrics.spacingS
                ) {
                    markerView(item)
                        .frame(width: 22, alignment: .trailing)
                    inlineText(item.text)
                        .font(.bodyText)
                        .lineSpacing(5)
                        .foregroundStyle(Palette.bodyInk)
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
                .font(.bodyText)
                .foregroundStyle(Palette.inkSecondaryOnFill)
        case .bullet:
            Text(item.level == 0 ? "•" : (item.level == 1 ? "◦" : "▪"))
                .font(.bodyText)
                .foregroundStyle(Palette.inkSecondaryOnFill)
        }
    }

    /// 表格（飞书式）：表头底面＋行间发丝线，列宽按内
    /// 容最长行估（72...220），总宽超屏整表横滚——窄
    /// 屏不挤字、不截断单元格
    private func tableView(
        header: [String],
        alignments: [MarkdownTableAlignment],
        rows: [[String]]
    ) -> some View {
        let widths = Self.columnWidths(header: header, rows: rows)
        return ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                tableRow(
                    cells: header, widths: widths,
                    alignments: alignments, isHeader: true
                )
                ForEach(
                    Array(rows.enumerated()), id: \.offset
                ) { _, row in
                    GroupDivider()
                    tableRow(
                        cells: row, widths: widths,
                        alignments: alignments, isHeader: false
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tableRow(
        cells: [String], widths: [CGFloat],
        alignments: [MarkdownTableAlignment], isHeader: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(
                Array(cells.enumerated()), id: \.offset
            ) { column, cell in
                inlineText(cell)
                    .font(
                        isHeader
                            ? .callout.weight(.semibold) : .callout
                    )
                    .foregroundStyle(Palette.bodyInk)
                    .frame(
                        width: widths[column],
                        alignment: Self.frameAlignment(
                            alignments[column]
                        )
                    )
                    .multilineTextAlignment(
                        Self.textAlignment(alignments[column])
                    )
                    .padding(.vertical, OneDayMetrics.spacingS)
                    .padding(.horizontal, OneDayMetrics.spacingS)
            }
        }
        .background(isHeader ? Palette.fieldFill : Color.clear)
    }

    private static func columnWidths(
        header: [String], rows: [[String]]
    ) -> [CGFloat] {
        header.indices.map { column in
            var longest = header[column].count
            for row in rows where column < row.count {
                longest = max(longest, row[column].count)
            }
            return min(max(CGFloat(longest) * 10 + 28, 76), 220)
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

    // MARK: - 行内（系统 intent 渲染：粗斜体/行内代码/
    // 链接原生呈现；删除线经 Core MarkdownInline 分段
    // 补齐，与聊天渲染同源不同面）

    private func inlineText(_ text: String) -> Text {
        MarkdownInline.segments(text).reduce(Text("")) {
            partial, segment in
            partial + Text(inlineAttributed(
                segment.text,
                strikethrough: segment.strikethrough
            ))
        }
    }

    private func inlineAttributed(
        _ text: String, strikethrough: Bool
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
        if strikethrough {
            for run in Array(attributed.runs) {
                let isCode = run.inlinePresentationIntent?
                    .contains(.code) ?? false
                if !isCode {
                    attributed[run.range].strikethroughStyle = .single
                }
            }
        }
        return attributed
    }

    // MARK: - 失败页（按类型给动作）

    private func failureView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("打开失败", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            ForEach(
                FileActionPolicy.failureActions(for: entry),
                id: \.self
            ) { action in
                Button(action.label) {
                    performFailure(action)
                }
            }
        }
    }

    private func performFailure(_ action: FileFailureAction) {
        switch action {
        case .retry:
            Task { await load() }
        case .download:
            Task { await shareOriginal() }
        case .dismiss:
            dismiss()
        }
    }

    // MARK: - 动作与取数

    private func perform(_ action: FileItemAction) {
        switch action {
        case .copyText:
            if let rawText {
                UIPasteboard.general.string = rawText
                notice = "已复制全文。"
                Haptics.success()
            }
        case .exportPDF:
            exportPDF()
        case .share, .download:
            Task { await shareOriginal() }
        case .preview, .delete:
            // 阅读面策略表不给这两项（见 FileActionPolicy
            // .readingActions），落到这里即策略表漂移——
            // 静默不执行、靠单测钉住表本身
            break
        }
    }

    private func exportPDF() {
        guard let blocks,
              let data = DocumentPDFExporter.pdfData(
                  title: displayTitle, blocks: blocks
              )
        else {
            notice = "导出 PDF 失败，请稍后再试。"
            Haptics.error()
            return
        }
        shareItem = try? FileShareItem.write(
            data: data, name: "\(displayTitle).pdf"
        )
    }

    private func shareOriginal() async {
        if let rawData {
            shareItem = try? FileShareItem.write(
                data: rawData, name: entry.name
            )
            return
        }
        do {
            let data = try await fetchData()
            shareItem = try FileShareItem.write(
                data: data, name: entry.name
            )
        } catch {
            notice = (error as? HermesError)?.userMessage
                ?? "下载失败，请稍后再试。"
        }
    }

    private func fetchData() async throws -> Data {
        try await appState.performAdmin { client, config in
            try await client.fileData(config: config, path: entry.path)
        }
    }

    private func load() async {
        loadError = nil
        do {
            let data = try await fetchData()
            rawData = data
            guard let kind = DocumentTextKind.kind(
                      forFileName: entry.name
                  ),
                  let text = FileTextExtractor.plainText(
                      from: data, entry: entry
                  )
            else {
                loadError = "这个文件没能读出文字。"
                return
            }
            rawText = text
            blocks = DocumentReading.blocks(for: text, kind: kind)
        } catch let error as HermesError {
            // §121 题二 b：失败文案走五分（不存在时
            // 如实说服务器上没有这个文件），不再一
            // 句兜底
            loadError = FileOpenFailure.classify(
                error: error
            ).message()
        } catch {
            loadError = FileOpenFailure.other.message()
        }
    }
}

/// 导出 PDF（阅读页块→A4 文本 PDF）：CoreText 排版分
/// 页——保文字可读可搜，不追求与阅读页像素一致（版
/// 式保真靠分享原文件）。表格以竖线分列成行、引用以
/// 缩进呈现，结构不丢。
enum DocumentPDFExporter {
    static func pdfData(
        title: String, blocks: [MarkdownBlock]
    ) -> Data? {
        let attributed = NSMutableAttributedString()
        let titleStyle = paragraphStyle(spaceAfter: 14)
        attributed.append(NSAttributedString(
            string: title + "\n",
            attributes: [
                .font: UIFont.boldSystemFont(ofSize: 20),
                .paragraphStyle: titleStyle,
                .foregroundColor: UIColor.label,
            ]
        ))
        for block in blocks {
            attributed.append(attributedString(for: block))
        }
        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842)
        let textRect = pageRect.insetBy(dx: 48, dy: 48)
        let framesetter = CTFramesetterCreateWithAttributedString(
            attributed as CFAttributedString
        )
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let data = renderer.pdfData { context in
            var range = CFRange(location: 0, length: 0)
            let total = attributed.length
            while range.location < total {
                context.beginPage()
                let frame = CTFramesetterCreateFrame(
                    framesetter, range,
                    CGPath(rect: textRect, transform: nil), nil
                )
                let cg = context.cgContext
                cg.saveGState()
                cg.translateBy(x: 0, y: pageRect.height)
                cg.scaleBy(x: 1, y: -1)
                CTFrameDraw(frame, cg)
                cg.restoreGState()
                let visible = CTFrameGetVisibleStringRange(frame)
                if visible.length == 0 { break }
                range.location += visible.length
            }
        }
        return data.isEmpty ? nil : data
    }

    private static func paragraphStyle(
        spaceAfter: CGFloat, indent: CGFloat = 0
    ) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 5
        style.paragraphSpacing = spaceAfter
        style.firstLineHeadIndent = indent
        style.headIndent = indent
        return style
    }

    private static func bodyAttributes(
        size: CGFloat = 13.5, mono: Bool = false,
        bold: Bool = false, indent: CGFloat = 0,
        spaceAfter: CGFloat = 9
    ) -> [NSAttributedString.Key: Any] {
        let font: UIFont = mono
            ? UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
            : (bold
                ? UIFont.boldSystemFont(ofSize: size)
                : UIFont.systemFont(ofSize: size))
        return [
            .font: font,
            .paragraphStyle: paragraphStyle(
                spaceAfter: spaceAfter, indent: indent
            ),
            .foregroundColor: UIColor.label,
        ]
    }

    private static func attributedString(
        for block: MarkdownBlock
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        switch block {
        case .paragraph(let text):
            result.append(NSAttributedString(
                string: MessagePlainText.make(from: text) + "\n",
                attributes: bodyAttributes()
            ))
        case .heading(let text, let level):
            result.append(NSAttributedString(
                string: MessagePlainText.make(from: text) + "\n",
                attributes: bodyAttributes(
                    size: level <= 1 ? 18 : 15.5, bold: true,
                    spaceAfter: 7
                )
            ))
        case .code(let code, _):
            result.append(NSAttributedString(
                string: code + "\n",
                attributes: bodyAttributes(size: 11.5, mono: true)
            ))
        case .blockquote(let lines):
            for line in lines {
                result.append(NSAttributedString(
                    string: MessagePlainText.make(from: 
                        line.text
                    ) + "\n",
                    attributes: bodyAttributes(indent: 16)
                ))
            }
        case .list(let items):
            for item in items {
                let marker: String
                switch item.marker {
                case .bullet: marker = "• "
                case .ordered(let number): marker = "\(number). "
                case .task(let checked):
                    marker = checked ? "☑ " : "☐ "
                }
                result.append(NSAttributedString(
                    string: marker
                        + MessagePlainText.make(from: item.text)
                        + "\n",
                    attributes: bodyAttributes(
                        indent: CGFloat(item.level) * 14,
                        spaceAfter: 3
                    )
                ))
            }
        case .table(let header, _, let rows):
            let lines = [header] + rows
            for row in lines {
                result.append(NSAttributedString(
                    string: row.joined(separator: " ｜ ") + "\n",
                    attributes: bodyAttributes(
                        size: 12, spaceAfter: 3
                    )
                ))
            }
        case .divider:
            result.append(NSAttributedString(
                string: "\n", attributes: bodyAttributes()
            ))
        }
        return result
    }
}
