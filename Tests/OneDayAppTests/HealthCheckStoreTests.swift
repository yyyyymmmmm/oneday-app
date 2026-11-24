import XCTest
import OneDayCore
@testable import OneDayApp

/// 体检引擎装配钉测（H1-a，台账 158）：执行口注入脚
/// 本，只验状态机本身——两组依次跑、跑中整面禁用且
/// 重入不双跑、一组失败不拖垮另一组、失败组可单独
/// 重试、结论摘要按服务器落痕。端点与日志解析的真
/// 形态在 OneDayCoreTests.OpsHealthTests 钉。
@MainActor
final class HealthCheckStoreTests: XCTestCase {

    private func makeSummaryStore() -> HealthSummaryStore {
        let suite = UserDefaults(
            suiteName: "healthcheck-tests-\(UUID().uuidString)"
        )!
        return HealthSummaryStore(defaults: suite)
    }

    private let doctorOK = HealthCheckStore.ActionResult(
        lines: ["◆ Python Environment", "✓ 环境正常", "✓ 依赖齐全"],
        exitCode: 0
    )
    private let auditOK = HealthCheckStore.ActionResult(
        lines: [
            "Found 0 known vulnerability finding(s) across 156 component(s)"
        ],
        exitCode: 0
    )

    func testRunAllFinishesBothGroupsAndSavesSummary() async {
        let summaryStore = makeSummaryStore()
        let store = HealthCheckStore(summaryStore: summaryStore)
        XCTAssertTrue(store.canStart)
        XCTAssertFalse(store.isRunning)

        await store.runAll(serverBase: "https://a.test") { action in
            switch action {
            case .doctor: return self.doctorOK
            case .securityAudit: return self.auditOK
            }
        }

        XCTAssertEqual(store.doctorPhase, .finished)
        XCTAssertEqual(store.auditPhase, .finished)
        XCTAssertEqual(store.doctorRun?.passCount, 2)
        XCTAssertEqual(store.auditRun?.totalFindings, 0)
        XCTAssertTrue(store.canStart)

        let saved = summaryStore.summary(for: "https://a.test")
        XCTAssertEqual(saved?.overall, .ok)
        XCTAssertEqual(saved?.doctor?.verdict, .ok)
        XCTAssertEqual(saved?.audit?.verdict, .ok)
        // 按服务器隔离：别的服务器读不到这份留痕
        XCTAssertNil(summaryStore.summary(for: "https://b.test"))
    }

    func testRunningDisablesStartAndReentryDoesNotDoubleRun() async {
        let summaryStore = makeSummaryStore()
        let store = HealthCheckStore(summaryStore: summaryStore)
        var doctorCalls = 0
        var auditCalls = 0
        let execute: HealthCheckStore.ActionExecutor = { action in
            switch action {
            case .doctor:
                doctorCalls += 1
                try await Task.sleep(for: .milliseconds(400))
                return self.doctorOK
            case .securityAudit:
                auditCalls += 1
                return self.auditOK
            }
        }

        let task = Task {
            await store.runAll(
                serverBase: "https://a.test", execute: execute
            )
        }
        // 让第一组进入跑中态后断言：整面禁用开始
        await Task.yield()
        XCTAssertTrue(store.isRunning)
        XCTAssertFalse(store.canStart)
        XCTAssertTrue(store.doctorPhase.isRunning)

        // 跑中重入：立即返回、不许再触发任何一组
        await store.runAll(
            serverBase: "https://a.test", execute: execute
        )
        await task.value

        XCTAssertEqual(doctorCalls, 1)
        XCTAssertEqual(auditCalls, 1)
        XCTAssertTrue(store.canStart)
    }

    func testGroupFailureIsIsolatedAndRetryable() async {
        let summaryStore = makeSummaryStore()
        let store = HealthCheckStore(summaryStore: summaryStore)

        await store.runAll(serverBase: "https://a.test") { action in
            switch action {
            case .doctor:
                throw HermesError.unreachable("桩")
            case .securityAudit:
                return self.auditOK
            }
        }

        // doctor 失败不拖垮 audit；失败文案是人话
        if case .failed(let message) = store.doctorPhase {
            XCTAssertEqual(message, "连不上服务器，检查网络后再试")
        } else {
            XCTFail("doctor 应为 failed，实际 \(store.doctorPhase)")
        }
        XCTAssertEqual(store.auditPhase, .finished)
        // 失败组留痕记没跑完，总判定随之没跑完
        var saved = summaryStore.summary(for: "https://a.test")
        XCTAssertEqual(saved?.doctor?.verdict, .incomplete)
        XCTAssertEqual(saved?.audit?.verdict, .ok)
        XCTAssertEqual(saved?.overall, .incomplete)

        // 单组重试 doctor：成功后留痕换新，audit 旧结论保留
        await store.retry(
            .doctor, serverBase: "https://a.test"
        ) { _ in
            self.doctorOK
        }
        XCTAssertEqual(store.doctorPhase, .finished)
        saved = summaryStore.summary(for: "https://a.test")
        XCTAssertEqual(saved?.doctor?.verdict, .ok)
        XCTAssertEqual(saved?.audit?.verdict, .ok)
        XCTAssertEqual(saved?.overall, .ok)
    }

    func testHumanMessages() {
        XCTAssertEqual(
            HealthCheckStore.humanMessage(
                for: HealthCheckEngineError.timedOut
            ),
            "等太久了，这一轮没等到结果"
        )
        XCTAssertEqual(
            HealthCheckStore.humanMessage(for: HermesError.sessionExpired),
            "登录已过期，重新连接后再试"
        )
        XCTAssertEqual(
            HealthCheckStore.humanMessage(
                for: HermesError.unexpectedStatus(
                    endpoint: "自检", status: 500
                )
            ),
            "这一项没跑成，稍后再试"
        )
    }
}
