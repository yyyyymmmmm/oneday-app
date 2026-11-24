import XCTest
@testable import OneDayCore

/// 主线主动认领判定（根治版包 1，DESIGN §330）钉
/// 死：①零候选（含标题不全等）无从认领②恰一条直
/// 接认领③归档候选认领且归档位随判定交出（保持归
/// 档）④多条按 oneday-main- 前缀池＋最近活动＋id
/// 升序选定⑤删除账排除——唯一候选被排除回零候
/// 选、部分排除后按剩余集判定（排除不计入匹配数）
final class MainlineClaimTests: XCTestCase {

    private func candidate(
        _ id: String, title: String? = "主线",
        activity: TimeInterval? = nil, archived: Bool = false
    ) -> MainlineAdoptionCandidate {
        MainlineAdoptionCandidate(
            id: id, title: title, lastActivityAt: activity,
            isArchived: archived
        )
    }

    private func directive(
        _ candidates: [MainlineAdoptionCandidate],
        excluded: Set<String> = []
    ) -> MainlineClaimDirective {
        MainlineClaimDirective.directive(
            title: "主线", candidates: candidates,
            excludedIDs: excluded
        )
    }

    // MARK: - 零候选

    func testEmptyDirectoryNoCandidate() {
        XCTAssertEqual(directive([]), .noCandidate)
    }

    func testTitleMustMatchExactly() {
        XCTAssertEqual(
            directive([
                candidate("s-1", title: "主线（旧）"),
                candidate("s-2", title: "我的主线"),
                candidate("s-3", title: nil),
            ]),
            .noCandidate
        )
    }

    // MARK: - 恰一条

    func testSingleCandidateClaims() {
        XCTAssertEqual(
            directive([candidate("oneday-main-a", activity: 10)]),
            .claim(sessionID: "oneday-main-a", isArchived: false)
        )
    }

    func testSingleArchivedCandidateClaimsKeepingArchived() {
        XCTAssertEqual(
            directive([
                candidate("oneday-main-a", activity: 10, archived: true)
            ]),
            .claim(sessionID: "oneday-main-a", isArchived: true)
        )
    }

    // MARK: - 多条选定序（与 §220 共用核）

    func testMultiplePrefersPrefixedPoolThenRecentActivity() {
        XCTAssertEqual(
            directive([
                candidate("other-1", activity: 999),
                candidate("oneday-main-old", activity: 100),
                candidate("oneday-main-new", activity: 200),
            ]),
            .claimAmongMultiple(
                sessionID: "oneday-main-new", matchCount: 3,
                isArchived: false
            )
        )
    }

    func testMultipleWithoutPrefixedPoolUsesAllMatches() {
        XCTAssertEqual(
            directive([
                candidate("srv-b", activity: 100),
                candidate("srv-a", activity: 300),
            ]),
            .claimAmongMultiple(
                sessionID: "srv-a", matchCount: 2, isArchived: false
            )
        )
    }

    func testMultipleTieBreakByIDAscending() {
        XCTAssertEqual(
            directive([
                candidate("oneday-main-b", activity: 100),
                candidate("oneday-main-a", activity: 100),
            ]),
            .claimAmongMultiple(
                sessionID: "oneday-main-a", matchCount: 2,
                isArchived: false
            )
        )
    }

    func testMultiplePickCarriesArchivedFlagOfPick() {
        XCTAssertEqual(
            directive([
                candidate("oneday-main-a", activity: 100),
                candidate(
                    "oneday-main-b", activity: 200, archived: true
                ),
            ]),
            .claimAmongMultiple(
                sessionID: "oneday-main-b", matchCount: 2,
                isArchived: true
            )
        )
    }

    // MARK: - 删除账排除（防复活）

    func testExcludedOnlyCandidateYieldsNoCandidate() {
        XCTAssertEqual(
            directive(
                [candidate("oneday-main-a", activity: 10)],
                excluded: ["oneday-main-a"]
            ),
            .noCandidate
        )
    }

    func testExcludedOneOfTwoClaimsTheOtherAsSingle() {
        XCTAssertEqual(
            directive(
                [
                    candidate("oneday-main-a", activity: 200),
                    candidate("oneday-main-b", activity: 100),
                ],
                excluded: ["oneday-main-a"]
            ),
            .claim(sessionID: "oneday-main-b", isArchived: false)
        )
    }

    func testExcludedNonCandidateDoesNotChangeOutcome() {
        XCTAssertEqual(
            directive(
                [candidate("oneday-main-a", activity: 10)],
                excluded: ["someone-else"]
            ),
            .claim(sessionID: "oneday-main-a", isArchived: false)
        )
    }
}
