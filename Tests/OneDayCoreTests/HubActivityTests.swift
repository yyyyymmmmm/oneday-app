import OneDayCore
import XCTest

/// 活动流降级拼装（phase3-data-design §4）：会话主实体、
/// cron run 合并、日志时间窗关联——全部保守口径，错配
/// 宁可副题为空，不许拿噪声日志冒充活动说明。
final class HubActivityTests: XCTestCase {
    private let decoder = JSONDecoder()
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return cal
    }
    /// 固定 now：2026-11-09 12:00（+08）
    private var now: Date {
        ISO8601DateFormatter().date(from: "2026-11-09T04:00:00Z")!
    }

    private func session(_ json: String) throws -> ServerSession {
        try decoder.decode(ServerSession.self, from: Data(json.utf8))
    }

    private func epoch(_ iso: String) -> Double {
        ISO8601DateFormatter().date(from: iso)!.timeIntervalSince1970
    }

    /// 2026-11-09 10:00–10:05（+08）的已结束会话
    private func baseSession(id: String = "s1") throws -> ServerSession {
        try session("""
        {"id": "\(id)", "source": "dashboard",
         "display_name": "看看服务器状态",
         "started_at": \(epoch("2026-11-09T02:00:00Z")),
         "ended_at": \(epoch("2026-11-09T02:05:00Z")),
         "message_count": 4}
        """)
    }

    func testSessionRunMergeSameID() throws {
        let main = try baseSession()
        let run = try session("""
        {"id": "s1", "source": "cron",
         "started_at": \(epoch("2026-11-09T02:00:00Z")),
         "ended_at": \(epoch("2026-11-09T02:05:00Z"))}
        """)
        let groups = HubActivityAssembler.assemble(
            sessions: [main], runsByJobID: ["job-1": [run]],
            jobTitles: ["job-1": "节点巡检"], logs: [],
            fetchedAt: now, now: now, calendar: calendar
        )
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].items.count, 1)
        // 主表字段优先：标题仍是会话人话名，不被 run 覆盖
        XCTAssertEqual(groups[0].items[0].title, "看看服务器状态")
        XCTAssertEqual(groups[0].items[0].jobID, "job-1")
    }

    func testTwoJobsClaimSameRunSmallerIDWins() throws {
        let run = try session("""
        {"id": "r1", "source": "cron", "display_name": null,
         "started_at": \(epoch("2026-11-09T02:00:00Z")),
         "ended_at": \(epoch("2026-11-09T02:05:00Z"))}
        """)
        let groups = HubActivityAssembler.assemble(
            sessions: [], runsByJobID: ["job-b": [run], "job-a": [run]],
            jobTitles: ["job-a": "任务甲", "job-b": "任务乙"], logs: [],
            fetchedAt: now, now: now, calendar: calendar
        )
        XCTAssertEqual(groups[0].items.count, 1)
        XCTAssertEqual(groups[0].items[0].jobID, "job-a")
        // 无人话名时标题回落 job 标题
        XCTAssertEqual(groups[0].items[0].title, "任务甲")
    }

    func testLogAssociationAndSubtitleRules() throws {
        let main = try baseSession()
        let inWindow = LogEventParser.parse(
            "2026-11-09T02:03:00Z INFO gateway.run: 检查了节点连通性。全部正常"
        )
        let jsonLine = LogEventParser.parse(
            "2026-11-09T02:04:00Z INFO gateway.run: {\"raw\": true} 原始载荷"
        )
        let noTimestamp = LogEventParser.parse(
            "INFO gateway.run: 没有时间戳的一行。也在窗内语义"
        )
        let groups = HubActivityAssembler.assemble(
            sessions: [main], runsByJobID: [:], jobTitles: [:],
            logs: [inWindow, jsonLine, noTimestamp],
            fetchedAt: now, now: now, calendar: calendar
        )
        let item = groups[0].items[0]
        // JSON 行与无时间戳行都不作副题；结构化人话行入选
        XCTAssertEqual(item.subtitle, "检查了节点连通性")
        XCTAssertFalse(jsonLine.isSubtitleCandidate)
        XCTAssertFalse(noTimestamp.isSubtitleCandidate)
    }

    func testOverlappingSessionsShorterWindowWins() throws {
        // 长会话 10:00–11:00 与短会话 10:10–10:20 重叠，
        // 10:15 的日志应归短会话（窗更短优先）
        let long = try session("""
        {"id": "long", "source": "dashboard", "display_name": "长会话",
         "started_at": \(epoch("2026-11-09T02:00:00Z")),
         "ended_at": \(epoch("2026-11-09T03:00:00Z"))}
        """)
        let short = try session("""
        {"id": "short", "source": "dashboard", "display_name": "短会话",
         "started_at": \(epoch("2026-11-09T02:10:00Z")),
         "ended_at": \(epoch("2026-11-09T02:20:00Z"))}
        """)
        let log = LogEventParser.parse(
            "2026-11-09T02:15:00Z INFO agent.core: 处理了中间的请求。已完成"
        )
        let groups = HubActivityAssembler.assemble(
            sessions: [long, short], runsByJobID: [:], jobTitles: [:],
            logs: [log], fetchedAt: now, now: now, calendar: calendar
        )
        let items = groups.flatMap(\.items)
        let shortItem = items.first { $0.sessionID == "short" }
        let longItem = items.first { $0.sessionID == "long" }
        XCTAssertEqual(shortItem?.subtitle, "处理了中间的请求")
        XCTAssertNil(longItem?.subtitle)
    }

    func testActiveSessionDoesNotSortByNow() throws {
        // 活跃会话 occurredAt＝开始时刻，不许用 now 顶到
        // 列表最前：开始于 08:00 的活跃会话应排在 10:00
        // 已结束会话之后
        let active = try session("""
        {"id": "act", "source": "dashboard", "display_name": "进行中会话",
         "started_at": \(epoch("2026-11-09T00:00:00Z")), "ended_at": null}
        """)
        let ended = try baseSession(id: "end")
        let groups = HubActivityAssembler.assemble(
            sessions: [active, ended], runsByJobID: [:], jobTitles: [:],
            logs: [], fetchedAt: now, now: now, calendar: calendar
        )
        XCTAssertEqual(groups[0].items.map(\.sessionID), ["end", "act"])
        XCTAssertEqual(groups[0].label, "今天")
    }

    func testCrossDayGrouping() throws {
        let yesterday = try session("""
        {"id": "y1", "source": "cli", "display_name": "昨天的事",
         "started_at": \(epoch("2026-11-08T02:00:00Z")),
         "ended_at": \(epoch("2026-11-08T02:05:00Z"))}
        """)
        let today = try baseSession()
        let groups = HubActivityAssembler.assemble(
            sessions: [yesterday, today], runsByJobID: [:], jobTitles: [:],
            logs: [], fetchedAt: now, now: now, calendar: calendar
        )
        XCTAssertEqual(groups.map(\.label), ["今天", "昨天"])
    }

    func testSessionWithoutTimestampsExcluded() throws {
        let ghost = try session("""
        {"id": "ghost", "source": "cli", "display_name": "无时间会话"}
        """)
        let groups = HubActivityAssembler.assemble(
            sessions: [ghost], runsByJobID: [:], jobTitles: [:],
            logs: [], fetchedAt: now, now: now, calendar: calendar
        )
        XCTAssertTrue(groups.isEmpty)
    }

    /// 派生标题与 meta（0.6.1）：无名会话注入首条消
    /// 息后标题走内容摘要；meta 是行副题（时间·条
    /// 数·来源、无「进行中」段、与数据层 subtitle
    /// 分工不混）
    func testDerivedTitleAndMetaFromFirstUserMessage() throws {
        let unnamed = try session("""
        {"id": "s9", "source": "dashboard", "display_name": null,
         "started_at": \(epoch("2026-11-09T02:00:00Z")),
         "ended_at": \(epoch("2026-11-09T02:05:00Z")),
         "message_count": 3}
        """)
        let groups = HubActivityAssembler.assemble(
            sessions: [unnamed], runsByJobID: [:], jobTitles: [:],
            logs: [], fetchedAt: now, now: now, calendar: calendar,
            firstUserMessages: ["s9": "帮我查一下节点状态"]
        )
        let item = groups[0].items[0]
        XCTAssertEqual(item.title, "帮我查一下节点状态")
        XCTAssertEqual(item.meta, "今天 10:00 · 3 条 · 控制台")
        XCTAssertFalse(item.meta.contains("进行中"))
        // 无注入时回落未命名（不假造标题）
        let plain = HubActivityAssembler.assemble(
            sessions: [unnamed], runsByJobID: [:], jobTitles: [:],
            logs: [], fetchedAt: now, now: now, calendar: calendar
        )
        XCTAssertEqual(plain[0].items[0].title, "未命名会话")
        XCTAssertEqual(plain[0].items[0].meta, "今天 10:00 · 3 条 · 控制台")
    }
}
