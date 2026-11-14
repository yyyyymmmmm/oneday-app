import XCTest
@testable import OneDayCore

/// §208 枢纽收段：监测变化并入活动段的合成口径门。
/// 活动流必须同时含三类事件——服务端台账的审批记录
/// （kind=approval，本文件解码夹具钉死）与看板任务，
/// 加上客户端合成的监测变化条目（kind=monitor）。
final class LedgerMonitorSynthesisTests: XCTestCase {

    private func monitor(
        id: String = "mon_1", name: String = "官网价格页"
    ) -> BridgeMonitor {
        BridgeMonitor(
            id: id, name: name, target: "https://example.com/price",
            scheduleText: "每小时", cronJobId: "job_1",
            enabled: true, lastCheckedAt: 1_700_000_000,
            lastResult: "changed", lastError: nil,
            unreadChanges: 1, latestChangeSummary: "价格变了",
            latestChangeAt: 1_700_000_000,
            createdAt: 1_699_000_000, updatedAt: 1_700_000_000
        )
    }

    private func change(
        id: String, monitorId: String = "mon_1",
        at: Double, summary: String
    ) -> BridgeMonitorChange {
        BridgeMonitorChange(
            id: id, monitorId: monitorId, detectedAt: at,
            summary: summary, before: "¥199", after: "¥179",
            read: false
        )
    }

    // MARK: - 合成条目形态

    func testSynthesisProducesMonitorKindItemWithBackLink() {
        let item = LedgerMonitorSynthesis.item(
            monitor: monitor(),
            change: change(id: "chg_1", at: 1_700_000_100, summary: "价格从 ¥199 变为 ¥179")
        )
        XCTAssertEqual(item.id, "monitor-change:chg_1")
        XCTAssertEqual(item.kind, .monitor)
        XCTAssertEqual(item.kind.rawValue, "monitor")
        XCTAssertEqual(item.title, "价格从 ¥199 变为 ¥179")
        XCTAssertEqual(item.link?.kind, "monitor")
        XCTAssertEqual(item.link?.targetId, "mon_1")
        XCTAssertEqual(item.startedAt, 1_700_000_100)
        XCTAssertEqual(item.endedAt, 1_700_000_100)
        XCTAssertTrue(LedgerMonitorSynthesis.isSynthetic(itemID: item.id))
        XCTAssertFalse(LedgerMonitorSynthesis.isSynthetic(itemID: "appr:p1"))
    }

    func testSynthesisFallsBackToMonitorNameWhenSummaryEmpty() {
        let item = LedgerMonitorSynthesis.item(
            monitor: monitor(name: "库存监测"),
            change: change(id: "chg_2", at: 10, summary: "  ")
        )
        XCTAssertEqual(item.title, "库存监测")
    }

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
        let item = LedgerMonitorSynthesis.item(
            monitor: monitor(),
            change: change(id: "chg_3", at: 1_700_000_100, summary: "有变化")
        )
        let subtitle = LedgerBoard.subtitle(
            for: item, serverNow: 1_700_000_200,
            calendar: calendar, locale: Locale(identifier: "zh-Hans")
        )
        XCTAssertTrue(subtitle.hasPrefix("监测变化 · "), subtitle)
        XCTAssertFalse(subtitle.contains("已完成"), subtitle)
    }

    // MARK: - 批量合成（排序与上限）

    func testBatchSynthesisSortsByDetectedAtAndCapsTotal() {
        let m1 = monitor(id: "mon_1")
        let m2 = monitor(id: "mon_2", name: "第二监测")
        let items = LedgerMonitorSynthesis.items(
            monitors: [m1, m2],
            changesByMonitor: [
                "mon_1": [
                    change(id: "a", at: 100, summary: "a"),
                    change(id: "b", at: 300, summary: "b"),
                ],
                "mon_2": [
                    change(id: "c", monitorId: "mon_2", at: 200, summary: "c"),
                ],
            ],
            perMonitorLimit: 20, totalLimit: 2
        )
        XCTAssertEqual(items.map(\.id), ["monitor-change:b", "monitor-change:c"])
    }

    func testBatchSynthesisRespectsPerMonitorLimit() {
        let items = LedgerMonitorSynthesis.items(
            monitors: [monitor()],
            changesByMonitor: [
                "mon_1": [
                    change(id: "x1", at: 1, summary: "1"),
                    change(id: "x2", at: 2, summary: "2"),
                    change(id: "x3", at: 3, summary: "3"),
                ],
            ],
            perMonitorLimit: 2, totalLimit: 50
        )
        XCTAssertEqual(items.map(\.id), ["monitor-change:x3", "monitor-change:x2"])
    }

    func testBatchSynthesisMissingChangesYieldsNothing() {
        let items = LedgerMonitorSynthesis.items(
            monitors: [monitor()], changesByMonitor: [:]
        )
        XCTAssertTrue(items.isEmpty)
    }

    // MARK: - 活动流同列：审批与任务（服务端夹具）

    /// 活动段的台账主流里审批记录与看板任务本就在列
    /// （伴生采集器 write-gate／kanban 两源）——解码
    /// 夹具钉死这两类与合成监测条目同形同列、分组
    /// 合并后一并出现，防收段把任一类弄丢
    func testLedgerFixtureContainsApprovalAndKanbanAlongsideMonitor()
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
            }
          ],
          "snapshotSeq": 4, "serverNow": 1700000200
        }
        """
        let response = try JSONDecoder().decode(
            LedgerListResponse.self, from: Data(json.utf8)
        )
        let monitorItem = LedgerMonitorSynthesis.item(
            monitor: monitor(),
            change: change(id: "chg_9", at: 1_700_000_150, summary: "价格变了")
        )
        let merged = LedgerMerge.sorted(response.items + [monitorItem])
        XCTAssertEqual(
            merged.map(\.kind), [.monitor, .approval, .kanban]
        )
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
