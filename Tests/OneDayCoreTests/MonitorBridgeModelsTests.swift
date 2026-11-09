import OneDayCore
import XCTest

/// 监测桥契约测试（P6，0.12.0 客户端先行）：fixture
/// 按 monitor-bridge-contract-20261109.md 冻结形状落
/// 形（id 前缀 mon_/chg_、时间 epoch 秒 float、结果
/// 三分 changed/unchanged/failed）。红线：三分不许
/// 混淆、三分之外的值不许猜成无变化、没存原文的
/// 变化不许拼出假 diff。
final class MonitorBridgeModelsTests: XCTestCase {
    private let decoder = JSONDecoder()

    /// 契约全形样本：一条有变化、一条检查失败
    private let monitorChangedJSON = """
    {"id": "mon_735c0a39eb9e", "name": "PokePay 价格页",
     "target": "https://example.com/pricing",
     "scheduleText": "每 6 小时", "cronJobId": "job_abc123",
     "enabled": true, "lastCheckedAt": 1794217800.5,
     "lastResult": "changed", "lastError": null,
     "unreadChanges": 2,
     "latestChangeSummary": "价格从 ¥199 变为 ¥179",
     "latestChangeAt": 1794217800.5,
     "createdAt": 1794100000.0, "updatedAt": 1794217800.5}
    """

    private let monitorFailedJSON = """
    {"id": "mon_aaaa0000bbbb", "name": "机场状态页",
     "target": "https://example.com/status",
     "scheduleText": "每天 09:00", "cronJobId": null,
     "enabled": true, "lastCheckedAt": 1794210000.0,
     "lastResult": "failed", "lastError": "页面读取超时",
     "unreadChanges": 0,
     "latestChangeSummary": null, "latestChangeAt": null,
     "createdAt": 1794000000.0, "updatedAt": 1794210000.0}
    """

    private let changeJSON = """
    {"id": "chg_020af9aa0107", "monitorId": "mon_735c0a39eb9e",
     "detectedAt": 1794217800.5,
     "summary": "价格从 ¥199 变为 ¥179",
     "before": "¥199", "after": "¥179", "read": false}
    """

    private func decodeMonitor(
        _ json: String = ""
    ) throws -> BridgeMonitor {
        try decoder.decode(
            BridgeMonitor.self,
            from: Data((json.isEmpty ? monitorChangedJSON : json).utf8)
        )
    }

    private func makeMonitor(
        enabled: Bool = true,
        lastCheckedAt: Double? = 100,
        lastResult: String? = "unchanged",
        unreadChanges: Int = 0,
        latestChangeAt: Double? = nil,
        createdAt: Double = 1
    ) -> BridgeMonitor {
        BridgeMonitor(
            id: "mon_x", name: "测试", target: "https://example.com",
            scheduleText: "每天 09:00", cronJobId: nil,
            enabled: enabled, lastCheckedAt: lastCheckedAt,
            lastResult: lastResult, lastError: nil,
            unreadChanges: unreadChanges, latestChangeSummary: nil,
            latestChangeAt: latestChangeAt,
            createdAt: createdAt, updatedAt: createdAt
        )
    }

    // MARK: - 解码（契约全形与容缺）

    func testMonitorsResponseDecodesContractShape() throws {
        let data = Data(
            "{\"items\": [\(monitorChangedJSON), \(monitorFailedJSON)]}".utf8
        )
        let response = try decoder.decode(
            BridgeMonitorsResponse.self, from: data
        )
        XCTAssertEqual(response.items.count, 2)
        let monitor = response.items[0]
        XCTAssertEqual(monitor.id, "mon_735c0a39eb9e")
        XCTAssertEqual(monitor.name, "PokePay 价格页")
        XCTAssertEqual(monitor.target, "https://example.com/pricing")
        XCTAssertEqual(monitor.scheduleText, "每 6 小时")
        XCTAssertEqual(monitor.cronJobId, "job_abc123")
        XCTAssertTrue(monitor.enabled)
        XCTAssertEqual(monitor.lastCheckedAt, 1794217800.5)
        XCTAssertEqual(monitor.checkResult, .changed)
        XCTAssertNil(monitor.lastError)
        XCTAssertEqual(monitor.unreadChanges, 2)
        XCTAssertEqual(monitor.latestChangeSummary, "价格从 ¥199 变为 ¥179")
        XCTAssertEqual(monitor.latestChangeAt, 1794217800.5)
        let failed = response.items[1]
        XCTAssertEqual(failed.checkResult, .failed)
        XCTAssertEqual(failed.lastError, "页面读取超时")
        XCTAssertNil(failed.cronJobId)
    }

    func testMonitorDecodesMissingOptionalsWithDefaults() throws {
        let data = Data(
            "{\"id\": \"mon_min\", \"name\": \"只有名字\"}".utf8
        )
        let monitor = try decoder.decode(BridgeMonitor.self, from: data)
        XCTAssertEqual(monitor.target, "")
        XCTAssertEqual(monitor.scheduleText, "")
        XCTAssertNil(monitor.cronJobId)
        XCTAssertTrue(monitor.enabled)
        XCTAssertNil(monitor.lastCheckedAt)
        XCTAssertNil(monitor.lastResult)
        XCTAssertEqual(monitor.unreadChanges, 0)
        XCTAssertEqual(monitor.createdAt, 0)
    }

    func testChangesResponseDecodesContractShape() throws {
        let data = Data("{\"items\": [\(changeJSON)]}".utf8)
        let response = try decoder.decode(
            BridgeMonitorChangesResponse.self, from: data
        )
        XCTAssertEqual(response.items.count, 1)
        let change = response.items[0]
        XCTAssertEqual(change.id, "chg_020af9aa0107")
        XCTAssertEqual(change.monitorId, "mon_735c0a39eb9e")
        XCTAssertEqual(change.detectedAt, 1794217800.5)
        XCTAssertEqual(change.before, "¥199")
        XCTAssertEqual(change.after, "¥179")
        XCTAssertFalse(change.read)
    }

    func testChangeDecodesMissingBeforeAfterAsNil() throws {
        let data = Data(
            """
            {"id": "chg_min", "monitorId": "mon_x", "detectedAt": 5,
             "summary": "页面标题变了"}
            """.utf8
        )
        let change = try decoder.decode(
            BridgeMonitorChange.self, from: data
        )
        XCTAssertNil(change.before)
        XCTAssertNil(change.after)
        XCTAssertFalse(change.read)
    }

    // MARK: - 状态分类（三分不混淆）

    func testStatusMapsThreeResults() {
        XCTAssertEqual(
            MonitorPresentation.status(
                of: makeMonitor(lastResult: "changed")
            ), .changed
        )
        XCTAssertEqual(
            MonitorPresentation.status(
                of: makeMonitor(lastResult: "unchanged")
            ), .unchanged
        )
        XCTAssertEqual(
            MonitorPresentation.status(
                of: makeMonitor(lastResult: "failed")
            ), .failed
        )
        XCTAssertEqual(
            MonitorPresentation.statusText(
                of: makeMonitor(lastResult: "changed")
            ), "有变化"
        )
        XCTAssertEqual(
            MonitorPresentation.statusText(
                of: makeMonitor(lastResult: "unchanged")
            ), "无变化"
        )
        XCTAssertEqual(
            MonitorPresentation.statusText(
                of: makeMonitor(lastResult: "failed")
            ), "检查失败"
        )
    }

    func testStatusPausedDominatesResult() {
        let monitor = makeMonitor(enabled: false, lastResult: "changed")
        XCTAssertEqual(MonitorPresentation.status(of: monitor), .paused)
        XCTAssertEqual(MonitorPresentation.statusText(of: monitor), "已暂停")
    }

    func testStatusNeverCheckedWhenNoCheckTime() {
        let monitor = makeMonitor(lastCheckedAt: nil, lastResult: nil)
        XCTAssertEqual(
            MonitorPresentation.status(of: monitor), .neverChecked
        )
        XCTAssertEqual(
            MonitorPresentation.statusText(of: monitor), "还没检查过"
        )
    }

    func testStatusUnknownForUnrecognizedResult() {
        // 契约三分之外的值：不许猜成无变化
        let monitor = makeMonitor(lastResult: "partial")
        XCTAssertNil(monitor.checkResult)
        XCTAssertEqual(MonitorPresentation.status(of: monitor), .unknown)
        XCTAssertEqual(
            MonitorPresentation.statusText(of: monitor), "状态未识别"
        )
    }

    // MARK: - 未读聚合与排序

    func testTotalUnreadSumsServerCounts() throws {
        let changed = try decodeMonitor()
        let failed = try decodeMonitor(monitorFailedJSON)
        XCTAssertEqual(
            MonitorPresentation.totalUnread([changed, failed]), 2
        )
        XCTAssertEqual(MonitorPresentation.totalUnread([]), 0)
    }

    func testOrderingUnreadFirstThenLatestChange() {
        let quiet = makeMonitor(
            unreadChanges: 0, latestChangeAt: 900, createdAt: 1
        )
        let loud = makeMonitor(
            unreadChanges: 3, latestChangeAt: 100, createdAt: 2
        )
        let mid = makeMonitor(
            unreadChanges: 3, latestChangeAt: 500, createdAt: 3
        )
        let sorted = MonitorOrdering.sorted([quiet, loud, mid])
        XCTAssertEqual(sorted.map(\.createdAt), [3, 2, 1])
    }

    func testChangeOrderingDescendingByDetectedAt() throws {
        let older = try decoder.decode(
            BridgeMonitorChange.self,
            from: Data(
                """
                {"id": "chg_a", "monitorId": "mon_x",
                 "detectedAt": 10, "summary": "旧"}
                """.utf8
            )
        )
        let newer = try decoder.decode(
            BridgeMonitorChange.self,
            from: Data(
                """
                {"id": "chg_b", "monitorId": "mon_x",
                 "detectedAt": 20, "summary": "新"}
                """.utf8
            )
        )
        XCTAssertEqual(
            MonitorChangeOrdering.sorted([older, newer]).map(\.id),
            ["chg_b", "chg_a"]
        )
    }

    // MARK: - 差异行组装（有什么给什么）

    func testChangeDetailRowsWithOriginalText() throws {
        let change = try decoder.decode(
            BridgeMonitorChange.self, from: Data(changeJSON.utf8)
        )
        let rows = MonitorChangeDetail.rows(for: change)
        XCTAssertEqual(rows.summary, "价格从 ¥199 变为 ¥179")
        XCTAssertEqual(rows.before, "¥199")
        XCTAssertEqual(rows.after, "¥179")
        XCTAssertTrue(rows.hasOriginalText)
    }

    func testChangeDetailRowsWithoutOriginalText() throws {
        let change = try decoder.decode(
            BridgeMonitorChange.self,
            from: Data(
                """
                {"id": "chg_min", "monitorId": "mon_x",
                 "detectedAt": 5, "summary": "页面标题变了",
                 "before": "  ", "after": null}
                """.utf8
            )
        )
        let rows = MonitorChangeDetail.rows(for: change)
        XCTAssertNil(rows.before)
        XCTAssertNil(rows.after)
        XCTAssertFalse(rows.hasOriginalText)
    }

    func testMarkingReadReturnsReadCopy() throws {
        let change = try decoder.decode(
            BridgeMonitorChange.self, from: Data(changeJSON.utf8)
        )
        let read = change.markingRead()
        XCTAssertTrue(read.read)
        XCTAssertEqual(read.id, change.id)
        XCTAssertEqual(read.summary, change.summary)
        XCTAssertFalse(change.read)
    }

    // MARK: - 新建监测（0.12.1：频率档与请求体）

    private func jsonObject<T: Encodable>(
        _ value: T
    ) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        let object = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(object as? [String: Any])
    }

    func testFrequencyMapsToIntervalAndScheduleText() {
        XCTAssertNil(MonitorFrequency.manual.intervalSeconds)
        XCTAssertEqual(MonitorFrequency.manual.scheduleText, "手动检查")
        XCTAssertEqual(MonitorFrequency.hourly.intervalSeconds, 3600)
        XCTAssertEqual(MonitorFrequency.hourly.scheduleText, "每小时检查")
        XCTAssertEqual(MonitorFrequency.daily.intervalSeconds, 86400)
        XCTAssertEqual(MonitorFrequency.daily.scheduleText, "每天检查")
        XCTAssertEqual(MonitorFrequency.allCases.count, 3)
    }

    func testMonitorCreateRequestManualOmitsIntervalAndCron() throws {
        let request = BridgeMonitorCreateRequest.make(
            name: " 价格页 ", target: " https://example.com/pricing ",
            frequency: .manual
        )
        let object = try jsonObject(request)
        XCTAssertEqual(object["name"] as? String, "价格页")
        XCTAssertEqual(
            object["target"] as? String, "https://example.com/pricing"
        )
        XCTAssertEqual(object["scheduleText"] as? String, "手动检查")
        // 手动档不落 intervalSeconds（桥据此判手动型）、
        // cron 高级档留口不落键
        XCTAssertNil(object["intervalSeconds"])
        XCTAssertNil(object["cron"])
    }

    func testMonitorCreateRequestHourlyCarriesInterval() throws {
        let object = try jsonObject(
            BridgeMonitorCreateRequest.make(
                name: "价格页", target: "https://example.com",
                frequency: .hourly
            )
        )
        XCTAssertEqual(object["intervalSeconds"] as? Int, 3600)
        XCTAssertEqual(object["scheduleText"] as? String, "每小时检查")
        XCTAssertNil(object["cron"])
    }

    func testMonitorCreateRequestDailyCarriesInterval() throws {
        let object = try jsonObject(
            BridgeMonitorCreateRequest.make(
                name: "状态页", target: "https://example.com/status",
                frequency: .daily
            )
        )
        XCTAssertEqual(object["intervalSeconds"] as? Int, 86400)
        XCTAssertEqual(object["scheduleText"] as? String, "每天检查")
        XCTAssertNil(object["cron"])
    }

    // MARK: - 新建表单校验（与桥端 400 对齐）

    func testCreateValidationRejectsBlankName() {
        XCTAssertEqual(
            MonitorCreateValidation.problem(
                name: "  ", target: "https://example.com"
            ),
            "请填写监测名称。"
        )
    }

    func testCreateValidationRejectsBlankTarget() {
        XCTAssertEqual(
            MonitorCreateValidation.problem(name: "价格页", target: " "),
            "请填写要盯的链接。"
        )
    }

    func testCreateValidationRejectsNonHTTPAndAcceptsHTTP() {
        XCTAssertEqual(
            MonitorCreateValidation.problem(
                name: "价格页", target: "example.com"
            ),
            "链接要以 http:// 或 https:// 开头。"
        )
        XCTAssertEqual(
            MonitorCreateValidation.problem(
                name: "价格页", target: "ftp://example.com"
            ),
            "链接要以 http:// 或 https:// 开头。"
        )
        XCTAssertNil(
            MonitorCreateValidation.problem(
                name: "价格页", target: "http://example.com"
            )
        )
        XCTAssertNil(
            MonitorCreateValidation.problem(
                name: " 价格页 ", target: " https://example.com "
            )
        )
    }
}
