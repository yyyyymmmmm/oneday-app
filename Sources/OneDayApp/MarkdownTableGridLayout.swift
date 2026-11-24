import OneDayCore
import SwiftUI
import UIKit

/// 表格 Grid 列宽与单元格拼装单源（§396，总表
/// 139 裁定落码）：SwiftUI Grid 无列宽设定 API、
/// 格上 frame(maxWidth:) 不构成列宽约束（§329
/// 校准拟合实证：横滚组合下列按自然宽、整行不
/// 折）——列宽改由代码按「先量后排」的表格布局
/// 通行机制算定：逐列取表头与数据行的自然宽最
/// 大值、按 Core MarkdownTablePresentation
/// .maxColumnWidth 封顶。呈现（MarkdownText
/// .tableGridView 以显式宽喂格、格内折行）与量
/// 测（行高合成器 tableHeight 的 Grid 支）共用
/// 本件的拼装与列宽，两路永不分家。
/// 字体口径与合成器逐字同源：正文字体走 Inline-
/// TextFonts.baseFont(.callout)（粗体文本开关的
/// semibold 升档同口径）、strong 段走 preferred-
/// Font 叠 bold trait（与合成器 weightedFont
/// (.callout, .bold) 同式——.weight() 烘入的文
/// 本不受无障碍粗体环境影响）
enum MarkdownTableGridLayout {

    /// 单元格正文字体（合成器 plainFont(.callout) 同源）
    static func baseFont(
        category: UIContentSizeCategory,
        boldText: Bool
    ) -> UIFont {
        InlineTextFonts.baseFont(
            textStyle: .callout,
            category: category, boldText: boldText
        )
    }

    /// 单元格 strong 段字体（合成器 weightedFont
    /// (.callout, .bold) 同式）
    static func boldFont(
        category: UIContentSizeCategory
    ) -> UIFont {
        let preferred = UIFont.preferredFont(
            forTextStyle: .callout,
            compatibleWith: UITraitCollection(
                preferredContentSizeCategory: category
            )
        )
        let descriptor = preferred.fontDescriptor
            .addingAttributes([
                UIFontDescriptor.AttributeName.traits: [
                    UIFontDescriptor.TraitKey.weight:
                        UIFont.Weight.bold.rawValue,
                ],
            ])
        return UIFont(descriptor: descriptor, size: 0)
    }

    /// 表格格文本拼装（§396 起单源在本件：呈现列宽
    /// 与量测共用同一拼装；组版 0.50.99 并合 §392
    /// 收敛口径——行内语义解析只认 Core
    /// InlineRunBuilder 单源，本件只做 run 到
    /// NSAttributedString 的量测映射：strong 段
    /// 映射 boldFont、余皆 baseFont，与合成器旧
    /// 拼装逐项同口径；删除线不另立字体、不影响
    /// 宽高）
    static func cellAttributed(
        _ cell: String,
        category: UIContentSizeCategory,
        boldText: Bool
    ) -> NSAttributedString {
        let base = baseFont(
            category: category, boldText: boldText
        )
        let bold = boldFont(category: category)
        let result = NSMutableAttributedString()
        for run in InlineRunBuilder.runs(for: cell) {
            result.append(NSAttributedString(
                string: run.text,
                attributes: [.font: run.strong ? bold : base]
            ))
        }
        if result.length == 0 {
            return NSAttributedString(
                string: cell, attributes: [.font: base]
            )
        }
        return result
    }

    /// 自然宽备忘盒（锁盒＋@unchecked Sendable，
    /// 与 InlineTextFonts.SpecCacheBox 同式——静态
    /// 可变存储本身过不了 Swift 6 并发检查，读写
    /// 全在锁内）
    private final class NaturalWidthCacheBox:
        @unchecked Sendable {
        private let lock = NSLock()
        private var values: [String: CGFloat] = [:]

        func get(_ key: String) -> CGFloat? {
            lock.lock()
            defer { lock.unlock() }
            return values[key]
        }

        func set(_ key: String, _ value: CGFloat) {
            lock.lock()
            defer { lock.unlock() }
            values[key] = value
        }
    }

    /// 自然宽备忘：呈现侧每次 body 求值都算列宽、
    /// 流式行重渲频繁——同文同环境只量一次（量值
    /// 与量测同台同式、缓存只是工件，不碍单源）
    private static let naturalWidthCache =
        NaturalWidthCacheBox()

    /// 单元格自然单行宽（与量测同台：ChatNative-
    /// TextMeasure.naturalWidth）
    static func naturalWidth(
        ofCell cell: String,
        category: UIContentSizeCategory,
        boldText: Bool
    ) -> CGFloat {
        let key =
            "\(category.rawValue)|\(boldText)|\(cell)"
        if let cached = naturalWidthCache.get(key) {
            return cached
        }
        let width = ChatNativeTextMeasure.naturalWidth(
            attributed: cellAttributed(
                cell, category: category,
                boldText: boldText
            )
        )
        naturalWidthCache.set(key, width)
        return width
    }

    /// 列宽（呈现与量测单源）：逐列取表头＋全部
    /// 数据行格自然宽的最大值、按 Core 封顶值截
    /// 断；列数＝表头列数（解析层已把数据行钳制
    /// 到表头列数；短行缺格不计宽）
    static func columnWidths(
        header: [String], rows: [[String]],
        category: UIContentSizeCategory,
        boldText: Bool
    ) -> [CGFloat] {
        let cap = CGFloat(
            MarkdownTablePresentation.maxColumnWidth
        )
        return header.indices.map { column in
            var widest = naturalWidth(
                ofCell: header[column],
                category: category, boldText: boldText
            )
            for row in rows where column < row.count {
                widest = max(
                    widest,
                    naturalWidth(
                        ofCell: row[column],
                        category: category,
                        boldText: boldText
                    )
                )
            }
            return min(widest, cap)
        }
    }
}
