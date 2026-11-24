import Foundation
import XCTest
@testable import OneDayCore

/// 台账 154／G-04 发件箱自动重试策略验收（DESIGN
/// §336）：状态×记账的判定矩阵、退避算术、次数上
/// 限与人工接管标记逐格钉死——drain 的行为全由
/// 本矩阵决定，矩阵错即全链错
final class OutboxAutoRetryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func decision(
        _ state: ChatSendState?,
        attempts: Int = 0,
        lastAttemptSecondsAgo: TimeInterval? = nil,
        manualOnly: Bool = false
    ) -> OutboxAutoRetryPolicy.Decision {
        let record = (attempts == 0 && lastAttemptSecondsAgo == nil
                      && !manualOnly)
            ? nil
            : OutboxRetryRecord(
                  attempts: attempts,
                  lastAttemptAt: lastAttemptSecondsAgo.map {
                      now.addingTimeInterval(-$0)
                  },
                  manualOnly: manualOnly
              )
        return OutboxAutoRetryPolicy.decision(
            state: state, record: record, now: now
        )
    }

    func testNotInQueueStates() {
        XCTAssertEqual(decision(nil), .notInQueue)
        XCTAssertEqual(decision(.delivered), .notInQueue)
    }

    func testSendingOwnedByRunLedger() {
        // 提交段恒归账本/对账链：无记账、有记账、甚
        // 至打了人工接管标记，自动链都不插手
        XCTAssertEqual(decision(.sending), .ownedByRunLedger)
        XCTAssertEqual(
            decision(.sending, attempts: 1, lastAttemptSecondsAgo: 9999),
            .ownedByRunLedger
        )
        XCTAssertEqual(
            decision(.sending, manualOnly: true), .ownedByRunLedger
        )
    }

    func testInterruptedPrepStatesAutoNow() {
        // 准备段瞬态（进程中断孤儿）：无条件接管，
        // 次数账再大也不挡（它们从未抵达提交段）
        for state in [ChatSendState.queued, .uploading, .linking] {
            XCTAssertEqual(decision(state), .autoNow, "\(state)")
            XCTAssertEqual(
                decision(state, attempts: 9, lastAttemptSecondsAgo: 1),
                .autoNow, "\(state)"
            )
        }
    }

    func testFailedFirstAutoAttemptIsImmediate() {
        XCTAssertEqual(decision(.failed), .autoNow)
        // 有一条空记账（次数 0、无时刻）同样立即
        XCTAssertEqual(
            decision(.failed, attempts: 0, lastAttemptSecondsAgo: nil),
            .autoNow
        )
    }

    func testFailedBackoffWindows() {
        // 第 1 次自动重试失败后须等 30s
        XCTAssertEqual(
            decision(.failed, attempts: 1, lastAttemptSecondsAgo: 29),
            .backoff(until: now.addingTimeInterval(1))
        )
        XCTAssertEqual(
            decision(.failed, attempts: 1, lastAttemptSecondsAgo: 30),
            .autoNow
        )
        // 第 2 次后须等 60s
        XCTAssertEqual(
            decision(.failed, attempts: 2, lastAttemptSecondsAgo: 59),
            .backoff(until: now.addingTimeInterval(1))
        )
        XCTAssertEqual(
            decision(.failed, attempts: 2, lastAttemptSecondsAgo: 61),
            .autoNow
        )
    }

    func testFailedAttemptsCapFallsBackToManual() {
        XCTAssertEqual(
            decision(
                .failed,
                attempts: OutboxAutoRetryPolicy.maxAutoAttempts,
                lastAttemptSecondsAgo: 86_400
            ),
            .manualOnly
        )
        XCTAssertEqual(
            decision(.failed, attempts: 99, lastAttemptSecondsAgo: 86_400),
            .manualOnly
        )
    }

    func testManualOnlyRecordBlocksAllQueueStates() {
        XCTAssertEqual(
            decision(.failed, manualOnly: true), .manualOnly
        )
        XCTAssertEqual(
            decision(.queued, manualOnly: true), .manualOnly
        )
        XCTAssertEqual(
            decision(.uploading, manualOnly: true), .manualOnly
        )
    }

    func testBackoffSecondsProgressionAndCap() {
        XCTAssertEqual(OutboxAutoRetryPolicy.backoffSeconds(afterAttempts: 0), 0)
        XCTAssertEqual(OutboxAutoRetryPolicy.backoffSeconds(afterAttempts: 1), 30)
        XCTAssertEqual(OutboxAutoRetryPolicy.backoffSeconds(afterAttempts: 2), 60)
        XCTAssertEqual(OutboxAutoRetryPolicy.backoffSeconds(afterAttempts: 3), 120)
        XCTAssertEqual(OutboxAutoRetryPolicy.backoffSeconds(afterAttempts: 4), 240)
        XCTAssertEqual(
            OutboxAutoRetryPolicy.backoffSeconds(afterAttempts: 5),
            OutboxAutoRetryPolicy.maxBackoffSeconds
        )
        XCTAssertEqual(
            OutboxAutoRetryPolicy.backoffSeconds(afterAttempts: 20),
            OutboxAutoRetryPolicy.maxBackoffSeconds
        )
    }

    func testRecordCodableRoundTrip() throws {
        let record = OutboxRetryRecord(
            attempts: 2, lastAttemptAt: now, manualOnly: true
        )
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(
            OutboxRetryRecord.self, from: data
        )
        XCTAssertEqual(decoded, record)
    }
}
