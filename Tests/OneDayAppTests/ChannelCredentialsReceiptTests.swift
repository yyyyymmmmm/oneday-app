import XCTest
@testable import OneDayApp

/// 频道凭据回执解码（频道二期）：新版伴生（1.0.46+
/// 即时生效字段、1.0.48 飞书 botName）与旧版伴生的
/// 回执都要解得出——加法字段缺失一律回落 nil，不许
/// 因解码失败把一次成功的保存报成失败。
final class ChannelCredentialsReceiptTests: XCTestCase {

    private func decode(_ json: String) throws -> ChannelCredentialsReceipt {
        try JSONDecoder().decode(
            ChannelCredentialsReceipt.self,
            from: Data(json.utf8))
    }

    func testFeishuReceiptWithApplyAndBotName() throws {
        let receipt = try decode("""
            {"platform": "feishu", "configured": true,
             "state": "pending_restart", "restartRequired": true,
             "applyTriggered": true, "applyError": null,
             "botName": "三狗助手", "message": null}
            """)
        XCTAssertEqual(receipt.platform, "feishu")
        XCTAssertTrue(receipt.configured)
        XCTAssertEqual(receipt.applyTriggered, true)
        XCTAssertNil(receipt.applyError)
        XCTAssertEqual(receipt.botName, "三狗助手")
    }

    func testApplyFailureReceiptCarriesReason() throws {
        let receipt = try decode("""
            {"platform": "telegram", "configured": true,
             "state": "pending_restart", "restartRequired": true,
             "applyTriggered": false,
             "applyError": "没能即时生效：连接被拒绝",
             "botUsername": "sangou_bot"}
            """)
        XCTAssertEqual(receipt.applyTriggered, false)
        XCTAssertEqual(receipt.applyError, "没能即时生效：连接被拒绝")
        XCTAssertEqual(receipt.botUsername, "sangou_bot")
        XCTAssertNil(receipt.botName)
    }

    func testLegacyReceiptWithoutApplyFields() throws {
        let receipt = try decode("""
            {"platform": "telegram", "configured": true,
             "state": "pending_restart", "restartRequired": true,
             "botUsername": "sangou_bot"}
            """)
        XCTAssertNil(receipt.applyTriggered)
        XCTAssertNil(receipt.applyError)
        XCTAssertNil(receipt.botName)
        XCTAssertNil(receipt.message)
    }
}
