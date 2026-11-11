import OneDayCore
import XCTest

/// 渲染计划缓存键（§132，DESIGN-V4 §132）：缓存的
/// 正确性全在失效条件上——本组逐项钉死：集合、形
/// 态、时刻、线程、跨日任一变化键必变；无关的输入
/// 顺序变化键不变（否则缓存永不命中、等于没做）
final class ChatRenderPlanKeyTests: XCTestCase {
    private let threadA = UUID()
    private let threadB = UUID()
    private let day1 = Date(timeIntervalSince1970: 1_700_000_000)
    private let day2 = Date(timeIntervalSince1970: 1_700_086_400)
    private let t0 = Date(timeIntervalSince1970: 1_699_900_000)

    private func stub(
        _ id: UUID, tool: Bool = false, at offset: TimeInterval = 0
    ) -> ChatRenderPlanKey.EntryStub {
        ChatRenderPlanKey.EntryStub(
            id: id,
            hasToolCardData: tool,
            createdAt: t0.addingTimeInterval(offset)
        )
    }

    private func key(
        thread: UUID? = nil,
        entries: [ChatRenderPlanKey.EntryStub],
        day: Date? = nil
    ) -> ChatRenderPlanKey {
        ChatRenderPlanKey.make(
            threadID: thread ?? threadA,
            entries: entries,
            dayStamp: day ?? day1
        )
    }

    func testSameInputsSameKey() {
        let ids = [UUID(), UUID()]
        let entries = [stub(ids[0]), stub(ids[1], tool: true, at: 5)]
        XCTAssertEqual(key(entries: entries), key(entries: entries))
    }

    func testEntryOrderDoesNotAffectKey() {
        let ids = [UUID(), UUID(), UUID()]
        let entries = [
            stub(ids[0]), stub(ids[1], tool: true), stub(ids[2], at: 9),
        ]
        XCTAssertEqual(
            key(entries: entries),
            key(entries: Array(entries.reversed()))
        )
    }

    func testInsertOrDeleteChangesKey() {
        let ids = [UUID(), UUID()]
        let base = [stub(ids[0]), stub(ids[1])]
        XCTAssertNotEqual(
            key(entries: base),
            key(entries: base + [stub(UUID())])
        )
        XCTAssertNotEqual(
            key(entries: base), key(entries: [stub(ids[0])])
        )
    }

    func testToolCardFlipChangesKey() {
        let id = UUID()
        XCTAssertNotEqual(
            key(entries: [stub(id, tool: false)]),
            key(entries: [stub(id, tool: true)])
        )
    }

    func testCreatedAtChangeChangesKey() {
        let id = UUID()
        XCTAssertNotEqual(
            key(entries: [stub(id, at: 0)]),
            key(entries: [stub(id, at: 60)])
        )
    }

    func testThreadChangeChangesKey() {
        let entries = [stub(UUID())]
        XCTAssertNotEqual(
            key(thread: threadA, entries: entries),
            key(thread: threadB, entries: entries)
        )
    }

    func testDayRolloverChangesKey() {
        let entries = [stub(UUID())]
        XCTAssertNotEqual(
            key(entries: entries, day: day1),
            key(entries: entries, day: day2)
        )
    }

    func testEmptyEntriesKeyIsStable() {
        XCTAssertEqual(key(entries: []), key(entries: []))
        XCTAssertEqual(key(entries: []).entryCount, 0)
    }
}
