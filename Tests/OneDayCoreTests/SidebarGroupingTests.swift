import XCTest
@testable import OneDayCore

final class SidebarGroupingTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    private func date(
        _ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12
    ) -> Date {
        calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour
        ))!
    }

    private typealias Item = SidebarGrouping.Item<String>

    /// 五段分界全覆盖：自然日差 0/1/2/7/8/30/31 与
    /// 跨年月份标签；置顶独立成组且不进时间段；组内
    /// 按 updatedAt 倒序（入参乱序喂入）。
    func testFiveTiersBoundariesAndMonthLabels() {
        let now = date(2026, 11, 9)
        let items: [Item] = [
            Item(key: "old-cross-year", updatedAt: date(2025, 12, 20), isPinned: false),
            Item(key: "today-early", updatedAt: date(2026, 11, 9, 8), isPinned: false),
            Item(key: "day30", updatedAt: date(2026, 10, 10), isPinned: false),
            Item(key: "pinned-old", updatedAt: date(2026, 9, 1), isPinned: true),
            Item(key: "day31-oct", updatedAt: date(2026, 10, 9), isPinned: false),
            Item(key: "day2", updatedAt: date(2026, 11, 7), isPinned: false),
            Item(key: "yesterday", updatedAt: date(2026, 11, 8, 23), isPinned: false),
            Item(key: "today-late", updatedAt: date(2026, 11, 9, 11), isPinned: false),
            Item(key: "day7", updatedAt: date(2026, 11, 2), isPinned: false),
            Item(key: "day8", updatedAt: date(2026, 11, 1), isPinned: false),
        ]
        let groups = SidebarGrouping.groups(
            items: items, now: now, calendar: calendar
        )
        XCTAssertEqual(groups.map(\.label), [
            "置顶", "今天", "昨天", "过去 7 天", "过去 30 天",
            "10月", "2025年12月",
        ])
        XCTAssertEqual(groups[0].keys, ["pinned-old"])
        XCTAssertEqual(groups[1].keys, ["today-late", "today-early"])
        XCTAssertEqual(groups[2].keys, ["yesterday"])
        XCTAssertEqual(groups[3].keys, ["day2", "day7"])
        XCTAssertEqual(groups[4].keys, ["day8", "day30"])
        XCTAssertEqual(groups[5].keys, ["day31-oct"])
        XCTAssertEqual(groups[6].keys, ["old-cross-year"])
    }

    /// 搜索态：单组「搜索结果」，置顶不单列、全按
    /// 时间倒序；空输入返回空数组（视图层走空态行）。
    func testSearchingFlattensToSingleGroup() {
        let now = date(2026, 11, 9)
        let items: [Item] = [
            Item(key: "a", updatedAt: date(2026, 11, 9, 9), isPinned: false),
            Item(key: "b", updatedAt: date(2026, 10, 1), isPinned: true),
            Item(key: "c", updatedAt: date(2026, 11, 8), isPinned: false),
        ]
        let groups = SidebarGrouping.groups(
            items: items, now: now, calendar: calendar, searching: true
        )
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].label, "搜索结果")
        XCTAssertEqual(groups[0].keys, ["a", "c", "b"])
        XCTAssertTrue(SidebarGrouping.groups(
            items: [Item](), now: now, calendar: calendar, searching: true
        ).isEmpty)
        XCTAssertTrue(SidebarGrouping.groups(
            items: [Item](), now: now, calendar: calendar
        ).isEmpty)
    }

    /// 时钟漂移防御：updatedAt 在未来（日差为负）
    /// 一律归「今天」，不许掉进月份组。
    func testFutureDatesFallIntoToday() {
        let now = date(2026, 11, 9)
        let items = [
            Item(key: "future", updatedAt: date(2026, 11, 12), isPinned: false)
        ]
        let groups = SidebarGrouping.groups(
            items: items, now: now, calendar: calendar
        )
        XCTAssertEqual(groups.map(\.label), ["今天"])
    }
}

final class DrawerGeometryTests: XCTestCase {
    /// 橡皮筋公式锚点与形状：0 处为 0、单调递增、
    /// 渐近线低于容器宽、小位移斜率趋近 c=0.55。
    func testRubberBandShape() {
        XCTAssertEqual(
            DrawerGeometry.rubberBand(overshoot: 0, containerWidth: 320), 0
        )
        XCTAssertEqual(
            DrawerGeometry.rubberBand(overshoot: -5, containerWidth: 320), 0
        )
        // (100 · 320 · 0.55) / (320 + 55) = 17600/375
        XCTAssertEqual(
            DrawerGeometry.rubberBand(overshoot: 100, containerWidth: 320),
            46.9333, accuracy: 0.001
        )
        let small = DrawerGeometry.rubberBand(
            overshoot: 1, containerWidth: 320
        )
        XCTAssertEqual(small, 0.5497, accuracy: 0.001)
        let huge = DrawerGeometry.rubberBand(
            overshoot: 100_000, containerWidth: 320
        )
        XCTAssertGreaterThan(huge, 300)
        XCTAssertLessThan(huge, 320)
        XCTAssertEqual(
            DrawerGeometry.rubberBand(overshoot: 10, containerWidth: 0), 0
        )
    }
}
