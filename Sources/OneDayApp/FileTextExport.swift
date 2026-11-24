import CoreText
import OneDayCore
import PDFKit
import UIKit

/// 文件文字提取（复制文字/导出 PDF 共用；原与文档
/// 阅读页同居，§259 阅读页退役后本文件只留文字提
/// 取与 PDF 导出两件工具）：PDF 走 PDFKit（系统
/// 件、真提取），其余按 UTF-8 解、失败退 UTF-16；
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

/// 导出 PDF（文本块→A4 文本 PDF）：CoreText 排版分
/// 页——保文字可读可搜，不追求与原文版式像素一致
/// （版式保真靠分享原文件）。表格以竖线分列成行、
/// 引用以缩进呈现，结构不丢。
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
