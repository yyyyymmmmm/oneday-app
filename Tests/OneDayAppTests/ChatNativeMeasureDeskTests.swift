import OneDayCore
import OneDayDesign
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// §331（0.50.70 热修题 3 根治）验收：
/// ① 对拍——量测工单（主线程快照 facet＋条目、
/// 后台队列以 §251 量测池整行量测）与现行同步
/// 合成逐行同高（容差取影子账既定一致口径的整
/// 行放宽值 2.0pt；文本原语级对拍另以 1.0pt 钉
/// 住，见 ③）——快照枚举漏一项即在此现形；
/// ② 量测台——未命中回兜底＋needsJob、投单后
/// 回填缓存＋发布代次 bump、再读命中确定高；
/// 同键工单去重（组装/执行都只一次）；
/// ③ 量测原语——ChatNativeTextMeasure 主线
/// 程（量测视图）与后台（量测池每线栈）逐值
/// 对拍，含空串口径（后台以字体行高补、与视
/// 图同定义）与自然宽
@MainActor
final class ChatNativeMeasureDeskTests: XCTestCase {
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

    private func parityEntries() -> [ChatEntry] {
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
                toolCard: ToolCard(
                    id: "parity-tool-1",
                    toolName: "terminal",
                    category: .terminal,
                    title: "运行命令",
                    summary: "ls ~/workspace",
                    result: "Documents\nDownloads",
                    resultFailed: false,
                    arguments: "{\"command\": \"ls\"}"
                )
            ),
            ChatEntry(
                role: "assistant", content: "",
                thread: nil,
                remoteImagePaths: ["/opt/data/img.png"]
            ),
            ChatEntry(
                role: "assistant",
                content: "[[deliver:dlv_parity_1]]",
                thread: nil
            ),
            ChatEntry(
                role: "assistant", content: "",
                thread: nil, traceKey: "trace-parity",
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
                thread: nil, echoKey: "goal-parity"
            ),
            ChatEntry(
                role: "assistant", content: "",
                thread: nil,
                approvalKey: "wg:skills:rec-parity-1"
            ),
        ]
    }

    /// 后台执行工单量测（与量测台同一执行形：
    /// 工单 measure 在非主线程跑）
    private func measureOnBackground(
        _ job: ChatNativeRowMeasureJob
    ) -> CGFloat {
        let box = HeightBox()
        DispatchQueue.global(qos: .userInitiated)
            .sync {
                box.value = job.measure()
            }
        return box.value
    }

    private final class HeightBox {
        var value: CGFloat = -1
    }

    private final class LockedCounter {
        private let lock = NSLock()
        private(set) var value = 0
        func increment() {
            lock.lock()
            value += 1
            lock.unlock()
        }

        /// §430 测试卫生：读也走锁——旧形态外部
        /// 裸读 value 与 increment 的锁写构成
        /// Swift access race（TSan 既存账之一），
        /// 本包顺手收口
        func snapshot() -> Int {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
    }

    // MARK: - ① 对拍

    func testMeasureJobMatchesLiveAdapterPerEntry() {
        let composer = makeComposer()
        for (index, entry) in parityEntries()
            .enumerated() {
            let live = composer.entryHeight(
                entry, dividerText: nil
            )
            let job = composer.makeEntryMeasureJob(
                for: entry, dividerText: nil,
                memoKey: "parity-\(index)",
                rowKey: "parity-row-\(index)"
            )
            let pooled = measureOnBackground(job)
            XCTAssertEqual(
                pooled, live, accuracy: 2.0,
                "第 \(index) 行工单高与同步高须同值"
                    + "（live=\(live) job=\(pooled)）"
            )
        }
        // 带分隔槽一行（分隔文本量测同入对拍）
        let entry = ChatEntry(
            role: "user", content: "带分隔的一行",
            thread: nil
        )
        let live = composer.entryHeight(
            entry, dividerText: "昨天 21:03"
        )
        let job = composer.makeEntryMeasureJob(
            for: entry, dividerText: "昨天 21:03",
            memoKey: "parity-divider", rowKey: "parity-divider-row"
        )
        XCTAssertEqual(
            measureOnBackground(job), live,
            accuracy: 2.0
        )
    }

    func testToolGroupAndZoneJobsMatchLive() {
        let ledger = ChatRowStateLedger()
        let composer = makeComposer(ledger: ledger)
        let card = ToolCard(
            id: "parity-group-1",
            toolName: "terminal",
            category: .terminal,
            title: "运行命令",
            summary: "ls",
            result: "ok",
            resultFailed: false,
            arguments: "{}"
        )
        let groupKey = "tg-parity"
        ledger.setExpansion(true, for: groupKey)
        let liveGroup = composer.toolGroupHeight(
            cards: [card], groupKey: groupKey
        )
        let groupJob = composer.makeToolGroupMeasureJob(
            cards: [card], groupKey: groupKey,
            memoKey: "parity-group", rowKey: groupKey
        )
        XCTAssertEqual(
            measureOnBackground(groupJob), liveGroup,
            accuracy: 2.0
        )
        // 审批区（默认宿主非 ready → 0 对 0）
        let liveZone = composer.approvalZoneHeight()
        let zoneJob = composer.makeZoneMeasureJob(
            memoKey: "parity-zone",
            rowKey: "approval-zone"
        )
        XCTAssertEqual(
            measureOnBackground(zoneJob), liveZone,
            accuracy: 0.5
        )
    }

    // MARK: - ② 量测台

    func testDeskFallbackFillAndPublish() async {
        let desk = ChatNativeRowMeasureDesk()
        let suffix = UUID().uuidString
        let memoKey = "desk-test-\(suffix)"
        let rowKey = "desk-row-\(suffix)"
        let first = desk.resolve(
            memoKey: memoKey, rowKey: rowKey,
            fallback: 120
        )
        XCTAssertEqual(first.height, 120)
        XCTAssertTrue(
            first.needsJob, "未命中须报 needsJob"
        )
        desk.collect(
            ChatNativeRowMeasureJob(
                memoKey: memoKey, rowKey: rowKey
            ) { 88 }
        )
        desk.flushCollected()
        // 等发布（40ms 合并窗＋余量；async 轮询
        // 不饿死 MainActor 上的完成回调）
        let deadline = Date().addingTimeInterval(5)
        while desk.publishedRevision == 0,
              Date() < deadline {
            try? await Task.sleep(
                nanoseconds: 50_000_000
            )
        }
        XCTAssertGreaterThan(
            desk.publishedRevision, 0,
            "工单完成且高变化须发布"
        )
        XCTAssertEqual(
            ChatNativeRowHeightComposer
                .cachedRowHeight(forKey: memoKey),
            88
        )
        let second = desk.resolve(
            memoKey: memoKey, rowKey: rowKey,
            fallback: 120
        )
        XCTAssertEqual(second.height, 88)
        XCTAssertFalse(
            second.needsJob, "命中后不许再投单"
        )
    }

    func testDeskDeduplicatesJobs() async {
        let desk = ChatNativeRowMeasureDesk()
        let suffix = UUID().uuidString
        let memoKey = "desk-dup-\(suffix)"
        let rowKey = "desk-dup-row-\(suffix)"
        let counter = LockedCounter()
        let job = ChatNativeRowMeasureJob(
            memoKey: memoKey, rowKey: rowKey
        ) {
            counter.increment()
            return 66
        }
        desk.collect(job)
        desk.collect(job)
        let again = desk.resolve(
            memoKey: memoKey, rowKey: rowKey,
            fallback: 120
        )
        XCTAssertFalse(
            again.needsJob, "已收集的键不许再报 needsJob"
        )
        desk.flushCollected()
        let deadline = Date().addingTimeInterval(5)
        while counter.snapshot() == 0, Date() < deadline {
            try? await Task.sleep(
                nanoseconds: 50_000_000
            )
        }
        try? await Task.sleep(
            nanoseconds: 300_000_000
        )
        XCTAssertEqual(
            counter.snapshot(), 1, "同键工单只许执行一次"
        )
    }

    // MARK: - ③ 量测原语对拍

    func testTextMeasurePoolParityWithView() {
        let font = UIFont.preferredFont(
            forTextStyle: .body
        )
        let samples: [String] = [
            "短行",
            "这是一段足够长的中文文本，用来在三百多"
                + "点的宽度下折成多行，检验后台量测池"
                + "与主线程量测视图在多行折行与行高合"
                + "成上是否逐值一致。",
            "func measure() -> CGFloat { return 42 }",
        ]
        for sample in samples {
            let attributed = NSAttributedString(
                string: sample,
                attributes: [.font: font]
            )
            let viewHeight = ChatNativeTextMeasure
                .height(
                    attributed: attributed, width: 320,
                    emptyLineHeight: font.lineHeight
                )
            var poolHeight: CGFloat = -1
            DispatchQueue.global(qos: .userInitiated)
                .sync {
                    poolHeight = ChatNativeTextMeasure
                        .height(
                            attributed: attributed,
                            width: 320,
                            emptyLineHeight:
                                font.lineHeight
                        )
                }
            XCTAssertEqual(
                poolHeight, viewHeight, accuracy: 1.0,
                "池/视图量测须在影子账一致口径（1.0pt）内"
            )
            let viewWidth = ChatNativeTextMeasure
                .naturalWidth(attributed: attributed)
            var poolWidth: CGFloat = -1
            DispatchQueue.global(qos: .userInitiated)
                .sync {
                    poolWidth = ChatNativeTextMeasure
                        .naturalWidth(
                            attributed: attributed
                        )
                }
            XCTAssertEqual(
                poolWidth, viewWidth, accuracy: 1.0,
                "自然宽池/视图须一致"
            )
        }
        // 空串口径（R10 实测修正）：视图对空串
        // 回自家字体实高（22.0、非字体行高）——
        // 后台经探针回同值、须与主线程逐值一致
        let empty = NSAttributedString(
            string: "",
            attributes: [.font: font]
        )
        let viewEmpty = ChatNativeTextMeasure.height(
            attributed: empty, width: 320,
            emptyLineHeight: font.lineHeight
        )
        var poolEmpty: CGFloat = -1
        DispatchQueue.global(qos: .userInitiated)
            .sync {
                poolEmpty = ChatNativeTextMeasure
                    .height(
                        attributed: empty, width: 320,
                        emptyLineHeight: font.lineHeight
                    )
            }
        XCTAssertEqual(
            poolEmpty, viewEmpty, accuracy: 0.5,
            "空串后台高须与量测视图同值（探针口径）"
        )
    }

    /// §333（待办 143 根治）：行键组装热路径零
    /// 重扫——同一助手条目逐趟调 entryMemoKey
    /// （ChatView body 每趟行构建的真实调用），
    /// 键须逐字稳定且 facet 路径并集只许第一趟
    /// 真扫、其后全走 EntryScanMemo 备忘（facet-
    /// Misses 不再增长）。旧形态每趟对正文重跑
    /// wholeMessagePath＋组合排除口径锚定探测
    /// 全文扫，本测试即其回归闸
    func testEntryMemoKeyAssemblyDoesNotRescan() {
        EntryScanMemo.removeAll()
        EntryScanMemo.resetMetrics()
        let composer = makeComposer()
        let entry = ChatEntry(
            role: "assistant",
            content:
                "归档完成，文件在下面一行。\n"
                + "/opt/data/files/report.png\n"
                + "MEDIA:/opt/data/cache/images/img_a.png\n"
                + "正文其余部分照常叙述，撑起多行。",
            thread: nil
        )
        let key1 = composer.entryMemoKey(
            for: entry, dividerText: nil
        )
        let afterFirst = EntryScanMemo.metrics()
        XCTAssertEqual(afterFirst.facetMisses, 1)
        // 模拟滚动期逐趟 body 求值：同条目连调多趟
        for _ in 0..<5 {
            let keyN = composer.entryMemoKey(
                for: entry, dividerText: nil
            )
            XCTAssertEqual(keyN, key1, "同输入行键须逐字稳定")
        }
        let afterRepeat = EntryScanMemo.metrics()
        XCTAssertEqual(
            afterRepeat.facetMisses, afterFirst.facetMisses,
            "逐趟键组装不许重扫正文（facet 未命中须不增长）"
        )
        XCTAssertGreaterThan(
            afterRepeat.facetHits, afterFirst.facetHits,
            "重复趟须走 facet 备忘命中"
        )
    }
    // MARK: - ④ 台账 190（方向感知／就地量测／积压账）

    private final class LockedRecorder {
        private let lock = NSLock()
        private(set) var values: [String] = []
        func append(_ value: String) {
            lock.lock()
            values.append(value)
            lock.unlock()
        }

        /// §430 测试卫生：读也走锁——runPass 轮询
        /// 与断言旧形态裸读 values，与 append 的
        /// 锁写构成 Swift access race（TSan 既存
        /// 账之二），本包顺手收口
        func snapshot() -> [String] {
            lock.lock()
            defer { lock.unlock() }
            return values
        }
        func clear() {
            lock.lock()
            values = []
            lock.unlock()
        }
    }

    func testDeskResolveReportsExactness() async {
        let desk = ChatNativeRowMeasureDesk()
        let suffix = UUID().uuidString
        let memoKey = "desk-exact-\(suffix)"
        let rowKey = "desk-exact-row-\(suffix)"
        let miss = desk.resolve(
            memoKey: memoKey, rowKey: rowKey, fallback: 120
        )
        XCTAssertFalse(miss.isExact, "未量测行高不许报确定")
        desk.collect(
            ChatNativeRowMeasureJob(
                memoKey: memoKey, rowKey: rowKey
            ) { 77 }
        )
        desk.flushCollected()
        let deadline = Date().addingTimeInterval(5)
        while desk.publishedRevision == 0,
              Date() < deadline {
            try? await Task.sleep(
                nanoseconds: 50_000_000
            )
        }
        let hit = desk.resolve(
            memoKey: memoKey, rowKey: rowKey, fallback: 120
        )
        XCTAssertTrue(hit.isExact, "量测回填后须报确定高")
        XCTAssertEqual(hit.height, 77)
    }

    func testDeskMeasureNowRunsJobSynchronously() {
        ChatMeasureDeskBacklog.reset()
        let desk = ChatNativeRowMeasureDesk()
        let suffix = UUID().uuidString
        let memoKey = "desk-now-\(suffix)"
        let rowKey = "desk-now-row-\(suffix)"
        _ = desk.resolve(
            memoKey: memoKey, rowKey: rowKey, fallback: 120
        )
        desk.collect(
            ChatNativeRowMeasureJob(
                memoKey: memoKey, rowKey: rowKey
            ) { 55 }
        )
        // 未 flush 即就地量测：同步回确定高＋缓存落账
        let measured = desk.measureNow(rowKey: rowKey)
        XCTAssertEqual(measured, 55)
        XCTAssertEqual(
            ChatNativeRowHeightComposer
                .cachedRowHeight(forKey: memoKey),
            55
        )
        XCTAssertTrue(
            ChatNativeRowMeasureDesk.backlogLine()
                .contains("就地量测 1"),
            "积压账须记就地量测一次"
        )
        // 无工单无缓存的行回 nil（布局侧保留喂入高）
        XCTAssertNil(
            desk.measureNow(rowKey: "no-such-row-\(suffix)")
        )
    }

    func testDeskUpwardTrendDispatchesAnchorFirst() async {
        let desk = ChatNativeRowMeasureDesk()
        let suffix = UUID().uuidString
        let recorder = LockedRecorder()
        let rowKeys = (0..<5).map { "ord-r\($0)-\(suffix)" }
        func runPass(tag: String) async {
            for (index, rowKey) in rowKeys.enumerated() {
                let memoKey = "ord-\(tag)-\(index)-\(suffix)"
                _ = desk.resolve(
                    memoKey: memoKey, rowKey: rowKey,
                    fallback: 120
                )
                desk.collect(
                    ChatNativeRowMeasureJob(
                        memoKey: memoKey, rowKey: rowKey
                    ) {
                        recorder.append(rowKey)
                        return 100
                    }
                )
            }
            desk.flushCollected()
            let deadline = Date().addingTimeInterval(5)
            while recorder.snapshot().count < 5,
                  Date() < deadline {
                try? await Task.sleep(
                    nanoseconds: 50_000_000
                )
            }
        }
        // 第一趟：建行序账（默认逆序＝最新先量）
        await runPass(tag: "p1")
        XCTAssertEqual(
            recorder.snapshot(), Array(rowKeys.reversed()),
            "无趋势时投单序恒逆序（现行口径）"
        )
        recorder.clear()
        // 锚先落最底行、再上移到第 1 行＝上滑趋势
        desk.noteTopVisible(rowKey: rowKeys[4])
        desk.noteTopVisible(rowKey: rowKeys[1])
        await runPass(tag: "p2")
        XCTAssertEqual(
            recorder.snapshot(),
            [rowKeys[1], rowKeys[0], rowKeys[2],
             rowKeys[3], rowKeys[4]],
            "上滑趋势下投单序须锚上方最近行先量、锚下方次之"
        )
    }
}
