import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp
import OneDayCore
import OneDayDesign

/// §362（流畅度专项 S2）行构建增量化钉测：
/// ①等价——备忘路（快照验证＋账面前缀＋facet 穿
/// 线）与全量路（entryBase／entry／entryMemoKey
/// 旧现算）逐行逐字段相等，含流式中途态、编辑重
/// 发后（同 id 换对象）、量测回填后稳态三态；
/// ②逐字段敏感性——entryBase 入账字段任一变更，
/// 快照必变、备忘必失效、修订必变且与全量路同值
/// （漏折防线：字段集增减在此先红）；
/// ③计数对账——稳态趟全命中、单行变更只多一次
/// 重建（成本只随变化行涨的账面证据）；
/// ④同口径量测——600KB 量级合成会话下全量趟 vs
/// 增量稳态趟 vs 单行变化趟（模拟器相对值、实验
/// 室口径，真机绝对值以探活报告第四节补测为准）
@MainActor
final class RowIncrementalEquivalenceS2Tests: XCTestCase {

    private func makeComposer()
        -> ChatNativeRowHeightComposer
    {
        // 合成器本体不持备忘（穿线经 entryMemoKey
        // 的 buildProducts 入参）；本工厂口径与
        // ChatLagFeedLayerTests 的 makeComposer
        // 逐值同（同 ledger/hubStore 读面）
        ChatNativeRowHeightComposer(
            screenWidth: 402,
            horizontalPadding: OneDayMetrics.pageGutter,
            sizeCategory: .large,
            boldText: false,
            displayScale: 3,
            ledger: ChatRowStateLedger(),
            hubStore: AppState().sharedHubStore(),
            agentDisplayName: "Hermes",
            emptyStateAvatarSize: 72
        )
    }

    /// 全字段富条目：entryBase 入账字段逐项在席
    private func makeRichEntry() -> ChatEntry {
        let entry = ChatEntry(
            role: "assistant",
            content: "Alpha 正文，含中文与 English、`code` 片段。",
            thread: nil,
            reasoning: "思考原文一段。",
            reasoningSeconds: 3.5
        )
        entry.imageData = Data(repeating: 7, count: 100)
        entry.imageDatasData = try? JSONEncoder().encode(
            [Data(repeating: 8, count: 50)]
        )
        entry.quoteRole = "user"
        entry.quoteContent = "被引原文"
        entry.feedPostID = "post-1"
        entry.feedPostTitle = "动态标题"
        entry.feedPostBody = "动态正文"
        entry.feedPostSource = "动态来源"
        entry.ideaQuoteID = "idea-1"
        entry.ideaQuoteTitle = "点子标题"
        entry.ideaQuoteBody = "点子正文"
        entry.fileQuoteName = "报告.pdf"
        entry.fileQuotePath = "/docs/报告.pdf"
        entry.goalQuoteCategory = "work"
        entry.toolCardData = Data("{\"tool\":\"web_search\"}".utf8)
        entry.remoteImagePathsData = try? JSONEncoder().encode(
            ["https://example.com/a.png"]
        )
        entry.remoteFilePathsData = try? JSONEncoder().encode(
            ["/files/b.pdf"]
        )
        entry.echoKey = nil
        entry.approvalKey = nil
        entry.traceKey = nil
        entry.traceEchoData = Data([1, 2, 3])
        entry.serverRowID = 42
        entry.reactionsData = Data([9, 9])
        entry.sendFailed = false
        entry.sendStateRaw = "sent"
        entry.deliveryState = nil
        entry.createdAt = Date(
            timeIntervalSinceReferenceDate: 780_000_000
        )
        return entry
    }

    // MARK: - ① 等价：基段／全修订／备忘键

    func testMemoBaseRevisionEqualsLegacyEntryBase() {
        let memo = ChatEntryRowBuildMemo()
        let entry = makeRichEntry()
        for divider in [nil, "今天 09:41", "昨天"] as [String?] {
            for unread in [false, true] {
                XCTAssertEqual(
                    memo.baseRevision(
                        for: entry, dividerText: divider,
                        showsUnreadDivider: unread
                    ),
                    ChatNativeRowRevision.entryBase(
                        entry, dividerText: divider,
                        showsUnreadDivider: unread
                    ),
                    "基段须逐值同（divider=\(divider ?? "nil") unread=\(unread)）"
                )
                XCTAssertEqual(
                    memo.entryRevision(
                        for: entry, dividerText: divider,
                        highlighted: true, styleKey: "style-a",
                        showsUnreadDivider: unread
                    ),
                    ChatNativeRowRevision.entry(
                        entry, dividerText: divider,
                        highlighted: true, styleKey: "style-a",
                        showsUnreadDivider: unread
                    ),
                    "全修订须逐值同"
                )
            }
        }
    }

    func testMemoKeyWithProductsEqualsLegacyPaths() {
        let composer = makeComposer()
        let memo = ChatEntryRowBuildMemo()
        var entries: [ChatEntry] = []
        // 助手行（带路径/MEDIA 扫描面）
        let assistant = ChatEntry(
            role: "assistant",
            content: "结论如下。\n/Users/test/报告.pdf\nMEDIA:/Users/test/图.png\n以上。",
            thread: nil,
            remoteImagePaths: ["https://example.com/x.png"]
        )
        entries.append(assistant)
        // 用户带图行
        let user = ChatEntry(
            role: "user", content: "带图消息", thread: nil,
            imageDatas: [Data(repeating: 3, count: 1_000)]
        )
        entries.append(user)
        // 审批锚行
        let approval = makeRichEntry()
        approval.role = "assistant"
        approval.content = ""
        approval.approvalKey = "wg:writegate:42"
        entries.append(approval)
        // 留痕回响行
        let trace = makeRichEntry()
        trace.traceKey = "trace:abc"
        entries.append(trace)
        // 回响行
        let echo = makeRichEntry()
        echo.echoKey = "goal:xyz"
        entries.append(echo)
        // 工具行
        let tool = ChatEntry(role: "tool", content: "", thread: nil)
        tool.toolCardData = Data(
            "{\"tool\":\"web_search\",\"title\":\"检索\"}".utf8
        )
        entries.append(tool)

        for entry in entries {
            let legacyBase = ChatNativeRowRevision.entryBase(
                entry, dividerText: "今天 09:41",
                showsUnreadDivider: false
            )
            let legacyKey = composer.entryMemoKey(
                baseRevision: legacyBase, entry: entry
            )
            let products = memo.products(for: entry)
            let memoBase = memo.baseRevision(
                products: products, dividerText: "今天 09:41",
                showsUnreadDivider: false
            )
            XCTAssertEqual(memoBase, legacyBase)
            let threadedKey = composer.entryMemoKey(
                baseRevision: memoBase, entry: entry,
                buildProducts: products
            )
            XCTAssertEqual(
                threadedKey, legacyKey,
                "穿线备忘键须与旧现算逐字同（role=\(entry.role)）"
            )
            // 原路径（entryMemoKey(for:) 内部重建基段）同键
            XCTAssertEqual(
                composer.entryMemoKey(
                    for: entry, dividerText: "今天 09:41",
                    showsUnreadDivider: false
                ),
                legacyKey,
                "entryMemoKey(for:) 与基段入参版须逐字同键"
            )
            // facet 扫描派生直取与 EntryScanMemo 现算同值
            let lists = ChatEntryRowBuildMemo.facetScanLists(
                products: products, entry: entry
            )
            XCTAssertEqual(
                lists.deliveryIDs,
                EntryScanMemo.scans(
                    entryID: entry.id, content: entry.content,
                    remoteImagePaths: entry.remoteImagePaths
                ).delivery.deliveryIDs
            )
            XCTAssertEqual(
                lists.paths,
                EntryScanMemo.facetPaths(
                    entryID: entry.id, content: entry.content,
                    remoteImagePaths: entry.remoteImagePaths
                )
            )
        }
    }

    // MARK: - ② 逐字段敏感性（漏折防线）

    func testEveryEntryBaseFieldInvalidatesMemo() {
        let mutations: [(String, (ChatEntry) -> Void)] = [
            ("role", { $0.role = "user" }),
            ("content同长改字", { e in
                e.content = "B" + String(e.content.dropFirst())
            }),
            ("content增长", { $0.content += "多一字" }),
            ("imageData", { $0.imageData = Data(repeating: 9, count: 100) }),
            ("imageDatasData", { e in
                e.imageDatasData = try? JSONEncoder().encode(
                    [Data(repeating: 1, count: 60)]
                )
            }),
            ("quoteRole", { $0.quoteRole = "assistant" }),
            ("quoteContent", { $0.quoteContent = "另一段被引原文" }),
            ("feedPostID", { $0.feedPostID = "post-2" }),
            ("feedPostTitle", { $0.feedPostTitle = "另一标题" }),
            ("feedPostBody", { $0.feedPostBody = "另一正文" }),
            ("feedPostSource", { $0.feedPostSource = "另一来源" }),
            ("ideaQuoteID", { $0.ideaQuoteID = "idea-2" }),
            ("ideaQuoteTitle", { $0.ideaQuoteTitle = "另一标题" }),
            ("ideaQuoteBody", { $0.ideaQuoteBody = "另一正文" }),
            ("fileQuoteName", { $0.fileQuoteName = "另一.pdf" }),
            ("fileQuotePath", { $0.fileQuotePath = "/docs/另一.pdf" }),
            ("goalQuoteCategory", { $0.goalQuoteCategory = "life" }),
            ("reasoning", { $0.reasoning = "另一段思考原文。" }),
            ("reasoningSeconds", { $0.reasoningSeconds = 4.5 }),
            ("toolCardData", { $0.toolCardData = Data("{\"tool\":\"shell\"}".utf8) }),
            ("remoteImagePathsData", { e in
                e.remoteImagePathsData = try? JSONEncoder().encode(
                    ["https://example.com/b.png"]
                )
            }),
            ("remoteFilePathsData", { e in
                e.remoteFilePathsData = try? JSONEncoder().encode(
                    ["/files/c.pdf"]
                )
            }),
            ("echoKey", { $0.echoKey = "goal:abc" }),
            ("approvalKey", { $0.approvalKey = "wg:writegate:7" }),
            ("traceKey", { $0.traceKey = "trace:def" }),
            ("traceEchoData", { $0.traceEchoData = Data([4, 5]) }),
            ("serverRowID", { $0.serverRowID = 43 }),
            ("reactionsData", { $0.reactionsData = Data([8]) }),
            ("sendFailed", { $0.sendFailed = true }),
            ("sendStateRaw", { $0.sendStateRaw = "failed" }),
            ("deliveryState", { $0.deliveryState = "pending" }),
            ("createdAt", { e in
                e.createdAt = e.createdAt.addingTimeInterval(60)
            }),
        ]
        for (name, mutate) in mutations {
            let memo = ChatEntryRowBuildMemo()
            let entry = makeRichEntry()
            let before = memo.products(for: entry)
            let baseBefore = memo.baseRevision(
                products: before, dividerText: nil,
                showsUnreadDivider: false
            )
            XCTAssertEqual(memo.missCount, 1, "\(name)：首建应为 miss")
            mutate(entry)
            let after = memo.products(for: entry)
            XCTAssertEqual(
                memo.missCount, 2,
                "\(name)：字段变更后备忘必须失效重建"
            )
            XCTAssertNotEqual(
                before.snapshot, after.snapshot,
                "\(name)：快照必须随字段变更而变"
            )
            let baseAfter = memo.baseRevision(
                products: after, dividerText: nil,
                showsUnreadDivider: false
            )
            XCTAssertNotEqual(
                baseBefore, baseAfter,
                "\(name)：修订必须随字段变更而变（漏折）"
            )
            XCTAssertEqual(
                baseAfter,
                ChatNativeRowRevision.entryBase(
                    entry, dividerText: nil,
                    showsUnreadDivider: false
                ),
                "\(name)：变更后备忘路与全量路须逐值同"
            )
        }
    }

    /// 环境尾段（分隔／未读旗）不入快照：只换尾段
    /// 不触发重建、修订仍逐值同且随尾段变
    func testEnvironmentTailDoesNotInvalidate() {
        let memo = ChatEntryRowBuildMemo()
        let entry = makeRichEntry()
        let a = memo.baseRevision(
            for: entry, dividerText: "今天", showsUnreadDivider: false
        )
        let b = memo.baseRevision(
            for: entry, dividerText: "昨天", showsUnreadDivider: true
        )
        XCTAssertEqual(memo.missCount, 1, "尾段变化不许触发重建")
        XCTAssertEqual(memo.hitCount, 1)
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(
            b,
            ChatNativeRowRevision.entryBase(
                entry, dividerText: "昨天", showsUnreadDivider: true
            )
        )
    }

    // MARK: - ①三态：流式中途／编辑重发／回填稳态

    /// 流式中途态：同一条目对象正文逐拍生长，每拍
    /// 备忘路与全量路逐值同、每拍恰一次重建
    func testStreamingGrowthStaysEquivalent() {
        let memo = ChatEntryRowBuildMemo()
        let entry = ChatEntry(
            role: "assistant", content: "第一段。", thread: nil
        )
        var chunks = ["第一段。", "第一段。\n\n第二段生长中", "第一段。\n\n第二段生长中，长长长", "第一段。\n\n第二段生长完成。\n\n第三段。"]
        chunks.removeFirst()
        var expectedMisses = 1
        _ = memo.products(for: entry)
        for chunk in chunks {
            entry.content = chunk
            let products = memo.products(for: entry)
            expectedMisses += 1
            XCTAssertEqual(memo.missCount, expectedMisses)
            XCTAssertEqual(
                memo.baseRevision(
                    products: products, dividerText: nil,
                    showsUnreadDivider: false
                ),
                ChatNativeRowRevision.entryBase(
                    entry, dividerText: nil,
                    showsUnreadDivider: false
                ),
                "流式中途态每拍须逐值同"
            )
        }
    }

    /// 编辑重发后：同 id 换新对象（新内容）——快照
    /// 不等、备忘重建、不许吃旧账
    func testEditResendSameIDNewObjectRebuilds() {
        let memo = ChatEntryRowBuildMemo()
        let fixedID = UUID()
        let old = ChatEntry(
            role: "user", content: "旧稿内容", thread: nil
        )
        old.id = fixedID
        let oldBase = memo.baseRevision(
            for: old, dividerText: nil, showsUnreadDivider: false
        )
        let edited = ChatEntry(
            role: "user", content: "编辑后的新稿", thread: nil
        )
        edited.id = fixedID
        let newBase = memo.baseRevision(
            for: edited, dividerText: nil,
            showsUnreadDivider: false
        )
        XCTAssertEqual(memo.missCount, 2, "同 id 换对象换内容必须重建")
        XCTAssertNotEqual(oldBase, newBase)
        XCTAssertEqual(
            newBase,
            ChatNativeRowRevision.entryBase(
                edited, dividerText: nil,
                showsUnreadDivider: false
            )
        )
    }

    /// 量测回填后稳态：条目不变、趟数连跑——全命
    /// 中零重建、产物逐趟同值；prune 后重建但仍等价
    func testSteadyStateHitsAndPruneRebuilds() {
        let memo = ChatEntryRowBuildMemo()
        let entries = (0..<10).map { i in
            ChatEntry(
                role: i % 2 == 0 ? "assistant" : "user",
                content: "第 \(i) 条内容", thread: nil
            )
        }
        for entry in entries { _ = memo.products(for: entry) }
        XCTAssertEqual(memo.missCount, 10)
        memo.resetCounts()
        var firstPass: [ChatNativeRowRevision] = []
        for entry in entries {
            firstPass.append(
                memo.baseRevision(
                    for: entry, dividerText: nil,
                    showsUnreadDivider: false
                )
            )
        }
        XCTAssertEqual(memo.hitCount, 10, "稳态趟应全命中")
        XCTAssertEqual(memo.missCount, 0, "稳态趟应零重建")
        for (i, entry) in entries.enumerated() {
            XCTAssertEqual(
                memo.baseRevision(
                    for: entry, dividerText: nil,
                    showsUnreadDivider: false
                ),
                firstPass[i],
                "稳态产物逐趟须同值"
            )
        }
        memo.prune(keeping: [])
        _ = memo.products(for: entries[0])
        XCTAssertEqual(memo.missCount, 1, "prune 后必须重建")
        XCTAssertEqual(
            memo.baseRevision(
                for: entries[0], dividerText: nil,
                showsUnreadDivider: false
            ),
            firstPass[0],
            "重建产物与清账前须逐值同"
        )
    }

    // MARK: - ④ 同口径量测（实验室口径）

    /// 合成会话：300 条、正文＋思考合计约 600KB
    /// （与探活/施工前探针同配方）
    private func makeSession(textScale: Int = 1) -> [ChatEntry] {
        var entries: [ChatEntry] = []
        let baseDate = Date(timeIntervalSinceReferenceDate: 780_000_000)
        let assistantChunk = String(
            repeating: "这是助手正文的一段，包含中文与 English words 以及 `code` 片段，用来填充真实量级的文本。\n",
            count: 16 * textScale
        )
        let reasoningChunk = String(
            repeating: "思考过程片段：先分解问题，再逐项核对约束，最后组织答案。\n",
            count: 10 * textScale
        )
        for i in 0..<300 {
            let created = baseDate.addingTimeInterval(Double(i) * 47)
            switch i % 10 {
            case 0, 2, 4, 6:
                let e = ChatEntry(
                    role: "assistant",
                    content: assistantChunk + "［第\(i)条］"
                        + assistantChunk,
                    thread: nil,
                    reasoning: i % 4 == 0
                        ? reasoningChunk + "［思\(i)］" + reasoningChunk
                        : nil,
                    reasoningSeconds: i % 4 == 0 ? 3.5 : nil
                )
                e.createdAt = created
                entries.append(e)
            case 8:
                let e = ChatEntry(role: "tool", content: "", thread: nil)
                e.createdAt = created
                e.toolCardData = Data(
                    String(
                        repeating: "{\"tool\":\"web_search\",\"args\":\"填充字段填充字段\"}",
                        count: 12
                    ).utf8
                )
                entries.append(e)
            default:
                if i == 55 || i == 155 {
                    let e = ChatEntry(
                        role: "user",
                        content: "带图消息 \(i)",
                        thread: nil,
                        imageDatas: [
                            Data(repeating: 0xC1, count: 800_000),
                            Data(repeating: 0xC2, count: 200_000),
                        ]
                    )
                    e.createdAt = created
                    entries.append(e)
                } else {
                    let e = ChatEntry(
                        role: "user",
                        content: "用户提问第 \(i) 条："
                            + String(
                                repeating: "这是一个中等长度的问题描述。",
                                count: 6 * textScale
                            ),
                        thread: nil
                    )
                    e.createdAt = created
                    entries.append(e)
                }
            }
        }
        return entries
    }

    private func benchBest(
        passes: Int = 5, _ body: () -> Int
    ) -> UInt64 {
        _ = body()
        var best = UInt64.max
        var sink = 0
        for _ in 0..<passes {
            let start = DispatchTime.now().uptimeNanoseconds
            sink += body()
            best = min(
                best, DispatchTime.now().uptimeNanoseconds - start
            )
        }
        XCTAssertGreaterThan(sink, 0)
        return best
    }

    func testPassCostIncrementalVsLegacy() {
        let composer = makeComposer()
        let entries = makeSession()
        let totalText = entries.reduce(0) {
            $0 + $1.content.utf8.count
                + ($1.reasoning?.utf8.count ?? 0)
        }

        // 全量趟（修前口径：entryBase＋entryMemoKey 旧现算）
        let legacyNs = benchBest {
            var n = 0
            for e in entries {
                let base = ChatNativeRowRevision.entryBase(
                    e, dividerText: nil, showsUnreadDivider: false
                )
                n += composer.entryMemoKey(
                    baseRevision: base, entry: e
                ).count
            }
            return n
        }

        // 增量稳态趟（备忘已热：验证＋账面组装）
        let memo = ChatEntryRowBuildMemo()
        for e in entries { _ = memo.products(for: e) }
        let steadyNs = benchBest {
            var n = 0
            for e in entries {
                let products = memo.products(for: e)
                let base = memo.baseRevision(
                    products: products, dividerText: nil,
                    showsUnreadDivider: false
                )
                n += composer.entryMemoKey(
                    baseRevision: base, entry: e,
                    buildProducts: products
                ).count
            }
            return n
        }
        XCTAssertEqual(memo.missCount, 300, "稳态趟前只有首建 miss")
        XCTAssertGreaterThanOrEqual(memo.hitCount, 300)

        // 单行变化趟：一行正文翻转（改一字再改回，
        // 每趟恰一行变），其余行全验证命中
        let target = entries[100]
        let original = target.content
        var flip = false
        let singleChangeNs = benchBest {
            flip.toggle()
            target.content = flip ? original + "。" : original
            var n = 0
            for e in entries {
                let products = memo.products(for: e)
                let base = memo.baseRevision(
                    products: products, dividerText: nil,
                    showsUnreadDivider: false
                )
                n += composer.entryMemoKey(
                    baseRevision: base, entry: e,
                    buildProducts: products
                ).count
            }
            return n
        }
        target.content = original

        print(
            "S2 量测（实验室口径）：合成会话 300 条／正文＋思考 "
                + "\(totalText) 字节；全量趟 \(legacyNs / 1_000)µs；"
                + "增量稳态趟 \(steadyNs / 1_000)µs；"
                + "单行变化趟 \(singleChangeNs / 1_000)µs"
        )
        XCTAssertLessThan(
            steadyNs, legacyNs / 3,
            "增量稳态趟须显著低于全量趟（全量 \(legacyNs)ns vs 稳态 \(steadyNs)ns）"
        )
        XCTAssertLessThan(
            singleChangeNs, legacyNs / 3,
            "单行变化趟须接近稳态趟、不许随全量付费（全量 \(legacyNs)ns vs 单行 \(singleChangeNs)ns）"
        )

        // 文本量脱钩：同行数、文本 ×4——稳态趟不许
        // 随文本量同比例涨，全量趟则显著涨（对照）
        let bigEntries = makeSession(textScale: 4)
        let bigLegacyNs = benchBest {
            var n = 0
            for e in bigEntries {
                let base = ChatNativeRowRevision.entryBase(
                    e, dividerText: nil, showsUnreadDivider: false
                )
                n += composer.entryMemoKey(
                    baseRevision: base, entry: e
                ).count
            }
            return n
        }
        let bigMemo = ChatEntryRowBuildMemo()
        for e in bigEntries { _ = bigMemo.products(for: e) }
        let bigSteadyNs = benchBest {
            var n = 0
            for e in bigEntries {
                let products = bigMemo.products(for: e)
                let base = bigMemo.baseRevision(
                    products: products, dividerText: nil,
                    showsUnreadDivider: false
                )
                n += composer.entryMemoKey(
                    baseRevision: base, entry: e,
                    buildProducts: products
                ).count
            }
            return n
        }
        print(
            "S2 量测（文本×4 对照）：全量趟 \(bigLegacyNs / 1_000)µs；"
                + "增量稳态趟 \(bigSteadyNs / 1_000)µs"
        )
        XCTAssertGreaterThan(
            bigLegacyNs, legacyNs * 3 / 2,
            "全量趟应随文本量显著涨（对照组须成立）"
        )
        XCTAssertLessThan(
            bigSteadyNs, steadyNs * 2,
            "增量稳态趟不许随文本量同比例涨（稳态 \(steadyNs)ns vs ×4 文本 \(bigSteadyNs)ns）"
        )
    }
}
