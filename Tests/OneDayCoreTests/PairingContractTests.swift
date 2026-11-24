import OneDayCore
import XCTest

/// 平台用户配对契约钉测（DESIGN §359）：两列清单解
/// 码、请求体组装、回执解码、失败分类矩阵、回读判
/// 定——全部对 9119 ops.py 源码形状与探活实证（蓝
/// 图一期探活报告 §3.2），不许凭图臆测
final class PairingContractTests: XCTestCase {

    private func decodeList(_ json: String) throws -> PairingListResponse {
        try JSONDecoder().decode(
            PairingListResponse.self, from: Data(json.utf8)
        )
    }

    private func encodeToDict<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        let object = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(object as? [String: Any])
    }

    // MARK: - 清单解码（ops.py 回文形状）

    func testListDecodesPendingAndApproved() throws {
        let response = try decodeList("""
        {
          "pending": [
            {
              "platform": "telegram",
              "request_id": "req-abc123",
              "user_id": "424242",
              "user_name": "小明",
              "age_minutes": 12.5
            }
          ],
          "approved": [
            {
              "platform": "whatsapp",
              "user_id": "8613800000000",
              "user_name": "阿华",
              "approved_at": "2026-11-20T08:30:00Z"
            }
          ]
        }
        """)
        XCTAssertEqual(response.pending.count, 1)
        let pending = response.pending[0]
        XCTAssertEqual(pending.platform, "telegram")
        XCTAssertEqual(pending.requestID, "req-abc123")
        XCTAssertEqual(pending.userID, "424242")
        XCTAssertEqual(pending.userName, "小明")
        XCTAssertEqual(pending.ageMinutes, 12.5)
        XCTAssertTrue(pending.canApprove)
        XCTAssertEqual(response.approved.count, 1)
        XCTAssertEqual(response.approved[0].userID, "8613800000000")
        XCTAssertEqual(
            response.approved[0].approvedAt, "2026-11-20T08:30:00Z"
        )
    }

    /// 旧版明文条目 request_id 为空串——解码保留空串、
    /// canApprove 为假（只能走码批准，本面结构上批不了）
    func testListDecodesLegacyPendingWithoutRequestID() throws {
        let response = try decodeList("""
        {
          "pending": [
            {
              "platform": "telegram",
              "request_id": "",
              "user_id": "777",
              "user_name": "",
              "age_minutes": 3
            }
          ],
          "approved": []
        }
        """)
        let entry = response.pending[0]
        XCTAssertEqual(entry.requestID, "")
        XCTAssertFalse(entry.canApprove)
        // 无编号条目的身份退平台＋用户，清单内仍可区分
        XCTAssertEqual(entry.id, "pending:telegram:777")
    }

    /// 键缺失宽容：整份空对象与 approved_at 缺失都不炸
    func testListDecodesMissingKeysTolerantly() throws {
        let empty = try decodeList("{}")
        XCTAssertTrue(empty.pending.isEmpty)
        XCTAssertTrue(empty.approved.isEmpty)

        let response = try decodeList("""
        {
          "pending": [],
          "approved": [
            {"platform": "signal", "user_id": "u1", "user_name": "甲"}
          ]
        }
        """)
        XCTAssertNil(response.approved[0].approvedAt)
    }

    // MARK: - 请求体组装

    /// 批准只走 request_id 路径：请求体恰 platform＋
    /// request_id 两键，绝不带 code（不经手配对码本体）
    func testApproveRequestCarriesOnlyPlatformAndRequestID() throws {
        let dict = try encodeToDict(
            PairingApproveRequest(platform: "telegram", requestID: "req-1")
        )
        XCTAssertEqual(Set(dict.keys), ["platform", "request_id"])
        XCTAssertEqual(dict["platform"] as? String, "telegram")
        XCTAssertEqual(dict["request_id"] as? String, "req-1")
    }

    func testRevokeRequestCarriesPlatformAndUserID() throws {
        let dict = try encodeToDict(
            PairingRevokeRequest(platform: "whatsapp", userID: "8613")
        )
        XCTAssertEqual(Set(dict.keys), ["platform", "user_id"])
        XCTAssertEqual(dict["user_id"] as? String, "8613")
    }

    // MARK: - 回执解码

    func testApproveReceiptDecodesUser() throws {
        let receipt = try JSONDecoder().decode(
            PairingApproveReceipt.self,
            from: Data("""
            {"ok": true, "user": {"user_id": "424242", "user_name": "小明"}}
            """.utf8)
        )
        XCTAssertTrue(receipt.ok)
        XCTAssertEqual(receipt.userID, "424242")
        XCTAssertEqual(receipt.userName, "小明")
    }

    func testClearPendingReceiptDecodesClearedCount() throws {
        let receipt = try JSONDecoder().decode(
            PairingClearPendingReceipt.self,
            from: Data(#"{"ok": true, "cleared": 3}"#.utf8)
        )
        XCTAssertTrue(receipt.ok)
        XCTAssertEqual(receipt.cleared, 3)
    }

    // MARK: - 失败分类矩阵

    func testDirectiveMatrix() {
        XCTAssertEqual(PairingActionDirective.directive(status: 200), .done)
        XCTAssertEqual(PairingActionDirective.directive(status: 204), .done)
        XCTAssertEqual(PairingActionDirective.directive(status: 404), .gone)
        XCTAssertEqual(
            PairingActionDirective.directive(status: 429), .platformLocked
        )
        XCTAssertEqual(
            PairingActionDirective.directive(status: 401), .sessionExpired
        )
        XCTAssertEqual(PairingActionDirective.directive(status: 400), .failed)
        XCTAssertEqual(PairingActionDirective.directive(status: 500), .failed)
    }

    // MARK: - 回读判定

    private func list(
        pending: [PairingPendingEntry],
        approved: [PairingApprovedEntry]
    ) -> PairingListResponse {
        PairingListResponse(pending: pending, approved: approved)
    }

    private var pendingMing: PairingPendingEntry {
        PairingPendingEntry(
            platform: "telegram", requestID: "req-1",
            userID: "424242", userName: "小明", ageMinutes: 5
        )
    }

    private var approvedMing: PairingApprovedEntry {
        PairingApprovedEntry(
            platform: "telegram", userID: "424242",
            userName: "小明", approvedAt: "2026-11-22T09:00:00Z"
        )
    }

    func testReadbackApproveConfirmedOnlyWhenMoved() {
        // 进已批准列且离待批列 → 确认
        XCTAssertTrue(PairingReadback.isApproveConfirmed(
            platform: "telegram", userID: "424242",
            in: list(pending: [], approved: [approvedMing])
        ))
        // 还在待批列 → 未确认（哪怕已批准列也有同名）
        XCTAssertFalse(PairingReadback.isApproveConfirmed(
            platform: "telegram", userID: "424242",
            in: list(pending: [pendingMing], approved: [approvedMing])
        ))
        // 没进已批准列 → 未确认
        XCTAssertFalse(PairingReadback.isApproveConfirmed(
            platform: "telegram", userID: "424242",
            in: list(pending: [], approved: [])
        ))
        // 平台不同不算数
        XCTAssertFalse(PairingReadback.isApproveConfirmed(
            platform: "whatsapp", userID: "424242",
            in: list(pending: [], approved: [approvedMing])
        ))
    }

    func testReadbackRevokeAndClear() {
        XCTAssertTrue(PairingReadback.isRevokeConfirmed(
            platform: "telegram", userID: "424242",
            in: list(pending: [], approved: [])
        ))
        XCTAssertFalse(PairingReadback.isRevokeConfirmed(
            platform: "telegram", userID: "424242",
            in: list(pending: [], approved: [approvedMing])
        ))
        XCTAssertTrue(PairingReadback.isClearConfirmed(
            in: list(pending: [], approved: [approvedMing])
        ))
        XCTAssertFalse(PairingReadback.isClearConfirmed(
            in: list(pending: [pendingMing], approved: [])
        ))
    }
}
