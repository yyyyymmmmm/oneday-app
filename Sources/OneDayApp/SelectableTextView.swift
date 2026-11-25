import OneDayCore
import OneDayDesign
import SwiftUI
import UIKit

/// 列表标记（§168）：合并散文段内由文本存储自带
/// 标记——标记文字经右对齐制表位落在固定列宽内、
/// 正文经左对齐制表位起排、续行以 headIndent 悬挂
/// 对齐正文（与旧「标记列＋正文」HStack 几何同值：
/// 列宽 22＋其后 spacingS 间隔、level 逐级 spacingM）
struct InlineListMarker {
    var text: String
    var levelIndent: CGFloat
    var columnWidth: CGFloat = 22
    var textGap: CGFloat = 8
}

/// 可选段落（§149）：SelectableInlineText 的输入单
/// 位——一段＝一组 Core InlineRun＋段级缩进／段后
/// 距。段落、正文标题、用户泡都是单段；引用块多行
/// 合一走多段（逐行一段、按引用 depth 缩进）
struct InlineTextParagraph {
    var runs: [InlineRun]
    var headIndent: CGFloat = 0
    var spaceAfter: CGFloat = 0
    /// §168：段级字阶覆盖（合并段内标题段用）；
    /// nil＝随视图的 textStyle
    var textStyleOverride: UIFont.TextStyle? = nil
    /// §168：段级次级墨色（H6 走弱化档，与旧标题
    /// 视图的前景分档同口径）
    var dimmed: Bool = false
    /// §168：列表标记（合并段内列表项用）；非空时
    /// headIndent 由标记几何接管（levelIndent 起排）
    var listMarker: InlineListMarker? = nil

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
///
/// §168 增补：段落可带段级字阶覆盖／次级墨色／列
/// 表标记（制表位悬挂缩进）——一条消息的全部散文
/// 段由此同住一个文本视图（Core MarkdownMessage-
/// Assembler 装配），双击选词与手柄扩选在整段散文
/// 内连续成立；承载视图显式 TextKit 2，量测走离
/// 屏视图、不再在布局期改写承载文本。
struct SelectableInlineText: View {
    var paragraphs: [InlineTextParagraph]
    /// 聊天正文字阶（§263 升 .body；旧 .callout 是次
    /// 级字阶、且实测行距连其规格行高都没到）
    var textStyle: UIFont.TextStyle = .body
    var foreground: Color = Palette.bodyInk
    /// §168：次级墨色解析源（dimmed 段与列表标记
    /// 用）；默认与引用块前景同档
    var dimmedForeground: Color = Palette.inkSecondaryOnFill
    var onSelectionChange: ((Bool) -> Void)?
    /// §471：列表呈现态传 false——正文禁长按直接
    /// 选字（仲裁归消息菜单、选字只从菜单「选择」
    /// 行进 sheet）；默认 true＝其余呈现面（选择
    /// sheet 本体、动态/技能等无菜单竞争面）逐字
    /// 不变
    var allowsDirectSelection: Bool = true
    /// 台账 190 留账②（§335）：排版产物段串直贴——
    /// 非 nil 时呈现直用本串（与量测同一拼装、同一
    /// 实例，入串色为 trait 动态色随承载 trait 解
    /// 析）、跳过 §168 拼装缓存；nil 时走既有拼装
    /// 路（产物未就绪回落＋非条目面）。串内容与
    /// builtAttributedString 同源同式（同 build、
    /// 同段落映射），承载/选区口径不因来源而异
    var prebuiltAttributed: NSAttributedString?
    /// §503：查找着色查询（对话内查找激活且本行在
    /// 命中集内时由 ChatView 注入；其余消费面不传
    /// ＝nil、行为逐字不变）——呈现串的副本上给全
    /// 部命中词加 findMatchFill 底。着色只动背景属
    /// 性、不动布局度量，量测台走 build 直拼不受
    /// 影响；着色副本不进拼装缓存（缓存单源不被
    /// 查找态污染，查找开关不使缓存失效）
    var searchHighlightQuery: String? = nil

    @Environment(\.self) private var environment
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.legibilityWeight) private var legibilityWeight
    @Environment(\.openURL) private var openURL

    var body: some View {
        SelectableTextRepresentable(
            attributed: presentedAttributed,
            linkColor: UIColor(
                cgColor: Palette.primary.resolve(in: environment).cgColor
            ),
            onSelectionChange: onSelectionChange,
            openURL: openURL,
            allowsDirectSelection: allowsDirectSelection
        )
    }

    /// §503：呈现串——拼装/产物串本体，查找着色在
    /// 副本上施加（区间由 Core ChatFind 在呈现串本
    /// 体上求，呈现所见即着色所及）
    private var presentedAttributed: NSAttributedString {
        let base = prebuiltAttributed ?? builtAttributedString
        guard let query = searchHighlightQuery
        else { return base }
        return Self.applyingFindHighlight(
            to: base, query: query,
            color: UIColor(
                cgColor: Palette.findMatchFill
                    .resolve(in: environment).cgColor
            )
        )
    }

    /// §503：查找着色施加（放宽 internal 作装配钉
    /// 接缝，与 build 同例）：命中区间在副本上加背
    /// 景色后返回；无查询/无命中 → 原串原样返回
    /// （同一实例，updateUIView 的 isEqual 短路不
    /// 被无谓触发）；入参本体永不改写（拼装缓存
    /// 实例可安全共享）
    static func applyingFindHighlight(
        to base: NSAttributedString, query: String,
        color: UIColor
    ) -> NSAttributedString {
        guard ChatFind.normalizedQuery(query) != nil
        else { return base }
        let ranges = ChatFind.occurrenceRanges(
            in: base.string, query: query
        )
        guard !ranges.isEmpty else { return base }
        let copy = NSMutableAttributedString(
            attributedString: base
        )
        for range in ranges {
            copy.addAttribute(
                .backgroundColor, value: color, range: range
            )
        }
        return copy
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
            overrideFont: { style in
                InlineTextFonts.baseFont(
                    textStyle: style,
                    category: dynamicTypeSize.contentSizeCategory,
                    boldText: boldTextEnabled
                )
            },
            textColor: UIColor(
                cgColor: foreground.resolve(in: environment).cgColor
            ),
            dimmedColor: UIColor(
                cgColor: dimmedForeground
                    .resolve(in: environment).cgColor
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
            dimmedForeground.resolve(in: environment).cgColor
                .components?.map { "\($0)" }.joined(separator: ",")
                ?? "",
        ]
        for paragraph in paragraphs {
            let markerKey: String
            if let marker = paragraph.listMarker {
                markerKey = "\(marker.text)@\(marker.levelIndent)"
                    + "/\(marker.columnWidth)/\(marker.textGap)"
            } else {
                markerKey = "-"
            }
            parts.append(
                "p\(paragraph.headIndent)/\(paragraph.spaceAfter)"
                    + "/\(paragraph.textStyleOverride?.rawValue ?? "-")"
                    + "/\(paragraph.dimmed ? "d" : "-")"
                    + "/\(markerKey)"
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

    /// §251：放宽为 internal——排版产物层（Layout-
    /// ProductService）按同一拼装产属性串作量测工
    /// 件；拼装口径仍只此一份，产物层不另拼
    nonisolated static func build(
        paragraphs: [InlineTextParagraph],
        baseFont: UIFont,
        overrideFont: (UIFont.TextStyle) -> UIFont,
        textColor: UIColor,
        dimmedColor: UIColor
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, paragraph) in paragraphs.enumerated() {
            let paragraphStart = result.length
            // §168：段级字体／墨色——合并段内标题段
            // 用自己的字阶、H6 用次级墨，其余随视图
            // 基准（与旧逐块视图的逐块参数同口径）
            let font = paragraph.textStyleOverride
                .map(overrideFont) ?? baseFont
            let color = paragraph.dimmed ? dimmedColor : textColor
            let style = NSMutableParagraphStyle()
            style.lineBreakMode = .byWordWrapping
            style.paragraphSpacing = paragraph.spaceAfter
            // §263：行高不在段落样式里另设数值——text
            // style 的规格 leading 由 preferredFont＋
            // TextKit 布局管理器的默认行高交付（默认
            // 档 .body pitch 实测 22＝HIG 表值）；首轮
            // 曾试 min/max 钉 font.lineHeight，被 CI
            // 实测证伪：font.lineHeight 是字体自然行
            // 高（.body 20.29），不是规格值、且 TK2
            // 并不据此给 pitch，已撤。lineHeightMul-
            // tiple 同理不许设（自设比冒充规格）
            if let marker = paragraph.listMarker {
                // 标记几何：首行自 levelIndent 起，
                // \t 落右对齐制表位（标记收尾于列
                // 宽内、与旧标记列右对齐同形），再
                // \t 落左对齐制表位起正文；续行
                // headIndent＝正文起点，悬挂对齐
                let markerEnd = marker.levelIndent
                    + marker.columnWidth
                let textStart = markerEnd + marker.textGap
                style.firstLineHeadIndent = marker.levelIndent
                style.headIndent = textStart
                style.tabStops = [
                    NSTextTab(
                        textAlignment: .right, location: markerEnd
                    ),
                    NSTextTab(
                        textAlignment: .left, location: textStart
                    ),
                ]
                let tabAttributes: [NSAttributedString.Key: Any] = [
                    .font: font, .foregroundColor: color,
                ]
                result.append(NSAttributedString(
                    string: "\t", attributes: tabAttributes
                ))
                result.append(NSAttributedString(
                    string: marker.text,
                    attributes: [
                        .font: font,
                        .foregroundColor: dimmedColor,
                    ]
                ))
                result.append(NSAttributedString(
                    string: "\t", attributes: tabAttributes
                ))
            } else {
                style.headIndent = paragraph.headIndent
                style.firstLineHeadIndent = paragraph.headIndent
            }
            for run in paragraph.runs {
                result.append(
                    attributedRun(
                        run, baseFont: font, textColor: color
                    )
                )
            }
            // 分隔换行归属本段末尾（TextKit 按段首
            // 字符取段落样式，换行须同段同式，段后
            // 距才稳定落在段尾）
            if index < paragraphs.count - 1 {
                result.append(NSAttributedString(string: "\n"))
            }
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

    nonisolated private static func attributedRun(
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
    nonisolated private static func font(
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
/// 基字体＝preferredFont 本体按字号档直取；粗体
/// 文本开启时基字重 semibold（BoldTextPolicy 根
/// 口径＝未钉字重文本统一此档），只换字重 trait、
/// 保留 text style 描述符。
/// §263 定因：旧法只摘 preferredFont 的 pointSize、
/// 再以 systemFont 重构——systemFont 无 text style，
/// 其自然行高（≈1.19×字号）顶替了规格 leading
/// （.callout 实测 pitch 19.0＜规格 21），是行距
/// 偏紧的根。规格 leading 的读口在 specLineHeight
/// （与量测池同栈实量），不在 font.lineHeight
/// （那是字体自然行高：.body 20.29≠规格 22，CI 实
/// 测钉死、不许拿它冒充规格）
enum InlineTextFonts {
    static func baseFont(
        textStyle: UIFont.TextStyle,
        category: UIContentSizeCategory,
        boldText: Bool
    ) -> UIFont {
        let preferred = UIFont.preferredFont(
            forTextStyle: textStyle,
            compatibleWith: UITraitCollection(
                preferredContentSizeCategory: category
            )
        )
        guard boldText else { return preferred }
        let descriptor = preferred.fontDescriptor.addingAttributes([
            UIFontDescriptor.AttributeName.traits: [
                UIFontDescriptor.TraitKey.weight:
                    UIFont.Weight.semibold.rawValue,
            ],
        ])
        return UIFont(descriptor: descriptor, size: 0)
    }

    /// text style 规格行高（HIG Dynamic Type 表的
    /// leading：.body 默认档 22、XXL 档 26、.callout
    /// 默认档 21）。没有可直读的字体属性：font.line-
    /// Height 是自然行高（20.29≠22），老读口 NSLay-
    /// outManager.defaultLineHeight 在 iOS 26 SDK
    /// 已无此成员（二轮 CI 编译实证）——故以与量
    /// 测池/呈现同栈（TK2）同步实量一行的高为本体：
    /// 定义即同源，行高模型下限与单测断言都从这
    /// 里读（§263）。结果按（字阶×档×粗体）缓存
    /// （盒＋锁，与 LayoutMeasurePool 的并发口径同
    /// 形——静态可变字典本身过不了 Swift 6 并发检查）
    private final class SpecCacheBox: @unchecked Sendable {
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

    private static let specCache = SpecCacheBox()

    static func specLineHeight(
        textStyle: UIFont.TextStyle,
        category: UIContentSizeCategory,
        boldText: Bool
    ) -> CGFloat {
        let key = "\(textStyle.rawValue)|\(category.rawValue)|\(boldText)"
        if let cached = specCache.get(key) { return cached }
        let assembled = SelectableInlineText.build(
            paragraphs: [.plain("测")],
            baseFont: baseFont(
                textStyle: textStyle, category: category,
                boldText: boldText
            ),
            overrideFont: { style in
                baseFont(
                    textStyle: style, category: category,
                    boldText: boldText
                )
            },
            textColor: .label,
            dimmedColor: .secondaryLabel
        )
        let storage = NSTextContentStorage()
        let layoutManager = NSTextLayoutManager()
        let container = NSTextContainer()
        container.lineFragmentPadding = 0
        container.size = CGSize(
            width: 10_000,
            height: CGFloat.greatestFiniteMagnitude
        )
        layoutManager.textContainer = container
        storage.addTextLayoutManager(layoutManager)
        storage.attributedString = assembled
        layoutManager.ensureLayout(for: storage.documentRange)
        let height = layoutManager.usageBoundsForTextContainer.height
        specCache.set(key, height)
        return height
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
    /// 聊天正文门控：拒绝 UITextView 长按手势（归消息菜单），
    /// 允许双击选词、拖柄扩选与编辑菜单。
    var suppressesDirectSelection = false

    override func gestureRecognizerShouldBegin(
        _ gestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        if suppressesDirectSelection {
            if gestureRecognizer
                is UILongPressGestureRecognizer {
                return false
            }
        }
        return super.gestureRecognizerShouldBegin(
            gestureRecognizer
        )
    }

    override func canPerformAction(
        _ action: Selector, withSender sender: Any?
    ) -> Bool {
        return super.canPerformAction(
            action, withSender: sender
        )
    }

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

/// §251：放宽为 internal——产物层对拍基准（measured-
/// Size/referenceHeight）与单测要够得着现量测本体；
/// 类型本身仍只在聊天文本面内使用
struct SelectableTextRepresentable: UIViewRepresentable {
    let attributed: NSAttributedString
    let linkColor: UIColor
    let onSelectionChange: ((Bool) -> Void)?
    let openURL: OpenURLAction
    /// §471：false＝列表态抑制直接选字（默认 true
    /// 保持其余面逐字不变）
    var allowsDirectSelection: Bool = true

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onSelectionChange: onSelectionChange, openURL: openURL
        )
    }

    func makeUIView(context: Context) -> SelectableUITextView {
        // §168：显式钉 TextKit 2——UITextView 自
        // iOS 16 起默认即 TK2（本仓亦无人碰
        // .layoutManager 触发 TK1 兼容回退，已查
        // 实），此处用官方便利构造把口径钉死、不
        // 依赖默认值（诊断报告外部核查节）
        let textView = SelectableUITextView(
            usingTextLayoutManager: true
        )
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        // §265（换代包 5·T4）：数据探测只开 [.link,
        // .phoneNumber]——探针报告 gen5-t4-probe-
        // 20261115 实证定案：两类命中干净、出口全走
        // 既有 shouldInteractWith→openURL 通道（电话
        // 的点按主动作走系统 UITextItem 默认动作＝
        // 拨号确认，即目标行为、无需拦截）；.calen-
        // darEvent/.address 在 en-US 口径下中文基本
        // 不识别且裸时刻碎片会被错期链化、.all 会把
        // 金额「¥1,299.00」链化，三者不开（日期/地址
        // 挂 zh-Hans 真机复验账，翻案时出口须走
        // UITextItem delegate 组、不是本处开关）
        textView.dataDetectorTypes = [.phoneNumber, .link]
        textView.suppressesDirectSelection =
            !allowsDirectSelection
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
        // §471：抑制旗随呈现态更新；由开转关（抑制
        // 生效）时若已有残留选区即刻清掉——列表态
        // 不许有选区在场（与 presentReactionBar 的
        // §152 让行守卫同口径：守卫对象自此只剩
        // sheet 外的历史残留）
        let suppresses = !allowsDirectSelection
        if uiView.suppressesDirectSelection != suppresses {
            uiView.suppressesDirectSelection = suppresses
            if suppresses, uiView.selectedRange.length > 0 {
                uiView.selectedRange = NSRange(
                    location: uiView.selectedRange.location,
                    length: 0
                )
            }
        }
        // §168：拼装走进程内缓存、同内容恒同实例，
        // isEqual 在此实际为恒等短路——内容键未变
        // 绝不重设文本（重设即冲选区）；布局期量测
        // 已离屏化，本方法是承载文本唯一写入点
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

    /// 离屏量测视图（§168）：与承载视图同构配置、
    /// 只量不用。旧形态 sizeThatFits 在布局期把新
    /// 文本写回**承载**视图——SwiftUI 在一次手势的
    /// 布局往返里重跑量测时，承载文本被重设、刚成
    /// 形的选区随之被冲（诊断报告机理候选二）；量
    /// 测自此永不碰承载视图，updateUIView 是唯一
    /// 写入点且只在内容键真变时写。量测在主线程
    /// 布局期串行发生，共用一台安全
    private static let measuringView: SelectableUITextView = {
        let view = SelectableUITextView(
            usingTextLayoutManager: true
        )
        view.isEditable = false
        view.isSelectable = false
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        return view
    }()

    /// 自量高：宽有提议按提议宽量高（换行后高度），
    /// 宽无提议按自然单行宽量——与 SwiftUI Text 在
    /// 气泡／列表行内的尺寸口径对齐
    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: SelectableUITextView,
        context: Context
    ) -> CGSize? {
        Self.measuredSize(
            attributed: attributed, proposal: proposal
        )
    }

    /// 量测备忘（143 根治）：（串实例身份 × 量化
    /// 宽）→尺寸——SwiftUI 在滚动中对同一行反复布
    /// 局、每次都全量 TextKit 现量是滚动路径同步量
    /// 测的大头；§168 拼装缓存保证同内容恒同实例，
    /// 身份键即内容键。备忘命中＝零量测（与 OB/
    /// LegendList「滚动不现量、尺寸来自既有产物」
    /// 同构）；未命中才真量一次并落账。容量有界、
    /// 超限整表重置（尺寸可重算、不许备忘自带无界
    /// 内存）
    /// 备忘值持串本体：钉住实例身份——实例活着，
    /// 其 ObjectIdentifier 就不会被新串复用（防地
    /// 址回收串键）；命中时再以 === 复核一次
    private static var measuredSizeCache: [
        MeasuredSizeKey: (string: NSAttributedString, size: CGSize)
    ] = [:]
    private static let measuredSizeCacheLock = NSLock()
    private static let measuredSizeCacheLimit = 1024

    private struct MeasuredSizeKey: Hashable {
        let instance: ObjectIdentifier
        let length: Int
        let widthBits: Int
    }

    /// 现量测本体（§168 离屏量测视图）：sizeThatFits
    /// 与产物层对拍基准共用——基准与现行路径同源
    /// 一台，不许有第二台「测试用量测」。143 根治
    /// 后本体先查备忘：真量只在未命中时发生一次；
    /// §251 影子对拍随之只在真量时记账（旧制每趟
    /// sizeThatFits 都付一遍全串 FNV 哈希＋串拷贝
    /// ——滚动路径的同步税，备忘命中后归零）
    static func measuredSize(
        attributed: NSAttributedString,
        proposal: ProposedViewSize
    ) -> CGSize {
        let width = measuredWidth(proposal)
        let key = MeasuredSizeKey(
            instance: ObjectIdentifier(attributed),
            length: attributed.length,
            widthBits: Int((width * 2).rounded())
        )
        measuredSizeCacheLock.lock()
        let cached = measuredSizeCache[key]
        measuredSizeCacheLock.unlock()
        if let cached, cached.string === attributed {
            return cached.size
        }
        // §419 包 1 回归哨：量测台变异只许主线程——
        // 后台量测一律走 ChatNativeTextMeasure 分发
        // 落量测池；本段（setAttributedText＋size-
        // ThatFits）被后台线程触达即线程禁闭破口。
        // debug 断言、release 行为不变，保留一个版
        // 本周期作哨
        assert(
            Thread.isMainThread,
            "§419 量测台变异离主线程：measuredSize 变异段被后台线程触达"
        )
        let measure = Self.measuringView
        if !measure.attributedText.isEqual(to: attributed) {
            measure.attributedText = attributed
        }
        let size = measure.sizeThatFits(
            CGSize(
                width: width,
                height: CGFloat.greatestFiniteMagnitude
            )
        )
        measuredSizeCacheLock.lock()
        if measuredSizeCache.count
            >= measuredSizeCacheLimit {
            measuredSizeCache.removeAll()
        }
        measuredSizeCache[key] = (attributed, size)
        measuredSizeCacheLock.unlock()
        // §251 影子对拍：同串同宽投后台量测池复量、
        // 与本值在 LayoutShadowLedger 记账比对——只
        // 记账不消费，返回值仍是现量测（行高来源不
        // 变、呈现零改动）；143 后只在真量时记（见上）
        LayoutShadowLedger.shared.record(
            attributed: attributed,
            width: width,
            referenceHeight: size.height
        )
        return size
    }

    /// 备忘命中读数（测试口：与布局匣计数口同式，
    /// 生产路径只多一次加锁查表）
    static var measuredSizeCacheCount: Int {
        measuredSizeCacheLock.lock()
        defer { measuredSizeCacheLock.unlock() }
        return measuredSizeCache.count
    }

    /// 对拍基准高（产物层/单测入口）：按给定宽走现
    /// 量测本体；宽为 nil 走自然宽口径（10_000）
    static func referenceHeight(
        attributed: NSAttributedString, width: CGFloat?
    ) -> CGFloat {
        measuredSize(
            attributed: attributed,
            proposal: ProposedViewSize(
                width: width, height: nil
            )
        ).height
    }

    /// 本次量测的实际宽：提议宽合法用提议宽、无提
    /// 议（或非法）按自然单行宽口径 10_000（与旧
    /// sizeThatFits 逐字同口径）
    static func measuredWidth(
        _ proposal: ProposedViewSize
    ) -> CGFloat {
        guard let proposedWidth = proposal.width,
              proposedWidth > 0,
              proposedWidth < .greatestFiniteMagnitude
        else { return 10_000 }
        return proposedWidth
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
