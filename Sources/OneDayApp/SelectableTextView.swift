import OneDayCore
import OneDayDesign
import SwiftUI
import UIKit

/// 可选段落（§149）：SelectableInlineText 的输入单
/// 位——一段＝一组 Core InlineRun＋段级缩进／段后
/// 距。段落、正文标题、用户泡都是单段；引用块多行
/// 合一走多段（逐行一段、按引用 depth 缩进）
struct InlineTextParagraph {
    var runs: [InlineRun]
    var headIndent: CGFloat = 0
    var spaceAfter: CGFloat = 0

    /// markdown 行内文本一段（经 Core 拼装）
    static func markdown(
        _ text: String,
        headIndent: CGFloat = 0,
        spaceAfter: CGFloat = 0
    ) -> InlineTextParagraph {
        InlineTextParagraph(
            runs: InlineRunBuilder.runs(for: text),
            headIndent: headIndent,
            spaceAfter: spaceAfter
        )
    }

    /// 纯文本一段（不解析 markdown）
    static func plain(
        _ text: String,
        headIndent: CGFloat = 0,
        spaceAfter: CGFloat = 0
    ) -> InlineTextParagraph {
        InlineTextParagraph(
            runs: InlineRunBuilder.plainRuns(text),
            headIndent: headIndent,
            spaceAfter: spaceAfter
        )
    }
}

/// 气泡正文可选文本（§149）：UITextView（selectable、
/// 非 editable、关滚动）包装——iOS 26 上 SwiftUI
/// .textSelection 只有整段菜单、没有选字手柄（外部
/// 核查 DESIGN §149.2），双击选词／拖柄选段／系
/// 统编辑菜单（拷贝／全选／查询／翻译）只有系统
/// 文本交互给得出，与 Muse 对照形态同源。
///
/// 拼装口径：run → NSAttributedString 在本层完成
/// （字体按环境字号档缩放、粗体文本开启时基字重
/// 升 semibold 与根口径同档；颜色经 resolve(in:)
/// 把 Palette 角色快照成 UIColor，环境一变重拼）；
/// 拼装结果按（文本＋样式键）缓存，列表滚动重排
/// 不反复解析 markdown。updateUIView 内容未变不
/// 重设 attributedText——已有选区不被父级重渲冲掉。
struct SelectableInlineText: View {
    var paragraphs: [InlineTextParagraph]
    var textStyle: UIFont.TextStyle = .callout
    var foreground: Color = Palette.bodyInk
    var onSelectionChange: ((Bool) -> Void)?

    @Environment(\.self) private var environment
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.legibilityWeight) private var legibilityWeight
    @Environment(\.openURL) private var openURL

    var body: some View {
        SelectableTextRepresentable(
            attributed: builtAttributedString,
            linkColor: UIColor(
                cgColor: Palette.primary.resolve(in: environment).cgColor
            ),
            onSelectionChange: onSelectionChange,
            openURL: openURL
        )
    }

    // MARK: - 拼装

    private var boldTextEnabled: Bool { legibilityWeight == .bold }

    private var baseFont: UIFont {
        InlineTextFonts.baseFont(
            textStyle: textStyle,
            category: dynamicTypeSize.contentSizeCategory,
            boldText: boldTextEnabled
        )
    }

    private var builtAttributedString: NSAttributedString {
        let key = cacheKey
        if let cached = InlineTextRenderCache.shared
            .object(forKey: key) {
            return cached
        }
        let built = Self.build(
            paragraphs: paragraphs,
            baseFont: baseFont,
            textColor: UIColor(
                cgColor: foreground.resolve(in: environment).cgColor
            )
        )
        InlineTextRenderCache.shared.setObject(built, forKey: key)
        return built
    }

    /// 缓存键：段落 run 全文＋标记位＋段级参数＋字
    /// 体档＋字号档＋粗体开关＋前景色解析值——任一
    /// 变即新键，旧拼装自然淘汰（NSCache 计数封顶）
    private var cacheKey: NSString {
        var parts: [String] = [
            textStyle.rawValue,
            dynamicTypeSize.contentSizeCategory.rawValue,
            boldTextEnabled ? "b" : "r",
            foreground.resolve(in: environment).cgColor
                .components?.map { "\($0)" }.joined(separator: ",")
                ?? "",
        ]
        for paragraph in paragraphs {
            parts.append(
                "p\(paragraph.headIndent)/\(paragraph.spaceAfter)"
            )
            for run in paragraph.runs {
                parts.append(
                    "\(run.text)|\(run.strong ? 1 : 0)"
                        + "\(run.emphasis ? 1 : 0)"
                        + "\(run.code ? 1 : 0)"
                        + "\(run.strikethrough ? 1 : 0)"
                        + "|\(run.link?.absoluteString ?? "")"
                )
            }
        }
        return parts.joined(separator: "\u{1}") as NSString
    }

    private static func build(
        paragraphs: [InlineTextParagraph],
        baseFont: UIFont,
        textColor: UIColor
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, paragraph) in paragraphs.enumerated() {
            let paragraphStart = result.length
            for run in paragraph.runs {
                result.append(
                    attributedRun(
                        run, baseFont: baseFont, textColor: textColor
                    )
                )
            }
            // 分隔换行归属本段末尾（TextKit 按段首
            // 字符取段落样式，换行须同段同式，段后
            // 距才稳定落在段尾）
            if index < paragraphs.count - 1 {
                result.append(NSAttributedString(string: "\n"))
            }
            let style = NSMutableParagraphStyle()
            style.headIndent = paragraph.headIndent
            style.firstLineHeadIndent = paragraph.headIndent
            style.paragraphSpacing = paragraph.spaceAfter
            style.lineBreakMode = .byWordWrapping
            result.addAttribute(
                .paragraphStyle, value: style,
                range: NSRange(
                    location: paragraphStart,
                    length: result.length - paragraphStart
                )
            )
        }
        return result
    }

    private static func attributedRun(
        _ run: InlineRun, baseFont: UIFont, textColor: UIColor
    ) -> NSAttributedString {
        var attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: textColor,
            .font: font(for: run, baseFont: baseFont),
        ]
        if let link = run.link {
            attributes[.link] = link
        }
        if run.strikethrough {
            attributes[.strikethroughStyle] =
                NSUnderlineStyle.single.rawValue
        }
        return NSAttributedString(
            string: run.text, attributes: attributes
        )
    }

    /// run 字体映射：strong＝基字体加 traitBold、
    /// emphasis＝traitItalic（两者叠加）、code＝同
    /// 字号等宽（字重随基字重）；与旧 SwiftUI 读法
    /// 的差异如实记：旧版 emphasis-only／code run
    /// 的字体由系统解析默认字号决定，本层起统一到
    /// 基字号（DESIGN §149.3 第 1 条注）
    private static func font(
        for run: InlineRun, baseFont: UIFont
    ) -> UIFont {
        if run.code {
            return UIFont.monospacedSystemFont(
                ofSize: baseFont.pointSize,
                weight: baseFont.weight
            )
        }
        var traits: UIFontDescriptor.SymbolicTraits = []
        if run.strong { traits.insert(.traitBold) }
        if run.emphasis { traits.insert(.traitItalic) }
        guard !traits.isEmpty,
              let descriptor = baseFont.fontDescriptor
                .withSymbolicTraits(traits)
        else { return baseFont }
        return UIFont(descriptor: descriptor, size: baseFont.pointSize)
    }
}

/// 拼装缓存（进程内）：键含全文与样式键，滚动重
/// 排命中即免解析；封顶 256 条防长会话无限涨。
/// 内部只有 NSCache（系统保证线程安全），故
/// @unchecked Sendable——可变状态全在它内部
private final class InlineTextRenderCache: @unchecked Sendable {
    static let shared = InlineTextRenderCache()
    private let cache = NSCache<NSString, NSAttributedString>()

    init() { cache.countLimit = 256 }

    func object(forKey key: NSString) -> NSAttributedString? {
        cache.object(forKey: key)
    }

    func setObject(_ object: NSAttributedString, forKey key: NSString) {
        cache.setObject(object, forKey: key)
    }
}

/// 字体构造单源（正文拼装与列表基线对齐共用）：
/// 基字体＝系统字体按 Metrics 依字号档缩放；粗体
/// 文本开启时基字重 semibold（BoldTextPolicy 根
/// 口径＝未钉字重文本统一此档）
enum InlineTextFonts {
    static func baseFont(
        textStyle: UIFont.TextStyle,
        category: UIContentSizeCategory,
        boldText: Bool
    ) -> UIFont {
        let weight: UIFont.Weight = boldText ? .semibold : .regular
        let standard = UIFont.preferredFont(
            forTextStyle: textStyle,
            compatibleWith: UITraitCollection(
                preferredContentSizeCategory: .large
            )
        )
        let unscaled = UIFont.systemFont(
            ofSize: standard.pointSize, weight: weight
        )
        return UIFontMetrics(forTextStyle: textStyle).scaledFont(
            for: unscaled,
            compatibleWith: UITraitCollection(
                preferredContentSizeCategory: category
            )
        )
    }

    /// 首行基线距视图顶（列表标记列 firstTextBase-
    /// line 对齐用）：inset 与 lineFragmentPadding
    /// 均归零时，首行基线＝基字体 ascender
    static func firstBaseline(
        textStyle: UIFont.TextStyle,
        category: UIContentSizeCategory,
        boldText: Bool
    ) -> CGFloat {
        baseFont(
            textStyle: textStyle, category: category, boldText: boldText
        ).ascender
    }
}

private extension UIFont {
    /// UIFont.Weight 近似读回（monospaced 字重对
    /// 齐用）：UIFont 无公开 weight 读口，按
    /// fontDescriptor 的 traits 字典取
    var weight: UIFont.Weight {
        guard let raw = fontDescriptor.object(
            forKey: .traits
        ) as? [UIFontDescriptor.TraitKey: Any],
            let value = raw[.weight] as? NSNumber
        else { return .regular }
        return UIFont.Weight(rawValue: CGFloat(value.doubleValue))
    }
}

// MARK: - UITextView 包装

/// 复制净化（§149）：选区复制剥掉 TextShaping 的
/// WORD JOINER——整形字符只管断行、混进剪贴板
/// 会污染粘贴到别处的内容；系统「拷贝」走本覆盖，
/// 选区与高亮行为全归系统
final class SelectableUITextView: UITextView {
    override func copy(_ sender: Any?) {
        let range = selectedRange
        guard range.length > 0, let attributedText,
              range.location >= 0,
              range.location + range.length <= attributedText.length
        else {
            super.copy(sender)
            return
        }
        let raw = attributedText
            .attributedSubstring(from: range).string
        UIPasteboard.general.string = raw.replacingOccurrences(
            of: TextShaping.wordJoiner, with: ""
        )
    }
}

private struct SelectableTextRepresentable: UIViewRepresentable {
    let attributed: NSAttributedString
    let linkColor: UIColor
    let onSelectionChange: ((Bool) -> Void)?
    let openURL: OpenURLAction

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onSelectionChange: onSelectionChange, openURL: openURL
        )
    }

    func makeUIView(context: Context) -> SelectableUITextView {
        let textView = SelectableUITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.dataDetectorTypes = []
        textView.delegate = context.coordinator
        textView.attributedText = attributed
        textView.linkTextAttributes = [
            .foregroundColor: linkColor
        ]
        textView.setContentCompressionResistancePriority(
            .defaultLow, for: .horizontal
        )
        return textView
    }

    func updateUIView(
        _ uiView: SelectableUITextView, context: Context
    ) {
        context.coordinator.onSelectionChange = onSelectionChange
        context.coordinator.openURL = openURL
        if !uiView.attributedText.isEqual(to: attributed) {
            let previousRange = uiView.selectedRange
            uiView.attributedText = attributed
            if previousRange.location != NSNotFound {
                let location = min(
                    previousRange.location, attributed.length
                )
                uiView.selectedRange = NSRange(
                    location: location,
                    length: min(
                        previousRange.length,
                        attributed.length - location
                    )
                )
            }
        }
        uiView.linkTextAttributes = [
            .foregroundColor: linkColor
        ]
    }

    /// 自量高：宽有提议按提议宽量高（换行后高度），
    /// 宽无提议按自然单行宽量——与 SwiftUI Text 在
    /// 气泡／列表行内的尺寸口径对齐
    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: SelectableUITextView,
        context: Context
    ) -> CGSize? {
        if !uiView.attributedText.isEqual(to: attributed) {
            uiView.attributedText = attributed
        }
        guard let proposedWidth = proposal.width,
              proposedWidth > 0,
              proposedWidth < .greatestFiniteMagnitude
        else {
            return uiView.sizeThatFits(
                CGSize(
                    width: CGFloat(10_000),
                    height: CGFloat.greatestFiniteMagnitude
                )
            )
        }
        return uiView.sizeThatFits(
            CGSize(
                width: proposedWidth,
                height: CGFloat.greatestFiniteMagnitude
            )
        )
    }

    static func dismantleUIView(
        _ uiView: SelectableUITextView, coordinator: Coordinator
    ) {
        coordinator.onSelectionChange?(false)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var onSelectionChange: ((Bool) -> Void)?
        var openURL: OpenURLAction

        init(
            onSelectionChange: ((Bool) -> Void)?,
            openURL: OpenURLAction
        ) {
            self.onSelectionChange = onSelectionChange
            self.openURL = openURL
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            onSelectionChange?(textView.selectedRange.length > 0)
        }

        /// 链接点按：交环境 openURL（与 SwiftUI
        /// Text 链接同一出口，聊天根的拦截若在场
        /// 自动跟随）、不许系统直开
        func textView(
            _ textView: UITextView,
            shouldInteractWith url: URL,
            in characterRange: NSRange,
            interaction: UITextItemInteraction
        ) -> Bool {
            openURL(url)
            return false
        }
    }
}
