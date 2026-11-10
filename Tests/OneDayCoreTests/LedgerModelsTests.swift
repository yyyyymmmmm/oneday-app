import XCTest
@testable import OneDayCore

/// 工作台账读面契约与呈现口径钉测（§95）：解码以
/// 伴生 ledger.py 的 item_view／_ledger_list_view／
/// _ledger_counts_view 实形为准（字段逐个对账见
/// DESIGN-V4 §95 契约对账表）；呈现口径（人话／耗
/// 时／新鲜度／合并／分组／副题）全为纯函数确定性
/// 断言。固定日历（公历＋上海时区）与固定 now。
final class LedgerModelsTests: XCTestCase {

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return cal
    }

    private func date(
        _ year: Int, _ month: Int, _ day: Int,
        _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0
    ) -> Date {
        calendar.date(from: DateComponents(
            year: year, month: month, day: day,
            hour: hour, minute: minute, second: second
        ))!
    }

    private func epoch(
        _ year: Int, _ month: Int, _ day: Int,
        _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0
    ) -> Double {
        date(year, month, day, hour, minute, second)
            .timeIntervalSince1970
    }

    /// 基准时刻：2026-11-10 15:10:00（上海）
    private var now: Double { epoch(2026, 11, 10, 15, 10, 0) }

    private func decode<T: Decodable>(
        _ type: T.Type, _ json: String
    ) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    private func makeItem(
        id: String = "run:r1",
        status: LedgerStatus = .running,
        startedAt: Double,
        endedAt: Double? = nil,
        lastEvidenceAt: Double? = nil,
        evidenceLagging: Bool = false,
        failCategory: String? = nil,
        origin: String = "reported"
    ) -> LedgerItem {
        LedgerItem(
            id: id, kind: .run, source: .app,
            title: "标题", titleSource: "user_excerpt",
            status: status, startedAt: startedAt,
            endedAt: endedAt, lastEvidenceAt: lastEvidenceAt,
            origin: origin, link: nil, counts: [:],
            failReason: failCategory.map {
                LedgerFailReason(category: $0, excerpt: nil)
            },
            evidenceLagging: evidenceLagging, lastSeq: 1,
            sessionId: nil, runId: nil, correctedBy: nil,
            history: []
        )
    }

    // MARK: - 解码：桥实形

    func testListResponseDecodesBridgeShape() throws {
        let json = """
        {
          "items": [
            {
              "id": "run:r-123", "kind": "run", "source": "app",
              "title": "把两张对起来",
              "titleSource": "user_excerpt",
              "status": "blocked_approval",
              "startedAt": 1762700000.0, "endedAt": null,
              "lastEvidenceAt": 1762700100.0,
              "origin": "reported",
              "link": {"kind": "session", "targetId": "s-1"},
              "counts": {"toolCalls": 3, "subTasks": 1},
              "failReason": null, "evidenceLagging": true,
              "lastSeq": 42, "sessionId": "s-1",
              "runId": "r-123", "history": []
            },
            {
              "id": "task:t-9", "kind": "kanban",
              "source": "bridge", "title": "整理清单",
              "titleSource": "task_title", "status": "failed",
              "startedAt": 1762690000.0,
              "endedAt": 1762690600.0,
              "lastEvidenceAt": 1762690600.0,
              "origin": "bridge_self", "link": null,
              "counts": {},
              "failReason": {"category": "上游出错",
                             "excerpt": "boom"},
              "evidenceLagging": false, "lastSeq": 40
            }
          ],
          "snapshotSeq": 42,
          "ledgerUpdatedAt": 1762700100.0,
          "collectorHeartbeatAt": 1762700095.0,
          "serverNow": 1762700105.0,
          "counts": {
            "inProgress": 0, "blockedApproval": 1,
            "stale": 0, "todayCompleted": 2,
            "todayFailed": 1, "todayCancelled": 0,
            "byStatus": {"blocked_approval": 1, "failed": 1},
            "total": 2
          }
        }
        """
        let response = try decode(LedgerListResponse.self, json)
        XCTAssertEqual(response.snapshotSeq, 42)
        XCTAssertEqual(response.serverNow, 1762700105.0)
        XCTAssertEqual(response.collectorHeartbeatAt, 1762700095.0)
        XCTAssertEqual(response.items.count, 2)

        let first = response.items[0]
        XCTAssertEqual(first.status, .blockedApproval)
        XCTAssertEqual(first.kind, .run)
        XCTAssertEqual(first.source, .app)
        XCTAssertEqual(first.title, "把两张对起来")
        XCTAssertEqual(first.link?.kind, "session")
        XCTAssertEqual(first.link?.targetId, "s-1")
        XCTAssertEqual(first.toolCalls, 3)
        XCTAssertEqual(first.subTasks, 1)
        XCTAssertTrue(first.evidenceLagging)
        XCTAssertNil(first.failReason)
        XCTAssertFalse(first.isReconciled)

        let second = response.items[1]
        XCTAssertEqual(second.status, .failed)
        XCTAssertEqual(second.failReason?.category, "上游出错")
        XCTAssertEqual(second.failReason?.excerpt, "boom")
        XCTAssertNil(second.link)

        let counts = try XCTUnwrap(response.counts)
        XCTAssertEqual(counts.blockedApproval, 1)
        XCTAssertEqual(counts.todayFailed, 1)
        XCTAssertEqual(counts.total, 2)
        XCTAssertFalse(counts.degraded)
        XCTAssertNil(counts.collectorLastRunAt)
    }

    func testItemToleratesMissingOptionals() throws {
        let item = try decode(
            LedgerItem.self,
            #"{"id": "job:x", "status": "queued"}"#
        )
        XCTAssertEqual(item.id, "job:x")
        XCTAssertEqual(item.status, .queued)
        XCTAssertEqual(item.title, "")
        XCTAssertEqual(item.counts, [:])
        XCTAssertEqual(item.history, [])
        XCTAssertFalse(item.evidenceLagging)
        XCTAssertNil(item.endedAt)
        XCTAssertNil(item.toolCalls)
    }

    func testUnknownEnumValuesKeptAsOther() throws {
        let item = try decode(
            LedgerItem.self,
            #"{"id": "x", "kind": "widget", "source": "mars", "status": "hibernating"}"#
        )
        XCTAssertEqual(item.status, .other("hibernating"))
        XCTAssertEqual(item.status.rawValue, "hibernating")
        XCTAssertEqual(item.kind, .other("widget"))
        XCTAssertEqual(item.source, .other("mars"))
        XCTAssertFalse(item.status.isActive)
        XCTAssertFalse(item.status.isTerminal)
    }

    func testMillisecondTimestampsNormalized() throws {
        let item = try decode(
            LedgerItem.self,
            #"{"id": "x", "status": "running", "startedAt": 1762700000000, "endedAt": 1762700600000}"#
        )
        XCTAssertEqual(item.startedAt, 1762700000.0, accuracy: 0.001)
        XCTAssertEqual(item.endedAt ?? 0, 1762700600.0, accuracy: 0.001)
    }

    func testSnakeCaseFallbackKeys() throws {
        let item = try decode(
            LedgerItem.self,
            #"{"id": "x", "status": "completed", "title_source": "job_name", "started_at": 100.0, "ended_at": 160.0, "last_evidence_at": 160.0, "session_id": "s-2"}"#
        )
        XCTAssertEqual(item.titleSource, "job_name")
        XCTAssertEqual(item.startedAt, 100.0)
        XCTAssertEqual(item.endedAt, 160.0)
        XCTAssertEqual(item.lastEvidenceAt, 160.0)
        XCTAssertEqual(item.sessionId, "s-2")
    }

    func testFailReasonEmptyCategoryFilesAsUnknown() throws {
        let item = try decode(
            LedgerItem.self,
            #"{"id": "x", "status": "failed", "failReason": {"category": "", "excerpt": "raw"}}"#
        )
        XCTAssertEqual(item.failReason?.category, "原因未明")
        XCTAssertEqual(item.failReason?.excerpt, "raw")
    }

    func testSummaryDecodesSummaryEndpointShape() throws {
        let json = """
        {
          "inProgress": 2, "blockedApproval": 1, "stale": 1,
          "todayCompleted": 3, "todayFailed": 1,
          "todayCancelled": 0,
          "byStatus": {"running": 2}, "total": 7,
          "collectorHeartbeatAt": 1762700095.0,
          "ledgerUpdatedAt": 1762700100.0,
          "serverNow": 1762700105.0, "degraded": true,
          "collector": {"lastRunAt": 1762700090.0,
                        "sources": {}, "ambiguousDeviceCalls": 0}
        }
        """
        let summary = try decode(LedgerSummary.self, json)
        XCTAssertEqual(summary.inProgress, 2)
        XCTAssertEqual(summary.stale, 1)
        XCTAssertTrue(summary.degraded)
        XCTAssertEqual(summary.collectorLastRunAt, 1762700090.0)
    }

    func testDetailItemDecodesHistory() throws {
        let json = """
        {
          "id": "run:r-1", "kind": "run", "source": "app",
          "title": "t", "titleSource": "fallback",
          "status": "completed", "startedAt": 100.0,
          "endedAt": 200.0, "lastEvidenceAt": 200.0,
          "origin": "reconciled", "link": null, "counts": {},
          "failReason": null, "evidenceLagging": false,
          "lastSeq": 9, "correctedBy": "collector",
          "history": [
            {"at": 100.0, "from": null, "to": "running",
             "by": "collector"},
            {"at": 200.0, "from": "running", "to": "completed",
             "by": "collector", "corrected": true,
             "note": "对账落定"}
          ]
        }
        """
        let item = try decode(LedgerItem.self, json)
        XCTAssertTrue(item.isReconciled)
        XCTAssertEqual(item.correctedBy, "collector")
        XCTAssertEqual(item.history.count, 2)
        XCTAssertNil(item.history[0].from)
        XCTAssertEqual(item.history[0].to, "running")
        XCTAssertTrue(item.history[1].corrected)
        XCTAssertEqual(item.history[1].note, "对账落定")
    }

    func testCompanionInfoDecodes() throws {
        let json = """
        {
          "companionVersion": "1.0.3", "apiLevel": 1,
          "minAppVersion": "0.36.0", "hermesUp": true,
          "modules": {
            "oneday": {"state": "up", "degraded": false},
            "write-gate": {"state": "up", "detail": "ok"}
          },
          "generatedAt": "2026-11-10T19:00:00Z"
        }
        """
        let info = try decode(CompanionInfo.self, json)
        XCTAssertEqual(info.companionVersion, "1.0.3")
        XCTAssertEqual(info.apiLevel, 1)
        XCTAssertEqual(info.hermesUp, true)
        XCTAssertEqual(info.onedayModuleState, "up")
        XCTAssertEqual(info.modules["write-gate"]?.detail, "ok")
    }

    // MARK: - 上报体编码

    func testReportRequestEncoding() throws {
        let request = LedgerReportRequest(
            runId: "r-1", sessionId: "s-1", startedAt: 100,
            titleSeed: "第一行", terminal: "failed",
            endedAt: 200, failCategory: "超时",
            failExcerpt: "等太久"
        )
        let data = try JSONEncoder().encode(request)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(object["runId"] as? String, "r-1")
        XCTAssertEqual(object["terminal"] as? String, "failed")
        let reason = try XCTUnwrap(
            object["failReason"] as? [String: Any]
        )
        XCTAssertEqual(reason["category"] as? String, "超时")
        XCTAssertEqual(reason["excerpt"] as? String, "等太久")

        let heartbeat = LedgerReportRequest(
            runId: "r-2", stillRunning: true
        )
        let heartData = try JSONEncoder().encode(heartbeat)
        let heartObject = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: heartData
            ) as? [String: Any]
        )
        XCTAssertEqual(heartObject["stillRunning"] as? Bool, true)
        XCTAssertNil(heartObject["failReason"])
        XCTAssertNil(heartObject["terminal"])
    }

    // MARK: - 时刻归一

    func testLedgerTimeNormalize() {
        XCTAssertEqual(LedgerTime.normalize(1762700000.0), 1762700000.0)
        XCTAssertEqual(
            LedgerTime.normalize(1762700000000.0), 1762700000.0,
            accuracy: 0.001
        )
        XCTAssertEqual(LedgerTime.normalize(100.0), 100.0)
    }

    // MARK: - 人话映射

    func testStatusWords() {
        XCTAssertEqual(LedgerText.statusWord(.queued), "排队中")
        XCTAssertEqual(LedgerText.statusWord(.running), "进行中")
        XCTAssertEqual(LedgerText.statusWord(.blockedApproval), "等待审批")
        XCTAssertEqual(LedgerText.statusWord(.completed), "已完成")
        XCTAssertEqual(LedgerText.statusWord(.failed), "失败")
        XCTAssertEqual(LedgerText.statusWord(.cancelled), "已取消")
        XCTAssertEqual(LedgerText.statusWord(.stale), "失联待核")
        XCTAssertEqual(LedgerText.statusWord(.other("x")), "状态未知")
    }

    func testKindSourceOriginWords() {
        XCTAssertEqual(LedgerText.kindWord(.run), "对话运行")
        XCTAssertEqual(LedgerText.kindWord(.kanban), "看板任务")
        XCTAssertEqual(LedgerText.kindWord(.job), "定时作业")
        XCTAssertEqual(LedgerText.kindWord(.approval), "审批")
        XCTAssertEqual(LedgerText.kindWord(.device), "设备调用")
        XCTAssertEqual(LedgerText.sourceWord(.app), "OneDay 发起")
        XCTAssertEqual(LedgerText.sourceWord(.dashboard), "控制台")
        XCTAssertEqual(LedgerText.sourceWord(.cron), "定时任务")
        XCTAssertEqual(LedgerText.sourceWord(.bridge), "自动作业")
        XCTAssertEqual(LedgerText.originWord("reported"), "实时上报")
        XCTAssertEqual(LedgerText.originWord("bridge_self"), "自动记录")
        XCTAssertEqual(LedgerText.originWord("reconciled"), "对账补记")
        XCTAssertEqual(
            LedgerText.titleSourceWord("user_excerpt"), "你的原话"
        )
        XCTAssertEqual(
            LedgerText.titleSourceWord("server_llm"), "智能标题"
        )
        XCTAssertEqual(LedgerText.actorWord("collector"), "对账")
        XCTAssertEqual(LedgerText.actorWord("app"), "App 上报")
        XCTAssertEqual(LedgerText.actorWord(nil), "系统")
    }

    // MARK: - 已耗时格式

    func testElapsedFormatUnderHour() {
        XCTAssertEqual(LedgerElapsed.format(seconds: 0), "0:00")
        XCTAssertEqual(LedgerElapsed.format(seconds: 7), "0:07")
        XCTAssertEqual(LedgerElapsed.format(seconds: 133), "2:13")
        XCTAssertEqual(LedgerElapsed.format(seconds: 3599), "59:59")
        XCTAssertEqual(LedgerElapsed.format(seconds: 119.9), "1:59")
    }

    func testElapsedFormatOverHourAndNegative() {
        XCTAssertEqual(LedgerElapsed.format(seconds: 3600), "1:00:00")
        XCTAssertEqual(LedgerElapsed.format(seconds: 3723), "1:02:03")
        XCTAssertEqual(LedgerElapsed.format(seconds: -5), "0:00")
    }

    // MARK: - 新鲜度

    func testFreshnessEvaluate() {
        XCTAssertEqual(
            LedgerFreshness.evaluate(heartbeatAge: nil), .stalled
        )
        XCTAssertEqual(LedgerFreshness.evaluate(heartbeatAge: 10), .live)
        XCTAssertEqual(LedgerFreshness.evaluate(heartbeatAge: 30), .live)
        XCTAssertEqual(
            LedgerFreshness.evaluate(heartbeatAge: 31), .lagging
        )
        XCTAssertEqual(
            LedgerFreshness.evaluate(heartbeatAge: 300), .lagging
        )
        XCTAssertEqual(
            LedgerFreshness.evaluate(heartbeatAge: 301), .stalled
        )
    }

    func testFreshnessNote() {
        let at = epoch(2026, 11, 10, 9, 5)
        XCTAssertNil(
            LedgerFreshness.live.note(
                ledgerUpdatedAt: at, calendar: calendar
            )
        )
        XCTAssertEqual(
            LedgerFreshness.lagging.note(
                ledgerUpdatedAt: at, calendar: calendar
            ),
            "台账更新于 09:05"
        )
        XCTAssertEqual(
            LedgerFreshness.stalled.note(
                ledgerUpdatedAt: at, calendar: calendar
            ),
            "台账已停更 · 最后更新 09:05"
        )
        XCTAssertEqual(
            LedgerFreshness.stalled.note(
                ledgerUpdatedAt: nil, calendar: calendar
            ),
            "台账已停更"
        )
    }

    // MARK: - 合并与排序

    func testMergeReplacesInsertsAndSorts() {
        let a = makeItem(id: "a", status: .running, startedAt: 300)
        let b = makeItem(id: "b", status: .completed, startedAt: 100)
        let aDone = makeItem(id: "a", status: .completed, startedAt: 300)
        let c = makeItem(id: "c", status: .queued, startedAt: 200)
        let merged = LedgerMerge.merge(
            existing: [a, b], changes: [aDone, c]
        )
        XCTAssertEqual(merged.map(\.id), ["a", "c", "b"])
        XCTAssertEqual(merged[0].status, .completed)
    }

    func testMergeEmptyChangesKeepsExisting() {
        let a = makeItem(id: "a", startedAt: 100)
        XCTAssertEqual(
            LedgerMerge.merge(existing: [a], changes: []), [a]
        )
    }

    func testSortedTieBreaksByID() {
        let b = makeItem(id: "b", startedAt: 100)
        let a = makeItem(id: "a", startedAt: 100)
        XCTAssertEqual(
            LedgerMerge.sorted([b, a]).map(\.id), ["a", "b"]
        )
    }

    // MARK: - 分组与页首

    func testDayGroupsTitles() {
        let todayItem = makeItem(
            id: "t", startedAt: epoch(2026, 11, 10, 9, 0)
        )
        let yesterdayItem = makeItem(
            id: "y", startedAt: epoch(2026, 11, 9, 22, 0)
        )
        let groups = LedgerBoard.dayGroups(
            [todayItem, yesterdayItem],
            now: date(2026, 11, 10, 15, 0), calendar: calendar
        )
        XCTAssertEqual(groups.map(\.title), ["今天", "昨天"])
        XCTAssertEqual(groups[0].items.map(\.id), ["t"])
        XCTAssertEqual(groups[1].items.map(\.id), ["y"])
    }

    func testHeaderCountsPreferSummary() {
        let item = makeItem(
            id: "a", status: .running, startedAt: 100
        )
        let summary = LedgerSummary(
            inProgress: 5, blockedApproval: 2, stale: 0,
            todayCompleted: 0, todayFailed: 0, todayCancelled: 0,
            total: 9, byStatus: [:], degraded: false,
            collectorHeartbeatAt: nil, ledgerUpdatedAt: nil,
            serverNow: nil, collectorLastRunAt: nil
        )
        let counts = LedgerBoard.headerCounts(
            items: [item], summary: summary
        )
        XCTAssertEqual(counts.inProgress, 5)
        XCTAssertEqual(counts.blockedApproval, 2)
    }

    func testHeaderCountsFallbackFromItems() {
        let items = [
            makeItem(id: "1", status: .queued, startedAt: 1),
            makeItem(id: "2", status: .running, startedAt: 2),
            makeItem(id: "3", status: .blockedApproval, startedAt: 3),
            makeItem(id: "4", status: .stale, startedAt: 4),
            makeItem(id: "5", status: .completed, startedAt: 5),
        ]
        let counts = LedgerBoard.headerCounts(
            items: items, summary: nil
        )
        XCTAssertEqual(counts.inProgress, 2)
        XCTAssertEqual(counts.blockedApproval, 1)
    }

    func testHeaderText() {
        XCTAssertEqual(
            LedgerBoard.headerText(inProgress: 0, blockedApproval: 0),
            "现在没有进行中的工作"
        )
        XCTAssertEqual(
            LedgerBoard.headerText(inProgress: 3, blockedApproval: 0),
            "正在进行 3 件"
        )
        XCTAssertEqual(
            LedgerBoard.headerText(inProgress: 3, blockedApproval: 2),
            "正在进行 3 件 · 待审批 2 件"
        )
        XCTAssertEqual(
            LedgerBoard.headerText(inProgress: 0, blockedApproval: 1),
            "正在进行 0 件 · 待审批 1 件"
        )
    }

    // MARK: - 行副题

    func testSubtitleRunning() {
        let item = makeItem(
            status: .running, startedAt: now - 133
        )
        XCTAssertEqual(
            LedgerBoard.subtitle(
                for: item, serverNow: now, calendar: calendar
            ),
            "进行中 · 已运行 2:13"
        )
    }

    func testSubtitleRunningLaggingAddsLastConfirmed() {
        let item = makeItem(
            status: .running, startedAt: now - 600,
            lastEvidenceAt: epoch(2026, 11, 10, 15, 4, 30),
            evidenceLagging: true
        )
        XCTAssertEqual(
            LedgerBoard.subtitle(
                for: item, serverNow: now, calendar: calendar
            ),
            "进行中 · 已运行 10:00 · 最后确认 15:04:30"
        )
    }

    func testSubtitleQueuedAndBlocked() {
        let queued = makeItem(status: .queued, startedAt: now - 32)
        XCTAssertEqual(
            LedgerBoard.subtitle(
                for: queued, serverNow: now, calendar: calendar
            ),
            "排队中 · 已等 0:32"
        )
        let blocked = makeItem(
            status: .blockedApproval, startedAt: now - 133
        )
        XCTAssertEqual(
            LedgerBoard.subtitle(
                for: blocked, serverNow: now, calendar: calendar
            ),
            "等待审批 · 已等 2:13"
        )
    }

    func testSubtitleCompletedShowsEndTime() {
        let item = makeItem(
            status: .completed, startedAt: now - 3600,
            endedAt: epoch(2026, 11, 10, 15, 4)
        )
        XCTAssertEqual(
            LedgerBoard.subtitle(
                for: item, serverNow: now, calendar: calendar
            ),
            "已完成 · 15:04"
        )
    }

    func testSubtitleFailedAndCancelledCarryCategory() {
        let failed = makeItem(
            status: .failed, startedAt: now - 60,
            failCategory: "上游出错"
        )
        XCTAssertEqual(
            LedgerBoard.subtitle(
                for: failed, serverNow: now, calendar: calendar
            ),
            "失败 · 上游出错"
        )
        let bareFailed = makeItem(status: .failed, startedAt: now - 60)
        XCTAssertEqual(
            LedgerBoard.subtitle(
                for: bareFailed, serverNow: now, calendar: calendar
            ),
            "失败"
        )
        let cancelled = makeItem(
            status: .cancelled, startedAt: now - 60,
            failCategory: "用户停止"
        )
        XCTAssertEqual(
            LedgerBoard.subtitle(
                for: cancelled, serverNow: now, calendar: calendar
            ),
            "已取消 · 用户停止"
        )
    }

    func testSubtitleStaleShowsLastConfirmed() {
        let item = makeItem(
            status: .stale, startedAt: now - 7200,
            lastEvidenceAt: epoch(2026, 11, 10, 14, 58)
        )
        XCTAssertEqual(
            LedgerBoard.subtitle(
                for: item, serverNow: now, calendar: calendar
            ),
            "已失去联系 · 最后确认 14:58"
        )
        let noEvidence = makeItem(status: .stale, startedAt: now - 7200)
        XCTAssertEqual(
            LedgerBoard.subtitle(
                for: noEvidence, serverNow: now, calendar: calendar
            ),
            "已失去联系"
        )
    }

    // MARK: - 详情时长

    func testDurationText() {
        let running = makeItem(status: .running, startedAt: now - 65)
        XCTAssertEqual(
            LedgerBoard.durationText(for: running, serverNow: now),
            "已运行 1:05"
        )
        let done = makeItem(
            status: .completed, startedAt: 100, endedAt: 460
        )
        XCTAssertEqual(
            LedgerBoard.durationText(for: done, serverNow: now),
            "用时 6:00"
        )
        let doneNoEnd = makeItem(status: .completed, startedAt: 100)
        XCTAssertNil(
            LedgerBoard.durationText(for: doneNoEnd, serverNow: now)
        )
        let stale = makeItem(status: .stale, startedAt: 100)
        XCTAssertNil(
            LedgerBoard.durationText(for: stale, serverNow: now)
        )
    }
}
