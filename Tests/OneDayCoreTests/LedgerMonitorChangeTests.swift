import XCTest
@testable import OneDayCore

/// A-05 台账单流：监测变化条目的客户端契约门。条目
/// 本体已由服务端台账直供（伴生 _ledger_monitor_item，
/// 字段真源在彼、伴生 ledger_selftest Part D 钉死）；
/// 本文件只钉客户端还持有的三件事——id 契约、kind=
/// monitor 的解码与事件化呈现、监测与审批/任务在同
/// 一条服务端流里同列。§217 的客户端合成
/// （LedgerMonitorSynthesis）已退役，其批量窗口
/// （逐监测 20／总量 50）是拉取面口径、随合成一并
/// 退役，不再有客户端对拍对象。
final class LedgerMonitorChangeTests: XCTestCase {

    private func monitorItem(
        id: String = "monitor-change:chg_1",
        title: String = "价格从 ¥199 变为 ¥179",
        startedAt: Double = 1_700_000_100
    ) -> LedgerItem {
        LedgerItem(
            id: id, kind: .monitor, source: .bridge,
            title: title, titleSource: "monitor_change",
            status: .completed,
            startedAt: startedAt, endedAt: startedAt,
            lastEvidenceAt: startedAt, origin: "bridge_self",
            link: LedgerLink(kind: "monitor", targetId: "mon_1"),
            counts: [:], failReason: nil, evidenceLagging: false,
            lastSeq: 0, sessionId: nil, runId: nil,
            correctedBy: nil, history: []
        )
    }

    // MARK: - id 契约

    func testMonitorChangeIDContract() {
        XCTAssertEqual(
            LedgerMonitorChange.itemID(changeID: "chg_1"),
            "monitor-change:chg_1"
        )
        XCTAssertTrue(
            LedgerMonitorChange.isMonitorChange(
                itemID: "monitor-change:chg_1"
            )
        )
        XCTAssertFalse(
            LedgerMonitorChange.isMonitorChange(itemID: "appr:p1")
        )
        XCTAssertFalse(
            LedgerMonitorChange.isMonitorChange(itemID: "job:monitor:chg_1")
        )
    }

    // MARK: - 解码与呈现口径

    func testMonitorKindDecodesFromServerRawValue() {
        XCTAssertEqual(LedgerKind(rawValue: "monitor"), .monitor)
        XCTAssertEqual(
            LedgerText.kindWord(.monitor),
            L10n.string("监测")
        )
    }

    func testMonitorSubtitleIsEventWordedNotCompleted() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let subtitle = LedgerBoard.subtitle(
            for: monitorItem(), serverNow: 1_700_000_200,
            calendar: calendar, locale: Locale(identifier: "zh-Hans")
        )
        XCTAssertTrue(subtitle.hasPrefix("监测变化 · "), subtitle)
        XCTAssertFalse(subtitle.contains("已完成"), subtitle)
    }

    // MARK: - 服务端单流同列：审批＋任务＋监测（夹具）

    /// 活动段的一条流里三类事件同列——监测条目以服
    /// 务端直供的线形（_ledger_monitor_item 的产出形：
    /// 列表面无 history 键）出现在 /ledger 载荷里，
    /// 解码、定序合并、分组后一并出现，防单流收口
    /// 把任一类弄丢
    func testServerFixtureContainsApprovalKanbanAndMonitorInOneStream()
        throws
    {
        let json = """
        {
          "items": [
            {
              "id": "appr:p1", "kind": "approval", "source": "bridge",
              "title": "要改一处设置", "titleSource": "record_excerpt",
              "status": "blocked_approval",
              "startedAt": 1700000100, "endedAt": null,
              "lastEvidenceAt": 1700000100, "origin": "bridge_self",
              "link": {"kind": "approval", "targetId": "p1"},
              "counts": {}, "failReason": null,
              "evidenceLagging": false, "lastSeq": 3,
              "sessionId": null, "runId": null,
              "correctedBy": null, "history": []
            },
            {
              "id": "task:t1", "kind": "kanban", "source": "bridge",
              "title": "整理发票", "titleSource": "task_title",
              "status": "running",
              "startedAt": 1700000050, "endedAt": null,
              "lastEvidenceAt": 1700000090, "origin": "bridge_self",
              "link": {"kind": "kanban", "targetId": "t1"},
              "counts": {}, "failReason": null,
              "evidenceLagging": false, "lastSeq": 4,
              "sessionId": null, "runId": null,
              "correctedBy": null, "history": []
            },
            {
              "id": "monitor-change:chg_9", "kind": "monitor",
              "source": "bridge",
              "title": "价格变了", "titleSource": "monitor_change",
              "status": "completed",
              "startedAt": 1700000150, "endedAt": 1700000150,
              "lastEvidenceAt": 1700000150, "origin": "bridge_self",
              "link": {"kind": "monitor", "targetId": "mon_1"},
              "counts": {}, "failReason": null,
              "evidenceLagging": false, "lastSeq": 5,
              "sessionId": null, "runId": null,
              "correctedBy": null
            }
          ],
          "snapshotSeq": 5, "serverNow": 1700000200
        }
        """
        let response = try JSONDecoder().decode(
            LedgerListResponse.self, from: Data(json.utf8)
        )
        let merged = LedgerMerge.sorted(response.items)
        XCTAssertEqual(
            merged.map(\.kind), [.monitor, .approval, .kanban]
        )
        let monitor = try XCTUnwrap(
            merged.first { $0.kind == .monitor }
        )
        XCTAssertEqual(monitor.id, "monitor-change:chg_9")
        XCTAssertEqual(monitor.title, "价格变了")
        XCTAssertEqual(monitor.link?.targetId, "mon_1")
        let approval = try XCTUnwrap(
            merged.first { $0.kind == .approval }
        )
        XCTAssertEqual(approval.status, .blockedApproval)
        XCTAssertEqual(approval.link?.targetId, "p1")
        let groups = LedgerBoard.dayGroups(
            merged,
            now: Date(timeIntervalSince1970: 1_700_000_200)
        )
        XCTAssertEqual(groups.flatMap(\.items).count, 3)
    }
}
