import OneDayCore
import XCTest

/// 动态页呈现口径（P3，0.35.0）：排序（发布时间倒
/// 序）、按日分组与组头、相对时间档位、未读数、胶
/// 囊落点优先级、空态二分、正文摘剥形、DTO 宽容解
/// 码——全是进页前的纯计算，视图只渲染。
final class FeedBoardTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return cal
    }

    private func date(
        _ year: Int, _ month: Int, _ day: Int,
        _ hour: Int = 12, _ minute: Int = 0, _ second: Int = 0
    ) -> Date {
        calendar.date(from: DateComponents(
            year: year, month: month, day: day,
            hour: hour, minute: minute, second: second
        ))!
    }

    private func post(
        id: String, kind: FeedPostKind = .digest,
        title: String = "帖", body: String = "正文",
        createdAt: Date, readAt: Date? = nil
    ) -> BridgeFeedPost {
        BridgeFeedPost(
            id: id, kind: kind, title: title, body: body,
            createdAt: createdAt.timeIntervalSince1970,
            readAt: readAt?.timeIntervalSince1970
        )
    }

    // MARK: - 排序与分组

    func testSortedIsCreatedAtDescending() {
        let now = date(2026, 11, 10, 15)
        let posts = [
            post(id: "a", createdAt: date(2026, 11, 9, 9)),
            post(id: "b", createdAt: date(2026, 11, 10, 9)),
            post(id: "c", createdAt: date(2026, 11, 8, 9)),
        ]
        XCTAssertEqual(
            FeedBoard.sorted(posts).map(\.id), ["b", "a", "c"]
        )
        _ = now
    }

    func testDayGroupsTitlesAndOrder() {
        let now = date(2026, 11, 10, 15)  // 周二
        let posts = FeedBoard.sorted([
            post(id: "t1", createdAt: date(2026, 11, 10, 9)),
            post(id: "t2", createdAt: date(2026, 11, 10, 8)),
            post(id: "y1", createdAt: date(2026, 11, 9, 20)),
            post(id: "w1", createdAt: date(2026, 11, 6, 10)),
            post(id: "o1", createdAt: date(2026, 10, 30, 10)),
            post(id: "x1", createdAt: date(2025, 12, 31, 10)),
        ])
        let groups = FeedBoard.dayGroups(
            posts, now: now, calendar: calendar,
            locale: Locale(identifier: "zh-Hans")
        )
        XCTAssertEqual(
            groups.map(\.title),
            ["今天", "昨天", "星期五", "10月30日", "2025年12月31日"]
        )
        XCTAssertEqual(groups.first?.posts.map(\.id), ["t1", "t2"])
    }

    // MARK: - 相对时间

    func testRelativeTextTiers() {
        let now = date(2026, 11, 10, 15, 30)
        func rel(_ d: Date) -> String {
            FeedBoard.relativeText(
                for: d.timeIntervalSince1970, now: now,
                calendar: calendar,
                locale: Locale(identifier: "zh-Hans")
            )
        }
        XCTAssertEqual(rel(date(2026, 11, 10, 15, 29, 40)), "刚刚")
        XCTAssertEqual(rel(date(2026, 11, 10, 15, 29, 0)), "1分钟")
        XCTAssertEqual(rel(date(2026, 11, 10, 15, 10)), "20分钟")
        XCTAssertEqual(rel(date(2026, 11, 10, 13, 30)), "2小时")
        XCTAssertEqual(rel(date(2026, 11, 9, 22, 5)), "昨天 22:05")
        XCTAssertEqual(rel(date(2026, 11, 6, 8, 0)), "星期五 08:00")
        XCTAssertEqual(rel(date(2026, 10, 30, 8, 0)), "10月30日 08:00")
        XCTAssertEqual(rel(date(2025, 12, 31, 8, 0)), "2025年12月31日 08:00")
    }

    // MARK: - 未读与胶囊

    func testUnreadCount() {
        let posts = [
            post(id: "a", createdAt: date(2026, 11, 10, 9)),
            post(id: "b", createdAt: date(2026, 11, 10, 8),
                 readAt: date(2026, 11, 10, 10)),
            post(id: "c", createdAt: date(2026, 11, 9, 8)),
        ]
        XCTAssertEqual(FeedBoard.unreadCount(posts), 2)
    }

    func testCapsulePrefersTodaysDigest() {
        let now = date(2026, 11, 10, 15)
        let posts = [
            post(id: "m", kind: .morning,
                 createdAt: date(2026, 11, 10, 8, 30)),
            post(id: "d", kind: .digest,
                 createdAt: date(2026, 11, 10, 14, 43)),
            post(id: "old", kind: .morning,
                 createdAt: date(2026, 11, 9, 8, 30)),
        ]
        XCTAssertEqual(
            FeedBoard.capsulePost(posts, now: now, calendar: calendar)?.id,
            "d"
        )
    }

    func testCapsuleFallsToMorningThenUnreadThenLatest() {
        let now = date(2026, 11, 10, 15)
        let morningOnly = [
            post(id: "m", kind: .morning,
                 createdAt: date(2026, 11, 10, 8, 30)),
        ]
        XCTAssertEqual(
            FeedBoard.capsulePost(
                morningOnly, now: now, calendar: calendar
            )?.id, "m"
        )
        let readTodayUnreadOld = [
            post(id: "t", kind: .morning,
                 createdAt: date(2026, 11, 10, 8, 30),
                 readAt: date(2026, 11, 10, 9)),
            post(id: "o", kind: .digest,
                 createdAt: date(2026, 11, 9, 8, 30)),
        ]
        // 今日晨报已读、旧帖未读：今日优先仍胜（胶囊是
        // 「今日动态」的入口，不是未读收件箱）
        XCTAssertEqual(
            FeedBoard.capsulePost(
                readTodayUnreadOld, now: now, calendar: calendar
            )?.id, "t"
        )
        let allOld = [
            post(id: "o1", kind: .digest,
                 createdAt: date(2026, 11, 9, 9),
                 readAt: date(2026, 11, 9, 10)),
            post(id: "o2", kind: .morning,
                 createdAt: date(2026, 11, 8, 9)),
        ]
        XCTAssertEqual(
            FeedBoard.capsulePost(
                allOld, now: now, calendar: calendar
            )?.id, "o2"
        )
        XCTAssertNil(
            FeedBoard.capsulePost([], now: now, calendar: calendar)
        )
    }

    // MARK: - 空态

    func testEmptyKindSplits() {
        XCTAssertEqual(
            FeedBoard.emptyKind(
                hasAnyPost: false, morningLastRunAt: nil,
                eventsToday: 0
            ),
            .neverProduced
        )
        XCTAssertEqual(
            FeedBoard.emptyKind(
                hasAnyPost: false, morningLastRunAt: 123,
                eventsToday: 0
            ),
            .quiet
        )
        XCTAssertEqual(
            FeedBoard.emptyKind(
                hasAnyPost: false, morningLastRunAt: nil,
                eventsToday: 2
            ),
            .quiet
        )
        XCTAssertEqual(
            FeedBoard.emptyKind(
                hasAnyPost: true, morningLastRunAt: nil,
                eventsToday: 0
            ),
            .quiet
        )
    }

    // MARK: - 正文摘

    func testExcerptStripsMarkdownShape() {
        let body = "## 新点子\n- 14:43 新点子《甲》\n\n- 15:01 **任务** 变了"
        XCTAssertEqual(
            FeedBoard.excerpt(body),
            "新点子 14:43 新点子《甲》 15:01 任务 变了"
        )
    }

    func testExcerptTruncates() {
        let body = String(repeating: "长", count: 200)
        let out = FeedBoard.excerpt(body, maxLength: 10)
        XCTAssertEqual(out.count, 11)
        XCTAssertTrue(out.hasSuffix("…"))
    }

    // MARK: - DTO 解码

    func testPostDecodingIsLenient() throws {
        let json = """
        {"id": "f_1", "kind": "morning", "title": "晨报题",
         "body": "正文", "refs": [{"type": "briefing", "id": "b_1",
         "goalId": "g_1"}, {"type": "idea", "id": "i_1"}],
         "links": [{"title": "例", "url": "https://example.com"}],
         "why": "值得", "createdAt": 1794301646.0,
         "expiresAt": 1796893646.0, "readAt": null}
        """
        let decoded = try JSONDecoder().decode(
            BridgeFeedPost.self, from: Data(json.utf8)
        )
        XCTAssertEqual(decoded.kind, .morning)
        XCTAssertEqual(decoded.refs.count, 2)
        XCTAssertEqual(decoded.refs.first?.goalId, "g_1")
        XCTAssertEqual(decoded.refs.first?.refType, .briefing)
        XCTAssertNil(decoded.readAt)
        XCTAssertFalse(decoded.isRead)
    }

    func testPostDecodingDefaultsMissingFields() throws {
        let json = #"{"id": "f_2"}"#
        let decoded = try JSONDecoder().decode(
            BridgeFeedPost.self, from: Data(json.utf8)
        )
        XCTAssertEqual(decoded.kind, .unknown)
        XCTAssertEqual(decoded.title, "")
        XCTAssertTrue(decoded.refs.isEmpty)
    }

    func testGenerationDecoding() throws {
        let json = """
        {"assembly": {"date": "2026-11-10",
         "digestPostId": "f_1", "eventsToday": 3,
         "lastAssemblyAt": 1794301380.0, "kanbanNote": "任务板为空",
         "approvalTotal": 0, "approvalsNote": null},
         "morning": {"lastRunAt": 1794301645.0,
         "nextRunAt": 1794357000.0, "running": false,
         "history": [{"at": 1794301645.0, "trigger": "manual",
         "status": "ok", "produced": 1}]},
         "unread": 2}
        """
        let decoded = try JSONDecoder().decode(
            BridgeFeedGeneration.self, from: Data(json.utf8)
        )
        XCTAssertEqual(decoded.assembly?.eventsToday, 3)
        XCTAssertEqual(decoded.morning?.history.first?.status, "ok")
        XCTAssertEqual(decoded.unread, 2)
    }

    func testMarkedReadCopy() {
        let original = post(id: "a", createdAt: date(2026, 11, 10, 9))
        let read = original.markedRead(at: date(2026, 11, 10, 10)
            .timeIntervalSince1970)
        XCTAssertTrue(read.isRead)
        XCTAssertFalse(original.isRead)
        XCTAssertEqual(read.id, original.id)
    }
}
