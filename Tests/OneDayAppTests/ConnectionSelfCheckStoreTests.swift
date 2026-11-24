import XCTest
import OneDayCore
@testable import OneDayApp

/// 连接自检编排钉测（DESIGN §357）：失败分型映射、
/// 离线桩全景（逐项如实、不假绿）、未配密钥口径、
/// 留痕按服务器隔离。脚本化客户端走 FailingHermes-
/// Client（全方法恒 unreachable，C-13 冻结桩）
@MainActor
final class ConnectionSelfCheckStoreTests: XCTestCase {

    private func makeSummaryStore() -> SelfCheckSummaryStore {
        let suite = UserDefaults(
            suiteName: "selfcheck-tests-\(UUID().uuidString)"
        )!
        return SelfCheckSummaryStore(defaults: suite)
    }

    private var testConfig: ServerConfig {
        ServerConfig(rawInput: "https://a.test")!
    }

    private func row(
        _ report: SelfCheckReport, _ id: String
    ) -> SelfCheckRow {
        guard let found = report.rows.first(where: { $0.id == id })
        else {
            XCTFail("缺行 \(id)")
            return SelfCheckRow(id: id, title: id, status: .unprobed)
        }
        return found
    }

    // MARK: - 失败分型映射

    func testClassifyMapping() {
        XCTAssertEqual(
            ConnectionSelfCheckStore.classify(
                HermesError.apiKeyRejected
            ),
            .unauthorized
        )
        XCTAssertEqual(
            ConnectionSelfCheckStore.classify(
                HermesError.unexpectedStatus(
                    endpoint: "能力接口", status: 503
                )
            ),
            .httpStatus(503)
        )
        XCTAssertEqual(
            ConnectionSelfCheckStore.classify(
                HermesError.serverError(
                    endpoint: "待批接口", status: 503,
                    code: "approval_projection_unavailable"
                )
            ),
            .serverCode("approval_projection_unavailable")
        )
        XCTAssertEqual(
            ConnectionSelfCheckStore.classify(
                HermesError.decodingFailed(endpoint: "能力接口")
            ),
            .decoding
        )
        XCTAssertEqual(
            ConnectionSelfCheckStore.classify(
                HermesError.unreachable("离线")
            ),
            .unreachable
        )
        XCTAssertEqual(
            ConnectionSelfCheckStore.classify(
                NSError(domain: "test", code: 1)
            ),
            .unreachable
        )
    }

    // MARK: - 离线全景（FailingHermesClient）

    func testRunWithUnreachableServerReportsHonestly() async throws {
        let summaryStore = makeSummaryStore()
        let store = ConnectionSelfCheckStore(
            summaryStore: summaryStore
        )
        await store.run(
            client: FailingHermesClient(), config: testConfig,
            apiKey: "key-a"
        )

        let report = try XCTUnwrap(store.report)
        XCTAssertFalse(store.isRunning)
        // 连不上：可达行异常、密钥行异常（探了没通），
        // 能力组整组未探——不许把没探到说成正常
        XCTAssertEqual(row(report, "reachable").status, .warn)
        XCTAssertEqual(
            row(report, "reachable").reason, "连不上服务器"
        )
        XCTAssertEqual(row(report, "credential").status, .warn)
        XCTAssertEqual(row(report, "feature-skills_api").status, .unprobed)
        XCTAssertEqual(row(report, "check-state_db").status, .unprobed)
        XCTAssertEqual(row(report, "extEnrollment").status, .unprobed)
        XCTAssertEqual(
            row(report, "extReactions").reason, "暂无会话可探"
        )
        XCTAssertGreaterThan(report.warnCount, 0)
        XCTAssertEqual(
            report.overallWord, "\(report.warnCount) 项异常"
        )
        // 留痕与报告同源、按服务器隔离
        let saved = summaryStore.summary(for: "https://a.test")
        XCTAssertEqual(saved?.word, report.overallWord)
        XCTAssertEqual(saved?.warnCount, report.warnCount)
        XCTAssertNil(summaryStore.summary(for: "https://b.test"))
    }

    func testRunWithoutAPIKeyMarksBearerFacesUnprobed() async throws {
        let store = ConnectionSelfCheckStore(
            summaryStore: makeSummaryStore()
        )
        await store.run(
            client: FailingHermesClient(), config: testConfig,
            apiKey: nil
        )

        let report = try XCTUnwrap(store.report)
        // 无密钥：带鉴权面不发请求、显未配密钥未探；
        // 免鉴权的可达面照常探（此处仍是连不上→异常）
        let credential = row(report, "credential")
        XCTAssertEqual(credential.status, .unprobed)
        XCTAssertEqual(
            credential.reason, "未配置密钥，这一面没探"
        )
        XCTAssertEqual(row(report, "extApprovals").status, .unprobed)
        XCTAssertEqual(row(report, "extGrants").status, .unprobed)
        XCTAssertEqual(row(report, "reachable").status, .warn)
    }
}
