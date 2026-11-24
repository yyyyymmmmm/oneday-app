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
        manualOnly: Bool = false,
        kind: SendFailureKind? = nil
    ) -> OutboxAutoRetryPolicy.Decision {
        let record = (attempts == 0 && lastAttemptSecondsAgo == nil
                      && !manualOnly && kind == nil)
            ? nil
            : OutboxRetryRecord(
                  attempts: attempts,
                  lastAttemptAt: lastAttemptSecondsAgo.map {
                      now.addingTimeInterval(-$0)
                  },
                  manualOnly: manualOnly,
                  lastFailureKind: kind
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
        // 准备段瞬态（进程中断孤儿）：无记账在身时
        // 立即接管（它们从未抵达提交段）
        for state in [ChatSendState.queued, .uploading, .linking] {
            XCTAssertEqual(decision(state), .autoNow, "\(state)")
        }
    }

    func testPrepStatesWithRecordFollowBackoff() {
        // 发送失败机制包（横扫 P1-2 关账）：准备段
        // 有自动记账在身的，与失败态同账——查次数、
        // 等退避，不许恒立即。旧口径 attempts=9 仍
        // autoNow：任何「失败后状态停在准备段」的
        // 出口都是无上限立即重投
        for state in [ChatSendState.queued, .uploading, .linking] {
            XCTAssertEqual(
                decision(state, attempts: 9, lastAttemptSecondsAgo: 1),
                .backoff(until: now.addingTimeInterval(299)),
                "\(state)"
            )
            XCTAssertEqual(
                decision(state, attempts: 1, lastAttemptSecondsAgo: 30),
                .autoNow, "\(state)"
            )
        }
    }

    func testAcceptedOwnedByRunLedger() {
        // 双轴语义（语义 1）：已受理未落定归对账链，
        // 自动链不插手——与 .sending 同格
        XCTAssertEqual(decision(.accepted), .ownedByRunLedger)
        XCTAssertEqual(
            decision(.accepted, attempts: 2, lastAttemptSecondsAgo: 1),
            .ownedByRunLedger
        )
    }

    func testFailedKindAdmission() {
        // 成因准入（语义 3）：钉死类成因在账即
        // manualOnly，与次数无关（attempts=0 也钉）
        let pinned: [SendFailureKind] = [
            .rateLimited, .queueFull, .authRejected,
            .billingRejected, .modelRejected,
            .serverRejected, .businessRejected,
            .prepareFailed, .runBilling, .runTimeout,
            .runNetwork, .runService, .runGeneric,
            .runResultLost, .unknown
        ]
        for kind in pinned {
            XCTAssertEqual(
                decision(.failed, kind: kind), .manualOnly,
                "\(kind)"
            )
            XCTAssertEqual(
                decision(
                    .failed, attempts: 1,
                    lastAttemptSecondsAgo: 86_400, kind: kind
                ),
                .manualOnly, "\(kind)"
            )
        }
        // 传输类成因走正常预算：首次立即、其后退避
        let transport: [SendFailureKind] = [
            .offlineNotSent, .transportInterrupted, .hostUnreachable
        ]
        for kind in transport {
            XCTAssertEqual(
                decision(.failed, kind: kind), .autoNow, "\(kind)"
            )
            XCTAssertEqual(
                decision(
                    .failed, attempts: 1,
                    lastAttemptSecondsAgo: 29, kind: kind
                ),
                .backoff(until: now.addingTimeInterval(1)),
                "\(kind)"
            )
        }
        // 生成失败永不自动重发（语义 3 点名钉）：
        // run 面五档＋丢失终局，退避全满也不放行
        for kind in [SendFailureKind.runBilling, .runTimeout,
                     .runNetwork, .runService, .runGeneric,
                     .runResultLost] {
            XCTAssertEqual(
                decision(
                    .failed, attempts: 1,
                    lastAttemptSecondsAgo: 999_999, kind: kind
                ),
                .manualOnly, "\(kind)"
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

    func testRecordCodableWithFailureKind() throws {
        let record = OutboxRetryRecord(
            attempts: 1, lastAttemptAt: now, manualOnly: false,
            lastFailureKind: .serverRejected
        )
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(
            OutboxRetryRecord.self, from: data
        )
        XCTAssertEqual(decoded, record)
        XCTAssertEqual(decoded.lastFailureKind, .serverRejected)
    }

    func testLegacyRecordJSONWithoutKindDecodes() throws {
        // 存量落盘账（无 lastFailureKind 键）须能解：
        // kind 按 nil 走无成因老口径，不许整账解码
        // 失败连坐
        let json = #"{"attempts":2,"manualOnly":false}"#
        let decoded = try JSONDecoder().decode(
            OutboxRetryRecord.self, from: Data(json.utf8)
        )
        XCTAssertEqual(decoded.attempts, 2)
        XCTAssertNil(decoded.lastFailureKind)
    }
}
