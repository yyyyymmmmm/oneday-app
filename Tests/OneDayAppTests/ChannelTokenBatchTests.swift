import OneDayCore
import XCTest
@testable import OneDayApp

/// 频道二期·令牌批的 App 层钉测：凭据回执的加法字
/// 段解码（新桥带 apply* 字段、旧桥不带时回落 nil）
/// 与演示合成态的四家基线（与生产零接入同形）
final class ChannelTokenBatchTests: XCTestCase {

    private func decodeReceipt(
        _ json: String
    ) throws -> ChannelCredentialsReceipt {
        try JSONDecoder().decode(
            ChannelCredentialsReceipt.self,
            from: Data(json.utf8)
        )
    }

    func testReceiptDecodesApplyFieldsFromNewBridge() throws {
        let receipt = try decodeReceipt("""
        {"platform": "dingtalk", "configured": true,
         "state": "pending_restart", "restartRequired": true,
         "applyTriggered": true, "applyError": null,
         "botUsername": null,
         "message": "钥匙已保存，正在生效"}
        """)
        XCTAssertEqual(receipt.platform, "dingtalk")
        XCTAssertEqual(receipt.applyTriggered, true)
        XCTAssertNil(receipt.applyError)
    }

    func testReceiptDecodesApplyError() throws {
        let receipt = try decodeReceipt("""
        {"platform": "slack", "configured": true,
         "state": "pending_restart", "restartRequired": true,
         "applyTriggered": false,
         "applyError": "即时生效没触发成功，将在网关下次重启时生效",
         "botUsername": null, "message": "钥匙已保存，正在等待生效"}
        """)
        XCTAssertEqual(receipt.applyTriggered, false)
        XCTAssertEqual(
            receipt.applyError,
            "即时生效没触发成功，将在网关下次重启时生效")
    }

    func testReceiptFromOldBridgeLeavesApplyFieldsNil() throws {
        // 旧版伴生回执没有 apply 两字段：加法解码必须
        // 退回 nil，呈现层据此走等待生效老口径
        let receipt = try decodeReceipt("""
        {"platform": "qqbot", "configured": true,
         "state": "pending_restart", "restartRequired": true,
         "botUsername": null, "message": "钥匙已保存"}
        """)
        XCTAssertNil(receipt.applyTriggered)
        XCTAssertNil(receipt.applyError)
    }

    @MainActor
    func testDemoStatusesCoverTokenBatchAsNotConfigured() {
        for platform in ["dingtalk", "qqbot", "discord", "slack"] {
            let status = ChannelStatusStore.demoStatuses[platform]
            XCTAssertNotNil(status, "\(platform) 演示态缺行")
            XCTAssertEqual(status?.state, "not_configured")
            XCTAssertEqual(status?.kind, "token")
            XCTAssertEqual(status?.open, true)
            XCTAssertEqual(status?.configured, false)
            XCTAssertEqual(status?.connected, false)
        }
    }
}
