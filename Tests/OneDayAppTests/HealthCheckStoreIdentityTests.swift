import XCTest
import OneDayCore
@testable import OneDayApp

/// 身份对账组装配钉测（H1-d，台账 158）：取数口注
/// 入 fixture 快照，只验状态机——三组依次跑完落痕、
/// 身份组出问题不拖垮体检两组、取数失败记「没跑
/// 完」、单组重试只动身份组、两组版 runAll 不冲掉
/// 身份留痕。判定口径本体在 OneDayCoreTests
/// .OpsIdentityTests 钉。
@MainActor
final class HealthCheckStoreIdentityTests: XCTestCase {

    private func makeSummaryStore(
        defaults: UserDefaults? = nil
    ) -> HealthSummaryStore {
        let suite = defaults ?? UserDefaults(
            suiteName: "health-identity-tests-\(UUID().uuidString)"
        )!
        return HealthSummaryStore(defaults: suite)
    }

    private let doctorOK = HealthCheckStore.ActionResult(
        lines: ["◆ Python Environment", "✓ 环境正常"],
        exitCode: 0
    )
    private let auditOK = HealthCheckStore.ActionResult(
        lines: [
            "Found 0 known vulnerability finding(s) across 156 component(s)"
        ],
        exitCode: 0
    )

    private var okExecutor: HealthCheckStore.ActionExecutor {
        { action in
            switch action {
            case .doctor: return self.doctorOK
            case .securityAudit: return self.auditOK
            }
        }
    }

    /// 全一致快照：绑定命中、网关在跑、目录完整
    private let consistentInput = IdentityReconciliationInput(
        boundMainSessionID: "main-1",
        expectedMainTitle: "主线",
        catalog: .init(rows: [
            .init(
                id: "main-1", title: "主线",
                isArchived: false, messageCount: 42
            ),
        ]),
        gateway: .init(
            running: true, state: "running",
            apiServerState: "connected", version: "0.23.0"
        ),
        currentProfile: "default"
    )

    /// 绑定失效快照：本地绑定的 id 服务端目录里没有
    private let driftedInput = IdentityReconciliationInput(
        boundMainSessionID: "main-gone",
        expectedMainTitle: "主线",
        catalog: .init(rows: [
            .init(
                id: "main-1", title: "主线",
                isArchived: false, messageCount: 42
            ),
        ]),
        gateway: .init(
            running: true, state: "running",
            apiServerState: "connected", version: "0.23.0"
        ),
        currentProfile: "default"
    )

    func testRunAllWithIdentityFinishesAndSavesSummary() async {
        let summaryStore = makeSummaryStore()
        let store = HealthCheckStore(summaryStore: summaryStore)

        await store.runAll(
            serverBase: "https://a.test", execute: okExecutor,
            fetchIdentity: { self.consistentInput }
        )

        XCTAssertEqual(store.doctorPhase, .finished)
        XCTAssertEqual(store.auditPhase, .finished)
        XCTAssertEqual(store.identityPhase, .finished)
        XCTAssertEqual(store.identityRun?.verdict, .ok)
        XCTAssertEqual(store.identityRun?.currentProfile, "default")

        let saved = summaryStore.summary(for: "https://a.test")
        XCTAssertEqual(saved?.identity?.verdict, .ok)
        XCTAssertEqual(saved?.identity?.passCount, 3)
        XCTAssertEqual(saved?.overall, .ok)
    }

    func testIdentityProblemDoesNotBlockOtherGroups() async {
        let summaryStore = makeSummaryStore()
        let store = HealthCheckStore(summaryStore: summaryStore)

        await store.runAll(
            serverBase: "https://a.test", execute: okExecutor,
            fetchIdentity: { self.driftedInput }
        )

        XCTAssertEqual(store.doctorPhase, .finished)
        XCTAssertEqual(store.auditPhase, .finished)
        XCTAssertEqual(store.identityPhase, .finished)
        XCTAssertEqual(store.identityRun?.verdict, .problem)

        let saved = summaryStore.summary(for: "https://a.test")
        XCTAssertEqual(saved?.doctor?.verdict, .ok)
        XCTAssertEqual(saved?.audit?.verdict, .ok)
        XCTAssertEqual(saved?.identity?.verdict, .problem)
        XCTAssertEqual(saved?.identity?.failCount, 1)
        XCTAssertEqual(saved?.overall, .problem)
    }

    func testIdentityFetchFailureMarksGroupFailed() async {
        let summaryStore = makeSummaryStore()
        let store = HealthCheckStore(summaryStore: summaryStore)

        await store.runAll(
            serverBase: "https://a.test", execute: okExecutor,
            fetchIdentity: {
                throw HermesError.unreachable("离线")
            }
        )

        XCTAssertEqual(store.doctorPhase, .finished)
        XCTAssertEqual(store.auditPhase, .finished)
        if case .failed = store.identityPhase {} else {
            XCTFail("身份组应为 failed，实际 \(store.identityPhase)")
        }
        XCTAssertNil(store.identityRun)

        let saved = summaryStore.summary(for: "https://a.test")
        XCTAssertEqual(saved?.doctor?.verdict, .ok)
        XCTAssertEqual(saved?.identity?.verdict, .incomplete)
        XCTAssertEqual(saved?.overall, .incomplete)
    }

    func testRetryIdentityOnlyRerunsIdentityGroup() async {
        let summaryStore = makeSummaryStore()
        let store = HealthCheckStore(summaryStore: summaryStore)
        var doctorCalls = 0
        let countingExecutor: HealthCheckStore.ActionExecutor = {
            action in
            if action == .doctor { doctorCalls += 1 }
            switch action {
            case .doctor: return self.doctorOK
            case .securityAudit: return self.auditOK
            }
        }

        await store.runAll(
            serverBase: "https://a.test",
            execute: countingExecutor,
            fetchIdentity: { self.driftedInput }
        )
        XCTAssertEqual(
            summaryStore.summary(for: "https://a.test")?
                .identity?.verdict, .problem
        )

        await store.retryIdentity(
            serverBase: "https://a.test",
            fetchIdentity: { self.consistentInput }
        )

        XCTAssertEqual(doctorCalls, 1)
        XCTAssertEqual(store.identityRun?.verdict, .ok)
        let saved = summaryStore.summary(for: "https://a.test")
        XCTAssertEqual(saved?.identity?.verdict, .ok)
        XCTAssertEqual(saved?.doctor?.verdict, .ok)
        XCTAssertEqual(saved?.overall, .ok)
    }

    func testTwoGroupRunAllKeepsPreviousIdentitySummary() async {
        let summaryStore = makeSummaryStore()
        let store = HealthCheckStore(summaryStore: summaryStore)

        await store.runAll(
            serverBase: "https://a.test", execute: okExecutor,
            fetchIdentity: { self.driftedInput }
        )
        XCTAssertEqual(
            summaryStore.summary(for: "https://a.test")?
                .identity?.verdict, .problem
        )

        // H1-a 两组版口：身份组不参与，留痕沿用上次，
        // 不许被冲成「没跑过」
        await store.runAll(
            serverBase: "https://a.test", execute: okExecutor
        )
        let saved = summaryStore.summary(for: "https://a.test")
        XCTAssertEqual(saved?.identity?.verdict, .problem)
        XCTAssertEqual(saved?.doctor?.verdict, .ok)
    }

    func testIdentitySummaryRoundTripsThroughDefaults() async {
        let suite = UserDefaults(
            suiteName: "health-identity-rt-\(UUID().uuidString)"
        )!
        let summaryStore = makeSummaryStore(defaults: suite)
        let store = HealthCheckStore(summaryStore: summaryStore)

        await store.runAll(
            serverBase: "https://a.test", execute: okExecutor,
            fetchIdentity: { self.driftedInput }
        )

        let reread = HealthSummaryStore(defaults: suite)
        let saved = reread.summary(for: "https://a.test")
        XCTAssertEqual(saved?.identity?.verdict, .problem)
        XCTAssertEqual(saved?.identity?.failCount, 1)
        XCTAssertEqual(
            saved?.identity?.headline, "身份对账发现 1 项对不上"
        )
        XCTAssertEqual(saved?.overall, .problem)
    }
}
