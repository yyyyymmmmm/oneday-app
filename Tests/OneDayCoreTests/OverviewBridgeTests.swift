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

    // MARK: - 裁决联动（0.36.5：refId 契约增补＋消账判定）

    func testNotificationDecodesRefIdWhenPresent() throws {
        let data = Data("""
        {
          "items": [
            {
              "id": "wg-abc",
              "kind": "write_gate_decision",
              "title": "记忆写入已批准",
              "body": "一条记忆写入。",
              "createdAt": "2026-11-10T10:00:00Z",
              "read": false,
              "refId": "mem_0123"
            }
          ]
        }
        """.utf8)
        let response = try decoder.decode(
            OverviewNotificationsResponse.self, from: data
        )
        XCTAssertEqual(response.items[0].refId, "mem_0123")
        XCTAssertTrue(response.items[0].isDecisionReceipt)
    }

    func testNotificationRefIdNilWhenBridgeOmitsIt() throws {
        // 旧桥 payload 无 refId：解码为 nil、联动不
        // 成立（向后兼容，不许解码失败整表丢弃）
        let data = Data("""
        {
          "items": [
            {
              "id": "mon-1",
              "kind": "monitor_change",
              "title": "监测有变化",
              "body": "",
              "createdAt": "2026-11-10T10:00:00Z",
              "read": false
            }
          ]
        }
        """.utf8)
        let response = try decoder.decode(
            OverviewNotificationsResponse.self, from: data
        )
        XCTAssertNil(response.items[0].refId)
        XCTAssertFalse(response.items[0].isDecisionReceipt)
    }

    private func receipt(
        _ id: String, refId: String?, read: Bool = false,
        kind: String = "write_gate_decision"
    ) -> OverviewNotification {
        OverviewNotification(
            id: id, kind: kind, title: "t", body: "b",
            createdAt: "", read: read, refId: refId
        )
    }

    func testReceiptsToResolveMatchesSelfDecidedOnly() {
        let items = [
            receipt("n1", refId: "mem_1"),
            receipt("n2", refId: "mem_2"),
        ]
        XCTAssertEqual(
            ApprovalResolution.receiptsToResolve(
                notifications: items, selfDecidedIDs: ["mem_1"]
            ),
            ["n1"]
        )
    }

    func testReceiptsToResolveSkipsReadNonReceiptAndMissingRef() {
        let items = [
            receipt("n1", refId: "mem_1", read: true),
            receipt("n2", refId: "mem_1", kind: "monitor_change"),
            receipt("n3", refId: nil),
        ]
        XCTAssertTrue(
            ApprovalResolution.receiptsToResolve(
                notifications: items, selfDecidedIDs: ["mem_1"]
            ).isEmpty
        )
    }

    func testReceiptsToResolveEmptySetResolvesNothing() {
        let items = [receipt("n1", refId: "mem_1")]
        XCTAssertTrue(
            ApprovalResolution.receiptsToResolve(
                notifications: items, selfDecidedIDs: []
            ).isEmpty
        )
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
    // §259 迁移（2026-11-14）：入参改单源 channelUp
    // （App 层合成：探活 ?? 桥 hermesUp）＋pending 计
    // 数；每条用例的 channelUp 即旧双入参经合成规则的
    // 结果，判定矩阵逐例等价、原用例名与意图不动
    func testStatusLineUnreachableWhenNoSnapshotAndChannelUnknown() {
        XCTAssertEqual(
            OverviewStatusLine.resolve(channelUp: nil, pendingApprovals: 0),
            "联系不上"
        )
    }

    func testStatusLineUnreachableWhenHermesDownPerBridge() {
        XCTAssertEqual(
            OverviewStatusLine.resolve(
                channelUp: false, pendingApprovals: 2
            ),
            "联系不上"
        )
    }

    /// 本轮钉死的核心用例：桥 401（快照为空）＋聊天
    /// 通道（Hermes API 探活）正常 → 状态必须是「在线」，
    /// 不许再被桥的失败污染成「联系不上」
    func testStatusLineOnlineWhenBridgeDownButChannelUp() {
        XCTAssertEqual(
            OverviewStatusLine.resolve(channelUp: true, pendingApprovals: 0),
            "在线"
        )
    }

    /// 通道探活为假是「联系不上」的唯一新来源：哪怕桥
    /// 快照自称在线也不许翻案（聊天走的就是这条通道）
    func testStatusLineUnreachableWhenChannelDownEvenIfBridgeUp() {
        XCTAssertEqual(
            OverviewStatusLine.resolve(
                channelUp: false, pendingApprovals: 2
            ),
            "联系不上"
        )
    }

    /// 通道直探优先于桥的 hermesUp 自述：桥说 Hermes
    /// 不在、但 API 通道刚探通 → 在线（桥字段是二手数）
    func testStatusLineChannelProbeWinsOverBridgeHermesUp() {
        XCTAssertEqual(
            OverviewStatusLine.resolve(
                channelUp: true, pendingApprovals: 0
            ),
            "在线"
        )
    }

    func testStatusLinePendingApprovals() {
        XCTAssertEqual(
            OverviewStatusLine.resolve(
                channelUp: true, pendingApprovals: 2
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
                channelUp: true, pendingApprovals: 0
            ),
            "在线"
        )
    }

    func testStatusLineIdle() {
        XCTAssertEqual(
            OverviewStatusLine.resolve(
                channelUp: true, pendingApprovals: 0
            ),
            "在线"
        )
    }

    /// §259 新签名独有可表达态：结论未知时计数不许
    /// 单独把状态顶成「待审批」——未知就是联系不上，
    /// 计数只在结论为真时露面
    func testStatusLineUnknownChannelIgnoresPendingCount() {
        XCTAssertEqual(
            OverviewStatusLine.resolve(
                channelUp: nil, pendingApprovals: 3
            ),
            "联系不上"
        )
        XCTAssertEqual(
            OverviewStatusLine.tone(
                channelUp: nil, pendingApprovals: 3
            ),
            .offline
        )
    }

    // 0.19.0：状态点语气与状态词同源（classify 一处判
    // 定）——桥挂＋通道在时词报「在线」、点必须是
    // online（绿），不许再落灰；下列用例与上方词用例
    // 逐条对位钉死
    func testToneOnlineWhenBridgeDownButChannelUp() {
        XCTAssertEqual(
            OverviewStatusLine.tone(channelUp: true, pendingApprovals: 0),
            .online
        )
    }

    func testToneOfflineWhenChannelDownEvenIfBridgeUp() {
        XCTAssertEqual(
            OverviewStatusLine.tone(
                channelUp: false, pendingApprovals: 2
            ),
            .offline
        )
    }

    func testToneOfflineWhenNoSnapshotAndChannelUnknown() {
        XCTAssertEqual(
            OverviewStatusLine.tone(channelUp: nil, pendingApprovals: 0),
            .offline
        )
    }

    func testToneAttentionWhenPendingApprovals() {
        XCTAssertEqual(
            OverviewStatusLine.tone(
                channelUp: true, pendingApprovals: 2
            ),
            .attention
        )
    }

    func testToneOnlineWhenBridgeReportsUp() {
        XCTAssertEqual(
            OverviewStatusLine.tone(
                channelUp: true, pendingApprovals: 0
            ),
            .online
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
