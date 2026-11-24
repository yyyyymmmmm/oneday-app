import OneDayCore
import XCTest

/// G-03 人话化（DESIGN §389，台账 120）：四类底表
/// （网络/鉴权/服务端/未知）分类钉测＋主文案洁净
/// 钉测（状态码/子系统名永不进 userMessage）＋诊
/// 断详情承接钉测（技术原文只许在 diagnostic-
/// Detail）＋分页被拒判定（台账 117 降级触发口）。
final class HermesErrorG03Tests: XCTestCase {

    private let zh = Locale(identifier: "zh-Hans")

    // MARK: - 四类映射底表

    func testCategoryTableNetwork() {
        XCTAssertEqual(HermesError.unreachable("x").category, .network)
        XCTAssertEqual(HermesError.transientNetwork.category, .network)
        XCTAssertEqual(HermesError.runNetworkInterrupted.category, .network)
    }

    func testCategoryTableAuthentication() {
        XCTAssertEqual(HermesError.loginRejected.category, .authentication)
        XCTAssertEqual(HermesError.loginRateLimited.category, .authentication)
        XCTAssertEqual(HermesError.loginFailed(status: 401).category, .authentication)
        XCTAssertEqual(HermesError.apiKeyRejected.category, .authentication)
        XCTAssertEqual(HermesError.sessionExpired.category, .authentication)
        XCTAssertEqual(HermesError.enrollmentCodeInvalid.category, .authentication)
        XCTAssertEqual(HermesError.enrollmentCodeExpired.category, .authentication)
        XCTAssertEqual(HermesError.enrollmentLocked.category, .authentication)
        XCTAssertEqual(HermesError.enrollmentTooManyPending.category, .authentication)
    }

    func testCategoryTableServer() {
        XCTAssertEqual(HermesError.healthCheckFailed(status: 503).category, .server)
        XCTAssertEqual(
            HermesError.unexpectedStatus(endpoint: "接口", status: 500).category,
            .server
        )
        XCTAssertEqual(
            HermesError.serverError(endpoint: "接口", status: 500, code: "x").category,
            .server
        )
        XCTAssertEqual(HermesError.decodingFailed(endpoint: "接口").category, .server)
        XCTAssertEqual(HermesError.sessionBusy.category, .server)
        XCTAssertEqual(HermesError.runServiceUnavailable.category, .server)
        XCTAssertEqual(HermesError.runBillingExhausted.category, .server)
        XCTAssertEqual(HermesError.runTimedOut.category, .server)
        XCTAssertEqual(HermesError.speechProviderUnavailable.category, .server)
        XCTAssertEqual(HermesError.reactionTargetGone.category, .server)
        XCTAssertEqual(HermesError.modelNotUpstream("m").category, .server)
    }

    func testCategoryTableUnknown() {
        XCTAssertEqual(HermesError.invalidServerAddress.category, .unknown)
        XCTAssertEqual(HermesError.cancelled.category, .unknown)
        XCTAssertEqual(HermesError.demoLimitReached.category, .unknown)
        XCTAssertEqual(HermesError.runFailedGeneric.category, .unknown)
    }

    func testCategoryHeadlinesAreDistinctAndHuman() {
        let headlines = HermesErrorCategory.allCases.map {
            $0.headline(locale: zh)
        }
        XCTAssertEqual(Set(headlines).count, 4, "四类底表文案必须互不相同")
        for headline in headlines {
            XCTAssertFalse(headline.isEmpty)
            XCTAssertFalse(
                headline.contains("HTTP"),
                "底表文案不许带技术字样：\(headline)"
            )
        }
    }

    // MARK: - 主文案洁净（G-03 本体）

    func testUserMessageNeverCarriesStatusOrEndpoint() {
        let endpoint = "内部子系统XYZ"
        let cases: [HermesError] = [
            .healthCheckFailed(status: 503),
            .loginFailed(status: 401),
            .unexpectedStatus(endpoint: endpoint, status: 500),
            .serverError(endpoint: endpoint, status: 502, code: "bad_gateway"),
            .decodingFailed(endpoint: endpoint),
        ]
        for error in cases {
            let message = error.userMessage(locale: zh)
            XCTAssertFalse(
                message.contains("503") || message.contains("401")
                    || message.contains("500") || message.contains("502"),
                "\(error) 的主文案泄漏状态码：\(message)"
            )
            XCTAssertFalse(
                message.contains(endpoint),
                "\(error) 的主文案泄漏子系统名：\(message)"
            )
            XCTAssertFalse(
                message.contains("状态"),
                "\(error) 的主文案仍在报状态：\(message)"
            )
        }
    }

    // MARK: - 诊断详情承接

    func testDiagnosticDetailCarriesTechnicalFacts() {
        XCTAssertEqual(
            HermesError.healthCheckFailed(status: 503).diagnosticDetail,
            "健康检查 · HTTP 503"
        )
        XCTAssertEqual(
            HermesError.loginFailed(status: 401).diagnosticDetail,
            "登录 · HTTP 401"
        )
        XCTAssertEqual(
            HermesError.unexpectedStatus(endpoint: "会话消息", status: 400)
                .diagnosticDetail,
            "会话消息 · HTTP 400"
        )
        XCTAssertEqual(
            HermesError.serverError(
                endpoint: "会话消息", status: 400, code: "invalid_pagination"
            ).diagnosticDetail,
            "会话消息 · HTTP 400 · invalid_pagination"
        )
        XCTAssertEqual(
            HermesError.decodingFailed(endpoint: "会话消息").diagnosticDetail,
            "会话消息 · 响应解码失败"
        )
        // 无技术细节的错误不许硬造详情（横幅不显详情钮）
        XCTAssertNil(HermesError.transientNetwork.diagnosticDetail)
        XCTAssertNil(HermesError.sessionExpired.diagnosticDetail)
        XCTAssertNil(HermesError.cancelled.diagnosticDetail)
    }

    // MARK: - 分页被拒判定（台账 117）

    func testPaginationRejectedPredicate() {
        XCTAssertTrue(
            HermesError.serverError(
                endpoint: "会话消息", status: 400, code: "invalid_pagination"
            ).isPaginationRejected
        )
        XCTAssertTrue(
            HermesError.unexpectedStatus(endpoint: "会话消息", status: 400)
                .isPaginationRejected
        )
        XCTAssertFalse(
            HermesError.serverError(
                endpoint: "会话消息", status: 400, code: "other_code"
            ).isPaginationRejected
        )
        XCTAssertFalse(
            HermesError.unexpectedStatus(endpoint: "会话消息", status: 500)
                .isPaginationRejected
        )
        XCTAssertFalse(HermesError.transientNetwork.isPaginationRejected)
        XCTAssertFalse(HermesError.sessionExpired.isPaginationRejected)
    }
}
