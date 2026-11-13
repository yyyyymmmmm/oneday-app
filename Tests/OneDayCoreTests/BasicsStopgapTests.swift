import XCTest
@testable import OneDayCore

/// 基础体验止血包（2026-11-13，依 basics-ux-audit
/// P1–P9）Core 侧验收：run 失败文案分型映射与不漏
/// 原文、重发幂等闸的账本口径、草稿落盘点判定、待
/// 发附件线程分格、零条目空状态判定。文案断言口径
/// 同 DemoLimitTests：测试环境无字符串目录宿主，
/// userMessage 回落 zh-Hans 源串、按源串断言。
/// HermesError 非 Equatable（带关联值），分型断言
/// 走 tag(of:) 模式匹配标签，不用 XCTAssertEqual
/// 直接比枚举值
final class BasicsStopgapTests: XCTestCase {

    /// 分型标签（只认本包五档，其余一律 other）
    private func tag(of error: HermesError) -> String {
        switch error {
        case .runBillingExhausted: return "billing"
        case .runServiceUnavailable: return "service"
        case .runTimedOut: return "timeout"
        case .runNetworkInterrupted: return "network"
        case .runFailedGeneric: return "generic"
        default: return "other"
        }
    }

    private func classifyTag(
        errorText: String?, outputText: String?
    ) -> String {
        tag(of: RunFailureClassifier.classify(
            errorText: errorText, outputText: outputText
        ))
    }

    // MARK: - P5 · run 失败文案分型映射

    func testClassifierBillingByStatusCode() {
        XCTAssertEqual(
            classifyTag(
                errorText: "HTTP 402 Payment Required",
                outputText: nil
            ),
            "billing"
        )
    }

    func testClassifierBillingByWording() {
        XCTAssertEqual(
            classifyTag(
                errorText: "Insufficient balance for this account",
                outputText: nil
            ),
            "billing"
        )
        XCTAssertEqual(
            classifyTag(errorText: nil, outputText: "账户余额不足"),
            "billing"
        )
    }

    func testClassifierTimedOut() {
        XCTAssertEqual(
            classifyTag(
                errorText: "The request timed out.", outputText: nil
            ),
            "timeout"
        )
        XCTAssertEqual(
            classifyTag(errorText: "请求超时", outputText: nil),
            "timeout"
        )
    }

    func testClassifierNetworkInterrupted() {
        XCTAssertEqual(
            classifyTag(
                errorText: "The network connection was lost.",
                outputText: nil
            ),
            "network"
        )
        XCTAssertEqual(
            classifyTag(
                errorText: nil, outputText: "生成中断：网络连接已断开"
            ),
            "network"
        )
    }

    func testClassifierServiceUnavailable() {
        XCTAssertEqual(
            classifyTag(
                errorText: "503 Service Unavailable", outputText: nil
            ),
            "service"
        )
        XCTAssertEqual(
            classifyTag(
                errorText: "Internal Server Error", outputText: nil
            ),
            "service"
        )
    }

    func testClassifierUnknownFallsToGeneric() {
        XCTAssertEqual(
            classifyTag(
                errorText: "something unexpected happened",
                outputText: nil
            ),
            "generic"
        )
        XCTAssertEqual(
            classifyTag(errorText: nil, outputText: nil), "generic"
        )
        XCTAssertEqual(
            classifyTag(errorText: "", outputText: ""), "generic"
        )
    }

    /// 状态码按数字边界认：正文里的长数字（如 token
    /// 数 15000）不得误判成服务端错误
    func testClassifierStatusCodeNeedsDigitBoundary() {
        XCTAssertEqual(
            classifyTag(
                errorText: "usage 15000 tokens, aborted",
                outputText: nil
            ),
            "generic"
        )
    }

    /// 分型优先级：欠费先于超时/服务端（同帧多签名
    /// 时按最该用户处理的一档呈现）
    func testClassifierBillingWinsOverOthers() {
        XCTAssertEqual(
            classifyTag(
                errorText: "402 payment required after timeout, 500",
                outputText: nil
            ),
            "billing"
        )
    }

    /// 服务端原文（含可能夹带的敏感回显）永不进呈
    /// 现文案：五档文案钉死为定稿源串、与输入无关
    func testRunFailureCopyPinnedAndLeakFree() {
        let secret = "sk-live-9f8e7d6c5b"
        let failure = RunFailureClassifier.classify(
            errorText: "402 \(secret) rejected", outputText: nil
        )
        XCTAssertEqual(tag(of: failure), "billing")
        XCTAssertFalse(failure.userMessage.contains(secret))
        XCTAssertEqual(
            HermesError.runBillingExhausted.userMessage,
            "生成失败：账户余额或额度不足，处理好后再试。"
        )
        XCTAssertEqual(
            HermesError.runServiceUnavailable.userMessage,
            "生成失败：服务器那边出了点问题，稍后再试。"
        )
        XCTAssertEqual(
            HermesError.runTimedOut.userMessage,
            "生成超时了，稍后再试一次。"
        )
        XCTAssertEqual(
            HermesError.runNetworkInterrupted.userMessage,
            "网络断开了，生成没能完成。等网络恢复后再试。"
        )
        XCTAssertEqual(
            HermesError.runFailedGeneric.userMessage,
            "生成失败，请稍后再试。"
        )
    }

    /// 五档新失败形态都不许走「自动退回重试」瞬时
    /// 语义（落定失败＝终局，动作是用户点重发）
    func testRunFailureCasesAreNotTransient() {
        for failure in [
            HermesError.runBillingExhausted, .runServiceUnavailable,
            .runTimedOut, .runNetworkInterrupted, .runFailedGeneric,
        ] {
            XCTAssertFalse(failure.isTransient)
        }
    }

    // MARK: - P1/P2 · 重发幂等闸（与发送同一本账）

    /// 重发与首发共用同一道闸：账本里还有本线程未
    /// 落定轮次时 entry(forThreadID:) 非空（重发被
    /// 拦、先对账）；账本清除后为空（放行重发）
    func testResendGateFollowsRunLedger() {
        let entry = RunLedgerEntry(
            threadID: "thread-a", sessionID: "sess-1",
            runID: nil, idempotencyKey: "key-1",
            userEntryID: "entry-1", submittedAt: Date()
        )
        var ledger = RunLedger.upsert([], entry)
        XCTAssertNotNil(
            RunLedger.entry(forThreadID: "thread-a", in: ledger)
        )
        XCTAssertNil(
            RunLedger.entry(forThreadID: "thread-b", in: ledger)
        )
        ledger = RunLedger.removing(threadID: "thread-a", from: ledger)
        XCTAssertNil(
            RunLedger.entry(forThreadID: "thread-a", in: ledger)
        )
    }

    /// 幂等键由发送侧每轮新铸、账本只存凭据——重发
    /// 走 driveRun 时新铸一键，服务端按会话尾条语义
    /// 不会落两份（App 侧 launchTurn 前置闸见上测）
    func testLedgerUpsertKeepsOneEntryPerThread() {
        let first = RunLedgerEntry(
            threadID: "t", sessionID: "s", runID: nil,
            idempotencyKey: "k1", userEntryID: "e1",
            submittedAt: Date()
        )
        let second = RunLedgerEntry(
            threadID: "t", sessionID: "s", runID: "r2",
            idempotencyKey: "k2", userEntryID: "e2",
            submittedAt: Date()
        )
        let ledger = RunLedger.upsert(
            RunLedger.upsert([], first), second
        )
        XCTAssertEqual(ledger.count, 1)
        XCTAssertEqual(ledger.first?.idempotencyKey, "k2")
    }

    // MARK: - P4 · 待发附件线程分格

    func testStashIsolatesPerThread() {
        var stash = ThreadBoundStash<[String]>()
        let a = UUID(), b = UUID()
        stash.store(["a.pdf"], for: a)
        stash.store(["b.png"], for: b)
        XCTAssertEqual(stash.peek(for: a), ["a.pdf"])
        XCTAssertEqual(stash.peek(for: b), ["b.png"])
        XCTAssertFalse(stash.isEmpty)
    }

    /// 取出即清格：切回同一线程不许把上次的附件再
    /// 呈现一遍（防串带与防重复发送同源）
    func testStashTakeClearsSlot() {
        var stash = ThreadBoundStash<[String]>()
        let a = UUID()
        stash.store(["a.pdf"], for: a)
        XCTAssertEqual(stash.take(for: a), ["a.pdf"])
        XCTAssertNil(stash.take(for: a))
        XCTAssertNil(stash.peek(for: a))
        XCTAssertTrue(stash.isEmpty)
    }

    func testStashRemoveAndOverwrite() {
        var stash = ThreadBoundStash<Int>()
        let a = UUID()
        stash.store(1, for: a)
        stash.store(2, for: a)
        XCTAssertEqual(stash.peek(for: a), 2)
        stash.remove(for: a)
        XCTAssertNil(stash.peek(for: a))
        XCTAssertTrue(stash.isEmpty)
    }

    // MARK: - P3 · 草稿落盘点判定

    func testDraftSavePolicy() {
        XCTAssertTrue(
            DraftSavePolicy.shouldSaveOnLeavingActive(
                hasCurrentThread: true, threadStillExists: true
            )
        )
        // 线程已被删：无处落，不写
        XCTAssertFalse(
            DraftSavePolicy.shouldSaveOnLeavingActive(
                hasCurrentThread: true, threadStillExists: false
            )
        )
        // 无当前线程（落地态）：没有可绑定的草稿
        XCTAssertFalse(
            DraftSavePolicy.shouldSaveOnLeavingActive(
                hasCurrentThread: false, threadStillExists: true
            )
        )
        XCTAssertFalse(
            DraftSavePolicy.shouldSaveOnLeavingActive(
                hasCurrentThread: false, threadStillExists: false
            )
        )
    }

    // MARK: - P9 · 零条目空状态判定

    func testChatEmptyState() {
        // 无当前线程 → 显示（既有口径）
        XCTAssertTrue(
            ChatEmptyState.shows(
                threadIsNil: true, entryCount: 0, isStreaming: false
            )
        )
        // 有线程零条目 → 显示（本包新增面）
        XCTAssertTrue(
            ChatEmptyState.shows(
                threadIsNil: false, entryCount: 0, isStreaming: false
            )
        )
        // 有条目 → 不显示
        XCTAssertFalse(
            ChatEmptyState.shows(
                threadIsNil: false, entryCount: 3, isStreaming: false
            )
        )
        // 流式在飞 → 不显示（等流式呈现接管）
        XCTAssertFalse(
            ChatEmptyState.shows(
                threadIsNil: true, entryCount: 0, isStreaming: true
            )
        )
        XCTAssertFalse(
            ChatEmptyState.shows(
                threadIsNil: false, entryCount: 0, isStreaming: true
            )
        )
    }
}
