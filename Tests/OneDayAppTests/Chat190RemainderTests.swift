import OneDayCore
import OneDayDesign
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// 台账 190 留账包＋nanoMuse 列表三件＋台账 196
/// （DESIGN §335）验收：
/// ① displayText 单源助手——存在性开/关两态摘行
/// 与旧派生口径一致（产物/量测/呈现同文的地基）
/// ② 产物段下标与呈现段序列同位（结构段不在产
/// 物内）＋产物串入串色为 trait 动态色（双档解
/// 析与 Palette 令牌同值）
/// ③ 预计算级（助手行）：产物段高合成与确定高
/// 对拍；毒产物（伪段高）不入文本备忘（确路后
/// 读仍为真值）；用户/锚定行不适用回 nil
/// ④ 台账 196 §2.4：回响行高文字列宽按视图本
/// 体算术（HStack 三对 spacingS；诊断的时刻字
/// 阶子项经复核为 SwiftUI/UIKit 同档异名、不成
/// 立）——临界宽下旧式一行、新式两行，分界验
/// ⑤ 台账 196 修复方向 2：facet 快照器对锚定行
/// 跳过助手扫描支（文件 facet 恒空）、普通助手
/// 行照旧
/// ⑥ 高度缓存归布局层：同修订临界重喂不许把匣
/// 内确高打回（内容高不变）、修订变即失效
/// ⑦ 浏览期冻结覆盖减速空窗：delegate 浏览态
/// 在 isTracking/isDecelerating 双 false 的空窗
/// 拍内仍冻结喂入、停滚后放行
@MainActor
final class Chat190RemainderTests: XCTestCase {

    // MARK: - 夹具

    private func makeComposer(
        screenWidth: CGFloat = 402
    ) -> ChatNativeRowHeightComposer {
        ChatNativeRowHeightComposer(
            screenWidth: screenWidth,
            horizontalPadding: OneDayMetrics.pageGutter,
            sizeCategory: .large,
            boldText: false,
            displayScale: 3,
            agentDisplayName: "Hermes",
            emptyStateAvatarSize: 72,
            facets: ChatNativeRowFacets()
        )
    }

    override func setUp() {
        super.setUp()
        EntryScanMemo.removeAll()
    }

    // MARK: - ① displayText 单源

    func testAssistantDisplayTextSingleSource() {
        let content = """
            前文一行
            MEDIA:/opt/data/cache/images/img_a.png
            /opt/data/files/report.png
            后文一行
            """
        let entryID = UUID()
        let scans = EntryScanMemo.scans(
            entryID: entryID, content: content,
            remoteImagePaths: []
        )
        let stripped = ChatNativeRowHeightComposer
            .assistantDisplayText(
                entryID: entryID, scans: scans
            ) { $0 == "/opt/data/files/report.png" }
        XCTAssertFalse(
            stripped.contains("report.png"),
            "确证存在的独立行图片须被摘除：\(stripped)"
        )
        XCTAssertTrue(stripped.contains("前文一行"))
        XCTAssertTrue(stripped.contains("后文一行"))

        let kept = ChatNativeRowHeightComposer
            .assistantDisplayText(
                entryID: entryID, scans: scans
            ) { _ in false }
        XCTAssertTrue(
            kept.contains("report.png"),
            "未确证存在时独立行不许摘：\(kept)"
        )
    }

    // MARK: - ② 产物段对位与动态色

    func testProductSegmentsAlignAndColorsDynamic()
        async throws {
        let text = """
            第一段正文，包含 **粗体** 与链接。

            ```
            let x = 1
            ```

            > 引用一行
            > 引用二行

            第二段正文。
            """
        let style = LayoutStyleContext(
            sizeCategory: .large, boldText: false
        )
        let width = LayoutProductService.textWidth(
            isUser: false,
            screenWidth: UIScreen.main.bounds.width
        )
        let entryID = UUID()
        let product = await Task.detached {
            LayoutProductService.shared
                .productSynchronously(
                    entryID: entryID,
                    renderedText: text,
                    isUser: false,
                    width: width,
                    style: style
                )
        }.value
        let unwrapped = try XCTUnwrap(
            product, "产物同步生产须成功"
        )

        // 段对位：产物段下标＝呈现段序列中散文/引
        // 用段的下标全集，代码段（结构段）不在内
        let segments = MarkdownMessageAssembler
            .segments(for: text)
        var expectedIndices: Set<Int> = []
        for (index, segment) in segments.enumerated() {
            switch segment {
            case .prose, .quote:
                expectedIndices.insert(index)
            default:
                break
            }
        }
        XCTAssertEqual(
            Set(unwrapped.presentationSegmentStrings().keys),
            expectedIndices,
            "产物段下标须与呈现段同位"
        )
        XCTAssertEqual(
            unwrapped.structuralSegmentCount,
            segments.count - expectedIndices.count
        )

        // 动态色：首段串前景色在明/暗 trait 下解析
        // 出 Palette.bodyInk 的双档值（静态定格色
        // 双档同值、在此现形）
        let first = try XCTUnwrap(
            unwrapped.segments.first?.attributed
        )
        let fg = try XCTUnwrap(
            first.attribute(
                .foregroundColor, at: 0,
                effectiveRange: nil
            ) as? UIColor,
            "产物串须带前景色"
        )
        let light = fg.resolvedColor(
            with: UITraitCollection(
                userInterfaceStyle: .light
            )
        )
        let dark = fg.resolvedColor(
            with: UITraitCollection(
                userInterfaceStyle: .dark
            )
        )
        var lightEnv = EnvironmentValues()
        lightEnv.colorScheme = .light
        var darkEnv = EnvironmentValues()
        darkEnv.colorScheme = .dark
        let expectedLight = UIColor(
            cgColor: Palette.bodyInk
                .resolve(in: lightEnv).cgColor
        )
        let expectedDark = UIColor(
            cgColor: Palette.bodyInk
                .resolve(in: darkEnv).cgColor
        )
        XCTAssertTrue(
            light.isEqual(expectedLight),
            "浅档解析须与令牌同值"
        )
        XCTAssertTrue(
            dark.isEqual(expectedDark),
            "暗档解析须与令牌同值（动态色）"
        )
        XCTAssertFalse(
            light.isEqual(dark),
            "双档同值＝静态定格色、非动态色"
        )
    }

    // MARK: - ③ 预计算级

    private func makeProduct(
        entryID: UUID, text: String,
        segmentHeight: CGFloat,
        assistantTextWidth: CGFloat
    ) -> LayoutProduct {
        LayoutProduct(
            key: LayoutProductKey(
                entryID: entryID, content: text,
                width: Double(assistantTextWidth),
                style: LayoutStyleContext(
                    sizeCategory: .large, boldText: false
                ).coreKey
            ),
            segments: [
                LayoutSegmentProduct(
                    segmentIndex: 0, kind: .prose,
                    attributed: NSAttributedString(
                        string: text
                    ),
                    height: Double(segmentHeight)
                ),
            ],
            structuralSegmentCount: 0
        )
    }

    func testPrecomputedMatchesExactAndRejectsOthers() {
        let composer = makeComposer()
        let text = "这是一段足够长的助手正文，用来验证"
            + "预计算与确定高对拍，全文没有任何结构标记。"
        let entry = ChatEntry(
            role: "assistant", content: text, thread: nil
        )
        let snapshot = ChatEntryHeightSnapshot(entry)
        let exact = composer.entryHeightCore(
            snapshot, dividerText: nil
        )
        let product = makeProduct(
            entryID: entry.id, text: text,
            segmentHeight: composer.markdownHeight(text),
            assistantTextWidth: composer.assistantTextWidth
        )
        let precomputed = composer.precomputedEntryHeight(
            for: entry, dividerText: nil, product: product
        )
        XCTAssertEqual(
            try XCTUnwrap(precomputed), exact,
            accuracy: 0.6,
            "预计算（产物段高＋公式）须与确定高对拍"
        )

        // 不适用面：用户行（宽口径闸）与锚定行回 nil
        let userEntry = ChatEntry(
            role: "user", content: text, thread: nil
        )
        XCTAssertNil(
            composer.precomputedEntryHeight(
                for: userEntry, dividerText: nil,
                product: product
            ),
            "用户行不走预计算（产物宽差 40）"
        )
        let traceEntry = ChatEntry(
            role: "assistant", content: text, thread: nil
        )
        traceEntry.traceKey = "trace:test"
        XCTAssertNil(
            composer.precomputedEntryHeight(
                for: traceEntry, dividerText: nil,
                product: product
            ),
            "锚定行无产物口径、回 nil"
        )
    }

    func testPrecomputeDoesNotPoisonExactMemo() {
        let composer = makeComposer()
        let text = "另一段正文，专供毒产物检验，预计算"
            + "不得污染确定路的文本备忘。"
        let entry = ChatEntry(
            role: "assistant", content: text, thread: nil
        )
        let poison = makeProduct(
            entryID: entry.id, text: text,
            segmentHeight: 9999,
            assistantTextWidth: composer.assistantTextWidth
        )
        let precomputed = composer.precomputedEntryHeight(
            for: entry, dividerText: nil, product: poison
        )
        XCTAssertGreaterThan(
            try XCTUnwrap(precomputed), 9000,
            "毒产物段高须真实进入预计算（验覆盖在席）"
        )
        // 确路后读：同合成器与新合成器读到的文本备
        // 忘都必须是全量量测真值、非毒值
        let fresh = makeComposer()
        let truth = fresh.markdownHeight(text)
        XCTAssertLessThan(truth, 1000)
        XCTAssertEqual(
            composer.markdownHeight(text), truth,
            accuracy: 0.6,
            "预计算混合总高禁入文本备忘"
        )
    }

    // MARK: - ④ 196 §2.4 回响算术

    func testTraceEchoHeightCountsAllHStackGaps() {
        let traits = UITraitCollection(
            preferredContentSizeCategory: .large
        )
        let footnoteFont = UIFont.preferredFont(
            forTextStyle: .footnote, compatibleWith: traits
        )
        // 时刻字阶：视图 SwiftUI .caption 与 UIKit
        // .caption1 同档异名——公式两侧同用
        // caption1 计宽（196 §2.4 字阶子项复核结论）
        let caption1Font = UIFont.preferredFont(
            forTextStyle: .caption1, compatibleWith: traits
        )
        func lineWidth(_ s: String, _ f: UIFont) -> CGFloat {
            NSAttributedString(
                string: s, attributes: [.font: f]
            ).size().width
        }
        // 时刻文案：固定当日 14:05（与合成器
        // traceEchoTimeText 同式生成）
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let created = calendar.date(
            byAdding: DateComponents(hour: 14, minute: 5),
            to: today
        )!
        let timeText = created.formatted(
            .dateTime.hour().minute()
        )
        let headline = String(
            repeating: "测", count: 20
        )
        let headlineWidth = lineWidth(headline, footnoteFont)
        // 列宽标定：旧式（扣 2×spacingS）下主句
        // 恰一行（宽余 2）；新式（扣 3×spacingS）
        // 窄一份 spacingS、主句折两行——以总高
        // 是否跨过两行门槛分界
        let contentWidth = headlineWidth + 2
            + OneDayMetrics.spacingM * 2 + 13
            + OneDayMetrics.spacingS * 2
            + lineWidth(timeText, caption1Font)
        let composer = makeComposer(
            screenWidth: contentWidth + 40
        )
        let entry = ChatEntry(
            role: "assistant", content: headline,
            thread: nil
        )
        entry.traceKey = "trace:test"
        entry.createdAt = created
        entry.traceEchoData = try? JSONEncoder().encode(
            TraceEchoSnapshot(
                headline: headline, targetLabel: "",
                openableSessionID: nil, outcome: "",
                isFailed: false
            )
        )
        let total = composer.traceEchoHeight(
            ChatEntryHeightSnapshot(entry)
        )
        XCTAssertGreaterThan(
            total,
            OneDayMetrics.spacingS * 2
                + footnoteFont.lineHeight * 1.6,
            "新式列宽下主句须折两行（总高 \(total)）"
        )
        // 宽屏对照：列宽充裕时回一行高
        let wide = makeComposer(screenWidth: 900)
        let wideTotal = wide.traceEchoHeight(
            ChatEntryHeightSnapshot(entry)
        )
        XCTAssertLessThan(
            wideTotal,
            OneDayMetrics.spacingS * 2
                + footnoteFont.lineHeight * 1.6,
            "宽列下主句须为一行（总高 \(wideTotal)）"
        )
        XCTAssertGreaterThan(total, wideTotal)
    }

    // MARK: - ⑤ 196 facet 跳支

    func testEntryFacetsSkipScanBranchForAnchoredRows() {
        let ledger = ChatRowStateLedger()
        let hubStore = AppState().sharedHubStore()
        let path = "/opt/data/files/report.png"
        let content = "处理完成\n\(path)"
        // 对照种子：recordFileState 的记录分两路——
        // 存在性账未落时不记 fileExistences、元数据
        // 大小到手即记 fileSizes；以 record 同步种
        // 大小账，对照断言钉 fileSizes（存在性账无
        // 同步种子口、不断言其非空）
        FileMetadataStore.shared.record(
            path: path, size: 123, modifiedAt: nil
        )
        let trace = ChatEntry(
            role: "assistant", content: content, thread: nil
        )
        trace.traceKey = "trace:test"
        let traceFacets = ChatNativeRowFacetSnapshotter
            .entryFacets(
                for: trace, ledger: ledger,
                hubStore: hubStore
            )
        XCTAssertTrue(
            traceFacets.fileExistences.isEmpty
                && traceFacets.fileSizes.isEmpty,
            "锚定行须跳过助手扫描支（文件 facet 恒空）"
        )
        let plain = ChatEntry(
            role: "assistant", content: content, thread: nil
        )
        let plainFacets = ChatNativeRowFacetSnapshotter
            .entryFacets(
                for: plain, ledger: ledger,
                hubStore: hubStore
            )
        XCTAssertEqual(
            plainFacets.fileSizes[path], 123,
            "普通助手行对照：文件 facet 照旧记录"
        )
    }
}

/// §335 装配级验收（⑥ 布局匣确高备忘／⑦ 浏览
/// 期冻结空窗）：真壳装配（窗口→根→承载）＋定
/// 高回喂行——本组验的是布局层状态机（匣内高
/// 与冻结闸门），行高由回喂值 .absolute 决定、
/// 与行内容拟合无关，故行内容用极简视图（与装
/// 配族以真实行内容验拟合的口径分工不同、此处
/// 只认 contentSize 读数）
@MainActor
final class Chat190RemainderAssemblyTests: XCTestCase {

    private let windowW: CGFloat = 402
    private let windowH: CGFloat = 874

    private var window: UIWindow!
    private var controller: ChatRootViewController!
    private var handle: ChatNativeListHandle!

    override func tearDown() {
        window?.isHidden = true
        window = nil
        controller = nil
        handle = nil
        super.tearDown()
    }

    private func assemble() {
        window = UIWindow(
            frame: CGRect(
                x: 0, y: 0, width: windowW, height: windowH
            )
        )
        let root = UIViewController()
        window.rootViewController = root
        window.makeKeyAndVisible()
        handle = ChatNativeListHandle()
        controller = ChatRootViewController()
        controller.handle = handle
        controller.callbacks = ChatNativeListCallbacks(
            onScrollGeometry: {},
            onTopVisibleEntry: { _ in },
            onBlankTap: {}
        )
        handle.controller = controller
        root.addChild(controller)
        controller.view.frame = root.view.bounds
        root.view.addSubview(controller.view)
        controller.didMove(toParent: root)
        root.view.layoutIfNeeded()
    }

    private func fixedRow(
        _ key: String, revision: String,
        height: CGFloat, provisional: Bool
    ) -> ChatNativeRow {
        ChatNativeRow(
            key: key, entryID: nil,
            revision: ChatNativeRowRevision(
                parts: [.text(revision)]
            ),
            height: height,
            heightIsProvisional: provisional,
            makeView: { AnyView(Text("行")) }
        )
    }

    private func apply(rows: [ChatNativeRow]) {
        controller.apply(
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
            bottomMargin: 16,
            composerView: AnyView(Color.clear),
            arrowView: AnyView(Color.clear)
        )
        window.layoutIfNeeded()
    }

    private func drain(_ seconds: TimeInterval = 1.2) {
        let exp = expectation(description: "drain")
        DispatchQueue.main.asyncAfter(
            deadline: .now() + seconds
        ) { exp.fulfill() }
        wait(for: [exp], timeout: seconds + 10)
        window.layoutIfNeeded()
    }

    private var contentHeight: CGFloat {
        controller.collectionView.contentSize.height
    }

    // MARK: - ⑥ 布局匣确高备忘

    func testLayoutBoxRestoresExactHeightForSameRevision() {
        assemble()
        apply(rows: [
            fixedRow("a", revision: "v1", height: 300,
                     provisional: false),
        ])
        drain()
        let exactTotal = contentHeight
        XCTAssertGreaterThan(exactTotal, 300)

        // 同修订以临界高重喂（模拟上游备忘逐出后
        // 的量测台口径）：匣内确高须回填、内容高
        // 不许跌回临界值
        apply(rows: [
            fixedRow("a", revision: "v1", height: 120,
                     provisional: true),
        ])
        drain()
        XCTAssertEqual(
            contentHeight, exactTotal, accuracy: 1.0,
            "同修订临界重喂不许打回匣内确高"
        )

        // 修订变：旧确高失效、新临界值照喂
        apply(rows: [
            fixedRow("a", revision: "v2", height: 120,
                     provisional: true),
        ])
        drain()
        XCTAssertEqual(
            contentHeight, exactTotal - 180,
            accuracy: 1.0,
            "修订变后确高备忘须失效"
        )
    }

    // MARK: - ⑦ 浏览期冻结空窗

    func testBrowsingFreezeCoversDecelerationGap() {
        assemble()
        apply(rows: [
            fixedRow("a", revision: "v1", height: 200,
                     provisional: false),
        ])
        drain()
        let settled = contentHeight

        // 空窗构造：delegate 已报拖动开始、集合视
        // 图旗标双 false（无真实触摸）——旧口径两
        // 道闸门在此拍都会放行施工
        let cv = controller.collectionView
        controller.scrollViewWillBeginDragging(cv)
        XCTAssertFalse(cv.isTracking)
        XCTAssertFalse(cv.isDecelerating)

        apply(rows: [
            fixedRow("a", revision: "v1", height: 380,
                     provisional: false),
        ])
        drain(0.4)
        XCTAssertEqual(
            contentHeight, settled, accuracy: 1.0,
            "浏览态内喂入只许记账、不许施工"
        )

        // 离屏将减速：空窗延续（减速未开始的拍）
        controller.scrollViewDidEndDragging(
            cv, willDecelerate: true
        )
        drain(0.4)
        XCTAssertEqual(
            contentHeight, settled, accuracy: 1.0,
            "减速空窗内仍须冻结"
        )

        // 减速落定：浏览结束、记账喂入放行施工
        controller.scrollViewDidEndDecelerating(cv)
        drain()
        XCTAssertEqual(
            contentHeight, settled + 180, accuracy: 1.0,
            "停滚后记账喂入须落写"
        )
    }
}
