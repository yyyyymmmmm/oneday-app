import OneDayCore
import OneDayDesign
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// §330（0.50.70 热修）三件的单元层验收，§332
/// （二次修复）题 1/题 2 换代后本文件同步换代；
/// 题 1 于 §374.8（换引擎步骤 5）再换代：触摸
/// 序列门退役、收敛为选区单键暂缓——装配层：
/// 选区在场行 reconfigure 暂存、清账后一拍恰
/// 落写一次；高度-only 变化不触发
/// reconfigure（回归断言）；
/// 题 2 承载换代——历经 delegate 内建通道
/// （§332）→控制器长按识别器＋自绘动作面（台账
/// 187）：落点不分工（文本内/外同发呈现请求）、
/// 选区在场行让路、动作项集与 186 菜单逐项同＋
/// cell 本体不挂 UIContextMenuInteraction；
/// 题 3 整行备忘——真实形态行集（含表格/工具卡/
/// 引用/审批/交付）预填后重复多趟（模拟滚动期
/// body 求值＋合成器每趟现建）实算计数不涨、高
/// 度逐值不变；账本翻转只失效其行；245 行形态同
/// 口径。
/// 覆盖边界（诚实标注）：装配层以句柄选区行键
/// 直写模拟选区在场驱动生产分流；原生面手势的
/// 端到端真触摸序列 CI 无有效
/// 信号（基线红族＋AX 环境所限，定因报告题 2 对
/// 账在案），流式进行中的双击/长按终判归用户真
/// 机（交卷清单）
@MainActor
final class ChatNativeHotfix330Tests: XCTestCase {
    private var window: UIWindow?
    private var controller: ChatRootViewController?
    private var handle: ChatNativeListHandle?

    override func tearDown() {
        window?.isHidden = true
        window = nil
        controller = nil
        handle = nil
        super.tearDown()
    }

    /// 装配与 ChatNativeListR3AssemblyTests 同式
    /// （窗口＋根 VC＋handle＋carrier 回调＋
    /// addChild 挂载）——控制器回调口只有
    /// ChatNativeListCallbacks 一处，不另设
    private func assemble() {
        let win = UIWindow(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874)
        )
        let root = UIViewController()
        win.rootViewController = root
        win.makeKeyAndVisible()
        let listHandle = ChatNativeListHandle()
        let list = ChatRootViewController()
        // §377（0.50.97 组版）：本套断言以 §329 逐行
        // section 构造寻址（section＝行／提供者计数），
        // 缺省翻真后经测试覆盖口钉旧构造；新构造等价
        // 由 ChatSwapStep3 五套＋生产链双形态把守
        list.testSingleSectionOverride = false
        list.handle = listHandle
        list.callbacks = ChatNativeListCallbacks(
            onScrollGeometry: {},
            onTopVisibleEntry: { _ in },
            onBlankTap: {}
        )
        listHandle.controller = list
        root.addChild(list)
        list.view.frame = root.view.bounds
        root.view.addSubview(list.view)
        list.didMove(toParent: root)
        root.view.layoutIfNeeded()
        window = win
        controller = list
        handle = listHandle
    }

    private func apply(_ rows: [ChatNativeRow]) {
        controller?.apply(
            rows: rows,
            layout: ChatNativeLayout(
                horizontalPadding: OneDayMetrics.pageGutter,
                topPadding: OneDayMetrics.spacingM,
                bottomPadding: 8,
                rowSpacing: OneDayMetrics.spacingL,
                arrowTrailing: OneDayMetrics.spacingM,
                arrowGapAboveComposer: 8,
                arrowSize: OneDayMetrics.minTapTarget
            ),
            topInset: 122,
            bottomMargin: 0,
            composerView: AnyView(
                Rectangle()
                    .fill(Color.gray)
                    .frame(height: 54)
            ),
            arrowView: AnyView(Color.clear)
        )
        window?.layoutIfNeeded()
    }

    private func drain(_ seconds: TimeInterval) {
        let exp = expectation(
            description: "drain \(seconds)"
        )
        DispatchQueue.main.asyncAfter(
            deadline: .now() + seconds
        ) { exp.fulfill() }
        wait(for: [exp], timeout: seconds + 10)
        window?.layoutIfNeeded()
    }

    private func hostingCell(
        at index: Int, file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> ChatNativeHostingCell {
        let cell = controller?.collectionView
            .cellForItem(
                at: IndexPath(item: 0, section: index)
            )
        return try XCTUnwrap(
            cell as? ChatNativeHostingCell,
            "section \(index) 应有托管 cell",
            file: file, line: line
        )
    }

    private func textRow(
        _ key: String, text: String,
        height: CGFloat = 60
    ) -> ChatNativeRow {
        ChatNativeRow(
            key: key, entryID: nil,
            revision: ChatNativeRowRevision(
                parts: [.text(text)]
            ),
            height: height,
            makeView: {
                AnyView(
                    Text(text)
                        .frame(
                            maxWidth: .infinity,
                            alignment: .leading
                        )
                )
            }
        )
    }

    // MARK: - 题 1：选区单键暂缓（§374.8，原 §332 序列门退役）

    /// 装配层：选区在场行当拍暂存、他行当拍落
    /// 写；选区清账（行键清零＋保护结束转达）后
    /// 经 flush 恰落写一次（生产读口＝cell 配置
    /// 普查）
    func testSelectionKeyDefersReconfigureUntilClear()
        throws
    {
        assemble()
        var rows = [
            textRow("a", text: "a-v1"),
            textRow("b", text: "b-v1"),
            textRow("c", text: "c-v1"),
        ]
        apply(rows)
        drain(0.6)
        let cellB = try hostingCell(at: 1)
        let cellC = try hostingCell(at: 2)
        let baseB = cellB.configureCount
        let baseC = cellC.configureCount
        handle?.selectionActiveRowKey = "b"
        rows[1] = textRow("b", text: "b-v2")
        rows[2] = textRow("c", text: "c-v2")
        apply(rows)
        XCTAssertEqual(
            cellC.configureCount, baseC + 1,
            "他行须当拍落写"
        )
        XCTAssertEqual(
            cellB.configureCount, baseB,
            "选区在场行 reconfigure 须暂存、不冲选区"
        )
        handle?.selectionActiveRowKey = nil
        handle?.noteSelectionProtectionEnded()
        drain(1.2)
        XCTAssertEqual(
            cellB.configureCount, baseB + 1,
            "选区清账后须恰落写一次"
        )
        XCTAssertEqual(cellB.configuredKey, "b")
    }

    /// 流式工况的形状：连发三拍修订（模拟流式期
    /// body 求值连拍），选区在场行全程零重配、他
    /// 行逐拍落写；清账后选区行只补写一次（最新
    /// 修订）
    func testStreamingPatsNeverReconfigureSelectionRow()
        throws
    {
        assemble()
        var rows = [
            textRow("a", text: "a-v1"),
            textRow("b", text: "b-v1"),
            textRow("c", text: "c-v1"),
        ]
        apply(rows)
        drain(0.6)
        let cellB = try hostingCell(at: 1)
        let cellC = try hostingCell(at: 2)
        let baseB = cellB.configureCount
        let baseC = cellC.configureCount
        handle?.selectionActiveRowKey = "b"
        for version in 2...4 {
            rows[1] = textRow(
                "b", text: "b-v\(version)"
            )
            rows[2] = textRow(
                "c", text: "c-v\(version)"
            )
            apply(rows)
        }
        XCTAssertEqual(
            cellB.configureCount, baseB,
            "连发拍下选区在场行须零重配"
        )
        XCTAssertEqual(
            cellC.configureCount, baseC + 3,
            "他行须逐拍落写"
        )
        handle?.selectionActiveRowKey = nil
        handle?.noteSelectionProtectionEnded()
        drain(1.2)
        XCTAssertEqual(
            cellB.configureCount, baseB + 1,
            "清账后只补写一次（最新修订）"
        )
    }

    /// 高度-only 变化（同键同修订、仅高变）：不触
    /// 发任何 reconfigure、帧高经落定拍落写新值
    /// （§330 备忘下滚动期高频路径的回归断言）
    func testHeightOnlyChangeDoesNotReconfigure()
        throws
    {
        assemble()
        var rows = [
            textRow("a", text: "a-v1"),
            textRow("b", text: "b-v1"),
            textRow("c", text: "c-v1"),
        ]
        apply(rows)
        drain(0.6)
        let counts = try (0..<3).map {
            try hostingCell(at: $0).configureCount
        }
        rows[1] = textRow(
            "b", text: "b-v1", height: 140
        )
        apply(rows)
        drain(0.6)
        for index in 0..<3 {
            XCTAssertEqual(
                try hostingCell(at: index)
                    .configureCount,
                counts[index],
                "高度-only 变化不许重配 section \(index)"
            )
        }
        let frame = controller?.collectionView
            .layoutAttributesForItem(
                at: IndexPath(item: 0, section: 1)
            )?.frame
        XCTAssertEqual(
            frame?.height ?? 0, 140, accuracy: 1,
            "帧高须落写新值"
        )
    }

    // MARK: - 题 2：菜单承载换代

    private struct MenuProbeTextHost:
        UIViewRepresentable
    {
        func makeUIView(
            context: Context
        ) -> UITextView {
            let textView = UITextView()
            textView.text =
                "按你说的顺序来，这是一段可选中的文字。"
            textView.isScrollEnabled = false
            textView.isEditable = false
            return textView
        }

        func updateUIView(
            _ uiView: UITextView, context: Context
        ) {}
    }

    private func firstTextView(
        in view: UIView
    ) -> UITextView? {
        if let textView = view as? UITextView {
            return textView
        }
        for subview in view.subviews {
            if let found = firstTextView(in: subview) {
                return found
            }
        }
        return nil
    }

    /// 台账 200 拆换：动作项集/序/图符以菜单数
    /// 据单源组装（ChatRowActionSheetData.
    /// actionItems）为准断言——与 186 菜单逐项
    /// 同。原「动作面触发」用例随控制器长按识别
    /// 器＋自绘面退役同批删除（呈现改系统上下文
    /// 菜单、由 UI 套件在真链路上验）
    func testMenuItemsMatchLegacySetAndOrder() {
        // 动作项集/序/图符：动作面单源组装为准（与
        // 186 的 UIMenu 断言逐项同集同序）
        let data = ChatRowActionSheetData(
            plainText: "你好",
            canReact: false, ownEmoji: nil,
            onPickReaction: { _ in },
            onReply: {}, onFork: {},
            onSelect: {}, onShare: {}
        )
        let items = data.actionItems()
        XCTAssertEqual(
            items.map(\.title),
            ["回复", "在旁聊里接着问", "复制", "选择", "分享"],
            "动作项集/序须与 186 菜单逐项同"
        )
        XCTAssertEqual(
            items.map(\.systemImage),
            [
                MessageActionSymbols.reply,
                MessageActionSymbols.fork,
                MessageActionSymbols.copy,
                MessageActionSymbols.select,
                MessageActionSymbols.share,
            ],
            "动作图符须与 186 菜单逐项同"
        )
    }

    /// 台账 186 组装口径（187 动作面沿革）：纯图片
    /// 消息（plainText 空）的动作列表——文本依赖项
    /// （复制/选择/分享）不出（不给假动作），条目
    /// 动作（回复/接问）在席；有文本时五项全序不
    /// 变（与上例同口径的组装层直证）
    func testActionSheetOmitsTextItemsWhenPlainTextEmpty() {
        let imageOnlyData = ChatRowActionSheetData(
            plainText: "",
            canReact: false, ownEmoji: nil,
            onPickReaction: { _ in },
            onReply: {}, onFork: {},
            onSelect: {}, onShare: {}
        )
        let titles = imageOnlyData.actionItems().map(\.title)
        XCTAssertEqual(
            titles, ["回复", "在旁聊里接着问"],
            "纯图片消息动作面只许条目动作，实得 \(titles)"
        )
    }

    // MARK: - 题 3：整行备忘

    private func makeComposer(
        ledger: ChatRowStateLedger =
            ChatRowStateLedger()
    ) -> ChatNativeRowHeightComposer {
        ChatNativeRowHeightComposer(
            screenWidth: 402,
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

    private func memoToolCardSample() -> ToolCard {
        ToolCard(
            id: "memo-tool-1", toolName: "terminal",
            category: .terminal,
            title: "运行命令",
            summary: "ls ~/workspace",
            result: "Documents\nDownloads",
            resultFailed: false,
            arguments: "{\"command\": \"ls\"}"
        )
    }

    /// 备忘行集：覆盖现行文本备忘未及的形态——表
    /// 格（网格/降级列表）/工具卡/引用/审批锚/交付/
    /// 远端文件/回响/委派回响/思考/代码/任务清单
    private func memoFacetEntries() -> [ChatEntry] {
        [
            ChatEntry(
                role: "user",
                content: "你好，今天服务器状态怎么样？",
                thread: nil
            ),
            ChatEntry(
                role: "user", content: "就按这个办",
                thread: nil,
                quote: MessageQuote(
                    role: "assistant",
                    content: "前文摘要：先备份，再迁移。"
                )
            ),
            ChatEntry(
                role: "user", content: "",
                thread: nil,
                remoteFilePaths: ["/opt/data/report.xlsx"]
            ),
            ChatEntry(
                role: "assistant",
                content:
                    "状态正常。**粗体结论**先行，其后是说明"
                    + "文字，包含一段较长的叙述用来撑开多行"
                    + "排版，看看换行与行距是否稳定。",
                thread: nil
            ),
            ChatEntry(
                role: "assistant",
                content:
                    "示例代码：\n\n```swift\n"
                    + "let value = compute(input)\n"
                    + "print(value)\n```",
                thread: nil
            ),
            ChatEntry(
                role: "assistant",
                content:
                    "| 名称 | 状态 | 备注 |\n"
                    + "| --- | --- | --- |\n"
                    + "| 甲服务 | 正常 | 延迟 12ms |\n"
                    + "| 乙服务 | 异常 | 正在排查 |",
                thread: nil
            ),
            ChatEntry(
                role: "assistant",
                content:
                    "| 甲 | 乙 | 丙 | 丁 | 戊 |\n"
                    + "| --- | --- | --- | --- | --- |\n"
                    + "| 一 | 二 | 三 | 四 | 五 |",
                thread: nil
            ),
            ChatEntry(
                role: "assistant",
                content:
                    "- [x] 已完成的事项\n"
                    + "- [ ] 待办的事项\n"
                    + "- 普通列表项",
                thread: nil
            ),
            ChatEntry(
                role: "assistant",
                content: "思考后的正文。",
                thread: nil,
                reasoning: "先查内存，再看容器日志。",
                reasoningSeconds: 3.2
            ),
            ChatEntry(
                role: "tool", content: "",
                thread: nil,
                toolCard: memoToolCardSample()
            ),
            ChatEntry(
                role: "assistant", content: "",
                thread: nil,
                remoteImagePaths: ["/opt/data/img.png"]
            ),
            ChatEntry(
                role: "assistant",
                content: "[[deliver:dlv_memo_1]]",
                thread: nil
            ),
            ChatEntry(
                role: "assistant", content: "",
                thread: nil, traceKey: "trace-memo",
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
                thread: nil, echoKey: "goal-memo"
            ),
            ChatEntry(
                role: "assistant", content: "",
                thread: nil,
                approvalKey: "wg:skills:rec-memo-1"
            ),
        ]
    }

    private func heights(
        of entries: [ChatEntry],
        composer: ChatNativeRowHeightComposer
    ) -> [CGFloat] {
        entries.map {
            composer.entryHeight($0, dividerText: nil)
        }
    }

    /// 预填一趟后（每行恰实算一次），其后每趟以
    /// 新建合成器重算（镜像 ChatView.nativeRows
    /// 每趟现建合成器的生产口径）实算增量恒 0、
    /// 高度逐值不变——滚动期不再每趟重算整行高
    func testRowMemoHitsAcrossPassesWithFreshComposers() {
        let entries = memoFacetEntries()
        ChatNativeRowHeightComposer
            .resetRowComputationCount()
        let first = heights(
            of: entries, composer: makeComposer()
        )
        XCTAssertEqual(
            ChatNativeRowHeightComposer
                .rowComputationCount,
            entries.count,
            "首趟每行恰实算一次"
        )
        for pass in 1...5 {
            let again = heights(
                of: entries, composer: makeComposer()
            )
            XCTAssertEqual(
                again, first,
                "第 \(pass) 趟高度须逐值不变"
            )
            XCTAssertEqual(
                ChatNativeRowHeightComposer
                    .rowComputationCount,
                entries.count,
                "第 \(pass) 趟须全命中、零实算"
            )
        }
    }

    /// 245 行形态（长会话量级）：预填后连过十趟
    /// 实算增量恒 0
    func testRowMemoScalesToLongConversation() {
        var entries: [ChatEntry] = []
        while entries.count < 245 {
            entries.append(contentsOf: memoFacetEntries())
        }
        entries = Array(entries.prefix(245))
        ChatNativeRowHeightComposer
            .resetRowComputationCount()
        let first = heights(
            of: entries, composer: makeComposer()
        )
        XCTAssertEqual(
            ChatNativeRowHeightComposer
                .rowComputationCount,
            entries.count,
            "245 行预填每行恰实算一次"
        )
        for _ in 1...10 {
            let again = heights(
                of: entries, composer: makeComposer()
            )
            XCTAssertEqual(again, first)
        }
        XCTAssertEqual(
            ChatNativeRowHeightComposer
                .rowComputationCount,
            entries.count,
            "十趟滚动模拟须零新增实算"
        )
    }

    /// 账本翻转只失效其行：工具条目展开覆盖翻转
    /// →该行恰重算一次且高变（展开更高）；未翻转
    /// 的合成器口径仍命中旧值；工具组同口径
    func testRowMemoInvalidatesOnlyOnLedgerFlip() {
        let card = memoToolCardSample()
        guard
            let toolEntry = memoFacetEntries().first(
                where: { $0.toolCard != nil }
            )
        else {
            XCTFail("行集须含工具条目")
            return
        }
        let collapsedLedger = ChatRowStateLedger()
        let expandedLedger = ChatRowStateLedger()
        expandedLedger.setExpansion(
            true,
            for: ChatRowStateKeys.toolEntry(
                toolEntry.id
            )
        )
        ChatNativeRowHeightComposer
            .resetRowComputationCount()
        let collapsed = makeComposer(
            ledger: collapsedLedger
        ).entryHeight(toolEntry, dividerText: nil)
        XCTAssertEqual(
            ChatNativeRowHeightComposer
                .rowComputationCount, 1
        )
        let expanded = makeComposer(
            ledger: expandedLedger
        ).entryHeight(toolEntry, dividerText: nil)
        XCTAssertEqual(
            ChatNativeRowHeightComposer
                .rowComputationCount, 2,
            "翻转后该行恰重算一次"
        )
        XCTAssertGreaterThan(
            expanded, collapsed, "展开态须更高"
        )
        let collapsedAgain = makeComposer(
            ledger: collapsedLedger
        ).entryHeight(toolEntry, dividerText: nil)
        XCTAssertEqual(collapsedAgain, collapsed)
        XCTAssertEqual(
            ChatNativeRowHeightComposer
                .rowComputationCount, 2,
            "未翻转口径仍命中、不重算"
        )
        // 工具组：同卡同组键，组展开覆盖翻转同理
        let groupKey = "tg-memo"
        let groupLedger = ChatRowStateLedger()
        // 键稳定性直断（R10 红定位）：两台新合成
        // 器对同组须产同键——不等时失败信息带出
        // 两键全文、可一段定位分歧所在
        let probeKey1 = makeComposer(
            ledger: groupLedger
        ).toolGroupMemoKey(
            cards: [card], groupKey: groupKey
        )
        let probeKey2 = makeComposer(
            ledger: groupLedger
        ).toolGroupMemoKey(
            cards: [card], groupKey: groupKey
        )
        XCTAssertEqual(
            probeKey1, probeKey2,
            "工具组备忘键须跨合成器稳定"
        )
        let groupCollapsed = makeComposer(
            ledger: groupLedger
        ).toolGroupHeight(cards: [card], groupKey: groupKey)
        XCTAssertNotNil(
            ChatNativeRowHeightComposer
                .cachedRowHeight(forKey: probeKey1),
            "首算后备忘须可按同键读回"
        )
        let groupCountAfterFirst =
            ChatNativeRowHeightComposer
                .rowComputationCount
        let groupAgain = makeComposer(
            ledger: groupLedger
        ).toolGroupHeight(cards: [card], groupKey: groupKey)
        XCTAssertEqual(groupAgain, groupCollapsed)
        XCTAssertEqual(
            ChatNativeRowHeightComposer
                .rowComputationCount,
            groupCountAfterFirst,
            "工具组未翻转须命中"
        )
        groupLedger.setExpansion(true, for: groupKey)
        _ = makeComposer(ledger: groupLedger)
            .toolGroupHeight(
                cards: [card], groupKey: groupKey
            )
        XCTAssertEqual(
            ChatNativeRowHeightComposer
                .rowComputationCount,
            groupCountAfterFirst + 1,
            "工具组翻转后恰重算一次"
        )
    }

}
