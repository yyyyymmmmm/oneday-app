import XCTest
@testable import OneDayCore

/// §451（发送机制换代）Core 钉测：账本多条化、落
/// 定提取改锚 serverRowID（多轮不串段）、配对图与
/// 对账同源、提交泵车道策略（严格保序）。
final class SendMechanism451Tests: XCTestCase {

    // MARK: - 账本多条化（App-2）

    private func ledgerEntry(
        thread: String, userEntryID: String,
        runID: String? = nil, at epoch: Double
    ) -> RunLedgerEntry {
        RunLedgerEntry(
            threadID: thread, sessionID: "sess",
            runID: runID, idempotencyKey: "key-\(userEntryID)",
            userEntryID: userEntryID,
            submittedAt: Date(timeIntervalSince1970: epoch)
        )
    }

    func testLedgerHoldsMultipleEntriesPerThread() {
        var entries: [RunLedgerEntry] = []
        entries = RunLedger.upsert(entries, ledgerEntry(
            thread: "t1", userEntryID: "e2", at: 2000
        ))
        entries = RunLedger.upsert(entries, ledgerEntry(
            thread: "t1", userEntryID: "e1", at: 1000
        ))
        XCTAssertEqual(entries.count, 2)
        // 提交序读口：按 submittedAt 排，头＝最早一条
        let ordered = RunLedger.entries(
            forThreadID: "t1", in: entries
        )
        XCTAssertEqual(ordered.map(\.userEntryID), ["e1", "e2"])
        XCTAssertEqual(
            RunLedger.entry(forThreadID: "t1", in: entries)?
                .userEntryID,
            "e1"
        )
    }

    func testLedgerUpsertSameKeyUpdatesInPlace() {
        var entries: [RunLedgerEntry] = []
        entries = RunLedger.upsert(entries, ledgerEntry(
            thread: "t1", userEntryID: "e1", at: 1000
        ))
        entries = RunLedger.upsert(entries, ledgerEntry(
            thread: "t1", userEntryID: "e2", at: 2000
        ))
        // 同键补 runID（提交前落账→受理后回填）：不
        // 新增、不换位
        entries = RunLedger.upsert(entries, ledgerEntry(
            thread: "t1", userEntryID: "e1",
            runID: "run-1", at: 1000
        ))
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].userEntryID, "e1")
        XCTAssertEqual(entries[0].runID, "run-1")
    }

    func testLedgerRemoveByUserEntryKeepsOthers() {
        var entries: [RunLedgerEntry] = []
        entries = RunLedger.upsert(entries, ledgerEntry(
            thread: "t1", userEntryID: "e1", at: 1000
        ))
        entries = RunLedger.upsert(entries, ledgerEntry(
            thread: "t1", userEntryID: "e2", at: 2000
        ))
        entries = RunLedger.removing(
            userEntryID: "e1", from: entries
        )
        XCTAssertEqual(entries.map(\.userEntryID), ["e2"])
        // 整线程清账口径仍在（线程删除等全清场景）
        entries = RunLedger.removing(
            threadID: "t1", from: entries
        )
        XCTAssertTrue(entries.isEmpty)
    }

    // MARK: - 落定改锚（App-4 硬门）

    private func row(
        id: Int, role: String, content: String,
        displayKind: String? = nil
    ) -> SessionMessage {
        SessionMessage(
            id: Double(id), role: role, content: content,
            displayKind: displayKind
        )
    }

    /// 两轮 transcript：先行轮落定提取绝不串入后轮
    func testAnchoredSettleDoesNotBleedAcrossTurns() {
        let messages = [
            row(id: 10, role: "user", content: "第一问"),
            row(id: 11, role: "assistant", content: "第一答"),
            row(id: 20, role: "user", content: "第二问"),
            row(id: 21, role: "assistant", content: "第二答")
        ]
        let first = RunTranscriptSettle.settle(
            messages: messages, anchorRowID: 10
        )
        XCTAssertTrue(first.found)
        XCTAssertEqual(first.finalText, "第一答")
        XCTAssertEqual(first.userRowID, 10)
        let second = RunTranscriptSettle.settle(
            messages: messages, anchorRowID: 20
        )
        XCTAssertEqual(second.finalText, "第二答")
        XCTAssertEqual(second.userRowID, 20)
        // 无锚兼容口径不变：仍取末轮
        let legacy = RunTranscriptSettle.settle(messages: messages)
        XCTAssertEqual(legacy.finalText, "第二答")
    }

    /// 后轮失败行不许污染先行轮的落定判定
    func testAnchoredSettleIgnoresLaterTurnFailure() {
        let messages = [
            row(id: 10, role: "user", content: "第一问"),
            row(id: 11, role: "assistant", content: "第一答"),
            row(id: 20, role: "user", content: "第二问"),
            row(
                id: 21, role: "assistant", content: "上游挂了",
                displayKind: "failed_turn"
            )
        ]
        let first = RunTranscriptSettle.settle(
            messages: messages, anchorRowID: 10
        )
        XCTAssertTrue(first.found)
        XCTAssertFalse(first.failed)
        XCTAssertEqual(first.finalText, "第一答")
        let second = RunTranscriptSettle.settle(
            messages: messages, anchorRowID: 20
        )
        XCTAssertTrue(second.failed)
    }

    /// 锚行未落盘：notFound，绝不回落末条锚拿别轮的段
    func testAnchoredSettleMissingAnchorIsNotFound() {
        let messages = [
            row(id: 10, role: "user", content: "第一问"),
            row(id: 11, role: "assistant", content: "第一答")
        ]
        let settled = RunTranscriptSettle.settle(
            messages: messages, anchorRowID: 999
        )
        XCTAssertFalse(settled.found)
    }

    /// 本轮段未出产物（后轮已在跑）：锚段为空即未落定
    func testAnchoredSettleEmptySegmentWaits() {
        let messages = [
            row(id: 10, role: "user", content: "第一问"),
            row(id: 20, role: "user", content: "第二问"),
            row(id: 21, role: "assistant", content: "第二答")
        ]
        let settled = RunTranscriptSettle.settle(
            messages: messages, anchorRowID: 10
        )
        XCTAssertFalse(settled.found)
    }

    // MARK: - 配对图（App-4 锚解析，与对账同源）

    func testPairedRowIDsMatchesReconcilePairing() {
        let messages = [
            SessionMessage(
                id: 5, role: "user", content: "甲",
                timestamp: 1_000
            ),
            SessionMessage(
                id: 6, role: "assistant", content: "答甲",
                timestamp: 1_001
            ),
            SessionMessage(
                id: 9, role: "user", content: "乙",
                timestamp: 2_000
            )
        ]
        let locals: [(
            content: String, createdAt: Date,
            filePaths: [String], imagePaths: [String]
        )] = [
            ("甲", Date(timeIntervalSince1970: 1_000), [], []),
            ("乙", Date(timeIntervalSince1970: 2_000), [], []),
            ("丙", Date(timeIntervalSince1970: 3_000), [], [])
        ]
        let pairs = RunTranscriptSettle.pairedRowIDs(
            messages: messages, localUserEntries: locals
        )
        XCTAssertEqual(pairs[0], 5)
        XCTAssertEqual(pairs[1], 9)
        XCTAssertNil(pairs[2])
        // 同源一致性：同一配对下对账判缺只剩服务端
        // 没有的「丙」对应的反面——服务端行全配上，
        // missing 为空
        let reconcile = RunTranscriptSettle
            .reconcileUserMessages(
                messages: messages, localUserEntries: locals
            )
        XCTAssertTrue(reconcile.missing.isEmpty)
    }

    // MARK: - 提交泵车道（App-1 严格保序）

    private func lane(
        _ id: UUID, ledger: Bool = false,
        manual: Bool = false, failed: Bool = false,
        due: Bool = false, awaiting: Bool = false
    ) -> SubmissionLane.Entry {
        SubmissionLane.Entry(
            entryID: id, hasLedgerEntry: ledger,
            manualOnly: manual, unacceptedFailure: failed,
            failureRetryDue: due, awaitingSubmission: awaiting
        )
    }

    func testLaneSubmitsFirstAwaitingSkippingAccepted() {
        let a = UUID(), b = UUID()
        let decision = SubmissionLane.decision(entries: [
            lane(a, ledger: true), lane(b, awaiting: true)
        ])
        XCTAssertEqual(decision, .submit(b))
    }

    func testLaneFailureBlocksLaterSubmissions() {
        let a = UUID(), b = UUID()
        // 失败未到重试点：堵泵，后条不许越过
        XCTAssertEqual(
            SubmissionLane.decision(entries: [
                lane(a, failed: true), lane(b, awaiting: true)
            ]),
            .blocked(failedEntryID: a)
        )
        // 失败到点：先重试失败条本身，仍不直接放后条
        XCTAssertEqual(
            SubmissionLane.decision(entries: [
                lane(a, failed: true, due: true),
                lane(b, awaiting: true)
            ]),
            .submit(a)
        )
    }

    func testLaneManualOnlyBlocks() {
        let a = UUID(), b = UUID()
        XCTAssertEqual(
            SubmissionLane.decision(entries: [
                lane(a, manual: true), lane(b, awaiting: true)
            ]),
            .blockedManual(entryID: a)
        )
    }

    func testLaneIdleWhenNothingToSubmit() {
        let a = UUID()
        XCTAssertEqual(
            SubmissionLane.decision(entries: [lane(a, ledger: true)]),
            .idle
        )
        XCTAssertEqual(SubmissionLane.decision(entries: []), .idle)
    }
}
