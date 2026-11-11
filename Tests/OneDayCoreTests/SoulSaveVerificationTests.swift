import OneDayCore
import XCTest

/// soul 保存回读比对（§155 HUB-1）：只容忍首尾空白差，
/// 正文内部任何差异都判未确认——报成功的门槛在这里。
final class SoulSaveVerificationTests: XCTestCase {

    func testIdenticalContentConfirms() {
        XCTAssertTrue(SoulSaveVerification.isConfirmed(
            submitted: "# 人设\n我是三狗。", fetched: "# 人设\n我是三狗。"
        ))
    }

    func testTrailingNewlineDifferenceConfirms() {
        XCTAssertTrue(SoulSaveVerification.isConfirmed(
            submitted: "我是三狗。", fetched: "我是三狗。\n\n"
        ))
    }

    func testLeadingAndTrailingWhitespaceConfirms() {
        XCTAssertTrue(SoulSaveVerification.isConfirmed(
            submitted: "  我是三狗。\n", fetched: "我是三狗。"
        ))
    }

    func testInnerCharacterDifferenceRejects() {
        XCTAssertFalse(SoulSaveVerification.isConfirmed(
            submitted: "我是三狗。", fetched: "我是二狗。"
        ))
    }

    func testInnerWhitespaceDifferenceRejects() {
        XCTAssertFalse(SoulSaveVerification.isConfirmed(
            submitted: "我是 三狗。", fetched: "我是三狗。"
        ))
    }

    func testEmptyBothSidesConfirms() {
        XCTAssertTrue(SoulSaveVerification.isConfirmed(
            submitted: "", fetched: " \n"
        ))
    }

    func testEmptyVersusContentRejects() {
        XCTAssertFalse(SoulSaveVerification.isConfirmed(
            submitted: "", fetched: "我是三狗。"
        ))
    }
}
