import XCTest
@testable import OneDayCore

/// §503（对话内查找全件修复）：命中计算／就近起
/// 点／着色区间／会话状态机的判定全集——findBar
/// 自 D9 起缺的全是接线，判定先在此钉死，视图层
/// 接线另有 ChatFindWiringTests 装配钉
final class ChatFindTests: XCTestCase {
    private func stub(
        _ n: Int, content: String, searchable: Bool = true
    ) -> ChatFind.EntryStub {
        ChatFind.EntryStub(
            id: UUID(
                uuidString: String(
                    format: "00000000-0000-0000-0000-%012d", n
                )
            )!,
            content: content, isSearchable: searchable
        )
    }

    private func id(_ n: Int) -> UUID {
        UUID(
            uuidString: String(
                format: "00000000-0000-0000-0000-%012d", n
            )
        )!
    }

    // MARK: - 命中计算

    func testMatchesCaseInsensitiveContains() {
        let entries = [
            stub(1, content: "Hello World"),
            stub(2, content: "nothing here"),
            stub(3, content: "say hello again"),
        ]
        let found = ChatFind.matches(entries: entries, query: "HELLO")
        XCTAssertEqual(found.map(\.id), [id(1), id(3)])
        XCTAssertEqual(found.map(\.position), [0, 2])
    }

    func testMatchesSkipsUnsearchableEntries() {
        // 工具卡/trace/回响/审批在调用方折成
        // isSearchable=false：正文命中也不进集
        let entries = [
            stub(1, content: "target text", searchable: false),
            stub(2, content: "target text"),
        ]
        let found = ChatFind.matches(entries: entries, query: "target")
        XCTAssertEqual(found.map(\.id), [id(2)])
    }

    func testMatchesEmptyOrBlankQueryFindsNothing() {
        let entries = [stub(1, content: "anything")]
        XCTAssertTrue(
            ChatFind.matches(entries: entries, query: "").isEmpty
        )
        XCTAssertTrue(
            ChatFind.matches(entries: entries, query: "   ").isEmpty
        )
    }

    func testMatchesTrimsQuery() {
        let entries = [stub(1, content: "a needle in text")]
        let found = ChatFind.matches(
            entries: entries, query: "  needle  "
        )
        XCTAssertEqual(found.map(\.id), [id(1)])
    }

    // MARK: - 就近起点

    func testNearestPicksClosestToAnchor() {
        // 命中在全序 2/9/14，锚在 10 → 取 9（下标 1）
        XCTAssertEqual(
            ChatFind.nearestMatchIndex(
                matchPositions: [2, 9, 14], anchorPosition: 10
            ),
            1
        )
    }

    func testNearestTiePrefersForwardMatch() {
        // 锚在 8，命中 5 与 11 同距（3）→ 锚后优先
        XCTAssertEqual(
            ChatFind.nearestMatchIndex(
                matchPositions: [5, 11], anchorPosition: 8
            ),
            1
        )
    }

    func testNearestAnchorOnMatchPicksItself() {
        XCTAssertEqual(
            ChatFind.nearestMatchIndex(
                matchPositions: [3, 7, 12], anchorPosition: 7
            ),
            1
        )
    }

    func testNearestWithoutAnchorFallsBackToFirst() {
        XCTAssertEqual(
            ChatFind.nearestMatchIndex(
                matchPositions: [4, 8], anchorPosition: nil
            ),
            0
        )
        XCTAssertEqual(
            ChatFind.nearestMatchIndex(
                matchPositions: [], anchorPosition: 3
            ),
            0
        )
    }

    // MARK: - 着色区间

    func testOccurrenceRangesAllCaseInsensitive() {
        let ranges = ChatFind.occurrenceRanges(
            in: "Foo bar FOO baz foo", query: "foo"
        )
        XCTAssertEqual(
            ranges.map { [$0.location, $0.length] },
            [[0, 3], [8, 3], [16, 3]]
        )
    }

    func testOccurrenceRangesNonOverlapping() {
        let ranges = ChatFind.occurrenceRanges(
            in: "aaaa", query: "aa"
        )
        XCTAssertEqual(
            ranges.map { [$0.location, $0.length] },
            [[0, 2], [2, 2]]
        )
    }

    func testOccurrenceRangesEmptyCases() {
        XCTAssertTrue(
            ChatFind.occurrenceRanges(in: "abc", query: "").isEmpty
        )
        XCTAssertTrue(
            ChatFind.occurrenceRanges(in: "abc", query: "z").isEmpty
        )
        XCTAssertTrue(
            ChatFind.occurrenceRanges(in: "", query: "a").isEmpty
        )
    }

    func testOccurrenceRangesCJK() {
        let ranges = ChatFind.occurrenceRanges(
            in: "去吃火锅，火锅好吃", query: "火锅"
        )
        XCTAssertEqual(
            ranges.map { [$0.location, $0.length] },
            [[2, 2], [5, 2]]
        )
    }

    // MARK: - 会话状态机

    func testSessionRecomputeLandsOnStartAndAssignsTarget() {
        var session = ChatFindSession()
        let target = session.recompute(
            matches: [id(1), id(2), id(3)], startIndex: 1
        )
        // 落座返回的目标即点亮赋值源：视图层据此置
        // findHighlightEntryID 并直调收敛落点
        XCTAssertEqual(target, id(2))
        XCTAssertEqual(session.currentMatchID, id(2))
        XCTAssertEqual(session.currentIndex, 1)
        XCTAssertEqual(session.matches.count, 3)
    }

    func testSessionRecomputeClampsStartIndex() {
        var session = ChatFindSession()
        let target = session.recompute(
            matches: [id(1), id(2)], startIndex: 99
        )
        XCTAssertEqual(target, id(2))
        XCTAssertEqual(session.currentIndex, 1)
    }

    func testSessionRecomputeEmptyClears() {
        var session = ChatFindSession()
        _ = session.recompute(matches: [id(1)], startIndex: 0)
        let target = session.recompute(matches: [], startIndex: 0)
        XCTAssertNil(target)
        XCTAssertNil(session.currentMatchID)
        XCTAssertEqual(session.currentIndex, 0)
    }

    func testSessionNavigationWrapsAround() {
        var session = ChatFindSession()
        _ = session.recompute(
            matches: [id(1), id(2), id(3)], startIndex: 0
        )
        XCTAssertEqual(session.moveNext(), id(2))
        XCTAssertEqual(session.moveNext(), id(3))
        // 末尾环绕回首条
        XCTAssertEqual(session.moveNext(), id(1))
        // 首条上翻环绕到末条
        XCTAssertEqual(session.movePrevious(), id(3))
        XCTAssertEqual(session.movePrevious(), id(2))
    }

    func testSessionNavigationEmptyReturnsNil() {
        var session = ChatFindSession()
        XCTAssertNil(session.moveNext())
        XCTAssertNil(session.movePrevious())
    }

    func testSessionTypingSequenceRecomputes() {
        // 输入即搜的判定面：逐字打入时每拍以新查询
        // 重算命中集并重新落座，计数随打随变
        let entries = [
            stub(1, content: "火锅底料"),
            stub(2, content: "火锅店排队"),
            stub(3, content: "烧烤"),
        ]
        var session = ChatFindSession()
        let first = ChatFind.matches(entries: entries, query: "火")
        _ = session.recompute(
            matches: first.map(\.id), startIndex: 0
        )
        XCTAssertEqual(session.matches.count, 2)
        let second = ChatFind.matches(entries: entries, query: "火锅店")
        let target = session.recompute(
            matches: second.map(\.id), startIndex: 0
        )
        XCTAssertEqual(session.matches.count, 1)
        XCTAssertEqual(target, id(2))
    }

    func testSessionReset() {
        var session = ChatFindSession()
        _ = session.recompute(matches: [id(1)], startIndex: 0)
        session.reset()
        XCTAssertTrue(session.matches.isEmpty)
        XCTAssertEqual(session.currentIndex, 0)
        XCTAssertNil(session.currentMatchID)
    }
}
