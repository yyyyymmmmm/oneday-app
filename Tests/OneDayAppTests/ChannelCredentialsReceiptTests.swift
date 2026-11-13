import XCTest
@testable import OneDayApp

/// 频道凭据保存回执的线格式（频道文案小包）：伴生
/// 1.0.46 的 applyTriggered/applyError 必须解得出
/// 来；旧版伴生不带这两字段时解码不许失败、字段
/// 为 nil（呈现回落 status）
final class ChannelCredentialsReceiptTests: XCTestCase {

    private func decode(_ json: String) throws
        -> ChannelCredentialsReceipt
    {
        try JSONDecoder().decode(
            ChannelCredentialsReceipt.self,
            from: Data(json.utf8)
        )
    }

    /// 新桥·触发成功：applyTriggered=true、无 applyError
    func testInstantApplyReceiptDecodes() throws {
        let receipt = try decode("""
            {"platform": "telegram", "configured": true,
             "state": "pending_restart", "restartRequired": true,
             "applyTriggered": true,
             "message": "钥匙已保存，正在生效"}
            """)
        XCTAssertEqual(receipt.applyTriggered, true)
        XCTAssertNil(receipt.applyError)
    }

    /// 新桥·触发失败：applyError 带桥回的人话原因
    func testApplyFailedReceiptDecodes() throws {
        let receipt = try decode("""
            {"platform": "telegram", "configured": true,
             "state": "pending_restart", "restartRequired": true,
             "applyTriggered": false,
             "applyError": "即时生效没触发成功，将在网关下次重启时生效",
             "message": "钥匙已保存，正在等待生效"}
            """)
        XCTAssertEqual(receipt.applyTriggered, false)
        XCTAssertEqual(
            receipt.applyError,
            "即时生效没触发成功，将在网关下次重启时生效"
        )
    }

    /// 旧桥回执（无新字段）：解码成功、新字段为 nil
    func testLegacyReceiptDecodesWithNilApplyFields() throws {
        let receipt = try decode("""
            {"platform": "telegram", "configured": true,
             "state": "pending_restart", "restartRequired": true,
             "message": "钥匙已保存，正在等待生效"}
            """)
        XCTAssertNil(receipt.applyTriggered)
        XCTAssertNil(receipt.applyError)
    }
}
