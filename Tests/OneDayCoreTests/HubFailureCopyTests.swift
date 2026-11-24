import XCTest
@testable import OneDayCore

/// 中枢失败人话钉测（§344，中枢四欠账·失败给人
/// 话）：监测详情「失败原因」的呈现文案单源
/// MonitorPresentation.failureReasonText——服务端
/// lastError 原文先过 §233 用户安全门（ServerError
/// Text），过门原样、不过门/为空落通用句、非失败
/// 态恒 nil。旧版详情页把 lastError 红字直出，英
/// 文技术串原样露面，本组钉死收口后的口径
final class HubFailureCopyTests: XCTestCase {

    private func makeMonitor(
        lastResult: String?,
        lastError: String?
    ) -> BridgeMonitor {
        BridgeMonitor(
            id: "mon_1", name: "价格监测",
            target: "https://example.com/item",
            scheduleText: "每小时", cronJobId: "job_1",
            enabled: true, lastCheckedAt: 1_700_000_000,
            lastResult: lastResult, lastError: lastError,
            unreadChanges: 0, latestChangeSummary: nil,
            latestChangeAt: nil,
            createdAt: 1_700_000_000, updatedAt: 1_700_000_000
        )
    }

    func testHumanReasonPassesThrough() {
        let monitor = makeMonitor(
            lastResult: "failed", lastError: "目标站点返回了 403"
        )
        XCTAssertEqual(
            MonitorPresentation.failureReasonText(of: monitor),
            "目标站点返回了 403"
        )
    }

    func testEnglishTechnicalReasonFallsBackToGeneric() {
        let monitor = makeMonitor(
            lastResult: "failed",
            lastError: "Connection reset by peer (errno 54)"
        )
        XCTAssertEqual(
            MonitorPresentation.failureReasonText(of: monitor),
            "检查失败，服务端没给出能显示的原因。"
        )
    }

    func testStackLikeReasonFallsBackToGeneric() {
        let monitor = makeMonitor(
            lastResult: "failed",
            lastError: "Traceback (most recent call last): 检查器内部异常堆栈"
        )
        XCTAssertEqual(
            MonitorPresentation.failureReasonText(of: monitor),
            "检查失败，服务端没给出能显示的原因。"
        )
    }

    func testMissingReasonFallsBackToGeneric() {
        let monitor = makeMonitor(lastResult: "failed", lastError: nil)
        XCTAssertEqual(
            MonitorPresentation.failureReasonText(of: monitor),
            "检查失败，服务端没给出能显示的原因。"
        )
    }

    func testEmptyReasonFallsBackToGeneric() {
        let monitor = makeMonitor(lastResult: "failed", lastError: "")
        XCTAssertEqual(
            MonitorPresentation.failureReasonText(of: monitor),
            "检查失败，服务端没给出能显示的原因。"
        )
    }

    func testNonFailedStatesHaveNoReason() {
        for result in ["changed", "unchanged"] {
            let monitor = makeMonitor(
                lastResult: result, lastError: "残留错误原文"
            )
            XCTAssertNil(
                MonitorPresentation.failureReasonText(of: monitor),
                "非失败态不应出原因行：\(result)"
            )
        }
        let neverChecked = makeMonitor(lastResult: nil, lastError: nil)
        XCTAssertNil(
            MonitorPresentation.failureReasonText(of: neverChecked)
        )
    }
}
