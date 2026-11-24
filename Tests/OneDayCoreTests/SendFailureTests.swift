import Foundation
import XCTest
@testable import OneDayCore

/// 发送失败机制包钉测（2026-11-24）：成因分类双面
/// 映射、准入/呈现集合、文案单表同源、拼接收尾归
/// 一、双轴状态谓词、run 丢失终局三闸、账本存量
/// 解码——新语义逐条钉死，回归即红
final class SendFailureTests: XCTestCase {

    // MARK: 提交面分类

    func testClassifySubmitByStatus() {
        let cases: [(HermesError, SendFailureKind)] = [
            (.unexpectedStatus(endpoint: "runs", status: 401), .authRejected),
            (.unexpectedStatus(endpoint: "runs", status: 403), .authRejected),
            (.unexpectedStatus(endpoint: "runs", status: 402), .billingRejected),
            (.unexpectedStatus(endpoint: "runs", status: 409), .queueFull),
            (.unexpectedStatus(endpoint: "runs", status: 429), .rateLimited),
            (.unexpectedStatus(endpoint: "runs", status: 500), .serverRejected),
            (.unexpectedStatus(endpoint: "runs", status: 503), .serverRejected),
            (.unexpectedStatus(endpoint: "runs", status: 400), .businessRejected),
            (.unexpectedStatus(endpoint: "runs", status: 422), .businessRejected),
            (.serverError(endpoint: "runs", status: 500, code: "queue_full"), .queueFull),
            (.serverError(endpoint: "runs", status: 409, code: "session_busy"), .queueFull),
            (.serverError(endpoint: "runs", status: 502, code: "bad_gateway"), .serverRejected)
        ]
        for (error, expected) in cases {
            XCTAssertEqual(
                SendFailureKind.classify(submit: error), expected,
                "\(error)"
            )
        }
    }

    func testClassifySubmitByCase() {
        XCTAssertEqual(
            SendFailureKind.classify(submit: .notSentOffline),
            .offlineNotSent
        )
        XCTAssertEqual(
            SendFailureKind.classify(submit: .transientNetwork),
            .transportInterrupted
        )
        XCTAssertEqual(
            SendFailureKind.classify(submit: .unreachable("x")),
            .hostUnreachable
        )
        XCTAssertEqual(
            SendFailureKind.classify(
                submit: .rateLimited(retryAfterSeconds: 1)
            ),
            .rateLimited
        )
        XCTAssertEqual(
            SendFailureKind.classify(submit: .apiKeyRejected),
            .authRejected
        )
        XCTAssertEqual(
            SendFailureKind.classify(submit: .sessionExpired),
            .authRejected
        )
        XCTAssertEqual(
            SendFailureKind.classify(submit: .modelNotUpstream("m")),
            .modelRejected
        )
        XCTAssertEqual(
            SendFailureKind.classify(submit: .sessionBusy),
            .businessRejected
        )
        XCTAssertEqual(
            SendFailureKind.classify(submit: .decodingFailed(endpoint: "runs")),
            .unknown
        )
    }

    // MARK: 运行面分类

    func testClassifyRunFace() {
        XCTAssertEqual(
            SendFailureKind.classify(run: .runBillingExhausted),
            .runBilling
        )
        XCTAssertEqual(
            SendFailureKind.classify(run: .runTimedOut), .runTimeout
        )
        XCTAssertEqual(
            SendFailureKind.classify(run: .runNetworkInterrupted),
            .runNetwork
        )
        XCTAssertEqual(
            SendFailureKind.classify(run: .runServiceUnavailable),
            .runService
        )
        XCTAssertEqual(
            SendFailureKind.classify(run: .runFailedGeneric),
            .runGeneric
        )
        // 提交面错误误入 run 分类时回提交面口径兜底
        XCTAssertEqual(
            SendFailureKind.classify(
                run: .unexpectedStatus(endpoint: "runs", status: 500)
            ),
            .serverRejected
        )
    }

    // MARK: 准入与呈现集合

    func testAdmissionSets() {
        let auto = SendFailureKind.allCases.filter(\.allowsAutoRetry)
        XCTAssertEqual(
            Set(auto),
            [.offlineNotSent, .transportInterrupted, .hostUnreachable]
        )
        let global = SendFailureKind.allCases.filter(\.presentsGlobally)
        XCTAssertEqual(Set(global), [.authRejected, .serverRejected])
        let gates = SendFailureKind.allCases.filter(\.isWaitGate)
        XCTAssertEqual(gates, [.rateLimited])
        // 运行面全体不准自动（生成失败永不自动重发）
        for kind in SendFailureKind.allCases where kind.isRunFace {
            XCTAssertFalse(kind.allowsAutoRetry, "\(kind)")
        }
    }

    // MARK: 文案单表

    func testRunFaceCopyMatchesHermesError() {
        // run 面五句与 HermesError run* 档逐字同源，
        // 两处同句不许漂移
        let pairs: [(SendFailureKind, HermesError)] = [
            (.runBilling, .runBillingExhausted),
            (.runTimeout, .runTimedOut),
            (.runNetwork, .runNetworkInterrupted),
            (.runService, .runServiceUnavailable),
            (.runGeneric, .runFailedGeneric)
        ]
        for (kind, error) in pairs {
            XCTAssertEqual(
                SendFailureCopy.message(kind: kind),
                error.userMessage, "\(kind)"
            )
        }
    }

    func testCopyTableCoversAllKinds() {
        for kind in SendFailureKind.allCases {
            XCTAssertFalse(
                SendFailureCopy.message(kind: kind).isEmpty,
                "\(kind)"
            )
        }
    }

    func testHermesErrorFallbackCopySplit() {
        // 横扫 P5-1：162/171 同句兜底关账——未预料
        // 状态与服务端错误不再同句
        let unexpected = HermesError.unexpectedStatus(
            endpoint: "runs", status: 500
        )
        let server = HermesError.serverError(
            endpoint: "runs", status: 500, code: "x"
        )
        XCTAssertNotEqual(unexpected.userMessage, server.userMessage)
        XCTAssertEqual(
            server.userMessage, "服务器内部错误，请稍后再试。"
        )
        // 429 独立档：等待门口径，不是失败句
        let limited = HermesError.rateLimited(retryAfterSeconds: 2)
        XCTAssertTrue(limited.userMessage.contains("稍等"))
    }

    // MARK: 拼接收尾归一（P2-1/P2-2）

    func testJoiningReasonNormalizesTerminalPunctuation() {
        let withMark = SendFailureCopy.joiningReason(
            head: "会话链接失败，这条还没发出去：",
            reason: "服务器内部错误，请稍后再试。",
            tail: "链接恢复后重发。"
        )
        XCTAssertFalse(withMark.contains("。。"))
        XCTAssertEqual(
            withMark,
            "会话链接失败，这条还没发出去：服务器内部错误，请稍后再试。链接恢复后重发。"
        )
        let withoutMark = SendFailureCopy.joiningReason(
            head: "头：", reason: "没标点的理由", tail: "尾。"
        )
        XCTAssertEqual(withoutMark, "头：没标点的理由。尾。")
        let empty = SendFailureCopy.joiningReason(
            head: "头：", reason: "  ", tail: "尾。"
        )
        XCTAssertEqual(empty, "头：尾。")
    }

    // MARK: 双轴状态

    func testAcceptedStateAxes() {
        // 语义 1：受理态记账轴在队（remainsInQueue）、
        // 提交轴不自动接管（mayAutoResume=false，
        // 对账链管辖）
        XCTAssertTrue(ChatSendState.accepted.remainsInQueue)
        XCTAssertFalse(ChatSendState.accepted.mayAutoResume)
        XCTAssertTrue(ChatSendState.sending.remainsInQueue)
        XCTAssertFalse(ChatSendState.delivered.remainsInQueue)
    }

    // MARK: run 丢失终局（语义 6）

    func testMissingRunIsLostGates() {
        // 双闸取或（RunLedger 定版口径）：次数满 3
        // 或首查距今满 24h，任一即判丢失
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        // 两闸都不满：不判
        XCTAssertFalse(RunLedger.missingRunIsLost(
            missingCount: 2, firstMissingAt: t0,
            now: t0.addingTimeInterval(23 * 3600)
        ))
        // 次数闸满（年龄为零）：判
        XCTAssertTrue(RunLedger.missingRunIsLost(
            missingCount: 3, firstMissingAt: t0, now: t0
        ))
        // 年龄闸满（次数只有 1）：判
        XCTAssertTrue(RunLedger.missingRunIsLost(
            missingCount: 1, firstMissingAt: t0,
            now: t0.addingTimeInterval(24 * 3600)
        ))
        // 无首查时刻且次数不满：不判
        XCTAssertFalse(RunLedger.missingRunIsLost(
            missingCount: 2, firstMissingAt: nil,
            now: t0.addingTimeInterval(72 * 3600)
        ))
    }

    func testRunLedgerEntryLegacyDecode() throws {
        // 存量账本 JSON（无丢失累计二字段）须能解，
        // 缺键按零账，不许连坐整账
        let json = """
        {"threadID":"t","sessionID":"s","runID":"r",\
        "idempotencyKey":"k","userEntryID":"u",\
        "submittedAt":720000000,"stopRequested":false}
        """
        let decoded = try JSONDecoder().decode(
            RunLedgerEntry.self, from: Data(json.utf8)
        )
        XCTAssertEqual(decoded.missingReconcileCount, 0)
        XCTAssertNil(decoded.firstMissingAt)
        XCTAssertEqual(decoded.runID, "r")
    }

    func testRunSubmitRetryUnknownClassification() {
        struct Weird: Error {}
        XCTAssertEqual(
            RunSubmitRetry.classify(Weird()), .unknown
        )
        XCTAssertEqual(
            RunSubmitRetry.classify(HermesError.notSentOffline),
            .notSentOffline
        )
        XCTAssertEqual(
            RunSubmitRetry.classify(
                HermesError.rateLimited(retryAfterSeconds: nil)
            ),
            .rejected
        )
    }
}
