import OneDayCore
import XCTest

/// 审批桥钥匙状态判定（§31 追加件）：设置页只认这组纯
/// 函数判「未设置／已设置」，Keychain 读写在 App 层走同
/// 一键，状态一律由回读值派生、不靠本地标记。
final class WriteGateKeyStatusTests: XCTestCase {

    func testNilIsNotSet() {
        XCTAssertEqual(WriteGateKeyStatus.resolve(storedValue: nil), .notSet)
    }

    func testEmptyAndWhitespaceAreNotSet() {
        XCTAssertEqual(WriteGateKeyStatus.resolve(storedValue: ""), .notSet)
        XCTAssertEqual(WriteGateKeyStatus.resolve(storedValue: "   "), .notSet)
        XCTAssertEqual(WriteGateKeyStatus.resolve(storedValue: " \n\t "), .notSet)
    }

    func testNonEmptyIsSet() {
        XCTAssertEqual(WriteGateKeyStatus.resolve(storedValue: "abc123"), .set)
        // 粘贴常带首尾空白/换行：有实质内容仍为已设置
        XCTAssertEqual(WriteGateKeyStatus.resolve(storedValue: "  abc123\n"), .set)
    }

    func testRemovedReturnsToNotSet() {
        // 移除＝删键，之后回读为 nil，状态须回未设置
        XCTAssertEqual(WriteGateKeyStatus.resolve(storedValue: "abc123"), .set)
        XCTAssertEqual(WriteGateKeyStatus.resolve(storedValue: nil), .notSet)
    }

    func testSanitizedForStorage() {
        XCTAssertEqual(WriteGateKeyStatus.sanitizedForStorage("  abc123\n"), "abc123")
        XCTAssertEqual(WriteGateKeyStatus.sanitizedForStorage("abc123"), "abc123")
        XCTAssertNil(WriteGateKeyStatus.sanitizedForStorage(nil))
        XCTAssertNil(WriteGateKeyStatus.sanitizedForStorage(""))
        XCTAssertNil(WriteGateKeyStatus.sanitizedForStorage("  \n "))
    }
}
