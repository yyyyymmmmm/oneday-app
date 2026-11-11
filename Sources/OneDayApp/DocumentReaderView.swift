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
    /// 行号锚点（§125，可选）：由打开页透传——text
    /// 类点开定位高亮该行段，呈现分工见 readerBody
    var anchor: FileLineAnchor? = nil

    @State private var blocks: [MarkdownBlock]?
    @State private var textKind: DocumentTextKind?
    @State private var rawText: String?
    @State private var rawData: Data?
    @State private var loadError: String?
    @State private var shareItem: FileShareItem?
    @State private var notice: String?

    private var displayTitle: String {
        DeliverableFileType.displayTitle(forFileName: entry.name)
    }

    var body: some View {
        FileReaderHost(
            title: displayTitle,
            failureMessage: loadError,
            failureActions: FileActionPolicy.failureActions(
                for: entry
            ),
            onFailureAction: performFailure,
            isLoading: blocks == nil && loadError == nil
        ) {
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
            }
        }
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

    // MARK: - 正文（块渲染收口 DocumentBlocksView，
    // §125 起与表格呈现页共用同一渲染器）

    private func readerBody(_ blocks: [MarkdownBlock]) -> some View {
        DocumentBlocksView(
            blocks: blocks,
            notice: notice,
            anchorExcerpt: anchorExcerpt,
            highlightLines: anchorHighlightLines,
            paragraphLineRanges: anchorParagraphRanges
        )
    }

    /// 块内高亮行段：plain（段落行段可精算）与
    /// structured（整段代码块、行号即原文行号）走块
    /// 内定位高亮；markdown/csv 无行↔块映射，走摘录
    /// 卡（anchorExcerpt），不假装能落到块
    private var anchorHighlightLines: ClosedRange<Int>? {
        guard let anchor,
              textKind == .plain || textKind == .structured
        else { return nil }
        return anchor.startLine...anchor.endLine
    }

    private var anchorParagraphRanges: [ClosedRange<Int>]? {
        guard anchor != nil, textKind == .plain,
              let rawText
        else { return nil }
        return DocumentReading.plainParagraphLineRanges(
            for: rawText
        )
    }

    private var anchorExcerpt: (
        anchor: FileLineAnchor, text: String
    )? {
        guard let anchor, let rawText,
              textKind == .markdown || textKind == .csv,
              let excerpt = DocumentReading.excerpt(
                  for: rawText, anchor: anchor
              )
        else { return nil }
        return (anchor, excerpt)
    }

    // MARK: - 失败页动作（失败页本体在 FileReaderHost）

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
        case .preview, .delete, .pin, .unpin, .rename, .openInFiles:
            // 阅读面策略表不给这几项（见 FileActionPolicy
            // .readingActions；pin/rename/openInFiles 是
            // 打开页专属，见 .openPageActions），落到这
            // 里即策略表漂移——静默不执行、靠单测钉住
            // 表本身
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
            textKind = kind
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


/// 阅读器呈现宿主（§139 合一，复杂度审计第 7 项）：
/// 文档阅读页与表格呈现页共用一套宿主——背景/标
/// 题/加载转圈/失败页（文案＋按类型给的动作行）只
/// 此一份实现；两阅读器只保留各自的数据准备（本
/// 地解析／伴生转码）与正文，正文块渲染走下方
/// DocumentBlocksView。失败分型九分（FileOpen-
/// Failure）是文案资产、不在此动。
struct FileReaderHost<Content: View>: View {
    let title: String
    /// 失败文案（nil＝未失败）；分型与文案由各阅读
    /// 器按自家口径算好传入（文档页 String、表格页
    /// FileOpenFailure.message()）
    var failureMessage: String? = nil
    /// 失败页动作（FileActionPolicy.failureActions
    /// 按类型给，不摆一套打天下）
    var failureActions: [FileFailureAction] = []
    var onFailureAction: (FileFailureAction) -> Void = { _ in }
    /// 无失败且正文未就绪时转圈
    var isLoading: Bool = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        Group {
            if let failureMessage {
                failureView(failureMessage)
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                content()
            }
        }
        .background(Palette.pageBG)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func failureView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("打开失败", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            ForEach(failureActions, id: \.self) { action in
                Button(action.label) {
                    onFailureAction(action)
                }
            }
        }
    }
}

/// 文档块渲染器（§125 抽出）：飞书式块排版单源——
/// 阅读页与表格呈现页（转码 CSV 成块）共用，块距/
/// 标题呼吸/高亮块/代码块/表格框线只此一份实现。
/// §125 增锚点呈现：摘录卡（无行↔块映射的种类）与
/// 块内高亮（plain 段落/structured 代码块）二选一，
/// 由宿主按种类算好传入，本件只管呈现。
struct DocumentBlocksView: View {
    let blocks: [MarkdownBlock]
    var notice: String? = nil
    var anchorExcerpt: (anchor: FileLineAnchor, text: String)? = nil
    var highlightLines: ClosedRange<Int>? = nil
    var paragraphLineRanges: [ClosedRange<Int>]? = nil

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: OneDayMetrics.spacingM) {
                    if let notice {
                        Text(notice)
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    if let anchorExcerpt {
                        excerptCard(
                            anchor: anchorExcerpt.anchor,
                            text: anchorExcerpt.text
                        )
                    }
                    ForEach(
                        Array(blocks.enumerated()), id: \.offset
                    ) { index, block in
                        blockView(block, at: index)
                            .padding(.top, topGap(for: block, at: index))
                            .id(index)
                    }
                }
                .padding(.horizontal, OneDayMetrics.pageGutter)
                .padding(.vertical, OneDayMetrics.spacingL)
            }
            .onAppear {
                if let target = firstHighlightedIndex {
                    // 定位滚动不抢首帧布局：下一轮循环再滚
                    DispatchQueue.main.async {
                        proxy.scrollTo(target, anchor: .top)
                    }
                }
            }
        }
    }

    /// 锚点摘录卡：行段原文整段呈现（定位落点），
    /// accent 底＋行段标头——用户点 `#L12-L20` 进来
    /// 第一眼就看到被引用的那几行
    private func excerptCard(
        anchor: FileLineAnchor, text: String
    ) -> some View {
        VStack(
            alignment: .leading, spacing: OneDayMetrics.spacingXS
        ) {
            Text(
                anchor.startLine == anchor.endLine
                    ? L10n.format("第 %lld 行", Int64(anchor.startLine))
                    : L10n.format(
                        "第 %lld–%lld 行",
                        Int64(anchor.startLine), Int64(anchor.endLine)
                    )
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(Palette.inkSecondary)
            Text(text)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(Palette.bodyInk)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OneDayMetrics.spacingSM)
        .background(
            Palette.primaryPale,
            in: RoundedRectangle(
                cornerRadius: OneDayMetrics.radiusThumb
            )
        )
    }

    private var firstHighlightedIndex: Int? {
        guard let highlightLines else { return nil }
        for (index, block) in blocks.enumerated() {
            switch block {
            case .paragraph:
                if let paragraphLineRanges,
                   index < paragraphLineRanges.count,
                   paragraphLineRanges[index].overlaps(highlightLines) {
                    return index
                }
            case .code(let code, _):
                let lineCount = code
                    .components(separatedBy: "\n").count
                if highlightLines.lowerBound <= lineCount {
                    return index
                }
            default:
                break
            }
        }
        return nil
    }

    private func paragraphHighlighted(at index: Int) -> Bool {
        guard let highlightLines, let paragraphLineRanges,
              index < paragraphLineRanges.count
        else { return false }
        return paragraphLineRanges[index].overlaps(highlightLines)
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
    private func blockView(
        _ block: MarkdownBlock, at index: Int
    ) -> some View {
        switch block {
        case .paragraph(let text):
            inlineText(TextShaping.prettyWrapDocument(text))
                .font(.bodyText)
                .lineSpacing(7)
                .foregroundStyle(Palette.bodyInk)
                .background {
                    // 锚点段落高亮：底色外扩不占布局，
                    // 段落本体几何与无锚点时逐字一致
                    if paragraphHighlighted(at: index) {
                        RoundedRectangle(
                            cornerRadius: OneDayMetrics.radiusThumb
                        )
                        .fill(Palette.primaryPale)
                        .padding(-OneDayMetrics.spacingS)
                    }
                }
        case .heading(let text, let level):
            inlineText(text)
                .font(Self.headingFont(level))
                .foregroundStyle(Palette.bodyInk)
        case .code(let code, let language):
            codeView(
                code, language: language,
                highlightLines: highlightLines
            )
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

    private func codeView(
        _ code: String, language: String?,
        highlightLines: ClosedRange<Int>? = nil
    ) -> some View {
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
                if let highlightLines,
                   highlightLines.lowerBound
                       <= code.components(separatedBy: "\n").count {
                    // 锚点高亮：按行分组渲染，锚点行段
                    // 整段 accent 底（structured 整段一
                    // 块、行号即原文行号，映射精确）
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(
                            Array(
                                Self.codeLineGroups(
                                    code: code,
                                    highlightLines: highlightLines
                                ).enumerated()
                            ),
                            id: \.offset
                        ) { _, group in
                            Text(group.text)
                                .font(
                                    .system(
                                        .footnote, design: .monospaced
                                    )
                                )
                                .foregroundStyle(Palette.bodyInk)
                                .background(
                                    group.highlighted
                                        ? Palette.primaryPale
                                        : Color.clear
                                )
                        }
                    }
                    .textSelection(.enabled)
                } else {
                    Text(code)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(Palette.bodyInk)
                        .textSelection(.enabled)
                }
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

    /// 代码行分组（锚点高亮用）：相邻同态行并组，保
    /// 持原文换行——组内以 \n 连接整段渲染
    private static func codeLineGroups(
        code: String, highlightLines: ClosedRange<Int>
    ) -> [(text: String, highlighted: Bool)] {
        var groups: [(text: String, highlighted: Bool)] = []
        for (index, line) in code
            .components(separatedBy: "\n").enumerated() {
            let highlighted = highlightLines.contains(index + 1)
            if var last = groups.last, last.highlighted == highlighted {
                last.text += "\n" + line
                groups[groups.count - 1] = last
            } else {
                groups.append((line, highlighted))
            }
        }
        return groups
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
