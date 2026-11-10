import XCTest
@testable import OneDayCore

/// 0.36.31（件三）：文件接入预检钉死——大小闸
/// 100MB 与服务端契约对齐、先查后读的判定边界、
/// 被拒汇总点名的名单拼装（1/2/3+ 与混合两类）
final class FileIntakeTests: XCTestCase {

    // MARK: 大小预检判定

    func testSizeVerdictAcceptsAtLimit() {
        XCTAssertEqual(
            FileIntake.sizeVerdict(declaredSize: FileIntake.maxFileBytes),
            .acceptable
        )
    }

    func testSizeVerdictRejectsAboveLimit() {
        XCTAssertEqual(
            FileIntake.sizeVerdict(
                declaredSize: FileIntake.maxFileBytes + 1
            ),
            .tooLarge
        )
    }

    func testSizeVerdictAcceptsZeroAndSmall() {
        XCTAssertEqual(FileIntake.sizeVerdict(declaredSize: 0), .acceptable)
        XCTAssertEqual(FileIntake.sizeVerdict(declaredSize: 1), .acceptable)
    }

    func testSizeVerdictUnknownWhenSizeMissing() {
        XCTAssertEqual(FileIntake.sizeVerdict(declaredSize: nil), .unknownSize)
    }

    func testIsOversizedBoundary() {
        XCTAssertFalse(FileIntake.isOversized(byteCount: FileIntake.maxFileBytes))
        XCTAssertTrue(
            FileIntake.isOversized(byteCount: FileIntake.maxFileBytes + 1)
        )
        XCTAssertFalse(FileIntake.isOversized(byteCount: 0))
    }

    // MARK: 汇总点名

    func testRejectionNoticeNilWhenNothingRejected() {
        XCTAssertNil(FileIntake.rejectionNotice(oversized: [], unreadable: []))
    }

    func testRejectionNoticeSingleOversized() {
        XCTAssertEqual(
            FileIntake.rejectionNotice(oversized: ["报告.pdf"], unreadable: []),
            "「报告.pdf」超过 100MB，未加入待发列表。"
        )
    }

    func testRejectionNoticeTwoOversized() {
        XCTAssertEqual(
            FileIntake.rejectionNotice(
                oversized: ["a.zip", "b.zip"], unreadable: []
            ),
            "「a.zip」、「b.zip」超过 100MB，未加入待发列表。"
        )
    }

    func testRejectionNoticeThreeOversizedFoldsToCount() {
        XCTAssertEqual(
            FileIntake.rejectionNotice(
                oversized: ["a.zip", "b.zip", "c.zip"], unreadable: []
            ),
            "「a.zip」、「b.zip」等 3 个文件超过 100MB，未加入待发列表。"
        )
    }

    func testRejectionNoticeSingleUnreadable() {
        XCTAssertEqual(
            FileIntake.rejectionNotice(oversized: [], unreadable: ["x.txt"]),
            "读取「x.txt」失败，未加入待发列表。"
        )
    }

    func testRejectionNoticeTwoUnreadable() {
        XCTAssertEqual(
            FileIntake.rejectionNotice(
                oversized: [], unreadable: ["a.txt", "b.txt"]
            ),
            "「a.txt」、「b.txt」没能读取，未加入待发列表。"
        )
    }

    func testRejectionNoticeManyUnreadableFoldsToCount() {
        XCTAssertEqual(
            FileIntake.rejectionNotice(
                oversized: [], unreadable: ["a.txt", "b.txt", "c.txt", "d.txt"]
            ),
            "「a.txt」、「b.txt」等 4 个文件没能读取，未加入待发列表。"
        )
    }

    func testRejectionNoticeMixedBothKinds() {
        XCTAssertEqual(
            FileIntake.rejectionNotice(
                oversized: ["big.zip"], unreadable: ["x.txt"]
            ),
            "「big.zip」超过 100MB，未加入待发列表。读取「x.txt」失败，未加入待发列表。"
        )
    }
}
