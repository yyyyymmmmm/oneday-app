import OneDayCore
import OneDayDesign
import SwiftUI
import UIKit

/// 行高合成器（§329）：聊天列表 .absolute 回喂高
/// 的唯一出处——由 ChatView 在 nativeRows() 逐行
/// 同步合成、随 ChatNativeRow.height 喂入布局。
///
/// 同源纪律（§251 不分家）：文本量测走呈现本体
/// 同一拼装（SelectableInlineText.build＋Mark-
/// downText.proseParagraphs/quoteParagraphs）＋同
/// 一量测台（SelectableTextRepresentable.refer-
/// enceHeight，§251 对拍基准台）；结构段与 facet
/// 高按各自视图几何逐项确定性合成（公式出处随
/// 各函数注）。合成输入与呈现读同一批状态源：条
/// 目模型、EntryScanMemo 扫描、FileMetadataStore
/// 存在性、DeliveryStore 登记 meta、行状态账本
/// （展开/审批详情）——任一源变化都经 ChatView
/// 重渲回到本合成器，不存在第二份高度事实。
///
/// 兜底（§329 入册）：facet 按视图本体的未就绪
/// 形态合成（未确证＝降级形态、meta 未到＝0），
/// 就绪后经重渲回填；整体不可达的防御分支用固
/// 定常量 fallbackHeight（单值、永不聚合）。
/// §331（题 3 根治）形态注：本合成器自 .70 起分
/// 两层——@MainActor 适配器（现行 init：持账本/
/// 宿主活读源，负责备忘键、facet 快照与量测工
/// 单组装）＋去隔离核心（facet 快照 init：只读
/// 值快照与环境，公式本体全在此层，线程无关、
/// 可在量测台后台队列整行执行）。核心读点一律
/// 经 facet 访问器（见 facet 节），活读源只许
/// 适配器与摘要函数碰——核心在后台算出与主线
/// 程同步算逐值同高，由对拍测试钉住
struct ChatNativeRowHeightComposer {
    /// 防御兜底高（§329）：单值常量、沿旧占位常
    /// 量语义，只在合成整体不可达时用。
    /// nonisolated：ChatNativeRow 的默认参数在
    /// 非隔离上下文引用本值（CGFloat 值类型、
    /// 恒定不变，隔离无意义）
    nonisolated static let fallbackHeight: CGFloat = 120

    /// 列表内容宽（屏宽−左右 inset 40）
    let contentWidth: CGFloat
    /// 助手正文宽（屏宽×文宽占屏比，与气泡布局
    /// 封顶同值，§263 单源）
    let assistantTextWidth: CGFloat
    let sizeCategory: UIContentSizeCategory
    let boldText: Bool
    let displayScale: CGFloat
    /// 活读源（适配器形态在席；量测台形态为 nil）
    let ledger: ChatRowStateLedger?
    let hubStore: AgentHubStore?
    let outboxRetry: OutboxRetryStore?
    let agentDisplayName: String
    let emptyStateAvatarSize: CGFloat
    /// 环境原值（量测工单按此重建核心）
    let screenWidth: CGFloat
    let horizontalPadding: CGFloat
    /// facet 快照（核心唯一外部输入；适配器形态
    /// 由各入口在调用核心前按行填入本值的副本）
    var facets = ChatNativeRowFacets()
    /// 预计算覆盖（台账 190 留账·nanoMuse 列表三
    /// 件②·§335）：仅预计算路（precomputedEntry-
    /// Height 组装的核心）非 nil——助手文本段高按
    /// 段下标取产物段高代全量量测；量测工单/同步
    /// 确路的核心恒 nil，两路同高对拍与备忘口径
    /// 不受扰（预计算混合总高禁入文本备忘，见
    /// markdownHeight）。用户行不走预计算（产物
    /// 宽与合成器正文宽差 40、段高系统性偏低，
    /// 见 precomputedEntryHeight 注），故无用户
    /// 侧覆盖口
    var productSegmentHeights: [Int: CGFloat]?

    init(
        screenWidth: CGFloat,
        horizontalPadding: CGFloat,
        sizeCategory: UIContentSizeCategory,
        boldText: Bool,
        displayScale: CGFloat,
        ledger: ChatRowStateLedger,
        hubStore: AgentHubStore,
        outboxRetry: OutboxRetryStore? = nil,
        agentDisplayName: String,
        emptyStateAvatarSize: CGFloat
    ) {
        self.contentWidth = screenWidth
            - horizontalPadding * 2
        self.assistantTextWidth = OneDayMetrics
            .assistantTextWidth(screenWidth: screenWidth)
        self.sizeCategory = sizeCategory
        self.boldText = boldText
        self.displayScale = displayScale
        self.ledger = ledger
        self.hubStore = hubStore
        self.outboxRetry = outboxRetry
        self.agentDisplayName = agentDisplayName
        self.emptyStateAvatarSize = emptyStateAvatarSize
        self.screenWidth = screenWidth
        self.horizontalPadding = horizontalPadding
    }

    /// 量测台形态（§331）：无活读源、facets 为唯
    /// 一外部输入——供后台队列整行量测
    init(
        screenWidth: CGFloat,
        horizontalPadding: CGFloat,
        sizeCategory: UIContentSizeCategory,
        boldText: Bool,
        displayScale: CGFloat,
        agentDisplayName: String,
        emptyStateAvatarSize: CGFloat,
        facets: ChatNativeRowFacets
    ) {
        self.contentWidth = screenWidth
            - horizontalPadding * 2
        self.assistantTextWidth = OneDayMetrics
            .assistantTextWidth(screenWidth: screenWidth)
        self.sizeCategory = sizeCategory
        self.boldText = boldText
        self.displayScale = displayScale
        self.ledger = nil
        self.hubStore = nil
        self.outboxRetry = nil
        self.agentDisplayName = agentDisplayName
        self.emptyStateAvatarSize = emptyStateAvatarSize
        self.screenWidth = screenWidth
        self.horizontalPadding = horizontalPadding
        self.facets = facets
    }

    // MARK: - 量测基元（与呈现同台）

    private var bodyBaseFont: UIFont {
        InlineTextFonts.baseFont(
            textStyle: .body,
            category: sizeCategory, boldText: boldText
        )
    }

    private func spec(
        _ style: UIFont.TextStyle
    ) -> CGFloat {
        InlineTextFonts.specLineHeight(
            textStyle: style,
            category: sizeCategory, boldText: boldText
        )
    }

    /// 未钉字重的纯文本字体（走 baseFont：粗体文
    /// 本开关的 semibold 升档与呈现同口径）
    private func plainFont(
        _ style: UIFont.TextStyle
    ) -> UIFont {
        InlineTextFonts.baseFont(
            textStyle: style,
            category: sizeCategory, boldText: boldText
        )
    }

    /// 钉字重字体（.weight() 烘入的文本不受无障碍
    /// 粗体环境影响，FontRoles 粗体映射注同口径）：
    /// preferredFont 按档取本体后叠字重 trait
    private func weightedFont(
        _ style: UIFont.TextStyle,
        _ weight: UIFont.Weight
    ) -> UIFont {
        let preferred = UIFont.preferredFont(
            forTextStyle: style,
            compatibleWith: UITraitCollection(
                preferredContentSizeCategory: sizeCategory
            )
        )
        let descriptor = preferred.fontDescriptor
            .addingAttributes([
                UIFontDescriptor.AttributeName.traits: [
                    UIFontDescriptor.TraitKey.weight:
                        weight.rawValue,
                ],
            ])
        return UIFont(descriptor: descriptor, size: 0)
    }

    private func monospacedFont(
        _ style: UIFont.TextStyle
    ) -> UIFont {
        let preferred = UIFont.preferredFont(
            forTextStyle: style,
            compatibleWith: UITraitCollection(
                preferredContentSizeCategory: sizeCategory
            )
        )
        guard let descriptor = preferred.fontDescriptor
            .withDesign(.monospaced)
        else { return preferred }
        return UIFont(descriptor: descriptor, size: 0)
    }

    /// 纯文本量测（呈现同台）：拼装口径与 Select-
    /// ableInlineText.build 的段落样式同（词断行、
    /// 段后距 0）；空串由量测台回字体行高（与视
    /// 图渲染空 Text 占一行同值）
    private func measurePlain(
        _ text: String,
        font: UIFont,
        width: CGFloat,
        lineLimit: Int? = nil,
        styleForLimit: UIFont.TextStyle? = nil
    ) -> CGFloat {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        let attributed = NSAttributedString(
            string: text,
            attributes: [
                .font: font, .paragraphStyle: style,
            ]
        )
        var height = ChatNativeTextMeasure.height(
            attributed: attributed, width: width,
            emptyLineHeight: font.lineHeight
        )
        if let lineLimit, let styleForLimit {
            height = min(
                height,
                spec(styleForLimit) * CGFloat(lineLimit)
            )
        }
        return height
    }

    private func plainHeight(
        _ text: String,
        _ style: UIFont.TextStyle,
        width: CGFloat,
        lineLimit: Int? = nil
    ) -> CGFloat {
        // 台账 196（§335）：plain 族接内容键文本备
        // 忘——回响行被副产四闸关在产物门外、无毕
        // 业路（196 定案），其行高三量（主句/结果
        // 行）与全体 plain 消费面自此同文同宽同变
        // 体只量一次，本层即回响行的第二层护盾；
        // 下游共享量测视图的尺寸备忘以串实例身份
        // 为键、现拼串结构性恒未命中且死键挤表，
        // 本层命中即整趟绕开。键变体含字阶/限行
        // （memoKey 另含文本哈希/量化宽/字号档/
        // 粗体，纯函数口径与 md/user 备忘同纪律）
        memoized(
            "ph|\(style.rawValue)|\(lineLimit ?? -1)",
            text, width
        ) {
            measurePlain(
                text, font: plainFont(style),
                width: width, lineLimit: lineLimit,
                styleForLimit: style
            )
        }
    }

    private func weightedHeight(
        _ text: String,
        _ style: UIFont.TextStyle,
        _ weight: UIFont.Weight,
        width: CGFloat,
        lineLimit: Int? = nil
    ) -> CGFloat {
        // §335/台账 196：同 plainHeight 备忘纪律
        // （变体含字重）
        memoized(
            "wh|\(style.rawValue)|\(weight.rawValue)"
                + "|\(lineLimit ?? -1)",
            text, width
        ) {
            measurePlain(
                text, font: weightedFont(style, weight),
                width: width, lineLimit: lineLimit,
                styleForLimit: style
            )
        }
    }

    /// 等宽 plain 量测（工具详情正文/修订 diff）：
    /// 同 plain 族内容键备忘纪律（§335/台账 196）
    private func monospacedHeight(
        _ text: String,
        _ style: UIFont.TextStyle,
        width: CGFloat
    ) -> CGFloat {
        memoized("mh|\(style.rawValue)", text, width) {
            measurePlain(
                text, font: monospacedFont(style),
                width: width
            )
        }
    }

    /// SwiftUI Text 单行实高（§329 续修校准实证）：
    /// UIFont 行高按显示像素向上取整——与量测台
    /// 的 spec 步长不同值（例 .footnote：实高
    /// 15.67 vs spec 18），凡呈现走 SwiftUI Text
    /// 的单行字（限行 1 的标题/标签类）走本式
    private func swiftLineHeight(_ font: UIFont) -> CGFloat {
        (font.lineHeight * displayScale).rounded(.up)
            / displayScale
    }

    /// SwiftUI Text 多行实高（§329 续修校准实
    /// 证）：折行点与量测台一致（同为 TextKit 折
    /// 行）、逐行量值不同——行数＝量测高÷字阶
    /// spec 步长取整，实高＝首行（swiftLine-
    /// Height）＋(行数−1)×spec 步长。校准集逐
    /// 值验算：思考正文 6 行 105.67、代码 5 行
    /// 87.67、工具详情等宽 3 行 46.33 全中。
    /// 凡呈现走 SwiftUI Text 的多行文本（代码/
    /// 思考正文/工具详情/表格格值）走本式，不
    /// 许再直用量测高
    private func swiftTextHeight(
        measured: CGFloat,
        stepStyle: UIFont.TextStyle,
        firstLineFont: UIFont
    ) -> CGFloat {
        guard measured > 0 else { return measured }
        let step = spec(stepStyle)
        guard step > 0 else { return measured }
        let lines = max(
            1, Int((measured / step).rounded())
        )
        return swiftLineHeight(firstLineFont)
            + CGFloat(lines - 1) * step
    }

    /// 自然单行宽（表格列宽/回响时间列宽用）
    private func naturalWidth(
        _ text: String, font: UIFont
    ) -> CGFloat {
        let attributed = NSAttributedString(
            string: text,
            attributes: [.font: font]
        )
        return ChatNativeTextMeasure.naturalWidth(
            attributed: attributed
        )
    }

    /// 自然宽备忘（§335/台账 196）：时刻宽（回响/
    /// 委派回响）与表格标签宽同入内容键备忘——同
    /// 文同字体变体只量一次（回响时刻串在卡间高
    /// 度重复、整段回响区共用少数条目）；键以字
    /// 体变体判别组装、宽位传 0（自然宽无宽入参，
    /// memoKey 的量化宽位恒 0 不碍判别）
    private func plainNaturalWidth(
        _ text: String, _ style: UIFont.TextStyle
    ) -> CGFloat {
        memoized("nw|\(style.rawValue)", text, 0) {
            naturalWidth(text, font: plainFont(style))
        }
    }

    private func weightedNaturalWidth(
        _ text: String, _ style: UIFont.TextStyle,
        _ weight: UIFont.Weight
    ) -> CGFloat {
        memoized(
            "nw|\(style.rawValue)|\(weight.rawValue)",
            text, 0
        ) {
            naturalWidth(
                text, font: weightedFont(style, weight)
            )
        }
    }

    /// 拼装量测（散文/引用/任务项正文）：与产物
    /// 层 build 同一拼装口（LayoutProductService
    /// .build 的 assemble 同式——颜色只作量测工
    /// 件属性、不影响高，解析口径照抄同源）
    private func assembledHeight(
        paragraphs: [InlineTextParagraph],
        foreground: Color,
        width: CGFloat
    ) -> CGFloat {
        let assembled = SelectableInlineText.build(
            paragraphs: paragraphs,
            baseFont: bodyBaseFont,
            overrideFont: { textStyle in
                InlineTextFonts.baseFont(
                    textStyle: textStyle,
                    category: sizeCategory,
                    boldText: boldText
                )
            },
            textColor: Self.resolved(foreground),
            dimmedColor: Self.resolved(
                Palette.inkSecondaryOnFill
            )
        )
        return ChatNativeTextMeasure.height(
            attributed: assembled, width: width,
            emptyLineHeight: bodyBaseFont.lineHeight
        )
    }

    /// 环境外解析颜色（与 LayoutProductService
    /// .resolved 同式：量测工件用、不影响高）
    private static func resolved(
        _ color: Color
    ) -> UIColor {
        var environment = EnvironmentValues()
        environment.colorScheme =
            UITraitCollection.current.userInterfaceStyle
                == .dark ? .dark : .light
        return UIColor(
            cgColor: color.resolve(in: environment)
                .cgColor
        )
    }

    // MARK: - 文本高备忘（同内容×宽×样式只量一次）

    /// nonisolated(unsafe)：NSCache 官方文档保
    /// 证线程安全（§331 起备忘被量测台后台队列
    /// 读写）、只是未标 Sendable——由本注背书
    /// §333：与整行备忘（rowCache 1024）同轨封
    /// 顶——旧形态无 countLimit，长会话文本备忘
    /// 无界涨、与整行层口径不一致
    private nonisolated(unsafe) static let textCache:
        NSCache<NSString, NSNumber> = {
        let cache = NSCache<NSString, NSNumber>()
        cache.countLimit = 1024
        return cache
    }()

    private func memoKey(
        _ kind: String, _ text: String, _ width: CGFloat
    ) -> NSString {
        let hash = LayoutProductKey.fnv1a(text)
        return "\(kind)|\(hash)|\(text.utf8.count)"
            + "|\(LayoutProductKey.quantizedWidth(Double(width)))"
            + "|\(sizeCategory.rawValue)|\(boldText ? "b" : "r")"
            as NSString
    }

    private func memoized(
        _ kind: String, _ text: String, _ width: CGFloat,
        _ compute: () -> CGFloat
    ) -> CGFloat {
        let key = memoKey(kind, text, width)
        if let hit = Self.textCache.object(forKey: key) {
            return CGFloat(hit.doubleValue)
        }
        let value = compute()
        Self.textCache.setObject(
            NSNumber(value: Double(value)), forKey: key
        )
        return value
    }

    // MARK: - 整行高备忘（§330 题 3 interim）

    /// 整行备忘（0.50.70 热修 §330，题 3 interim）：
    /// §329 后每次 ChatView body 求值都全表逐行同
    /// 步重算行高，未被文本备忘覆盖的 facet（表格
    /// 逐格自然宽/工具卡详情字段/审批卡逐项/文件
    /// 牌名/交付卡）走真实 TextKit 量测——长会话滚
    /// 动卡顿的实测主因（定因见 hotfix-05070-
    /// diagnosis 题 3）。本层在行入口加整行备忘：
    /// 键＝行修订摘要（ChatNativeRowRevision 结构
    /// 化派生，与重配判据同源）＋环境指纹（宽/字
    /// 阶/粗体/缩放/智能体名）＋facet 状态摘要（修
    /// 订之外的高度输入逐项折入：账本展开覆盖与
    /// 审批详情四态、宿主审批锚态/备注/裁决中、交
    /// 付 meta 与封面缓存态、文件存在性与元数据、
    /// 本地图解码态、回响时刻的日界），跨 body 求
    /// 值留存（静态缓存），O(1) 命中即整行跳过。
    /// 根治（量测异步预排版）随根治版，本层只做
    /// interim 减负、公式本体一字不动
    /// nonisolated(unsafe)：同 textCache 注
    private nonisolated(unsafe) static let rowCache:
        NSCache<NSString, NSNumber> = {
        let cache = NSCache<NSString, NSNumber>()
        cache.countLimit = 1024
        return cache
    }()

    /// 整行实算普查计数（测试读口，与 §329 布局
    /// 匣计数口同式：生产路径只多一次计数、无行
    /// 为影响）：备忘未命中而真算一行的次数——滚
    /// 动稳态下同修订同环境的行入口应全命中、本
    /// 计数不涨
    /// 计数盒（§331）：量测台后台队列也会触发
    /// 实算、裸 Int 静态量不再并发安全——锁盒承
    /// 载（与 OneDayCore ParseMemoBox 同式）
    private static let rowComputationBox =
        LockedRowComputationCounter()

    static var rowComputationCount: Int {
        rowComputationBox.read()
    }

    static func resetRowComputationCount() {
        rowComputationBox.reset()
    }

    /// 环境指纹：合成器构造口径中影响高的全体
    /// （宽经 LayoutProductKey 量化、与文本备忘
    /// 同口径）
    private var environmentFingerprint: String {
        "w\(LayoutProductKey.quantizedWidth(Double(contentWidth)))"
            + "|aw\(LayoutProductKey.quantizedWidth(Double(assistantTextWidth)))"
            + "|\(sizeCategory.rawValue)"
            + "|\(boldText ? "b" : "r")"
            + "|s\(displayScale)"
            + "|n\(LayoutProductKey.fnv1a(agentDisplayName))"
    }

    private func rowMemo(
        _ key: String, _ compute: () -> CGFloat
    ) -> CGFloat {
        let nsKey = key as NSString
        if let hit = Self.rowCache.object(forKey: nsKey) {
            return CGFloat(hit.doubleValue)
        }
        Self.rowComputationBox.increment()
        let value = compute()
        Self.rowCache.setObject(
            NSNumber(value: Double(value)), forKey: nsKey
        )
        return value
    }

    /// 整行备忘缓存口（§331）：同步路径（rowMemo）
    /// 与量测台回填共用同一缓存层——命中判定与落
    /// 写只此一处，两路不会各存一份。nonisolated：
    /// 量测台在后台队列回填（NSCache 本身线程安全）
    nonisolated static func cachedRowHeight(
        forKey key: String
    ) -> CGFloat? {
        rowCache.object(forKey: key as NSString)
            .map { CGFloat($0.doubleValue) }
    }

    nonisolated static func storeRowHeight(
        _ height: CGFloat, forKey key: String
    ) {
        rowCache.setObject(
            NSNumber(value: Double(height)),
            forKey: key as NSString
        )
    }

    // MARK: - 量测工单组装（§331 适配器）

    /// 条目行量测工单：主线程快照 facet＋条目，
    /// 工单在量测台后台队列以同形核心量测——与
    /// 同步路径 entryHeightWithFacets 逐值同高
    /// （对拍测试钉住）
    @MainActor
    func makeEntryMeasureJob(
        for entry: ChatEntry, dividerText: String?,
        showsUnreadDivider: Bool = false,
        sources: [MessageSource] = [],
        optionsCard: OptionsCardHeightInput? = nil,
        memoKey: String, rowKey: String
    ) -> ChatNativeRowMeasureJob {
        let facets: ChatNativeRowFacets
        if let ledger, let hubStore {
            facets = ChatNativeRowFacetSnapshotter
                .entryFacets(
                    for: entry, ledger: ledger,
                    hubStore: hubStore,
                    outboxRetry: outboxRetry,
                    optionsCard: optionsCard
                )
        } else {
            facets = ChatNativeRowFacets()
        }
        let snapshot = ChatEntryHeightSnapshot(
            entry, sources: sources
        )
        return makeJob(
            memoKey: memoKey, rowKey: rowKey,
            facets: facets,
            afterMeasure: makeEntryProductWork(
                snapshot: snapshot, facets: facets
            )
        ) {
            $0.entryHeightCore(
                snapshot, dividerText: dividerText,
                showsUnreadDivider: showsUnreadDivider
            )
        }
    }

    /// 条目排版产物副产（台账 190③）：工单量完行
    /// 高后顺产该条目的排版产物（段属性串＋各段
    /// 高）入 LayoutProductStore 同一本账——门控
    /// 与文本口径与 ChatView 预热（preheatEntries）
    /// 逐字同源（用户直取原文；助手过工具/留痕/
    /// 回响/审批四闸后取呈现文本——§335 起改走
    /// displayText 单源，与量测/呈现同文，旧摘记
    /// 文本口径作废），键（条目 id×
    /// 文本哈希×文本宽×样式键）与预热/流式估算
    /// 读口同键。执行线程分工：量测台后台队列走
    /// 同步产物口（拼装＋池同步量测）；主线程就
    /// 地量测路（measureNow）改投产物服务异步补
    /// 产（池同步口主线程禁用）
    private func makeEntryProductWork(
        snapshot: ChatEntryHeightSnapshot,
        facets: ChatNativeRowFacets
    ) -> (() -> Void)? {
        let renderedText: String
        let isUser: Bool
        if snapshot.role == "user" {
            renderedText = snapshot.content
            isUser = true
        } else if snapshot.role == "assistant",
                  snapshot.toolCard == nil,
                  snapshot.traceKey == nil,
                  snapshot.echoKey == nil,
                  snapshot.approvalKey == nil {
            // §335：副产文本改与量测/呈现同文——
            // displayText 单源助手＋本工单的 facet
            // 快照存在性（与工单核心量测同一快照、
            // 按构造同文）；文本在工单组装期先算
            // 定、副产闭包只携字符串（旧形态在副
            // 产执行期读活条目派生 media 文本，一
            // 并收口）
            var core = self
            core.facets = facets
            let scans = EntryScanMemo.scans(
                entryID: snapshot.id,
                content: snapshot.content,
                remoteImagePaths:
                    snapshot.remoteImagePaths
            )
            renderedText = Self.assistantDisplayText(
                entryID: snapshot.id, scans: scans
            ) { core.facetFileExistence($0) == .exists }
            isUser = false
        } else {
            return nil
        }
        guard !renderedText.isEmpty else { return nil }
        let entryID = snapshot.id
        let width = LayoutProductService.textWidth(
            isUser: isUser, screenWidth: screenWidth
        )
        let style = LayoutStyleContext(
            sizeCategory: sizeCategory, boldText: boldText
        )
        return {
            if Thread.isMainThread {
                Task {
                    _ = await LayoutProductService.shared
                        .product(
                            entryID: entryID,
                            renderedText: renderedText,
                            isUser: isUser, width: width,
                            style: style
                        )
                }
            } else {
                _ = LayoutProductService.shared
                    .productSynchronously(
                        entryID: entryID,
                        renderedText: renderedText,
                        isUser: isUser, width: width,
                        style: style
                    )
            }
        }
    }

    /// 工具组量测工单（同形）
    @MainActor
    func makeToolGroupMeasureJob(
        cards: [ToolCard], groupKey: String,
        memoKey: String, rowKey: String
    ) -> ChatNativeRowMeasureJob {
        let facets: ChatNativeRowFacets
        if let ledger {
            facets = ChatNativeRowFacetSnapshotter
                .groupFacets(
                    cards: cards, groupKey: groupKey,
                    ledger: ledger
                )
        } else {
            facets = ChatNativeRowFacets()
        }
        return makeJob(
            memoKey: memoKey, rowKey: rowKey,
            facets: facets
        ) {
            $0.toolGroupHeightUncached(
                cards: cards, groupKey: groupKey
            )
        }
    }

    /// 审批区量测工单（同形）
    @MainActor
    func makeZoneMeasureJob(
        memoKey: String, rowKey: String
    ) -> ChatNativeRowMeasureJob {
        let facets: ChatNativeRowFacets
        if let ledger, let hubStore {
            facets = ChatNativeRowFacetSnapshotter
                .zoneFacets(
                    ledger: ledger, hubStore: hubStore
                )
        } else {
            facets = ChatNativeRowFacets()
        }
        return makeJob(
            memoKey: memoKey, rowKey: rowKey,
            facets: facets
        ) {
            $0.approvalZoneHeightUncached()
        }
    }

    /// 回告卡量测工单（同形；卡面是纯值输入、无
    /// facet）
    @MainActor
    func makeReportMeasureJob(
        _ item: OverviewNotification,
        memoKey: String, rowKey: String
    ) -> ChatNativeRowMeasureJob {
        makeJob(memoKey: memoKey, rowKey: rowKey) {
            $0.reportCardHeightUncached(item)
        }
    }

    /// 工单骨架：环境按本适配器原值带走，后台以
    /// 量测台形态（facets 唯一输入）重建核心执行
    /// 核心闭包——工单内容自此不可变
    @MainActor
    private func makeJob(
        memoKey: String, rowKey: String,
        facets: ChatNativeRowFacets =
            ChatNativeRowFacets(),
        afterMeasure: (() -> Void)? = nil,
        core: @escaping (
            ChatNativeRowHeightComposer
        ) -> CGFloat
    ) -> ChatNativeRowMeasureJob {
        let screenWidth = self.screenWidth
        let horizontalPadding = self.horizontalPadding
        let sizeCategory = self.sizeCategory
        let boldText = self.boldText
        let displayScale = self.displayScale
        let agentDisplayName = self.agentDisplayName
        let emptyStateAvatarSize =
            self.emptyStateAvatarSize
        return ChatNativeRowMeasureJob(
            memoKey: memoKey, rowKey: rowKey
        ) {
            let composer = ChatNativeRowHeightComposer(
                screenWidth: screenWidth,
                horizontalPadding: horizontalPadding,
                sizeCategory: sizeCategory,
                boldText: boldText,
                displayScale: displayScale,
                agentDisplayName: agentDisplayName,
                emptyStateAvatarSize:
                    emptyStateAvatarSize,
                facets: facets
            )
            let height = core(composer)
            // 台账 190③：行高落定后顺产排版产物
            // （副产失败/缺产不影响行高本体）
            afterMeasure?()
            return height
        }
    }

    /// 修订摘要：ChatNativeRowRevision 的 parts
    /// 逐项 FNV-1a 折算（值清单→定长摘要；比较口
    /// 径与修订的 Equatable 逐值比较等价——摘要
    /// 只作备忘键、碰撞概率可忽略且碰撞后果仅是
    /// 一行高取错值，与文本备忘的 fnv 键同险同级）
    private static func revisionDigest(
        _ revision: ChatNativeRowRevision
    ) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        func mix(_ value: UInt64) {
            hash ^= value
            hash &*= 0x0000_0100_0000_01b3
        }
        for part in revision.parts {
            switch part {
            case .text(let string):
                mix(0x1)
                mix(LayoutProductKey.fnv1a(string))
            case .data(let data):
                mix(0x2)
                mix(fnv1a(data))
            case .flag(let flag):
                mix(flag ? 0x31 : 0x30)
            case .count(let count):
                mix(UInt64(bitPattern: Int64(count)))
            case .real(let real):
                mix(real.bitPattern)
            }
        }
        return "\(hash)"
    }

    private static func fnv1a(_ data: Data) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in data {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01b3
        }
        return hash
    }

    /// 工具卡结构化摘要（§331 R10 修）：逐字
    /// 段入修订摘要——原 JSON 编码摘要与 §325
    /// 结构化派生双轨并存、且实测同卡同组键二
    /// 算未命中（对照：全手写摘要的条目键跨趟
    /// 稳定），统一废止 JSON 口；字段集＝
    /// ToolCard 全字段、不漏一项
    private static func cardDigest(
        _ card: ToolCard
    ) -> String {
        var revision = ChatNativeRowRevision()
        revision.addText(card.id)
        revision.addText(card.toolName)
        revision.addText(card.category.rawValue)
        revision.addText(card.title)
        revision.addText(card.summary)
        revision.addText(card.result)
        revision.addFlag(card.resultFailed)
        revision.addText(card.arguments)
        return revisionDigest(revision)
    }

    /// 回告卡结构化摘要（同 cardDigest 口径）：
    /// 字段集＝OverviewNotification 全字段
    private static func reportDigest(
        _ item: OverviewNotification
    ) -> String {
        var revision = ChatNativeRowRevision()
        revision.addText(item.id)
        revision.addText(item.kind)
        revision.addText(item.title)
        revision.addText(item.body)
        revision.addText(item.createdAt)
        revision.addFlag(item.read)
        revision.addText(item.refId)
        revision.addText(item.changeId)
        return revisionDigest(revision)
    }

    private static func boolDigest(
        _ value: Bool?
    ) -> String {
        value.map { $0 ? "1" : "0" } ?? "-"
    }

    // MARK: - facet 访问器（§331 核心唯一外部读口）

    /// 展开覆盖：适配器形态读活账本、量测台形态
    /// 读快照——核心只经本口，不许直碰账本/宿主/
    /// 各 Store（后台队列上无活源可碰）
    private func facetExpansionOverride(
        for key: String
    ) -> Bool? {
        if let ledger {
            // 活读支仅适配器形态可达（恒主线程）；
            // 量测台形态 ledger 恒 nil 不可达——
            // assumeIsolated 前提由构造方式保证
            return MainActor.assumeIsolated {
                ledger.expansionOverride(for: key)
            }
        }
        return facets.expansionOverrides[key]
    }

    private func facetApprovalDetail(
        for recordID: String
    ) -> ApprovalDetailState {
        if let ledger {
            return MainActor.assumeIsolated {
                ledger.approvalDetail(for: recordID)
            }
        }
        return facets.approvalDetails[recordID]
            ?? ApprovalDetailState()
    }

    private func facetAnchorState(
        for recordID: String
    ) -> ApprovalAnchor.RowState {
        if let hubStore {
            return MainActor.assumeIsolated {
                hubStore.anchorRowState(
                    recordID: recordID
                )
            }
        }
        return facets.anchorStates[recordID] ?? .loading
    }

    private func facetCardNote(
        for recordID: String
    ) -> String? {
        if let hubStore {
            return MainActor.assumeIsolated {
                hubStore.cardNotes[recordID]
            }
        }
        return facets.cardNotes[recordID]
    }

    private func facetIsDeciding(
        _ recordID: String
    ) -> Bool {
        if let hubStore {
            return MainActor.assumeIsolated {
                hubStore.decidingIDs
                    .contains(recordID)
            }
        }
        return facets.decidingIDs.contains(recordID)
    }

    private func facetFileExistence(
        _ path: String
    ) -> FileMetadataStore.Existence? {
        if ledger != nil {
            return MainActor.assumeIsolated {
                FileMetadataStore.shared
                    .existence(for: path)
            }
        }
        return facets.fileExistences[path]
    }

    private func facetFileSize(
        _ path: String
    ) -> Int64? {
        if ledger != nil {
            return MainActor.assumeIsolated {
                FileMetadataStore.shared
                    .metadata(for: path)?.size
            }
        }
        return facets.fileSizes[path]
    }

    private func facetDeliveryMeta(
        _ id: String
    ) -> DeliveryStore.MetaResult? {
        if ledger != nil {
            return MainActor.assumeIsolated {
                DeliveryStore.shared
                    .metaResult(for: id)
            }
        }
        return facets.deliveryMetas[id]
    }

    /// 封面形态（§407 定高）：只认登记旗
    /// meta.cover.cover——入列时模型已知的唯一判
    /// 定；快照图/缩略图缓存是到达态、进公式即
    /// 「图到换高」，旧三路 OR 自此退役（钉测播
    /// 种把守）。快照形态读快照点同公式的定格值
    private func facetDeliveryCoverForm(
        _ meta: BridgeDelivery
    ) -> Bool {
        if ledger != nil {
            return meta.cover.cover
        }
        return facets.deliveryCoverForms[meta.id]
            ?? false
    }

    private func facetLocalImageDecoded(
        entryID: UUID, index: Int, data: Data
    ) -> Bool {
        if ledger != nil {
            return LocalImageStore.shared.image(
                entryID: entryID, index: index,
                data: data
            ) != nil
        }
        return facets.localImageDecoded.indices
            .contains(index)
            && facets.localImageDecoded[index]
    }

    private func facetFailureKind(
        for entryID: UUID
    ) -> SendFailureKind {
        if let outboxRetry {
            return MainActor.assumeIsolated {
                outboxRetry.record(for: entryID)?
                    .lastFailureKind ?? .unknown
            }
        }
        return facets.failureKinds[entryID] ?? .unknown
    }

    /// 审批区遍历集（ready 记录/锚定集/已决行
    /// id）：活读形态读宿主、快照形态读快照
    private func facetZoneInputs()
        -> (records: [WriteGateRecord],
            anchored: Set<String>,
            resolvedLineIDs: [String])?
    {
        if let hubStore {
            return MainActor.assumeIsolated {
                guard case .ready(let records)
                    = hubStore.approvalState
                else { return nil }
                return (
                    records,
                    hubStore.anchoredRecordIDs,
                    hubStore.resolvedLines.map(\.id)
                )
            }
        }
        guard let records = facets.zoneRecords
        else { return nil }
        return (
            records, facets.zoneAnchoredIDs,
            facets.zoneResolvedLineIDs
        )
    }

    /// 审批详情四态摘要（合成读的全体：展开/加载
    /// 态＋详情的注意行/原文失效位/diff 全文＋错
    /// 误文案）
    private func approvalDetailDigest(
        _ recordID: String
    ) -> String {
        let state = facetApprovalDetail(for: recordID)
        var parts = [
            "x\(state.expanded ? "1" : "0")",
            "l\(state.loading ? "1" : "0")",
            "e\(state.error.map { "\(LayoutProductKey.fnv1a($0))" } ?? "-")",
        ]
        if let detail = state.detail {
            var detailParts = detail.review.noteLabels
                .map { "\(LayoutProductKey.fnv1a($0))" }
            detailParts.append(
                "o\(detail.review.requestedOldString != nil ? "1" : "0")"
            )
            detailParts.append(
                "d\(LayoutProductKey.fnv1a(detail.review.displayDiff))"
            )
            parts.append(
                "D\(detailParts.joined(separator: ","))"
            )
        } else {
            parts.append("D-")
        }
        return parts.joined(separator: "|")
    }

    /// 审批记录本体摘要（卡面合成读的全体：问句/
    /// 原因行派生文案＋可裁决/阻断位＋备注＋裁决
    /// 中——记录其余字段不入高）
    private func approvalRecordDigest(
        _ record: WriteGateRecord
    ) -> String {
        "q\(LayoutProductKey.fnv1a(ApprovalCardCopy.question(for: record)))"
            + "|r\(ApprovalCardCopy.reasonLine(for: record).map { "\(LayoutProductKey.fnv1a($0))" } ?? "-")"
            + "|c\(record.canDecide ? "1" : "0")"
            + "|b\(record.isBlocked ? "1" : "0")"
            + "|n\(facetCardNote(for: record.id).map { "\(LayoutProductKey.fnv1a($0))" } ?? "-")"
            + "|d\(facetIsDeciding(record.id) ? "1" : "0")"
    }

    /// 文件状态摘要（牌/图/交付合成读的全体：存
    /// 在性＋元数据大小——牌面副行与菜单在席判定
    /// 的输入）
    private func fileStateDigest(
        _ path: String
    ) -> String {
        let existence = facetFileExistence(path)
        let size = facetFileSize(path)
        return "\(existence)|\(size.map(String.init) ?? "-")"
    }

    /// 交付 meta 摘要（交付合成读的全体：未到/
    /// 查无/已载三态；已载折状态/种类/名/大小＋
    /// 封面三路缓存态）
    private func deliveryMetaDigest(
        _ id: String
    ) -> String {
        switch facetDeliveryMeta(id) {
        case nil:
            return "nil"
        case .notFound:
            return "nf"
        case .failed(let message):
            return "err\(LayoutProductKey.fnv1a(message))"
        case .loaded(let meta):
            // 封面三路缓存态在高里只以合成形态
            // （coverForm）出现——摘要同口径折合
            // 成形态一位，与核心读点逐值对应
            let coverFlag = facetDeliveryCoverForm(meta)
                ? "1" : "0"
            return "ld\(meta.status)"
                + "|\(meta.kind)"
                + "|\(LayoutProductKey.fnv1a(meta.name))"
                + "|\(String(meta.size))"
                + "|cf\(coverFlag)"
        }
    }

    /// 条目行 facet 状态摘要：修订之外的高度输入
    /// 逐项折入（账本两键/审批锚全态/交付与文件
    /// 状态/本地图解码/回响日界）——摘要的每一项
    /// 都对应 entryHeight 家族的一处外部读，漏折
    /// 一项即旧高残留、与 §325 修订漏折同病，故
    /// 逐项按合成读点对账列全
    private func entryFacetDigest(
        _ entry: ChatEntry,
        buildProducts: ChatEntryRowBuildMemo.Products? = nil,
        optionsCard: OptionsCardHeightInput? = nil
    ) -> String {
        var parts: [String] = []
        parts.append(
            "rx\(Self.boolDigest(facetExpansionOverride(for: ChatRowStateKeys.reasoningEntry(entry.id))))"
        )
        parts.append(
            "tx\(Self.boolDigest(facetExpansionOverride(for: ChatRowStateKeys.toolEntry(entry.id))))"
        )
        parts.append(
            "sx\(Self.boolDigest(facetExpansionOverride(for: ChatRowStateKeys.sourcesEntry(entry.id))))"
        )
        if let oc = optionsCard {
            // 选择框（§441）：状态＋项数折入——卡
            // 出现/点选/过期都改行高，摘要必须同
            // 变；入参由行构建点按覆盖层派生（与
            // sources 同为呈现层派生入参），合成器
            // 核心读 facets 同值（快照器注入）
            parts.append("oc\(oc.kind == .live ? "l" : oc.kind == .selected ? "s" : "e")\(oc.optionCount)")
        }
        if entry.traceKey != nil {
            // 回响时刻文案随日界变宽（今天只时刻、
            // 跨日带月日）：折当日判定
            parts.append(
                "td\(Calendar.current.isDateInToday(entry.createdAt) ? "1" : "0")"
            )
        }
        if entry.approvalKey != nil {
            let recordID = ApprovalAnchor.recordID(
                fromKey: entry.approvalKey ?? ""
            ) ?? ""
            parts.append(
                "apd\(approvalDetailDigest(recordID))"
            )
            switch facetAnchorState(
                for: recordID
            ) {
            case .pending(let record):
                parts.append(
                    "app\(approvalRecordDigest(record))"
                )
            case .decided:
                parts.append("apDecided")
            case .stale:
                parts.append("apStale")
            case .loading:
                parts.append("apLoading")
            }
        }
        if entry.role == "user" {
            if entry.sendFailed {
                parts.append(
                    "sf\(facetFailureKind(for: entry.id).rawValue)"
                )
            }
            if !entry.allImageDatas.isEmpty {
                // 本地图行：任一解出即出卡（与合成
                // 同判）
                let decoded = entry.allImageDatas
                    .indices.contains { index in
                        facetLocalImageDecoded(
                            entryID: entry.id,
                            index: index,
                            data: entry.allImageDatas[
                                index
                            ]
                        )
                    }
                parts.append("li\(decoded ? "1" : "0")")
            }
            for rawPath in entry.remoteFilePaths {
                let split = FileLineAnchor.split(
                    pathWithAnchor: rawPath
                )
                parts.append(
                    "rf\(LayoutProductKey.fnv1a(split.path))=\(fileStateDigest(split.path))"
                )
            }
        } else if entry.traceKey == nil
            && entry.echoKey == nil {
            // 助手行：派生扫描与合成同源（EntryScan-
            // Memo 备忘在席、此处只多一趟缓存读）；
            // 存在性/交付态逐路径/逐 id 折入——disp-
            // layText 的剥离集与各图/牌/交付槽高都
            // 由这批状态决定
            // §362：扫描派生（交付 id 集／路径集，
            // 纯函数于正文＋远端图路径）——同趟已验
            // 证的 Products 在席时取行构建备忘账面
            // （免 EntryScanMemo 键组装的正文哈希），
            // 不在席走旧现算，两路逐值同
            let scanLists: (
                deliveryIDs: [String], paths: [String]
            )
            if let buildProducts {
                scanLists = ChatEntryRowBuildMemo
                    .facetScanLists(
                        products: buildProducts, entry: entry
                    )
            } else {
                scanLists = (
                    EntryScanMemo.scans(
                        entryID: entry.id,
                        content: entry.content,
                        remoteImagePaths: entry.remoteImagePaths
                    ).delivery.deliveryIDs,
                    EntryScanMemo.facetPaths(
                        entryID: entry.id,
                        content: entry.content,
                        remoteImagePaths: entry.remoteImagePaths
                    )
                )
            }
            for deliveryID in scanLists.deliveryIDs {
                parts.append(
                    "dl\(deliveryID)=\(deliveryMetaDigest(deliveryID))"
                )
            }
            // §333（待办 143 根治）：路径并集改走
            // EntryScanMemo.facetPaths 备忘（五源
            // 并集与旧现算逐字相等）——旧形态每趟
            // 键组装对正文重跑 wholeMessagePath＋
            // 组合排除口径的 detectStandalone-
            // Anchored 全文扫，长会话每趟 body 求
            // 值全表重付，是 §331 量测台落成后热
            // 路径上残余的主线程同步全扫；现第二
            // 趟起只剩备忘读＋逐路径状态摘要（状
            // 态本身仍逐趟活读、翻转即键变，失效
            // 语义不变）
            for path in scanLists.paths {
                parts.append(
                    "fx\(LayoutProductKey.fnv1a(path))=\(fileStateDigest(path))"
                )
            }
        } else {
            // 台账 196（§335）：系统锚定行（留痕回
            // 响/委派回响）跳过助手扫描支——其行高
            // 在 entryHeightCore 先行支返回、从不
            // 读交付/文件 facet，扫描产出恒弃（纯
            // 浪费摘除、零风险面）；产出恒空时旧形
            // 态在本支追加零项、摘要逐字不变（键不
            // 翻转）；偶有路径产出时旧键把无关文件
            // 态折入锚定行键、本次一并正
        }
        return parts.joined(separator: "|")
    }

    // MARK: - Markdown 高（助手正文/直播正文共用）

    /// MarkdownText 本体高：段序列与呈现同一装配
    /// （MarkdownMessageAssembler.segments），段
    /// 间 spacingSM——公式逐段见各分支注
    func markdownHeight(_ text: String) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        // §335 预计算路：产物段高代量测的混合总高
        // 不入文本备忘——备忘只存全量量测确值，防
        // 预计算值冒充确值回喂后续确路（预计算与
        // 确路同高是对拍验收项、非备忘共享项）
        if productSegmentHeights != nil {
            return markdownHeightUncached(text)
        }
        return memoized("md", text, assistantTextWidth) {
            markdownHeightUncached(text)
        }
    }

    private func markdownHeightUncached(
        _ text: String
    ) -> CGFloat {
        let segments = MarkdownMessageAssembler
            .segments(for: text)
        guard !segments.isEmpty else { return 0 }
        var total: CGFloat = 0
        for (index, segment) in segments.enumerated() {
            switch segment {
            case .prose, .quote:
                // §335 预计算路：文本段高以产物段高
                // 代量测（段下标与产物同源同位）；结
                // 构段无产物、恒走公式
                total += productSegmentHeights?[index]
                    ?? segmentHeight(segment)
            default:
                total += segmentHeight(segment)
            }
        }
        total += OneDayMetrics.spacingSM
            * CGFloat(segments.count - 1)
        return total
    }

    private func segmentHeight(
        _ segment: MarkdownMessageSegment
    ) -> CGFloat {
        let width = assistantTextWidth
        switch segment {
        case .prose(let paragraphs):
            // proseView：合并散文段单文本视图（拼
            // 装与产物层同源）
            return assembledHeight(
                paragraphs: MarkdownText.proseParagraphs(
                    paragraphs
                ),
                foreground: Palette.bodyInk,
                width: width
            )
        case .quote(let lines):
            // blockquoteView：竖条 3＋spacingS 后
            // 文本合一（宽折算与产物层 builder 同值）
            return assembledHeight(
                paragraphs: MarkdownText.quoteParagraphs(
                    lines
                ),
                foreground: Palette.inkSecondaryOnFill,
                width: width - (3 + OneDayMetrics.spacingS)
            )
        case .code(let code, _):
            // codeView：内距 spacingSM＋头行（复制
            // 钮命中域 44 恒在席）＋spacingXS＋代码
            // 文本（横滚不折行；呈现是 SwiftUI
            // Text——量测高只借行数、实高走
            // swiftTextHeight，§329 续修校准）
            // §419 包 1 收口：原直调 referenceHeight
            // (width: nil) 绕过分发、后台工单可达量测
            // 台变异（崩①）；nil 在 measuredWidth 落
            // 自然宽 10_000——改走分发原语同宽：主线
            // 程同口逐值不变、后台落量测池同宽同值
            let codeFont = monospacedFont(.footnote)
            let codeHeight = swiftTextHeight(
                measured: ChatNativeTextMeasure.height(
                    attributed: NSAttributedString(
                        string: code,
                        attributes: [.font: codeFont]
                    ),
                    width: 10_000,
                    emptyLineHeight: codeFont.lineHeight
                ),
                stepStyle: .footnote,
                firstLineFont: codeFont
            )
            return OneDayMetrics.spacingSM * 2
                + OneDayMetrics.minTapTarget
                + OneDayMetrics.spacingXS
                + codeHeight
        case .table(let header, _, let rows):
            return tableHeight(
                header: header, rows: rows, width: width
            )
        case .taskList(let items):
            // listView：项间 spacingXS；项＝标记列
            // 22＋spacingS＋正文（level 逐级再缩
            // spacingM），正文走拼装量测
            var total: CGFloat = 0
            for item in items {
                let textWidth = width
                    - 22 - OneDayMetrics.spacingS
                    - CGFloat(item.level)
                        * OneDayMetrics.spacingM
                total += assembledHeight(
                    paragraphs: [.markdown(item.text)],
                    foreground: Palette.bodyInk,
                    width: textWidth
                )
            }
            if items.count > 1 {
                total += OneDayMetrics.spacingXS
                    * CGFloat(items.count - 1)
            }
            return total
        case .divider:
            return 1 / max(displayScale, 1)
        }
    }

    /// 表格高（MarkdownTablePresentation 分流与
    /// 呈现同源：≤4 列 Grid、>4 列降级列表）
    private func tableHeight(
        header: [String], rows: [[String]],
        width: CGFloat
    ) -> CGFloat {
        if MarkdownTablePresentation.mode(
            columnCount: header.count
        ) == .list {
            return tableListHeight(
                header: header, rows: rows, width: width
            )
        }
        // Grid（§396 封顶折行模型）：列宽与呈现
        // 单源（MarkdownTableGridLayout.column-
        // Widths——逐列自然宽按 Core maxColumn-
        // Width 封顶、呈现以显式宽喂格折行）；逐
        // 行取各格在列宽下的实高最大值，格高走
        // 与降级列表支同一公式（量测高 tableCell-
        // TextHeight＋SwiftUI 行高换算 swiftText-
        // Height）；行间账（GroupDivider 一行＋
        // verticalSpacing spacingXS）不变。§329
        // 的自然宽单行模型自此退役（彼时呈现未
        // 折行、量测对齐呈现；本节呈现改折行、
        // 量测随改回封顶模型）
        let columnWidths = MarkdownTableGridLayout
            .columnWidths(
                header: header, rows: rows,
                category: sizeCategory,
                boldText: boldText
            )
        let dividerHeight = 1 / max(displayScale, 1)
        let gridRows = rows.count + 2
        func gridRowHeight(
            _ row: [String]
        ) -> CGFloat {
            var height: CGFloat = 0
            for (column, cell) in row.enumerated()
            where column < columnWidths.count {
                let measured = tableCellTextHeight(
                    cell, width: columnWidths[column]
                )
                height = max(
                    height,
                    swiftTextHeight(
                        measured: measured,
                        stepStyle: .callout,
                        firstLineFont: plainFont(.callout)
                    )
                )
            }
            return height
        }
        var total = gridRowHeight(header)
        for row in rows {
            total += gridRowHeight(row)
        }
        return total + dividerHeight
            + OneDayMetrics.spacingXS
                * CGFloat(gridRows - 1)
    }

    /// 表格降级列表高（>4 列）：逐数据行成组（组
    /// 间 GroupDivider＋spacingSM 节奏），组内逐
    /// 列一行「标签 footnote semibold＋值 callout」
    /// （HStack firstTextBaseline、spacingS）
    private func tableListHeight(
        header: [String], rows: [[String]],
        width: CGFloat
    ) -> CGFloat {
        let entries = MarkdownTablePresentation
            .listEntries(header: header, rows: rows)
        let dividerHeight = 1 / max(displayScale, 1)
        var total: CGFloat = 0
        for (rowIndex, row) in entries.enumerated() {
            if rowIndex > 0 {
                total += dividerHeight
                    + OneDayMetrics.spacingSM
            }
            var rowTotal: CGFloat = 0
            for entry in row {
                let labelWidth = weightedNaturalWidth(
                    entry.label, .footnote, .semibold
                )
                let valueWidth = max(
                    width - labelWidth
                        - OneDayMetrics.spacingS,
                    20
                )
                let valueHeight = tableCellTextHeight(
                    entry.value, width: valueWidth
                )
                rowTotal += max(
                    swiftLineHeight(
                        weightedFont(.footnote, .semibold)
                    ),
                    swiftTextHeight(
                        measured: valueHeight,
                        stepStyle: .callout,
                        firstLineFont: plainFont(.callout)
                    )
                )
            }
            if row.count > 1 {
                rowTotal += OneDayMetrics.spacingXS
                    * CGFloat(row.count - 1)
            }
            total += rowTotal
            if rowIndex > 0 {
                total += OneDayMetrics.spacingSM
            }
        }
        return total
    }

    /// 表格格文本拼装（§396 起单源在 Markdown-
    /// TableGridLayout.cellAttributed——呈现列宽
    /// 与量测共用同一拼装；本口只按本合成器的环
    /// 境口径转发）
    private func tableCellAttributed(
        _ cell: String
    ) -> NSAttributedString {
        MarkdownTableGridLayout.cellAttributed(
            cell, category: sizeCategory,
            boldText: boldText
        )
    }

    private func tableCellTextHeight(
        _ cell: String, width: CGFloat
    ) -> CGFloat {
        // §419 包 1 收口：原直调 referenceHeight 绕
        // 过分发、后台工单可达量测台变异（崩①同
        // 族）；改走分发原语——主线程同口逐值不
        // 变、后台落量测池
        ChatNativeTextMeasure.height(
            attributed: tableCellAttributed(cell),
            width: width,
            emptyLineHeight: MarkdownTableGridLayout
                .baseFont(
                    category: sizeCategory, boldText: boldText
                )
                .lineHeight
        )
    }

    // MARK: - 文件牌族

    /// FileChip 本体高（§452.2 微信式定宽卡）：
    /// 卡宽 = min(252, 行宽)；高 = 纵内距 10×2＋
    /// max(视觉位 50, 名列高)；名列 = 名（.body
    /// semibold ≤2 行，宽 = 卡宽−内距 12×2−间距
    /// 8−视觉位 40）＋spacingXS＋副行 caption 一
    /// 行。卡面无菜单（长按承载），旧菜单 44 项退
    /// 役。notice 反馈行对合成不可见（§329 残留
    /// ⑴、溢出＜行间距、不入账）
    func fileChipHeight(
        path: String, width: CGFloat
    ) -> CGFloat {
        let name = (path as NSString).lastPathComponent
        let cardWidth = min(FileCardMetrics.cardWidth, width)
        let nameWidth = cardWidth
            - FileCardMetrics.horizontalPadding * 2
            - FileCardMetrics.columnSpacing
            - FileCardMetrics.visualWidth
        let nameHeight = weightedHeight(
            name, .body, .semibold,
            width: nameWidth, lineLimit: 2
        )
        let columnHeight = nameHeight
            + OneDayMetrics.spacingXS + spec(.caption1)
        return FileCardMetrics.verticalPadding * 2 + max(
            FileCardMetrics.visualHeight, columnHeight
        )
    }

    /// AssistantFileChip：确证存在出牌、否则路径
    /// 原文 .callout 一行（可折行）——与视图存在
    /// 性门同判据（FileMetadataStore 同源读）。
    /// 台账 185 占位口径：存在性未定（unverified/
    /// 未读到）时先按牌高占位——旧口径未定即按文
    /// 本高、确证后翻牌高，整行凭空换高（与图片
    /// 槽 0↔190 同源病）；确证 missing 才落文本高
    func assistantFileChipHeight(
        path: String
    ) -> CGFloat {
        if facetFileExistence(path) == .missing {
            return plainHeight(
                path, .callout, width: contentWidth
            )
        }
        return fileChipHeight(
            path: path, width: contentWidth
        )
    }

    /// BarePathFileCard：确证不在出失效卡（无菜
    /// 单、几何与 FileChip 同族），其余走 FileChip
    func barePathFileCardHeight(
        path: String
    ) -> CGFloat {
        guard facetFileExistence(path) == .missing
        else {
            return fileChipHeight(
                path: path, width: contentWidth
            )
        }
        let name = (path as NSString).lastPathComponent
        let nameWidth = contentWidth
            - OneDayMetrics.spacingSM - 40
            - OneDayMetrics.spacingSM
        let nameHeight = weightedHeight(
            name, .body, .semibold,
            width: nameWidth, lineLimit: 2
        )
        let columnHeight = nameHeight
            + OneDayMetrics.spacingXS + spec(.caption1)
        return 20 + max(40, columnHeight)
    }

    // MARK: - 交付项

    /// AssistantDeliveryItem 高（DeliveryViews 状
    /// 态机同判）：meta 未到/失败＝紧凑卡片 64pt
    /// （不再用 0 或 190 造成空白或隐身）、查无＝
    /// 标记原文 .callout、gone＝一行 .callout、
    /// image＝§130 定高卡 190、其余＝封面卡
    func deliveryItemHeight(id: String) -> CGFloat {
        switch facetDeliveryMeta(id) {
        case nil, .failed:
            return 64
        case .notFound:
            return plainHeight(
                DeliveryMarker.markerText(for: id),
                .callout, width: contentWidth
            )
        case .loaded(let meta):
            if meta.status == .gone {
                return plainHeight(
                    L10n.format(
                        "%@（文件已删除）", meta.name
                    ),
                    .callout, width: contentWidth
                )
            }
            if meta.kind == "image" {
                return ChatImageSizing.cardHeight
            }
            return deliveryFileCardHeight(meta)
        }
    }

    /// DeliveryFileCard 高（§452.3）：封面形态＝
    /// 成品块定高——顶内距 8＋预览区 228＋元行
    /// （纵内距 10×2＋max(图标 24, 名行＋微距 2＋
    /// 类型标行)），名在块内恒一行、整高恒定；卡
    /// 形态＝FileChip 同式（fileChipHeight 同源计
    /// 算）。封面形态判定只认登记旗 meta.cover.
    /// cover（§407 定版续）
    func deliveryFileCardHeight(
        _ meta: BridgeDelivery
    ) -> CGFloat {
        guard facetDeliveryCoverForm(meta) else {
            return fileChipHeight(
                path: meta.path, width: contentWidth
            )
        }
        let nameLine = weightedHeight(
            "名", .body, .semibold,
            width: 10_000, lineLimit: 1
        )
        let labelLine = weightedHeight(
            "PDF", .subheadline, .regular,
            width: 10_000, lineLimit: 1
        )
        let metaRow = 20 + max(
            24, nameLine + OneDayMetrics.spacingMicro + labelLine
        )
        return OneDayMetrics.spacingS + 228 + metaRow
    }

    // MARK: - 思考块

    /// ReasoningBlock 高：头行 minTapTarget 44 恒
    /// 在席；展开且正文非空时＋spacingXS＋正文区
    /// （限高 maxBodyHeight、正文宽＝内容宽−左距
    /// bubblePaddingH−竖线 2−spacingS）
    func reasoningHeight(
        text: String, expanded: Bool
    ) -> CGFloat {
        var total = OneDayMetrics.minTapTarget
        if expanded, !text.isEmpty {
            let bodyWidth = contentWidth
                - OneDayMetrics.bubblePaddingH
                - 2 - OneDayMetrics.spacingS
            let bodyHeight = min(
                swiftTextHeight(
                    measured: plainHeight(
                        text, .footnote, width: bodyWidth
                    ),
                    stepStyle: .footnote,
                    firstLineFont: plainFont(.footnote)
                ),
                CGFloat(ReasoningPresentation.maxBodyHeight)
            )
            total += OneDayMetrics.spacingXS + bodyHeight
        }
        return total
    }

    // MARK: - 工具卡族

    /// 工具卡副行（ToolCardView.subtitle 同逻辑
    /// 复刻：浏览器页面行→摘要→状态兜底，Core 单
    /// 源函数同读）
    private func toolCardSubtitle(
        _ card: ToolCard
    ) -> String {
        if card.category == .browser,
           let result = card.result,
           result.hasPrefix("Page: "),
           let open = result.firstIndex(of: "("),
           let close = result.firstIndex(of: ")"),
           open < close {
            let url = String(
                result[result.index(after: open)..<close]
            )
            if url.hasPrefix("http") { return url }
        }
        if !card.summary.isEmpty { return card.summary }
        switch ToolCardPresentation.state(of: card) {
        case .succeeded:
            return ToolResultUnwrap.isMeaningless(
                card.result ?? ""
            ) ? "（无输出）" : ""
        case .failed:
            return ToolCardPresentation
                .firstMeaningfulLine(of: card.result)
                ?? ""
        case .running:
            return ""
        }
    }

    /// 卡行本体高：max(图标盒 36, 标题行＋副行)；
    /// 标题/副行均 SwiftUI Text 单行——走实高
    /// （§329 续修校准：标题 .subheadline
    /// medium 实高 18、副行 .caption 实高
    /// 14.33，spec 口径各虚高 2/1.67）
    private func toolCardRowHeight(
        _ card: ToolCard
    ) -> CGFloat {
        var textHeight = swiftLineHeight(
            weightedFont(.subheadline, .medium)
        )
        if !toolCardSubtitle(card).isEmpty {
            textHeight += OneDayMetrics.spacingMicro
                + swiftLineHeight(plainFont(.caption1))
        }
        return max(36, textHeight)
    }

    /// 详情字段高：标签 caption 单行实高＋
    /// spacingMicro＋正文（caption SwiftUI
    /// Text 多行实高，等宽档走等宽量测借行数）
    private func toolDetailFieldHeight(
        text: String, monospaced: Bool, width: CGFloat
    ) -> CGFloat {
        let measured = monospaced
            ? monospacedHeight(text, .caption1, width: width)
            : plainHeight(text, .caption1, width: width)
        let textHeight = swiftTextHeight(
            measured: measured,
            stepStyle: .caption1,
            firstLineFont: monospaced
                ? monospacedFont(.caption1)
                : plainFont(.caption1)
        )
        return swiftLineHeight(plainFont(.caption1))
            + OneDayMetrics.spacingMicro + textHeight
    }

    /// 详情区高（detailBody：参数字段→结果字段
    /// →工具名行，VStack spacingS）
    private func toolCardDetailHeight(
        _ card: ToolCard, width: CGFloat
    ) -> CGFloat {
        var fields: [CGFloat] = []
        if let arguments = card.arguments,
           !arguments.isEmpty {
            fields.append(toolDetailFieldHeight(
                text: Self.prettyArguments(arguments),
                monospaced: true, width: width
            ))
        } else if !card.summary.isEmpty {
            fields.append(toolDetailFieldHeight(
                text: card.summary,
                monospaced: false, width: width
            ))
        }
        let resultText = card.result.map {
            ToolResultUnwrap.isMeaningless($0)
                ? "（无输出）" : $0
        } ?? "进行中…"
        fields.append(toolDetailFieldHeight(
            text: resultText,
            monospaced: card.category == .terminal,
            width: width
        ))
        var total = fields.reduce(0, +)
            + swiftLineHeight(plainFont(.caption1))
        total += OneDayMetrics.spacingS
            * CGFloat(fields.count)
        return total
    }

    /// 参数详情排版（ToolCardView.prettyArguments
    /// 同式复刻：JSON 美化、解不出原文）
    private static func prettyArguments(
        _ raw: String
    ) -> String {
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization
                .jsonObject(with: data),
              let pretty = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys,
                          .withoutEscapingSlashes]
              ),
              let text = String(
                data: pretty, encoding: .utf8
              )
        else { return raw }
        return text
    }

    /// ToolCardView 高（§330 备忘包装）：键＝卡
    /// 本体编码摘要＋宽＋展开/素面位＋环境指纹
    /// （合成只读卡本体与入参、无外部状态）
    func toolCardHeight(
        card: ToolCard, width: CGFloat,
        expanded: Bool, plain: Bool
    ) -> CGFloat {
        let key = "tc|\(Self.cardDigest(card))"
            + "|\(LayoutProductKey.quantizedWidth(Double(width)))"
            + "|\(expanded ? "1" : "0")\(plain ? "1" : "0")"
            + "|\(environmentFingerprint)"
        return rowMemo(key) {
            toolCardHeightUncached(
                card: card, width: width,
                expanded: expanded, plain: plain
            )
        }
    }

    /// ToolCardView 高：plain（组内嵌）无自家内
    /// 距、独立卡内距 15；展开＋spacingS＋发丝线
    /// 1＋spacingS＋详情区。
    /// 活动线分支（2026-11-20 结构归位·对话页，
    /// 与 ToolCardView.usesLineForm 同口径）：独
    /// 立落定卡默认压线——头行恒 minTapTarget
    /// （视觉一行、命中 44，与思考头行同式）；展
    /// 开＋spacingS＋发丝线 1＋spacingS＋详情区
    /// （详情宽＝全宽−左距 bubblePaddingH，无卡
    /// 面内距）
    func toolCardHeightUncached(
        card: ToolCard, width: CGFloat,
        expanded: Bool, plain: Bool
    ) -> CGFloat {
        if !plain,
           ToolCardPresentation.state(of: card) != .running {
            var total = OneDayMetrics.minTapTarget
            if expanded {
                total += OneDayMetrics.spacingS * 2 + 1
                total += toolCardDetailHeight(
                    card,
                    width: width - OneDayMetrics.bubblePaddingH
                )
            }
            return total
        }
        var total = toolCardRowHeight(card)
        if !plain { total += 30 }
        if expanded {
            total += OneDayMetrics.spacingS * 2 + 1
            total += toolCardDetailHeight(
                card, width: width - (plain ? 0 : 30)
            )
        }
        return total
    }

    /// ToolCardGroupView 高（§330 备忘包装＋
    /// §331 适配器）：键见 toolGroupMemoKey
    @MainActor
    func toolGroupHeight(
        cards: [ToolCard], groupKey: String
    ) -> CGFloat {
        rowMemo(
            toolGroupMemoKey(
                cards: cards, groupKey: groupKey
            )
        ) {
            toolGroupHeightWithFacets(
                cards: cards, groupKey: groupKey
            )
        }
    }

    /// 工具组备忘键（§330/§331 共用单点）：组键
    /// ＋逐卡编码摘要＋组/逐卡展开覆盖＋环境指纹
    @MainActor
    func toolGroupMemoKey(
        cards: [ToolCard], groupKey: String
    ) -> String {
        var keyParts = ["tg|\(groupKey)"]
        for card in cards {
            keyParts.append(Self.cardDigest(card))
        }
        keyParts.append(
            "g\(Self.boolDigest(ledger?.expansionOverride(for: groupKey)))"
        )
        for card in cards {
            let cardKey = ChatRowStateKeys
                .toolGroupCard(
                    groupKey: groupKey, cardID: card.id
                )
            keyParts.append(
                "c\(Self.boolDigest(ledger?.expansionOverride(for: cardKey)))"
            )
        }
        keyParts.append(environmentFingerprint)
        return keyParts.joined(separator: "|")
    }

    /// 工具组适配器一趟（§331）：快照组展开覆
    /// 盖后交核心（量测工单同形）
    @MainActor
    func toolGroupHeightWithFacets(
        cards: [ToolCard], groupKey: String
    ) -> CGFloat {
        var core = self
        if let ledger {
            core.facets = ChatNativeRowFacetSnapshotter
                .groupFacets(
                    cards: cards, groupKey: groupKey,
                    ledger: ledger
                )
        }
        return core.toolGroupHeightUncached(
            cards: cards, groupKey: groupKey
        )
    }

    /// ToolCardGroupView 高：内距 15＋组头行 36；
    /// 展开＋顶距 spacingS＋逐卡 plain 高＋卡间
    /// 分隔（发丝线 1＋纵内距 spacingS×2）
    func toolGroupHeightUncached(
        cards: [ToolCard], groupKey: String
    ) -> CGFloat {
        var total = 30 + max(
            36,
            swiftLineHeight(
                weightedFont(.subheadline, .medium)
            )
        )
        let groupExpanded = facetExpansionOverride(
            for: groupKey
        ) ?? false
        guard groupExpanded, !cards.isEmpty
        else { return total }
        total += OneDayMetrics.spacingS
        for (index, card) in cards.enumerated() {
            if index > 0 {
                total += 1 + OneDayMetrics.spacingS * 2
            }
            let cardKey = ChatRowStateKeys.toolGroupCard(
                groupKey: groupKey, cardID: card.id
            )
            total += toolCardHeightUncached(
                card: card,
                width: contentWidth - 30,
                expanded: facetExpansionOverride(
                    for: cardKey
                ) ?? false,
                plain: true
            )
        }
        return total
    }

    // MARK: - 引用块族（用户行）

    /// quoteBlock 高：内距 spacingS 全周；左条 2
    /// ＋spacingS＋两行字（名 caption 无截断、摘
    /// 要 caption ≤2 行），名/摘要间 spacingMicro
    private func messageQuoteHeight(
        name: String, summary: String,
        columnWidth: CGFloat,
        nameSingleLine: Bool
    ) -> CGFloat {
        let textWidth = columnWidth
            - OneDayMetrics.spacingS * 2
            - 2 - OneDayMetrics.spacingS
        let nameHeight = nameSingleLine
            ? spec(.caption1)
            : plainHeight(
                name, .caption1, width: textWidth
            )
        let summaryHeight = plainHeight(
            summary, .caption1, width: textWidth,
            lineLimit: 2
        )
        return OneDayMetrics.spacingS * 2
            + nameHeight
            + OneDayMetrics.spacingMicro
            + summaryHeight
    }

    // MARK: - 审批族

    /// 审批卡高（ChatApprovalCard＝卡面 face＋宿
    /// 主内距 spacingM）：face 为 VStack(spacingS)
    /// ——时间行／问句（.headline 折行）／说明行
    /// （单行）／原因行（在席时）／提示行（在席
    /// 时）／详情区（账本四态）／动作区，逐项与
    /// ApprovalCardFace 几何同值
    func approvalCardHeight(
        record: WriteGateRecord, width: CGFloat
    ) -> CGFloat {
        let innerWidth = width
            - OneDayMetrics.spacingM * 2
        var items: [CGFloat] = []
        items.append(spec(.caption1))
        items.append(weightedHeight(
            ApprovalCardCopy.question(for: record),
            .body, .semibold, width: innerWidth, lineLimit: 2
        ))
        items.append(spec(.subheadline))
        if let reason = ApprovalCardCopy.reasonLine(
            for: record
        ) {
            items.append(plainHeight(
                reason, .footnote,
                width: innerWidth - 20
            ))
        }
        if let note = facetCardNote(for: record.id) {
            items.append(plainHeight(
                note, .caption1, width: innerWidth
            ))
        }
        // 详情区：收起＝SmoothExpand 零高一项；展
        // 开按四态分（加载行／内容＋收起行／错误
        // ＋收起行，内容与收起行各带顶距 spacingS
        // 且同为 face 的 VStack 子项）
        let detail = facetApprovalDetail(
            for: record.id
        )
        if !detail.expanded {
            items.append(0)
        } else if detail.loading {
            items.append(max(20, spec(.caption1)))
        } else if let loaded = detail.detail {
            items.append(
                OneDayMetrics.spacingS
                    + reviewContentHeight(
                        detail: loaded, record: record,
                        width: innerWidth
                    )
            )
            items.append(
                OneDayMetrics.spacingS + spec(.subheadline)
            )
        } else if let error = detail.error {
            items.append(plainHeight(
                error, .caption1, width: innerWidth
            ))
            items.append(
                OneDayMetrics.spacingS + spec(.subheadline)
            )
        } else {
            items.append(0)
        }
        // 动作区：提交中＝进度行；可裁决＝钮栈
        // （ApprovalCardSpec 单源；D10 定版④起
        // 三档异高——胶囊 48/文字级 36，总高经
        // actionStackHeight 单读口）；不可裁决
        // ＝说明 caption 折行
        if facetIsDeciding(record.id) {
            items.append(max(20, spec(.caption1)))
        } else if record.canDecide {
            let actions = ApprovalCardSpec.actionStack(
                canDecide: true,
                blocked: record.isBlocked,
                highRisk: record.isHighRisk
            )
            items.append(
                ApprovalCardSpec.actionStackHeight(actions)
            )
        } else {
            items.append(plainHeight(
                "这类写入暂不支持在 App 内审批，请在 Hermes 中处理",
                .caption1, width: innerWidth
            ))
        }
        var total = items.reduce(0, +)
        total += OneDayMetrics.spacingS
            * CGFloat(max(0, items.count - 1))
        return total + OneDayMetrics.spacingM * 2
    }

    /// 审批详情内容高（ApprovalReviewContent 内
    /// 嵌形态：VStack spacingM——注意行×k／原文
    /// 失效警告（在席时）／diff 等宽 footnote 折
    /// 行／原始信息 DisclosureGroup 收起一行；
    /// DisclosureGroup 展开态不可上提，§329 残
    /// 留 ⑵按收起合成）
    private func reviewContentHeight(
        detail: WriteGateDetail,
        record: WriteGateRecord,
        width: CGFloat
    ) -> CGFloat {
        var items: [CGFloat] = []
        for label in detail.review.noteLabels {
            items.append(plainHeight(
                label, .footnote, width: width - 20
            ))
        }
        if detail.review.requestedOldString != nil {
            items.append(plainHeight(
                "这条修订要改的原文已经不存在，可能基于旧内容，批准前请仔细核对。",
                .footnote, width: width - 20
            ))
        }
        items.append(monospacedHeight(
            detail.review.displayDiff, .footnote,
            width: width
        ))
        items.append(spec(.footnote))
        var total = items.reduce(0, +)
        total += OneDayMetrics.spacingM
            * CGFloat(max(0, items.count - 1))
        return total
    }

    /// 审批锚行高（approvalAnchorRow 四态）：待
    /// 批＝整卡；已决/失效/加载＝内距 spacingS
    /// 纵＋footnote 一行
    func approvalAnchorHeight(
        _ entry: ChatEntryHeightSnapshot
    ) -> CGFloat {
        let recordID = ApprovalAnchor.recordID(
            fromKey: entry.approvalKey ?? ""
        ) ?? ""
        switch facetAnchorState(
            for: recordID
        ) {
        case .pending(let record):
            return approvalCardHeight(
                record: record, width: contentWidth
            )
        case .decided, .stale, .loading:
            return OneDayMetrics.spacingS * 2
                + spec(.footnote)
        }
    }

    /// 审批区行高（§330 备忘包装＋§331 适配
    /// 器）：键见 zoneMemoKey
    @MainActor
    func approvalZoneHeight() -> CGFloat {
        rowMemo(zoneMemoKey()) {
            approvalZoneHeightWithFacets()
        }
    }

    /// 审批区备忘键（§330/§331 共用单点）：区
    /// facet 摘要（ready 态＋活卡卡面/详情摘要
    /// ＋未锚待批总数＋已决行 id 集）＋环境指纹
    @MainActor
    func zoneMemoKey() -> String {
        "az|\(approvalZoneFacetDigest())"
            + "|\(environmentFingerprint)"
    }

    /// 审批区 facet 摘要：与 approvalZoneHeight
    /// 的合成同源（D10 定版②）——活卡的记录/详
    /// 情摘要＋未锚待批总数（计数行在席随总数
    /// 变，键不含计数会留旧高）＋未锚定已决行
    /// id 集；锚定集经派生过滤间接在键内
    private func approvalZoneFacetDigest() -> String {
        guard let inputs = facetZoneInputs()
        else { return "notready" }
        let queue = ApprovalZoneQueue.derive(
            recordIDs: inputs.records.map(\.id),
            anchoredIDs: inputs.anchored
        )
        var parts: [String] = []
        if let activeID = queue.activeRecordID,
           let record = inputs.records.first(
               where: { $0.id == activeID }
           ) {
            parts.append(
                "r\(record.id)"
                    + "\(approvalRecordDigest(record))"
                    + "\(approvalDetailDigest(record.id))"
            )
        }
        parts.append("n\(queue.pendingCount)")
        for lineID in inputs.resolvedLineIDs
        where !inputs.anchored.contains(lineID) {
            parts.append("l\(lineID)")
        }
        return parts.joined(separator: "|")
    }

    /// 审批区适配器一趟（§331）：快照区 facet
    /// 后交核心（量测工单同形）
    @MainActor
    func approvalZoneHeightWithFacets() -> CGFloat {
        var core = self
        if let ledger, let hubStore {
            core.facets = ChatNativeRowFacetSnapshotter
                .zoneFacets(
                    ledger: ledger, hubStore: hubStore
                )
        }
        return core.approvalZoneHeightUncached()
    }

    /// 审批区行高（ChatApprovalZone）：非 ready
    /// ＝0；ready＝活卡一张（D10 定版②队列派
    /// 生，Core ApprovalZoneQueue 单源）＋收纳
    /// 计数行（余数 ≥1 时一行，与回执行同高
    /// 式）＋未锚定已决行、VStack spacingM
    func approvalZoneHeightUncached() -> CGFloat {
        guard let inputs = facetZoneInputs()
        else { return 0 }
        let queue = ApprovalZoneQueue.derive(
            recordIDs: inputs.records.map(\.id),
            anchoredIDs: inputs.anchored
        )
        var items: [CGFloat] = []
        if let activeID = queue.activeRecordID,
           let record = inputs.records.first(
               where: { $0.id == activeID }
           ) {
            items.append(approvalCardHeight(
                record: record, width: contentWidth
            ))
        } else {
            let hasUnanchoredResolved = inputs.resolvedLineIDs.contains {
                !inputs.anchored.contains($0)
            }
            if hasUnanchoredResolved {
                items.append(
                    OneDayMetrics.spacingXS * 2
                        + spec(.footnote)
                )
            }
        }
        guard !items.isEmpty else { return 0 }
        return items.reduce(0, +)
            + OneDayMetrics.spacingS
                * CGFloat(items.count - 1)
    }

    // MARK: - 回响族

    /// 留痕回响行高（traceEchoRow）：内距 H
    /// spacingM／V spacingS；左图标 13＋文字列
    /// （主句 footnote 折行／对象行单行／结果行
    /// ≤3 行、失败 ≤4 行，行间 spacingMicro）＋
    /// 右时刻 caption（宽现测、文字列宽随之折算）
    func traceEchoHeight(
        _ entry: ChatEntryHeightSnapshot
    ) -> CGFloat {
        let snapshot = entry.traceEcho
        let isFailed = snapshot?.isFailed ?? false
        let timeText = Self.traceEchoTimeText(
            entry.createdAt
        )
        // 台账 196 §2.4 核对（代码实证）：文字列
        // 宽——视图 HStack（spacingS）三个相邻对
        // （图标↔列、列↔Spacer、Spacer↔时刻）各
        // 吃一份 spacingS、旧式只扣两份（列宽多
        // 算一份 spacingS、临界折行时行数偏少、
        // 高低估一行），本次按视图对齐扣 3 份。
        // 诊断同项的时刻字阶子项经复核不成立：
        // 视图 .font(.caption) 是 SwiftUI 字阶、
        // 与 UIKit .caption1 同档异名（12pt 同
        //  ramp；UIFont.TextStyle 本无 .caption
        // 成员），旧式以 .caption1 量宽本已对位、
        // 下限 spec(.caption1) 同理不动——此轴只
        // 补备忘（时刻宽走自然宽备忘，§335/196
        // 第一层护盾）。真机临界折行样本帧验留
        // 账（196 §五同项）
        let timeWidth = plainNaturalWidth(
            timeText, .caption1
        )
        let textWidth = contentWidth
            - OneDayMetrics.spacingM * 2
            - 13 - OneDayMetrics.spacingS * 3
            - timeWidth
        var column = plainHeight(
            snapshot?.headline ?? entry.content,
            .footnote, width: textWidth
        )
        if let label = snapshot?.targetLabel,
           !label.isEmpty {
            column += OneDayMetrics.spacingMicro
                + spec(.footnote)
        }
        if let outcome = snapshot?.outcome,
           !outcome.isEmpty {
            column += OneDayMetrics.spacingMicro
                + plainHeight(
                    outcome, .footnote,
                    width: textWidth,
                    lineLimit: isFailed ? 4 : 3
                )
        }
        return OneDayMetrics.spacingS * 2
            + max(column, spec(.caption1))
    }

    /// 回响时刻文案（ChatView.traceEchoTimeText
    /// 同式：今天只时刻、跨日带月日）
    private static func traceEchoTimeText(
        _ date: Date
    ) -> String {
        if Calendar.current.isDateInToday(date) {
            return date.formatted(
                .dateTime.hour().minute()
            )
        }
        return date.formatted(
            .dateTime.month().day().hour().minute()
        )
    }

    /// 目标委派回响行高（echoRow）：图标 11＋正
    /// 文 footnote 居中折行＋时刻 caption2，纵内
    /// 距 spacingXS×2
    func echoHeight(_ entry: ChatEntryHeightSnapshot) -> CGFloat {
        let timeText = entry.createdAt.formatted(
            .dateTime.hour().minute()
        )
        // §335/台账 196：时刻宽走自然宽备忘（字阶
        // 与视图 .caption2 本已对位、算术核对无差）
        let timeWidth = plainNaturalWidth(
            timeText, .caption2
        )
        let textWidth = contentWidth
            - 11 - OneDayMetrics.spacingXS * 2
            - timeWidth
        let contentHeight = plainHeight(
            entry.content, .footnote, width: textWidth
        )
        return contentHeight
            + OneDayMetrics.spacingXS * 2
    }

    // MARK: - 回告卡

    /// 回告卡高（reportCard）：内距 spacingM 全
    /// 周；左图标 15＋文字列（标题 subheadline
    /// 折行＋正文 footnote ≤3 行、行间 spacing-
    /// Micro）＋右关闭钮 44；文字列宽＝内容宽−
    /// 内距−图标−两处 spacingS−钮 44
    func reportCardHeight(
        _ item: OverviewNotification
    ) -> CGFloat {
        rowMemo(reportMemoKey(item)) {
            reportCardHeightUncached(item)
        }
    }

    /// 回告卡备忘键（§330/§331 共用单点）
    func reportMemoKey(
        _ item: OverviewNotification
    ) -> String {
        "rc|\(item.id)"
            + "|\(Self.reportDigest(item))"
            + "|\(environmentFingerprint)"
    }

    func reportCardHeightUncached(
        _ item: OverviewNotification
    ) -> CGFloat {
        let textWidth = contentWidth
            - OneDayMetrics.spacingM * 2
            - 15 - OneDayMetrics.spacingS * 2
            - OneDayMetrics.minTapTarget
        var column = plainHeight(
            item.title, .subheadline, width: textWidth
        )
        if !item.body.isEmpty {
            column += OneDayMetrics.spacingMicro
                + plainHeight(
                    item.body, .footnote,
                    width: textWidth, lineLimit: 3
                )
        }
        return OneDayMetrics.spacingM * 2
            + max(OneDayMetrics.minTapTarget, column)
    }

    // MARK: - 空态族

    /// 空态建议条段高：顶距 spacingL＋各条建议
    /// 行（minHeight 50、行内文 callout 折行兜
    /// 底）＋行间 spacingS；§455 起文案动态化，
    /// 估高按当下实际建议文案、备忘键带文案指纹
    func emptySuggestionsHeight(texts: [String]) -> CGFloat {
        rowMemo("es|\(texts.joined(separator: "\u{1}"))|\(environmentFingerprint)") {
            emptySuggestionsHeightUncached(texts: texts)
        }
    }

    func emptySuggestionsHeightUncached(texts: [String]) -> CGFloat {
        var total = OneDayMetrics.spacingL
        for text in texts {
            let textHeight = plainHeight(
                L10n.string(text), .callout,
                width: contentWidth
                    - OneDayMetrics.spacingM * 2
                    - 15 - OneDayMetrics.spacingSM
            )
            total += max(50, textHeight)
        }
        if texts.count > 1 {
            total += OneDayMetrics.spacingS
                * CGFloat(texts.count - 1)
        }
        return total
    }

    /// 未配模型引导卡行高：行外顶距 spacingL（行
    /// 构建点 .padding(.top) 在席）＋卡（内距
    /// spacingM、题 callout semibold＋正文 foot-
    /// note 折行＋钮行 callout，行间 spacingS）
    func modelSetupCardHeight() -> CGFloat {
        rowMemo("ms|\(environmentFingerprint)") {
            modelSetupCardHeightUncached()
        }
    }

    func modelSetupCardHeightUncached() -> CGFloat {
        let innerWidth = contentWidth
            - OneDayMetrics.spacingM * 2
        let bodyHeight = plainHeight(
            "先去加一家服务商、选好模型，回来就能聊。",
            .footnote, width: innerWidth
        )
        let card = OneDayMetrics.spacingM * 2
            + spec(.callout)
            + OneDayMetrics.spacingS + bodyHeight
            + OneDayMetrics.spacingS + spec(.callout)
        return OneDayMetrics.spacingL + card
    }

    // MARK: - 占位行（§407；§409 步 D 直播行退役后仅余此件）

    /// 直播占位行高（§407，A 案简化模型）：生成
    /// 中状态行恒高——与等待泡上传形态同几何（一
    /// 行 callout 状态文案＋等待点，内容纵内距
    /// spacingXS×2＋气泡纵内距 bubblePaddingV×2），
    /// 不读任何阶段/内容输入：上传/思考/工具/生成
    /// 四相逐值同高，落定拍整行换落定条目行
    var livePlaceholderHeight: CGFloat {
        max(6, spec(.callout))
            + OneDayMetrics.spacingXS * 2
            + OneDayMetrics.bubblePaddingV * 2
    }

    // MARK: - 条目行（与 ChatView.bubble 分流同序）

    /// 条目行高总口（§330 备忘包装）：键＝条目
    /// 修订摘要（与 ChatView 构造点的修订同源派
    /// 生——点亮/选区/样式键不入高、恒以中性值
    /// 派生）＋facet 状态摘要＋环境指纹
    @MainActor
    func entryHeight(
        _ entry: ChatEntry, dividerText: String?,
        showsUnreadDivider: Bool = false,
        sources: [MessageSource] = []
    ) -> CGFloat {
        rowMemo(
            entryMemoKey(
                for: entry, dividerText: dividerText,
                showsUnreadDivider: showsUnreadDivider,
                sources: sources
            )
        ) {
            entryHeightWithFacets(
                entry, dividerText: dividerText,
                showsUnreadDivider: showsUnreadDivider,
                sources: sources
            )
        }
    }

    /// 条目行备忘键（§330/§331 共用单点）：同步
    /// 路径与量测台工单以同一键对账——键的构成
    /// 只此一处，不许两路各算一份
    @MainActor
    func entryMemoKey(
        for entry: ChatEntry, dividerText: String?,
        showsUnreadDivider: Bool = false,
        sources: [MessageSource] = []
    ) -> String {
        var key = entryMemoKey(
            baseRevision: ChatNativeRowRevision.entryBase(
                entry,
                dividerText: dividerText,
                showsUnreadDivider: showsUnreadDivider
            ),
            entry: entry
        )
        // D4 (§349): source set joins the memo key --
        // when the set changes (tool rows complete
        // after finalize) the key must change too
        if !sources.isEmpty {
            key += "|sx" + sources
                .map { "\($0.url)\u{1}\($0.title)" }
                .joined(separator: "\u{2}")
        }
        return key
    }

    /// 基段入参版（2026-11-20 卡顿修复包）：行构
    /// 造点已为行修订建过同一基段时直喂本口——基
    /// 段只建一遍，中性尾段（点亮 false/样式键空）
    /// 在此接续，与上式逐字同键（字段枚举单点在
    /// entryBase，两路不许各列一份）
    @MainActor
    func entryMemoKey(
        baseRevision: ChatNativeRowRevision,
        entry: ChatEntry,
        buildProducts: ChatEntryRowBuildMemo.Products? = nil,
        optionsCard: OptionsCardHeightInput? = nil
    ) -> String {
        var revision = baseRevision
        revision.addFlag(false)
        revision.addText("")
        return "e|\(entry.id.uuidString)"
            + "|\(Self.revisionDigest(revision))"
            + "|\(entryFacetDigest(entry, buildProducts: buildProducts, optionsCard: optionsCard))"
            + "|\(environmentFingerprint)"
    }

    /// 适配器一趟（§331）：主线程快照 facet＋条
    /// 目后交核心——同步路径经此、量测工单在后
    /// 台以同形直调 entryHeightCore，两路同高由
    /// 对拍测试钉住
    @MainActor
    func entryHeightWithFacets(
        _ entry: ChatEntry, dividerText: String?,
        showsUnreadDivider: Bool = false,
        sources: [MessageSource] = [],
        optionsCard: OptionsCardHeightInput? = nil
    ) -> CGFloat {
        var core = self
        if let ledger, let hubStore {
            core.facets = ChatNativeRowFacetSnapshotter
                .entryFacets(
                    for: entry, ledger: ledger,
                    hubStore: hubStore,
                    outboxRetry: outboxRetry,
                    optionsCard: optionsCard
                )
        } else if let optionsCard {
            core.facets.optionsCards[entry.id] = optionsCard
        }
        return core.entryHeightCore(
            ChatEntryHeightSnapshot(entry, sources: sources),
            dividerText: dividerText,
            showsUnreadDivider: showsUnreadDivider
        )
    }

    /// 预计算行高（台账 190 留账·nanoMuse 列表三
    /// 件②·§335）：产物段高＋facet 公式合成的近确
    /// 值——量测未就绪时由 ChatView 喂入层调用，
    /// 优先于上次高/120 兜底：与本行当前内容同文
    /// （产物键＝呈现文本）、文本段高是真量测值、
    /// 结构段与各槽走与确路同一公式，误差只剩段
    /// 高量测级。适用面与产物生产门控同界（工具
    /// 卡/留痕/回响/审批锚行无产物、回 nil）；用
    /// 户行另有一道宽口径闸——产物宽（屏宽−泡内
    /// 距−侧距）比合成器正文宽多 40（旧 gen3 几
    /// 何沿账：产物宽未扣列表左右 inset），段高
    /// 在更宽的列里量得、系统性偏低，故用户行不
    /// 走预计算（维持上次高/兜底，见 §335 对位
    /// 表）；助手产物宽与合成器正文宽逐值相等、
    /// 无此碍。facet 快照口径与 entryHeightWith-
    /// Facets 同式
    @MainActor
    func precomputedEntryHeight(
        for entry: ChatEntry, dividerText: String?,
        showsUnreadDivider: Bool = false,
        sources: [MessageSource] = [],
        optionsCard: OptionsCardHeightInput? = nil,
        product: LayoutProduct
    ) -> CGFloat? {
        guard entry.role == "assistant",
              entry.toolCard == nil,
              entry.traceKey == nil,
              entry.echoKey == nil,
              entry.approvalKey == nil
        else { return nil }
        var segmentHeights: [Int: CGFloat] = [:]
        for segment in product.segments {
            segmentHeights[segment.segmentIndex] =
                CGFloat(segment.height)
        }
        guard !segmentHeights.isEmpty else {
            return nil
        }
        var core = self
        if let ledger, let hubStore {
            core.facets = ChatNativeRowFacetSnapshotter
                .entryFacets(
                    for: entry, ledger: ledger,
                    hubStore: hubStore,
                    outboxRetry: outboxRetry,
                    optionsCard: optionsCard
                )
        } else if let optionsCard {
            core.facets.optionsCards[entry.id] = optionsCard
        }
        core.productSegmentHeights = segmentHeights
        return core.entryHeightCore(
            ChatEntryHeightSnapshot(entry, sources: sources),
            dividerText: dividerText,
            showsUnreadDivider: showsUnreadDivider
        )
    }

    /// 条目行高总口（核心，线程无关）：时间分隔
    /// 槽（在席时 footnote 一行＋spacingS）＋
    /// bubble 本体——分流序与 ChatView.bubble
    /// 逐字同序（回响→审批锚→委派回响→工具卡→
    /// 用户→助手）
    func entryHeightCore(
        _ entry: ChatEntryHeightSnapshot,
        dividerText: String?,
        showsUnreadDivider: Bool = false
    ) -> CGFloat {
        var total: CGFloat = 0
        if let dividerText {
            total += plainHeight(
                dividerText, .footnote,
                width: contentWidth
            ) + OneDayMetrics.spacingS
        }
        if showsUnreadDivider {
            // 台账 148：NEW 分界槽与时间分隔槽同式
            // （徽标一行＋spacingS 行间隙）——呈现
            // 侧 ChatUnreadDividerView 的高由徽标文
            // 本单行决定、与本槽逐值同高
            total += plainHeight(
                L10n.string("新消息"), .footnote,
                width: contentWidth
            ) + OneDayMetrics.spacingS
        }
        if entry.traceKey != nil {
            return total + traceEchoHeight(entry)
        }
        if entry.approvalKey != nil {
            return total + approvalAnchorHeight(entry)
        }
        if entry.echoKey != nil {
            return total + echoHeight(entry)
        }
        if let card = entry.toolCard {
            return total + toolCardHeightUncached(
                card: card, width: contentWidth,
                expanded: facetExpansionOverride(
                    for: ChatRowStateKeys.toolEntry(
                        entry.id
                    )
                ) ?? false,
                plain: false
            )
        }
        if entry.role == "user" {
            return total + userEntryHeight(entry)
                + reactionReserve(entry)
        }
        return total + assistantEntryHeight(entry)
            + reactionReserve(entry)
            + sourceStripSlot(entry)
            + optionsCardSlot(entry)
    }

    /// 反应铬件悬出预留（台账 187＋§432）：pill/角
    /// 标压气泡底角、半身悬在泡外（ChatReaction-
    /// Metrics 几何单源）——行高只多悬出净深一
    /// 笔；在场判定走快照 hasReactionChrome（与呈
    /// 现同判：§432 起 AI 反应开关关时，仅有 agent
    /// 反应的行不再预留），无铬件恒 0（两态差由
    /// 测试以断言钉住）。只挂 user/assistant 发言
    /// 行（本函数只在 entryHeightCore 的两支尾部
    /// 被调，工具卡/回响/锚定行走不到）
    private func reactionReserve(
        _ entry: ChatEntryHeightSnapshot
    ) -> CGFloat {
        entry.hasReactionChrome
            ? ChatReactionMetrics.rowReserve
            : 0
    }

    /// 选择框槽（总表 203／§441）：气泡下方选项
    /// 卡——活卡＝项数×单行高＋行间 spacingXS＋
    /// 槽距 spacingS；已选/过期＝一行紧凑高＋槽
    /// 距。视图侧 OptionsCardView 逐值同式（单行
    /// 截断、minTapTarget 行高）。无卡恒 0（两态
    /// 差由测试钉住）
    private func optionsCardSlot(
        _ entry: ChatEntryHeightSnapshot
    ) -> CGFloat {
        guard let input = facets.optionsCards[entry.id]
        else { return 0 }
        switch input.kind {
        case .live:
            let rows = CGFloat(max(input.optionCount, 0))
            return OneDayMetrics.spacingS
                + rows * OneDayMetrics.minTapTarget
                + max(rows - 1, 0) * OneDayMetrics.spacingXS
        case .selected, .expired:
            return OneDayMetrics.spacingS
                + OneDayMetrics.minTapTarget
        }
    }

    /// 来源条槽（D4，§349）：定稿气泡下方的轮级来
    /// 源清单——本槽价＝条本体高（sourceStrip-
    /// Height）＋一段 spacingS（entryRowContent 的
    /// VStack 槽距，与其余槽同口径）；无来源恒 0
    /// （两态差由拟合测试钉住，含「无来源零增量」）
    private func sourceStripSlot(
        _ entry: ChatEntryHeightSnapshot
    ) -> CGFloat {
        guard !entry.sources.isEmpty else { return 0 }
        return OneDayMetrics.spacingS
            + sourceStripHeight(entry)
    }

    /// 来源条本体高（D4，§349）：头行恒 minTap-
    /// Target（与视图 frame(minHeight:) 逐值）；展
    /// 开加列表段——段首 spacingXS＋逐行 footnote
    /// 一行价（视图行 lineLimit(1) 恒一行、本处以
    /// 限行量测价）＋行间 spacingXS
    func sourceStripHeight(
        _ entry: ChatEntryHeightSnapshot
    ) -> CGFloat {
        var total = OneDayMetrics.minTapTarget
        let expanded = facetExpansionOverride(
            for: ChatRowStateKeys.sourcesEntry(entry.id)
        ) ?? false
        if expanded, !entry.sources.isEmpty {
            // 行是 SwiftUI Text 单行（lineLimit(1)）
            // ——走 swiftLineHeight 实高口（§329 校准：
            // .footnote 实高 15.67 vs spec 步长 18，
            // 直用 plainHeight 的限行价会虚高 7pt，
            // 拟合测试实证）
            let rowLine = swiftLineHeight(
                plainFont(.footnote)
            )
            total += OneDayMetrics.spacingXS
                + rowLine * CGFloat(entry.sources.count)
                + OneDayMetrics.spacingXS
                    * CGFloat(entry.sources.count - 1)
        }
        return total
    }

    /// 用户行高：HStack{Spacer(min 44)＋[失败钮
    /// 44]＋VStack(spacingXS, trailing)}——列宽
    /// ＝内容宽−栈间距−侧让位−（失败钮＋间距在
    /// 席时）；VStack 槽序与 bubble 用户支逐字
    /// 同序：引用块／本地图行／远端图×n／正文泡
    /// ／文件牌组／待发状态行
    private func userEntryHeight(
        _ entry: ChatEntryHeightSnapshot
    ) -> CGFloat {
        // §329 续修（拟合直测校准实证）：HStack 与
        // Spacer 相邻处不另计默认间距（Spacer 本身
        // 即间距、相邻 stack spacing 被吸收）——旧
        // 稿多扣 8pt 令正文宽窄一档、长文虚高 3 行
        // §407（预排版步骤 1）：发送状态自此不进高
        // 度输入——失败钮/待发标记改 overlay 挂正
        // 文列左侧让位区（ChatView.sendStateMark），
        // 列宽恒按终态形态计、状态翻转同内容同高
        // （ChatPreLayoutStep1Tests 钉测把守）；旧
        // 失败扣列宽 52＋待发加槽＋失败 max 44 三
        // 项一并退役
        let columnWidth = contentWidth
            - OneDayMetrics.bubbleSideInset
        let textWidth = columnWidth
            - OneDayMetrics.bubblePaddingH * 2
        var slots: [CGFloat] = []
        if let quote = entry.quote {
            slots.append(messageQuoteHeight(
                name: MessageQuote.speakerName(
                    for: quote.role,
                    assistantName: agentDisplayName
                ),
                summary: quote.summary(maxLength: 80),
                columnWidth: columnWidth,
                nameSingleLine: false
            ))
        } else if let sourceQuote = entry.sourceQuote {
            let firstLine: String
            let summary: String
            switch sourceQuote {
            case .feed(let feedQuote):
                firstLine = feedQuote.mark.isEmpty
                    ? feedQuote.title
                    : "\(feedQuote.mark) \(feedQuote.title)"
                summary = feedQuote.summary(
                    maxLength: 80
                )
            case .idea(let ideaQuote):
                firstLine = ideaQuote.mark.isEmpty
                    ? ideaQuote.title
                    : "\(ideaQuote.mark) \(ideaQuote.title)"
                summary = ideaQuote.summary(
                    maxLength: 80
                )
            case .file(let fileQuote):
                firstLine = fileQuote.name
                summary = fileQuote.summary(
                    maxLength: 80
                )
            case .goal(let goalQuote):
                firstLine = goalQuote.title
                summary = goalQuote.summary(
                    maxLength: 80
                )
            }
            slots.append(messageQuoteHeight(
                name: firstLine, summary: summary,
                columnWidth: columnWidth,
                nameSingleLine: true
            ))
        }
        let localImageDatas = entry.imageDatas
        if !localImageDatas.isEmpty {
            // localImageRow：解码成功才出卡（同缓
            // 存同步读）、全失败整行 0——与视图同
            // 判（LocalImageStore 同源）
            let decoded = localImageDatas.indices
                .contains { index in
                    facetLocalImageDecoded(
                        entryID: entry.id, index: index,
                        data: localImageDatas[index]
                    )
                }
            slots.append(
                decoded ? ChatImageSizing.cardHeight : 0
            )
        }
        for _ in entry.remoteImagePaths {
            slots.append(ChatImageSizing.cardHeight)
        }
        if !entry.content.isEmpty {
            // 正文泡：plainRuns 整形拼装（与呈现/
            // 产物层同源）＋气泡内距 V 13×2
            let textHeight = memoized(
                "user", entry.content, textWidth
            ) {
                assembledHeight(
                    paragraphs: [
                        InlineTextParagraph(
                            runs: TextShaping.shapeRuns(
                                InlineRunBuilder
                                    .plainRuns(
                                        entry.content
                                    )
                            )
                        ),
                    ],
                    foreground: Palette.userBubbleText,
                    width: textWidth
                )
            }
            slots.append(
                textHeight
                    + OneDayMetrics.bubblePaddingV * 2
            )
        }
        if !entry.remoteFilePaths.isEmpty {
            var chips: CGFloat = 0
            for rawPath in entry.remoteFilePaths {
                let split = FileLineAnchor.split(
                    pathWithAnchor: rawPath
                )
                chips += fileChipHeight(
                    path: split.path,
                    width: columnWidth
                )
            }
            chips += OneDayMetrics.spacingXS
                * CGFloat(
                    entry.remoteFilePaths.count - 1
                )
            slots.append(chips)
        }
        if entry.sendFailed {
            let kind = facetFailureKind(for: entry.id)
            let copy = SendFailureCopy.message(kind: kind)
            let resendWidth = weightedNaturalWidth(
                "重新发送", .caption1, .medium
            )
            let statusTextWidth = max(
                1,
                columnWidth - OneDayMetrics.spacingS - resendWidth
            )
            let textHeight = swiftTextHeight(
                measured: plainHeight(
                    copy, .caption1, width: statusTextWidth
                ),
                stepStyle: .caption1,
                firstLineFont: plainFont(.caption1)
            )
            let resendHeight = swiftLineHeight(
                weightedFont(.caption1, .medium)
            )
            slots.append(
                OneDayMetrics.spacingMicro
                    + max(textHeight, resendHeight)
            )
        }
        var total: CGFloat = 0
        if !slots.isEmpty {
            total = slots.reduce(0, +)
                + OneDayMetrics.spacingXS
                    * CGFloat(slots.count - 1)
        }
        return total
    }

    /// 助手呈现文本派生（台账 190 留账②·DESIGN
    /// §335）：摘行集与 displayText 的唯一出处——
    /// 合成器行高（facet 存在性）、产物副产（同
    /// facet 快照）、ChatView 预热（活读存在性）
    /// 三方共用本函数，产物键自此与呈现/量测同
    /// 文。旧形态副产取 EntryScanMemo.media 原文，
    /// 有确证摘行时产物与呈现/量测分家（键按内容
    /// 哈希自会分家、不出错产物，但呈现永远查不
    /// 中）——同源缺口在此收口。存在性以闭包注
    /// 入：口径只认「独立成行＋确证存在才摘、整
    /// 条裸路径无条件摘」，三方逐字同式
    static func assistantDisplayText(
        entryID: UUID,
        scans: AssistantTextScans,
        existence: (String) -> Bool
    ) -> String {
        let mediaText = scans.media.text
        let wholePathRef = FileRefDetector
            .wholeMessagePath(in: mediaText)
        let inlineImages = scans.inlineCandidates
            .filter { $0.path != wholePathRef?.path }
        let standalonePaths = Set(scans.standalonePaths)
        let stripPaths = Set(
            inlineImages.filter {
                $0.isStandaloneLine && existence($0.path)
            }.map(\.path)
        ).union(
            scans.media.imagePaths.filter {
                standalonePaths.contains($0)
                    && existence($0)
            }
        ).union(
            wholePathRef.map { [$0.path] } ?? []
        )
        return EntryScanMemo.displayText(
            entryID: entryID,
            mediaText: mediaText,
            stripPaths: stripPaths
        )
    }

    /// 助手行高：VStack(spacingS, leading) 槽序
    /// 与 bubble 助手支逐字同序：思考块／远端图
    /// ×n／MEDIA 图×n／裸路径图×n／交付项×n／
    /// 整条裸路径／正文泡／文件牌组。摘行与派生
    /// 扫描全走 EntryScanMemo 同源（与视图同一
    /// 调用、同一备忘），存在性读 FileMetadata-
    /// Store 同源——视图怎么派生、合成怎么派生
    private func assistantEntryHeight(
        _ entry: ChatEntryHeightSnapshot
    ) -> CGFloat {
        let scans = EntryScanMemo.scans(
            entryID: entry.id,
            content: entry.content,
            remoteImagePaths: entry.remoteImagePaths
        )
        let deliverySplit = scans.delivery
        let mediaSplit = scans.media
        let wholePathRef = FileRefDetector
            .wholeMessagePath(in: mediaSplit.text)
        let inlineImages = scans.inlineCandidates
            .filter { $0.path != wholePathRef?.path }
        // §335：摘行集与呈现文本改走单源助手（与产
        // 物副产/预热同函数——产物键自此与量测同文）
        let displayText = Self.assistantDisplayText(
            entryID: entry.id, scans: scans
        ) { facetFileExistence($0) == .exists }
        var slots: [CGFloat] = []
        if let reasoning = entry.reasoning,
           !reasoning.isEmpty {
            let expanded = facetExpansionOverride(
                for: ChatRowStateKeys.reasoningEntry(
                    entry.id
                )
            ) ?? ReasoningPresentation
                .defaultExpanded(phase: .finished)
            slots.append(reasoningHeight(
                text: reasoning, expanded: expanded
            ))
        }
        for _ in entry.remoteImagePaths {
            slots.append(ChatImageSizing.cardHeight)
        }
        // 图片槽占位（台账 185）：存在性未定先按
        // 190 占位、确证 missing 才塌 0——旧口径未
        // 定即 0、解析回来凭空长高 190（用户报
        // 「间距有时会变」的最吻合落点）。视图侧
        // AssistantMediaImage 未确证时整行不显
        // 示，占位期该槽为空白填充、确证存在图在
        // 原位填入
        for _ in mediaSplit.imagePaths {
            slots.append(ChatImageSizing.cardHeight)
        }
        for _ in inlineImages {
            slots.append(ChatImageSizing.cardHeight)
        }
        for deliveryID in deliverySplit.deliveryIDs {
            slots.append(
                deliveryItemHeight(id: deliveryID)
            )
        }
        if let wholePathRef {
            if FileRefDetector.isImagePath(
                wholePathRef.path
            ) {
                slots.append(ChatImageSizing.cardHeight)
            } else {
                slots.append(barePathFileCardHeight(
                    path: wholePathRef.path
                ))
            }
        }
        if !displayText.isEmpty
            || (mediaSplit.imagePaths.isEmpty
                && inlineImages.isEmpty
                && deliverySplit.deliveryIDs.isEmpty
                && wholePathRef == nil) {
            slots.append(
                markdownHeight(displayText)
                    + OneDayMetrics.bubblePaddingV * 2
            )
        }
        let fileRefs = FileRefDetector
            .detectStandaloneAnchored(
                in: entry.content,
                excluding: entry.remoteImagePaths
                    + mediaSplit.imagePaths
                    + inlineImages.map(\.path)
                    + (wholePathRef.map { [$0.path] }
                        ?? [])
            )
        if !fileRefs.isEmpty {
            var chips: CGFloat = 0
            for ref in fileRefs {
                chips += assistantFileChipHeight(
                    path: ref.path
                )
            }
            chips += OneDayMetrics.spacingXS
                * CGFloat(fileRefs.count - 1)
            slots.append(chips)
        }
        guard !slots.isEmpty else { return 0 }
        return slots.reduce(0, +)
            + OneDayMetrics.spacingS
                * CGFloat(slots.count - 1)
    }
}


/// 整行实算计数锁盒（§331）：NSLock 护裸 Int、
/// @unchecked Sendable 依据＝一切读写都在锁内
/// （与 OneDayCore ParseMemoBox 同式）
private final class LockedRowComputationCounter:
    @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func increment() {
        lock.lock()
        value += 1
        lock.unlock()
    }

    func reset() {
        lock.lock()
        value = 0
        lock.unlock()
    }

    func read() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
