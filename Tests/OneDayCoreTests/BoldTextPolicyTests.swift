import XCTest
@testable import OneDayCore

/// 粗体文字策略闸（0.36.0，A11Y-S3）：关时不干
/// 预（nil）、开时根级 semibold；升档表单调封顶。
final class BoldTextPolicyTests: XCTestCase {

    func testRootWeightOffIsNil() {
        XCTAssertNil(BoldTextPolicy.rootWeight(boldTextEnabled: false))
    }

    func testRootWeightOnIsSemibold() {
        XCTAssertEqual(
            BoldTextPolicy.rootWeight(boldTextEnabled: true), .semibold
        )
    }

    func testBumpTable() {
        XCTAssertEqual(BoldTextPolicy.bumped(.regular), .medium)
        XCTAssertEqual(BoldTextPolicy.bumped(.medium), .semibold)
        XCTAssertEqual(BoldTextPolicy.bumped(.semibold), .bold)
        XCTAssertEqual(BoldTextPolicy.bumped(.bold), .bold)
    }
}
