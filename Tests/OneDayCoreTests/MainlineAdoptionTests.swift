import XCTest
@testable import OneDayCore

/// 主线收养分流（DESIGN §216）四分支钉死：①非 400/
/// 非 invalid_title 不触发②触发面成立但零匹配无从
/// 收养③恰一条直接收养④多条按 oneday-main- 前缀＋
/// 最近活动选定；外加标题全等口径（包含不算）、错
/// 误码解析（网关 error.code 形）与模型回读收口判定
final class MainlineAdoptionTests: XCTestCase {

    private func candidate(
        _ id: String, title: String?, activity: TimeInterval?
    ) -> MainlineAdoptionCandidate {
        MainlineAdoptionCandidate(
            id: id, title: title, lastActivityAt: activity
        )
    }

    // MARK: - 分支一：不触发（口径外错误照抛）

    func testNon400StatusNotApplicable() {
        XCTAssertEqual(
            MainlineAdoptionDirective.directive(
                status: 409, serverCode: "invalid_title", title: "主线",
                candidates: [candidate("oneday-main-a", title: "主线", activity: 1)]
            ),
            .notApplicable
        )
    }

    func testOtherCodeNotApplicable() {
        XCTAssertEqual(
            MainlineAdoptionDirective.directive(
                status: 400, serverCode: "invalid_params", title: "主线",
                candidates: [candidate("oneday-main-a", title: "主线", activity: 1)]
            ),
            .notApplicable
        )
    }

    func testMissingCodeNotApplicable() {
        XCTAssertEqual(
            MainlineAdoptionDirective.directive(
                status: 400, serverCode: nil, title: "主线",
                candidates: [candidate("oneday-main-a", title: "主线", activity: 1)]
            ),
            .notApplicable
        )
    }

    // MARK: - 分支二：零匹配无从收养

    func testZeroMatchesNoCandidate() {
        XCTAssertEqual(
            MainlineAdoptionDirective.directive(
                status: 400, serverCode: "invalid_title", title: "主线",
                candidates: [
                    candidate("oneday-side-x", title: "旁聊", activity: 9),
                    candidate("oneday-main-y", title: nil, activity: 9),
                ]
            ),
            .noCandidate
        )
    }

    /// 标题必须全等：包含目标标题的长标题不算匹配
    func testTitleMatchIsExactNotSubstring() {
        XCTAssertEqual(
            MainlineAdoptionDirective.directive(
                status: 400, serverCode: "invalid_title", title: "主线",
                candidates: [
                    candidate("oneday-main-z", title: "主线（旧）", activity: 9),
                ]
            ),
            .noCandidate
        )
    }

    // MARK: - 分支三：恰一条直接收养（本案实况）

    func testSingleMatchAdopted() {
        XCTAssertEqual(
            MainlineAdoptionDirective.directive(
                status: 400, serverCode: "invalid_title", title: "主线",
                candidates: [
                    candidate("oneday-side-x", title: "聊聊婚礼", activity: 99),
                    candidate(
                        "oneday-main-bfb4e3ed", title: "主线", activity: 10
                    ),
                ]
            ),
            .adopt(sessionID: "oneday-main-bfb4e3ed")
        )
    }

    // MARK: - 分支四：多条按前缀＋最近活动

    func testMultiplePrefersMainPrefixThenMostRecent() {
        XCTAssertEqual(
            MainlineAdoptionDirective.directive(
                status: 400, serverCode: "invalid_title", title: "主线",
                candidates: [
                    candidate("web-1", title: "主线", activity: 500),
                    candidate("oneday-main-old", title: "主线", activity: 100),
                    candidate("oneday-main-new", title: "主线", activity: 300),
                ]
            ),
            .adoptAmongMultiple(sessionID: "oneday-main-new", matchCount: 3)
        )
    }

    func testMultipleWithoutPrefixFallsBackToMostRecent() {
        XCTAssertEqual(
            MainlineAdoptionDirective.directive(
                status: 400, serverCode: "invalid_title", title: "主线",
                candidates: [
                    candidate("web-1", title: "主线", activity: 500),
                    candidate("web-2", title: "主线", activity: 900),
                ]
            ),
            .adoptAmongMultiple(sessionID: "web-2", matchCount: 2)
        )
    }

    /// 活动时刻缺失排末尾；同值按 id 升序保证确定性
    func testMultipleTieBreakDeterministic() {
        XCTAssertEqual(
            MainlineAdoptionDirective.directive(
                status: 400, serverCode: "invalid_title", title: "主线",
                candidates: [
                    candidate("oneday-main-b", title: "主线", activity: nil),
                    candidate("oneday-main-a", title: "主线", activity: nil),
                ]
            ),
            .adoptAmongMultiple(sessionID: "oneday-main-a", matchCount: 2)
        )
    }

    // MARK: - GatewayErrorCode 解析

    func testGatewayErrorCodeParsesErrorObject() {
        let body = Data(
            #"{"error": {"message": "Title '主线' is already in use", "type": "invalid_request_error", "param": null, "code": "invalid_title"}}"#
                .utf8
        )
        XCTAssertEqual(GatewayErrorCode.parse(body), "invalid_title")
    }

    func testGatewayErrorCodeRejectsOtherShapes() {
        XCTAssertNil(
            GatewayErrorCode.parse(Data(#"{"detail": "invalid_title"}"#.utf8))
        )
        XCTAssertNil(
            GatewayErrorCode.parse(Data(#"{"error": {"message": "x"}}"#.utf8))
        )
        XCTAssertNil(GatewayErrorCode.parse(Data("not json".utf8)))
        XCTAssertNil(
            GatewayErrorCode.parse(
                Data(#"{"error": {"code": "bad code!"}}"#.utf8)
            )
        )
    }

    // MARK: - 模型回读收口判定

    func testModelReconcileAdoptsServerWhenDiffers() {
        XCTAssertEqual(
            MainlineModelReconcile.serverModelToAdopt(
                serverModel: "claude-sonnet-4-6",
                localModel: "claude-haiku-4-5-20251001"
            ),
            "claude-sonnet-4-6"
        )
    }

    func testModelReconcileKeepsLocalWhenSameOrServerMissing() {
        XCTAssertNil(
            MainlineModelReconcile.serverModelToAdopt(
                serverModel: "claude-sonnet-4-6",
                localModel: "claude-sonnet-4-6"
            )
        )
        XCTAssertNil(
            MainlineModelReconcile.serverModelToAdopt(
                serverModel: nil, localModel: "claude-haiku-4-5-20251001"
            )
        )
        XCTAssertNil(
            MainlineModelReconcile.serverModelToAdopt(
                serverModel: "", localModel: "claude-haiku-4-5-20251001"
            )
        )
    }
}
