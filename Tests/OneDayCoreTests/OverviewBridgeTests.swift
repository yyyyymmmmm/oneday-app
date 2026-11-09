import OneDayCore
import XCTest

/// 总览桥冻结契约（0.6.0 一期）：DTO 按契约桩解码，
/// 状态行四支与角标聚合逐项钉死。桥未上线前本组就是
/// 契约的唯一机器可读口径，字段名不许漂移。
final class OverviewBridgeTests: XCTestCase {
    private let decoder = JSONDecoder()

    func testOverviewSnapshotDecodesContractFixture() throws {
        let data = Data("""
        {
          "hermesUp": true,
          "activeSessions": 2,
          "pendingApprovals": 3,
          "unreadNotifications": 4,
          "generatedAt": "2026-11-09T06:50:00Z"
        }
        """.utf8)
        let snapshot = try decoder.decode(OverviewSnapshot.self, from: data)
        XCTAssertTrue(snapshot.hermesUp)
        XCTAssertEqual(snapshot.activeSessions, 2)
        XCTAssertEqual(snapshot.pendingApprovals, 3)
        XCTAssertEqual(snapshot.unreadNotifications, 4)
        XCTAssertEqual(snapshot.generatedAt, "2026-11-09T06:50:00Z")
    }

    func testNotificationsDecodeContractFixture() throws {
        let data = Data("""
        {
          "items": [
            {
              "id": "n-1",
              "kind": "write_gate_decided",
              "title": "一条写入已批准",
              "body": "记忆写入已经落盘。",
              "createdAt": "2026-11-09T06:49:00Z",
              "read": false
            },
            {
              "id": "n-2",
              "kind": "write_gate_decided",
              "title": "一条写入已驳回",
              "body": "技能写入没有生效。",
              "createdAt": "2026-11-09T06:48:00Z",
              "read": true
            }
          ]
        }
        """.utf8)
        let response = try decoder.decode(
            OverviewNotificationsResponse.self, from: data
        )
        XCTAssertEqual(response.items.count, 2)
        XCTAssertEqual(response.items[0].id, "n-1")
        XCTAssertEqual(response.items[0].title, "一条写入已批准")
        XCTAssertFalse(response.items[0].read)
        XCTAssertTrue(response.items[1].read)
    }

    func testReadResponseDecodesContractFixture() throws {
        let response = try decoder.decode(
            OverviewReadResponse.self, from: Data(#"{"ok": true}"#.utf8)
        )
        XCTAssertTrue(response.ok)
    }

    private func snapshot(
        hermesUp: Bool = true, active: Int = 0,
        pending: Int = 0, unread: Int = 0
    ) -> OverviewSnapshot {
        OverviewSnapshot(
            hermesUp: hermesUp, activeSessions: active,
            pendingApprovals: pending, unreadNotifications: unread,
            generatedAt: "2026-11-09T06:50:00Z"
        )
    }

    // 0.6.1 短词口径：胶囊状态行只放可证事实短词
    // （联系不上／待审批 N／在线），整句不许回胶囊。
    // 0.7.0 通道口径修正（用户 16:05 真机截图坐实）：
    // 「联系不上」只认 Hermes API 通道探活，桥挂只降级
    // 桥自己的数——下列用例逐条钉死
    func testStatusLineUnreachableWhenNoSnapshotAndChannelUnknown() {
        XCTAssertEqual(
            OverviewStatusLine.resolve(snapshot: nil, hermesChannelUp: nil),
            "联系不上"
        )
    }

    func testStatusLineUnreachableWhenHermesDownPerBridge() {
        XCTAssertEqual(
            OverviewStatusLine.resolve(
                snapshot: snapshot(hermesUp: false, pending: 2),
                hermesChannelUp: nil
            ),
            "联系不上"
        )
    }

    /// 本轮钉死的核心用例：桥 401（快照为空）＋聊天
    /// 通道（Hermes API 探活）正常 → 状态必须是「在线」，
    /// 不许再被桥的失败污染成「联系不上」
    func testStatusLineOnlineWhenBridgeDownButChannelUp() {
        XCTAssertEqual(
            OverviewStatusLine.resolve(snapshot: nil, hermesChannelUp: true),
            "在线"
        )
    }

    /// 通道探活为假是「联系不上」的唯一新来源：哪怕桥
    /// 快照自称在线也不许翻案（聊天走的就是这条通道）
    func testStatusLineUnreachableWhenChannelDownEvenIfBridgeUp() {
        XCTAssertEqual(
            OverviewStatusLine.resolve(
                snapshot: snapshot(hermesUp: true, pending: 2),
                hermesChannelUp: false
            ),
            "联系不上"
        )
    }

    /// 通道直探优先于桥的 hermesUp 自述：桥说 Hermes
    /// 不在、但 API 通道刚探通 → 在线（桥字段是二手数）
    func testStatusLineChannelProbeWinsOverBridgeHermesUp() {
        XCTAssertEqual(
            OverviewStatusLine.resolve(
                snapshot: snapshot(hermesUp: false, pending: 0),
                hermesChannelUp: true
            ),
            "在线"
        )
    }

    func testStatusLinePendingApprovals() {
        XCTAssertEqual(
            OverviewStatusLine.resolve(
                snapshot: snapshot(active: 1, pending: 2),
                hermesChannelUp: true
            ),
            "待审批 2"
        )
    }

    /// 桥的 activeSessions 是契约字段（契约不动），
    /// 但客户端文案不许再把它说成「正在处理」：
    /// Hermes 不写 ended_at 时该数实为会话总数
    func testStatusLineActiveCountNeverImpliesProcessing() {
        XCTAssertEqual(
            OverviewStatusLine.resolve(
                snapshot: snapshot(active: 17), hermesChannelUp: nil
            ),
            "在线"
        )
    }

    func testStatusLineIdle() {
        XCTAssertEqual(
            OverviewStatusLine.resolve(
                snapshot: snapshot(), hermesChannelUp: nil
            ),
            "在线"
        )
    }

    func testBadgeAggregatesUnreadAndPending() {
        XCTAssertEqual(
            OverviewBadge.count(snapshot: snapshot(pending: 3, unread: 4)), 7
        )
        XCTAssertEqual(OverviewBadge.count(snapshot: snapshot()), 0)
    }

    func testBadgeIsZeroWhenUnreachable() {
        XCTAssertEqual(OverviewBadge.count(snapshot: nil), 0)
    }

    func testBadgeClampsNegativeInputs() {
        XCTAssertEqual(
            OverviewBadge.count(snapshot: snapshot(pending: -2, unread: -1)), 0
        )
    }
}
