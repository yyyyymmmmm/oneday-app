import OneDayCore
import OneDayDesign
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// §329 验证重建（拟合一致性直测）：行高改
/// .absolute 回喂后，布局采用高与视图真实拟合
/// 高必须逐值相等——这正是定因点名的量（同
/// flush 内以采用高回喂再拟合、断言不变）。本
/// 文件逐 facet 以独立 UIHostingController 托
/// 管生产视图本体量拟合高，与高度合成器
/// （ChatNativeRowHeightComposer）的合成高对
/// 账（±1pt）；任一 facet 不一致即合成公式与
/// 视图几何分家、在此以 facet 名现形。
///
/// 覆盖：markdown 散文/引用/代码/表格 Grid/表
/// 格降级列表/任务清单、用户长文（含栈间距校
/// 准文本：候选列宽 278/286 行数须不同、校准
/// 由本例自验）、工具卡（收/展）、工具组
/// （收/展）、思考块（收/展）、文件牌。
/// 未直测 facet（诚实边界）：审批卡与交付卡
/// 的合成须经 AgentHubStore/DeliveryStore 的
/// 服务端状态播种（协议客户端＋服务器配置），
/// 实验室无播种口——其行在生产链压测里以加
/// 载/空形态在席，公式逐项对 ApprovalCard-
/// Face/DeliveryFileCard 几何落码、终判归用
/// 户真机（见 §329 与组版报告）。
@MainActor
final class ChatNativeRowHeightFittingTests: XCTestCase {

    private let screenW: CGFloat = 402
    private var contentW: CGFloat { screenW - 40 }
    private var textW: CGFloat {
        OneDayMetrics.assistantTextWidth(screenWidth: screenW)
    }

    private func makeComposer(
        ledger: ChatRowStateLedger
    ) -> ChatNativeRowHeightComposer {
        ChatNativeRowHeightComposer(
            screenWidth: screenW,
            horizontalPadding: OneDayMetrics.pageGutter,
            sizeCategory: .large,
            boldText: false,
            displayScale: 3,
            ledger: ledger,
            hubStore: AppState().sharedHubStore(),
            agentDisplayName: "Hermes",
            emptyStateAvatarSize: 72
        )
    }

    /// 独立拟合：无界高与「以采用高为提议高」两
    /// 读数——后者即定因的回喂再拟合（pass 间拟
    /// 合须不动点）
    private func fit(
        _ view: AnyView, width: CGFloat,
        proposedHeight: CGFloat? = nil
    ) -> CGFloat {
        let host = UIHostingController(rootView: view)
        return host.sizeThatFits(
            in: CGSize(
                width: width,
                height: proposedHeight
                    ?? .greatestFiniteMagnitude
            )
        ).height
    }

    private func assertFit(
        _ name: String, view: AnyView, width: CGFloat,
        expected: CGFloat,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let unbounded = fit(view, width: width)
        XCTAssertEqual(
            unbounded, expected, accuracy: 1.0,
            "\(name)：拟合高 \(unbounded) 与合成高 \(expected) 须逐值相等（±1）",
            file: file, line: line
        )
        let refed = fit(
            view, width: width, proposedHeight: expected
        )
        XCTAssertEqual(
            refed, expected, accuracy: 1.0,
            "\(name)：以采用高回喂再拟合须为不动点，\(refed) vs \(expected)",
            file: file, line: line
        )
    }

    /// 助手正文泡形态（assistantBubble 的高度相
    /// 关几何：正文宽封顶＋纵内距；染色/背景不影
    /// 响高、不入拟合）
    private func assistantBubbleView(
        _ text: String
    ) -> AnyView {
        AnyView(
            MarkdownText(text)
                .frame(
                    width: textW, alignment: .leading
                )
                .padding(
                    .vertical, OneDayMetrics.bubblePaddingV
                )
                .environment(\.dynamicTypeSize, .large)
        )
    }

    private func assertMarkdownFit(
        _ name: String, _ text: String,
        composer: ChatNativeRowHeightComposer
    ) {
        assertFit(
            name,
            view: assistantBubbleView(text),
            width: textW + OneDayMetrics.bubblePaddingH * 2,
            expected: composer.markdownHeight(text)
                + OneDayMetrics.bubblePaddingV * 2
        )
    }

    // MARK: - Markdown facet 族

    func testMarkdownFacetsFitComposer() {
        let composer = makeComposer(
            ledger: ChatRowStateLedger()
        )
        assertMarkdownFit(
            "散文多段",
            """
            # 结论先行

            这是第一段正文，长度中等，包含一些需要折行的中文内容用来覆盖多行排版形态。

            - 列表项一
            - 列表项二，文字更长一些

            最后一段收尾，确认段间节奏与合成口径一致。
            """,
            composer: composer
        )
        assertMarkdownFit(
            "引用块",
            """
            先看这条引用。

            > 引用第一行
            > 引用第二行，内容稍长一点用来折行

            引用之后还有正文。
            """,
            composer: composer
        )
        assertMarkdownFit(
            "代码块",
            """
            代码如下：

            ```swift
            func greet(_ name: String) -> String {
                let message = "hello, \\(name)"
                print(message)
                return message
            }
            ```

            以上。
            """,
            composer: composer
        )
        assertMarkdownFit(
            "表格Grid",
            """
            | 项目 | 状态 | 备注 |
            | --- | --- | --- |
            | 构建 | 通过 | 两轮 CI 全绿 |
            | 真机 | 待验 | 长会话上翻到顶三遍往返不崩才算治愈 |
            | 文档 | 已更新 | 设计节与待办总表都已落账 |
            """,
            composer: composer
        )
        assertMarkdownFit(
            "表格Grid长格封顶折行",
            """
            | 项目 | 状态 | 备注 |
            | --- | --- | --- |
            | 换引擎 | 收官 | 步骤四五六全部合入组版，停滚落定跟手度与流式滑动结清帧率都留了真机门，等用户醒来逐项验收之后才算真正关账 |
            | 草稿 |  | 短注 |
            """,
            composer: composer
        )
        assertMarkdownFit(
            "表格降级列表",
            """
            | 甲 | 乙 | 丙 | 丁 | 戊 | 己 |
            | --- | --- | --- | --- | --- | --- |
            | 一行甲 | 一行乙 | 一行丙 | 一行丁 | 一行戊 | 一行己 |
            | 二行甲列长一点 | 二行乙 | 二行丙 | 二行丁 | 二行戊 | 二行己 |
            """,
            composer: composer
        )
        assertMarkdownFit(
            "任务清单",
            """
            - [x] 已完成的一项
            - [ ] 待办的一项，文字长一点需要折行验证行高
            - [ ] 最后一项
            """,
            composer: composer
        )
    }

    // MARK: - 用户行（栈间距校准）

    /// 用户正文文本视图（与 ChatView 用户泡同构
    /// 造：plainRuns 整形拼装＋气泡内距）
    private func userTextView(
        _ text: String, width: CGFloat?
    ) -> AnyView {
        let inner = SelectableInlineText(
            paragraphs: [
                InlineTextParagraph(
                    runs: TextShaping.shapeRuns(
                        InlineRunBuilder.plainRuns(text)
                    )
                ),
            ],
            textStyle: .body,
            foreground: Palette.userBubbleText
        )
        if let width {
            return AnyView(
                inner.frame(width: width)
                    .environment(\.dynamicTypeSize, .large)
            )
        }
        return AnyView(
            inner.environment(\.dynamicTypeSize, .large)
        )
    }

    func testUserRowFitAndStackGapCalibration() {
        let composer = makeComposer(
            ledger: ChatRowStateLedger()
        )
        // 校准文本自验：在候选正文宽 278（栈间距
        // 8）与 286（栈间距 0）下行数必须不同——
        // 否则本例对 stackGap 无判别力。从一族等
        // 长词文本里挑出有判别力的一条
        var calibration: String?
        for tokenLength in 4...9 {
            let token = String(
                repeating: "a", count: tokenLength
            )
            let candidate = Array(
                repeating: token, count: 64
            ).joined(separator: " ")
            let narrow = fit(
                userTextView(candidate, width: 278),
                width: 278
            )
            let wide = fit(
                userTextView(candidate, width: 286),
                width: 286
            )
            if abs(narrow - wide) > 1 {
                calibration = candidate
                break
            }
        }
        let text = try? XCTUnwrap(
            calibration,
            "校准文本族内须存在对列宽敏感的一条（278 vs 286 行数不同）"
        )
        guard let text else { return }
        let entry = ChatEntry(
            role: "user", content: text, thread: nil
        )
        // 真实用户行结构拟合：HStack{Spacer(min
        // 44)＋VStack(trailing, spacingXS){正文
        // 泡}}——栈间距由系统默认决定、与合成器
        // 的 stackGap 假设无关，是独立读数
        let rowView = AnyView(
            HStack {
                Spacer(
                    minLength: OneDayMetrics.bubbleSideInset
                )
                VStack(
                    alignment: .trailing,
                    spacing: OneDayMetrics.spacingXS
                ) {
                    SelectableInlineText(
                        paragraphs: [
                            InlineTextParagraph(
                                runs: TextShaping.shapeRuns(
                                    InlineRunBuilder.plainRuns(
                                        text
                                    )
                                )
                            ),
                        ],
                        textStyle: .body,
                        foreground: Palette.userBubbleText
                    )
                    .padding(
                        .horizontal,
                        OneDayMetrics.bubblePaddingH
                    )
                    .padding(
                        .vertical,
                        OneDayMetrics.bubblePaddingV
                    )
                }
            }
            .environment(\.dynamicTypeSize, .large)
        )
        assertFit(
            "用户长文行",
            view: rowView, width: contentW,
            expected: composer.entryHeight(
                entry, dividerText: nil
            )
        )
    }

    // MARK: - 工具卡/组、思考块、文件牌

    private func sampleCard(
        id: String = "tc-fit-1"
    ) -> ToolCard {
        ToolCard(
            id: id, toolName: "terminal",
            category: .terminal,
            title: "运行命令",
            summary: "ls -la /opt/data",
            result: "total 8\n-rw-r--r-- report.xlsx\n-rw-r--r-- notes.md",
            resultFailed: false,
            arguments: "{\"command\":\"ls -la /opt/data\"}"
        )
    }

    func testToolCardFitsComposer() {
        let ledger = ChatRowStateLedger()
        let composer = makeComposer(ledger: ledger)
        let card = sampleCard()
        let key = ChatRowStateKeys.toolEntry(
            UUID()
        )
        // 结构归位·对话页（活动线）：样本卡已落定
        // ——收起态合成高须恰为活动线头行高
        // minTapTarget（压线成立的数值钉）
        XCTAssertEqual(
            composer.toolCardHeight(
                card: card, width: contentW,
                expanded: false, plain: false
            ),
            OneDayMetrics.minTapTarget, accuracy: 0.5,
            "落定独立卡收起态应压成活动线（44），而非卡面高"
        )
        assertFit(
            "工具卡收起",
            view: AnyView(
                ToolCardView(
                    card: card, expansionKey: key,
                    ledger: ledger
                )
                .environment(\.dynamicTypeSize, .large)
            ),
            width: contentW,
            expected: composer.toolCardHeight(
                card: card, width: contentW,
                expanded: false, plain: false
            )
        )
        ledger.setExpansion(true, for: key)
        assertFit(
            "工具卡展开",
            view: AnyView(
                ToolCardView(
                    card: card, expansionKey: key,
                    ledger: ledger
                )
                .environment(\.dynamicTypeSize, .large)
            ),
            width: contentW,
            expected: composer.toolCardHeight(
                card: card, width: contentW,
                expanded: true, plain: false
            )
        )
    }

    /// 活动线的另一向：进行中卡不压线——保持卡
    /// 面（过程反馈在场），合成高与视图拟合一致
    /// 且大于活动线高
    func testRunningToolCardKeepsCardForm() {
        let ledger = ChatRowStateLedger()
        let composer = makeComposer(ledger: ledger)
        let running = ToolCard(
            id: "tc-fit-running", toolName: "terminal",
            category: .terminal,
            title: "运行命令",
            summary: "ls -la /opt/data",
            result: nil,
            resultFailed: false,
            arguments: "{\"command\":\"ls -la /opt/data\"}"
        )
        let height = composer.toolCardHeight(
            card: running, width: contentW,
            expanded: false, plain: false
        )
        XCTAssertGreaterThan(
            height, OneDayMetrics.minTapTarget,
            "进行中卡应保持卡面高（>活动线 44），实得 \(height)"
        )
        assertFit(
            "进行中工具卡",
            view: AnyView(
                ToolCardView(
                    card: running,
                    expansionKey: ChatRowStateKeys.toolEntry(
                        UUID()
                    ),
                    ledger: ledger
                )
                .environment(\.dynamicTypeSize, .large)
            ),
            width: contentW,
            expected: height
        )
    }

    func testToolGroupFitsComposer() {
        let ledger = ChatRowStateLedger()
        let composer = makeComposer(ledger: ledger)
        let cards = [
            sampleCard(id: "tc-fit-g1"),
            ToolCard(
                id: "tc-fit-g2", toolName: "read_file",
                category: .file,
                title: "读取文件",
                summary: "notes.md",
                result: "文件内容摘要一行",
                resultFailed: false,
                arguments: nil
            ),
        ]
        let groupKey = "toolgroup-fit"
        assertFit(
            "工具组收起",
            view: AnyView(
                ToolCardGroupView(
                    cards: cards, expansionKey: groupKey,
                    ledger: ledger
                )
                .environment(\.dynamicTypeSize, .large)
            ),
            width: contentW,
            expected: composer.toolGroupHeight(
                cards: cards, groupKey: groupKey
            )
        )
        ledger.setExpansion(true, for: groupKey)
        ledger.setExpansion(
            true,
            for: ChatRowStateKeys.toolGroupCard(
                groupKey: groupKey, cardID: cards[1].id
            )
        )
        assertFit(
            "工具组展开（含内卡展开）",
            view: AnyView(
                ToolCardGroupView(
                    cards: cards, expansionKey: groupKey,
                    ledger: ledger
                )
                .environment(\.dynamicTypeSize, .large)
            ),
            width: contentW,
            expected: composer.toolGroupHeight(
                cards: cards, groupKey: groupKey
            )
        )
    }

    func testReasoningBlockFitsComposer() {
        let ledger = ChatRowStateLedger()
        let composer = makeComposer(ledger: ledger)
        let text = """
        先把问题拆成三部分：第一是布局 pass 的自我失效路径，第二是行高来源，第三是验证方法。
        逐项核对之后发现闸门并不在这条路上，所以修法必须落在结构上而不是继续加守卫。
        最后把行高改成量测回喂的固定高，框架不再估算和修正，环按构造拆除。
        """
        let key = ChatRowStateKeys.liveReasoning
        assertFit(
            "思考块收起",
            view: AnyView(
                ReasoningBlock(
                    text: text, seconds: nil,
                    isStreaming: false,
                    expansionKey: key, ledger: ledger
                )
                .environment(\.dynamicTypeSize, .large)
            ),
            width: contentW,
            expected: composer.reasoningHeight(
                text: text, expanded: false
            )
        )
        ledger.setExpansion(true, for: key)
        assertFit(
            "思考块展开",
            view: AnyView(
                ReasoningBlock(
                    text: text, seconds: nil,
                    isStreaming: false,
                    expansionKey: key, ledger: ledger
                )
                .environment(\.dynamicTypeSize, .large)
            ),
            width: contentW,
            expected: composer.reasoningHeight(
                text: text, expanded: true
            )
        )
    }

    func testFileChipFitsComposer() {
        let composer = makeComposer(
            ledger: ChatRowStateLedger()
        )
        let path = "/opt/data/report.xlsx"
        assertFit(
            "文件牌",
            view: AnyView(
                FileChip(path: path) {}
                    .environment(AppState())
                    .environment(\.dynamicTypeSize, .large)
            ),
            width: contentW,
            expected: composer.fileChipHeight(
                path: path, width: contentW
            )
        )
    }

    // MARK: - 台账 185：间距跳变三落点

    /// 快照形态合成器（facet 手工注入——存在性/
    /// 交付 meta 逐值可控，不经实时 Store）
    private func makeSnapshotComposer(
        facets: ChatNativeRowFacets
    ) -> ChatNativeRowHeightComposer {
        ChatNativeRowHeightComposer(
            screenWidth: screenW,
            horizontalPadding: OneDayMetrics.pageGutter,
            sizeCategory: .large,
            boldText: false,
            displayScale: 3,
            agentDisplayName: "Hermes",
            emptyStateAvatarSize: 72,
            facets: facets
        )
    }

    /// 图片/交付/文件牌占位：存在性未定先按定高
    /// 占位、确证 missing 才塌——同一条目在未定
    /// 与确证存在两态行高逐值相等（不再 0↔190
    /// 翻转），确证不存在时恰少一个卡高
    func testUnverifiedSlotsReserveCardHeight() {
        // 路径须在下载根内（MediaMarker 摘行门：
        // 根外路径整行留作纯文本、不进图片槽）
        let path = "/opt/data/cache/images/pic-185.png"
        let entry = ChatEntry(
            role: "assistant",
            content: "图在下面：\nMEDIA:\(path)",
            thread: nil
        )
        var unverifiedFacets = ChatNativeRowFacets()
        unverifiedFacets.fileExistences = [:]
        let unverified = makeSnapshotComposer(
            facets: unverifiedFacets
        )
        var existsFacets = ChatNativeRowFacets()
        existsFacets.fileExistences = [path: .exists]
        let exists = makeSnapshotComposer(
            facets: existsFacets
        )
        var missingFacets = ChatNativeRowFacets()
        missingFacets.fileExistences = [path: .missing]
        let missing = makeSnapshotComposer(
            facets: missingFacets
        )
        let hUnverified = unverified.entryHeight(
            entry, dividerText: nil
        )
        let hExists = exists.entryHeight(
            entry, dividerText: nil
        )
        let hMissing = missing.entryHeight(
            entry, dividerText: nil
        )
        XCTAssertEqual(
            hUnverified, hExists, accuracy: 0.5,
            "未定态行高须＝确证存在态（占位不翻转），"
                + "\(hUnverified) vs \(hExists)"
        )
        XCTAssertEqual(
            hExists - hMissing,
            ChatImageSizing.cardHeight, accuracy: 0.5,
            "确证不存在只塌一个卡高，差 \(hExists - hMissing)"
        )
        // 交付槽：meta 未到先按卡高占位（旧口径 0）
        XCTAssertEqual(
            unverified.deliveryItemHeight(id: "d-185"),
            ChatImageSizing.cardHeight,
            "交付 meta 未到须按卡高占位"
        )
        // 文件牌：未定按牌高、确证不存在落文本高
        XCTAssertEqual(
            unverified.assistantFileChipHeight(path: path),
            exists.assistantFileChipHeight(path: path),
            accuracy: 0.5,
            "文件牌未定态须＝确证存在态（牌高占位）"
        )
        XCTAssertLessThan(
            missing.assistantFileChipHeight(path: path),
            exists.assistantFileChipHeight(path: path),
            "文件牌确证不存在须落文本高（小于牌高）"
        )
    }


}

/// §329 验证重建（生产链压测）：种子线程经真
/// ChatView 生产链造行（ChatEntry→nativeEntry-
/// Row 全 facet＋极端高差相邻排布），连续小步
/// 滚动（≈40pt/步＋部分 drain）自底向顶再回
/// 底——断言：不崩（跑完即证据）、滚动全程布
/// 局提供者零新增调用（无重建/无失效源）、
/// contentSize 逐值稳态、采用高与帧高逐行相
/// 等、间隙 24±2。旧 BTIER 压测（R3 ⑮′）保
/// 留对照、本例是其生产链替代门。
@MainActor
final class ChatNativeRowHeightProductionChainTests: XCTestCase {

    private final class DeviceWindow: UIWindow {
        override var safeAreaInsets: UIEdgeInsets {
            UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
        }
    }

    private var window: DeviceWindow!
    private var swiftDataMount = SwiftDataTestMount()
    private var container: ModelContainer!

    override func tearDown() async throws {
        window?.rootViewController = nil
        window?.isHidden = true
        window = nil
        container = nil
        await swiftDataMount.release()
        try await super.tearDown()
    }

    // MARK: - facet 种子（一轮 14 行、极端高差相邻）

    private func facetEntries(
        thread: ChatThread, cycle: Int
    ) -> [ChatEntry] {
        let longMarkdown = (0..<8).map { i in
            """
            ## 第 \(i + 1) 节

            这是长回复的第 \(i + 1) 段正文，用来把行高拉到数百 pt 量级，与相邻的短行形成极端高差——真机崩溃正是发生在这种行集的上翻滚动里。

            - 要点一：量测与呈现同源
            - 要点二：行高回喂后框架不再修正
            """
        }.joined(separator: "\n\n")
        let codeLines = (0..<18).map {
            "let value\($0) = compute(\($0))"
        }.joined(separator: "\n")
        let codeText = """
        代码段：

        ```swift
        \(codeLines)
        ```

        代码之后一行收尾。
        """
        let tableGrid = """
        | 项目 | 状态 | 备注 |
        | --- | --- | --- |
        | 构建 | 通过 | 两轮 CI 全绿 |
        | 真机 | 待验 | 长会话上翻到顶三遍往返 |
        """
        let tableList = """
        | 甲 | 乙 | 丙 | 丁 | 戊 | 己 |
        | --- | --- | --- | --- | --- | --- |
        | 一 | 二 | 三 | 四 | 五 | 六 |
        """
        let taskText = """
        - [x] 已完成项
        - [ ] 待办项，文字长一点
        - [ ] 最后一项
        """
        let latin = Array(
            repeating: "abcd", count: 64
        ).joined(separator: " ")
        let card = ToolCard(
            id: "tc-chain-\(cycle)",
            toolName: "terminal", category: .terminal,
            title: "运行命令", summary: "ls",
            result: "done", resultFailed: false,
            arguments: nil
        )
        return [
            ChatEntry(
                role: "user", content: "嗯", thread: thread
            ),
            ChatEntry(
                role: "assistant", content: longMarkdown,
                thread: thread
            ),
            ChatEntry(
                role: "user", content: latin,
                thread: thread
            ),
            ChatEntry(
                role: "assistant", content: codeText,
                thread: thread
            ),
            ChatEntry(
                role: "assistant", content: tableGrid,
                thread: thread
            ),
            ChatEntry(
                role: "assistant", content: tableList,
                thread: thread
            ),
            ChatEntry(
                role: "assistant", content: taskText,
                thread: thread
            ),
            ChatEntry(
                role: "assistant", content: "结论一行。",
                thread: thread,
                reasoning: "思考过程第一行。\n思考过程第二行，稍长一点用来撑开折叠区。\n思考过程第三行收尾。",
                reasoningSeconds: 3
            ),
            ChatEntry(
                role: "tool", content: "", thread: thread,
                toolCard: card
            ),
            ChatEntry(
                role: "assistant", content: "",
                thread: thread,
                remoteImagePaths: ["/opt/data/img.png"]
            ),
            ChatEntry(
                role: "assistant",
                content: "[[deliver:dlv_chain_\(cycle)]]",
                thread: thread
            ),
            ChatEntry(
                role: "assistant", content: "",
                thread: thread, traceKey: "trace-\(cycle)",
                traceSnapshot: TraceEchoSnapshot(
                    headline: "Hermes 已完成检索",
                    targetLabel: "会话甲",
                    openableSessionID: nil,
                    outcome: "找到 3 条结果",
                    isFailed: false
                )
            ),
            ChatEntry(
                role: "assistant",
                content: "目标进度已更新",
                thread: thread, echoKey: "goal-\(cycle)"
            ),
            ChatEntry(
                role: "assistant", content: "",
                thread: thread,
                approvalKey: "wg:skills:rec-chain-\(cycle)"
            ),
        ]
    }

    private func assembleSeededPage(
        entryCount: inout Int
    ) throws {
        let schema = Schema([ChatThread.self, ChatEntry.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(
                schema: schema, isStoredInMemoryOnly: true
            )]
        )
        swiftDataMount.retain(container)
        self.container = container

        let context = ModelContext(container)
        let thread = ChatThread(title: "主线")
        context.insert(thread)
        var total = 0
        for cycle in 0..<3 {
            for entry in facetEntries(
                thread: thread, cycle: cycle
            ) {
                context.insert(entry)
                total += 1
            }
        }
        try context.save()
        entryCount = total

        let appState = AppState(
            client: DemoHermesClient(), demoMode: .connected
        )
        appState.router.drawerThreadSelection = thread.id
        let host = UIHostingController(
            rootView: ChatView(overviewStore: nil)
                .environment(appState)
                .environment(\.locale, AppLocale.uiLocale)
                .modelContainer(container)
        )
        window = DeviceWindow(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874)
        )
        window.rootViewController = host
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
    }

    private func findNativeRootController()
        -> ChatRootViewController? {
        var found: ChatRootViewController?
        func walk(_ vc: UIViewController) {
            if let hit = vc as? ChatRootViewController {
                found = hit
            }
            for child in vc.children { walk(child) }
        }
        if let root = window.rootViewController { walk(root) }
        return found
    }

    private func waitUntil(
        timeout: TimeInterval = 25,
        _ condition: () -> Bool
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.main.run(
                until: Date().addingTimeInterval(0.1)
            )
        }
        return condition()
    }

    // MARK: - 主例

    func testProductionChainContinuousScrollIsStable()
        throws
    {
        var entryCount = 0
        try assembleSeededPage(entryCount: &entryCount)
        // 行集＝条目行＋审批区行（回告行无 overview
        // 供给、空态行不与条目共存）
        let expectedSections = entryCount + 1

        var controller: ChatRootViewController?
        let mounted = waitUntil {
            guard let hit = self.findNativeRootController()
            else { return false }
            self.window.layoutIfNeeded()
            controller = hit
            return hit.collectionView.numberOfSections
                == expectedSections
        }
        XCTAssertTrue(
            mounted,
            "生产链行集须装配齐（期望 \(expectedSections) 行）"
        )
        let vc = try XCTUnwrap(controller)
        let cv = vc.collectionView
        window.layoutIfNeeded()

        // 落定相位（§329 续修）：异步 facet（审
        // 批区 overview 就绪等）会在装配后改写采
        // 用高并触发合法重召——滚动断言只对稳态
        // 成立，故先等采用高谱与提供者计数连续
        // 三采样不变再取快照
        var stableSamples = 0
        var lastHeights = vc.testAdoptedRowHeights
        var lastPasses = vc.testSectionProviderCallCount
        let settled = waitUntil(timeout: 20) {
            window.layoutIfNeeded()
            let heights = vc.testAdoptedRowHeights
            let passes = vc.testSectionProviderCallCount
            if heights == lastHeights, passes == lastPasses,
                heights.count == expectedSections
            {
                stableSamples += 1
            } else {
                stableSamples = 0
                lastHeights = heights
                lastPasses = passes
            }
            return stableSamples >= 3
        }
        XCTAssertTrue(
            settled,
            "生产链行集须在滚动前落定（采用高谱与提供者计数稳定）"
        )

        // 采用高谱：极端高差在席（长 markdown 行
        // 数百 pt、短行数十 pt）
        let adopted = vc.testAdoptedRowHeights
        XCTAssertEqual(adopted.count, expectedSections)
        XCTAssertGreaterThan(
            adopted.max() ?? 0, 500,
            "长 markdown 行采用高须成规模，实测最大 \(adopted.max() ?? -1)"
        )
        XCTAssertLessThan(
            adopted.min() ?? .infinity, 90,
            "短行/空形态行采用高须小，实测最小 \(adopted.min() ?? -1)"
        )

        // 采用高＝帧高（逐行）：.absolute 下布局不
        // 得再改写任何一行的高度
        func frame(at index: Int) throws -> CGRect {
            let attrs = cv.layoutAttributesForItem(
                at: IndexPath(item: 0, section: index)
            )
            return try XCTUnwrap(attrs).frame
        }
        for index in 0..<expectedSections {
            XCTAssertEqual(
                try frame(at: index).height,
                adopted[index], accuracy: 0.5,
                "行 \(index) 帧高须＝采用高（布局零修正）"
            )
        }
        // 间隙抽样：24±2
        for index in [0, 5, 13, 20, 33, expectedSections - 2] {
            let gap = try frame(at: index + 1).minY
                - frame(at: index).maxY
            XCTAssertEqual(
                gap, OneDayMetrics.spacingL, accuracy: 2.0,
                "行 \(index) 间隙须 24±2，实测 \(gap)"
            )
        }

        // 连续小步滚动：自底向顶、再回底（≈40pt
        // 一步、每 5 步部分 drain 一次）——全程布
        // 局提供者零新增调用、contentSize 逐值不
        // 动（无失效源、无修正、稳态）
        let steadySize = cv.contentSize
        let passesBefore = vc.testSectionProviderCallCount
        let maxOffset = max(
            0, steadySize.height - cv.bounds.height
        )
        var y = maxOffset
        var step = 0
        while y > 0 {
            y = max(0, y - 40)
            cv.contentOffset = CGPoint(x: 0, y: y)
            window.layoutIfNeeded()
            step += 1
            if step % 5 == 0 {
                RunLoop.main.run(
                    until: Date().addingTimeInterval(0.02)
                )
            }
        }
        while y < maxOffset {
            y = min(maxOffset, y + 40)
            cv.contentOffset = CGPoint(x: 0, y: y)
            window.layoutIfNeeded()
            step += 1
            if step % 5 == 0 {
                RunLoop.main.run(
                    until: Date().addingTimeInterval(0.02)
                )
            }
        }
        XCTAssertEqual(
            vc.testSectionProviderCallCount, passesBefore,
            "连续滚动全程布局提供者不得再被调用（无重建），\(passesBefore) → \(vc.testSectionProviderCallCount)"
        )
        XCTAssertEqual(
            cv.contentSize.height, steadySize.height,
            accuracy: 0.5,
            "滚动往返后 contentSize 须逐值不变"
        )
        for index in [0, 7, 21, expectedSections - 1] {
            XCTAssertEqual(
                try frame(at: index).height,
                adopted[index], accuracy: 0.5,
                "滚动后行 \(index) 帧高仍须＝采用高"
            )
        }
        print(
            "CHAIN-PASSES passes=\(vc.testSectionProviderCallCount) sections=\(expectedSections) content=\(steadySize.height)"
        )
    }

    // MARK: - §374.3 单 section 构造的生产链压测
    //
    /// §329 压测的单 section 变体：同一种子页、
    /// 同一生产链（真 ChatView 挂窗取行），仅布
    /// 局构造经 ChatListSingleSectionFeature 旗
    /// 翻为单 section——断言同口径：落定相位后
    /// 采用高＝帧高逐行、间隙 24±2、连续小步滚
    /// 动往返全程提供者零新增调用、contentSize
    /// 逐值不动（§329 成环在新构造下不复现的生
    /// 产链证据；托管内容与新构造的相互作用在
    /// 本例射程内、真机观察期仍归组版清单）
    func testProductionChainContinuousScrollIsStableSingleSection()
        throws
    {
        UserDefaults.standard.set(
            true,
            forKey: ChatListSingleSectionFeature
                .defaultsKey
        )
        defer {
            UserDefaults.standard.removeObject(
                forKey: ChatListSingleSectionFeature
                    .defaultsKey
            )
        }
        var entryCount = 0
        try assembleSeededPage(entryCount: &entryCount)
        let expectedRows = entryCount + 1

        var controller: ChatRootViewController?
        let mounted = waitUntil {
            guard let hit = self.findNativeRootController()
            else { return false }
            self.window.layoutIfNeeded()
            controller = hit
            return hit.collectionView.numberOfSections
                == 1
                && hit.collectionView
                    .numberOfItems(inSection: 0)
                    == expectedRows
        }
        XCTAssertTrue(
            mounted,
            "单 section 生产链行集须装配齐（期望 1 节 \(expectedRows) 行）"
        )
        let vc = try XCTUnwrap(controller)
        let cv = vc.collectionView
        window.layoutIfNeeded()

        // 落定相位（同 §329 续修口径）
        var stableSamples = 0
        var lastHeights = vc.testAdoptedRowHeights
        var lastPasses = vc.testSectionProviderCallCount
        let settled = waitUntil(timeout: 20) {
            window.layoutIfNeeded()
            let heights = vc.testAdoptedRowHeights
            let passes = vc.testSectionProviderCallCount
            if heights == lastHeights, passes == lastPasses,
                heights.count == expectedRows
            {
                stableSamples += 1
            } else {
                stableSamples = 0
                lastHeights = heights
                lastPasses = passes
            }
            return stableSamples >= 3
        }
        XCTAssertTrue(
            settled,
            "单 section 生产链行集须在滚动前落定（采用高谱与提供者计数稳定）"
        )

        let adopted = vc.testAdoptedRowHeights
        XCTAssertEqual(adopted.count, expectedRows)
        XCTAssertGreaterThan(
            adopted.max() ?? 0, 500,
            "长 markdown 行采用高须成规模，实测最大 \(adopted.max() ?? -1)"
        )
        XCTAssertLessThan(
            adopted.min() ?? .infinity, 90,
            "短行/空形态行采用高须小，实测最小 \(adopted.min() ?? -1)"
        )

        func frame(at index: Int) throws -> CGRect {
            let attrs = cv.layoutAttributesForItem(
                at: IndexPath(item: index, section: 0)
            )
            return try XCTUnwrap(attrs).frame
        }
        for index in 0..<expectedRows {
            XCTAssertEqual(
                try frame(at: index).height,
                adopted[index], accuracy: 0.5,
                "行 \(index) 帧高须＝采用高（单 section 布局零修正）"
            )
        }
        for index in [0, 5, 13, 20, 33, expectedRows - 2] {
            let gap = try frame(at: index + 1).minY
                - frame(at: index).maxY
            XCTAssertEqual(
                gap, OneDayMetrics.spacingL, accuracy: 2.0,
                "行 \(index) 间隙须 24±2，实测 \(gap)"
            )
        }

        let steadySize = cv.contentSize
        let passesBefore = vc.testSectionProviderCallCount
        let maxOffset = max(
            0, steadySize.height - cv.bounds.height
        )
        var y = maxOffset
        var step = 0
        while y > 0 {
            y = max(0, y - 40)
            cv.contentOffset = CGPoint(x: 0, y: y)
            window.layoutIfNeeded()
            step += 1
            if step % 5 == 0 {
                RunLoop.main.run(
                    until: Date().addingTimeInterval(0.02)
                )
            }
        }
        while y < maxOffset {
            y = min(maxOffset, y + 40)
            cv.contentOffset = CGPoint(x: 0, y: y)
            window.layoutIfNeeded()
            step += 1
            if step % 5 == 0 {
                RunLoop.main.run(
                    until: Date().addingTimeInterval(0.02)
                )
            }
        }
        XCTAssertEqual(
            vc.testSectionProviderCallCount, passesBefore,
            "单 section 连续滚动全程布局提供者不得再被调用（无重建），\(passesBefore) → \(vc.testSectionProviderCallCount)"
        )
        XCTAssertEqual(
            cv.contentSize.height, steadySize.height,
            accuracy: 0.5,
            "单 section 滚动往返后 contentSize 须逐值不变"
        )
        for index in [0, 7, 21, expectedRows - 1] {
            XCTAssertEqual(
                try frame(at: index).height,
                adopted[index], accuracy: 0.5,
                "滚动后行 \(index) 帧高仍须＝采用高"
            )
        }
        print(
            "CHAIN-PASSES-SINGLE passes=\(vc.testSectionProviderCallCount) rows=\(expectedRows) content=\(steadySize.height)"
        )
    }

}
