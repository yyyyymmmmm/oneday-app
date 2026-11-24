import XCTest
@testable import OneDayCore

/// 台账 150（搜索落点收敛）：摘要回找＋收敛判定
/// 全集——服务端命中只有会话级摘要（无消息 id），
/// 客户端按摘要回找目标行；收敛机 ≤6 次重滚、相
/// 邻两拍漂移 ≤1pt 判停、拖动/耗尽即弃
final class SearchFocusTests: XCTestCase {
    private func stub(
        _ n: Int, role: String, content: String
    ) -> SearchTargetResolution.EntryStub {
        SearchTargetResolution.EntryStub(
            id: UUID(
                uuidString: String(
                    format: "00000000-0000-0000-0000-%012d", n
                )
            )!,
            role: role, content: content
        )
    }

    // MARK: - 摘要回找

    func testExactSnippetMatch() {
        let entries = [
            stub(1, role: "user", content: "今天吃什么"),
            stub(2, role: "assistant", content: "去吃火锅吧，毛肚必点"),
        ]
        XCTAssertEqual(
            SearchTargetResolution.targetEntryID(
                entries: entries,
                snippet: "去吃火锅吧，毛肚必点", role: nil
            ),
            entries[1].id
        )
    }

    func testWhitespaceNormalizedMatch() {
        let entries = [
            stub(1, role: "assistant", content: "第一行\n第二行 内容"),
        ]
        XCTAssertEqual(
            SearchTargetResolution.targetEntryID(
                entries: entries,
                snippet: "第一行 第二行 内容", role: nil
            ),
            entries[0].id
        )
    }

    func testEllipsisSnippetUsesLongestSegment() {
        let entries = [
            stub(1, role: "assistant", content: "前文无关"),
            stub(2, role: "assistant",
                 content: "开头几句……后面是这段很长的命中文本内容在这里"),
        ]
        XCTAssertEqual(
            SearchTargetResolution.targetEntryID(
                entries: entries,
                snippet: "开头几句…后面是这段很长的命中文本内容在这里",
                role: nil
            ),
            entries[1].id
        )
    }

    func testRoleScopedSearch() {
        let entries = [
            stub(1, role: "user", content: "同一个关键词出现了"),
            stub(2, role: "assistant", content: "同一个关键词出现了"),
        ]
        XCTAssertEqual(
            SearchTargetResolution.targetEntryID(
                entries: entries,
                snippet: "同一个关键词出现了", role: "assistant"
            ),
            entries[1].id
        )
        // 角色未知时不收窄、取首个
        XCTAssertEqual(
            SearchTargetResolution.targetEntryID(
                entries: entries,
                snippet: "同一个关键词出现了", role: "system"
            ),
            entries[0].id
        )
    }

    func testTooShortOrMissingSnippetNoTarget() {
        let entries = [stub(1, role: "assistant", content: "abc 内容")]
        XCTAssertNil(
            SearchTargetResolution.targetEntryID(
                entries: entries, snippet: "ab", role: nil
            )
        )
        XCTAssertNil(
            SearchTargetResolution.targetEntryID(
                entries: entries, snippet: "不存在的文本段落", role: nil
            )
        )
        XCTAssertNil(
            SearchTargetResolution.targetEntryID(
                entries: entries, snippet: nil, role: nil
            )
        )
    }

    // MARK: - 收敛判定

    func testConvergesWhenPositionSettles() {
        var machine = SearchFocusConvergence()
        machine.begin()
        // 首拍只记账（已有一次滚动）
        XCTAssertEqual(machine.evaluate(shownPosition: 300), .scrollAgain)
        // 漂移收窄到容差内：收敛
        XCTAssertEqual(machine.evaluate(shownPosition: 299.5), .converged)
        XCTAssertFalse(machine.isActive)
    }

    func testExhaustsAfterSixScrolls() {
        var machine = SearchFocusConvergence()
        machine.begin()
        var verdicts: [SearchFocusConvergence.Evaluation] = []
        var position = 500.0
        while machine.isActive {
            verdicts.append(machine.evaluate(shownPosition: position))
            position -= 40  // 每拍大漂移、永不收敛
        }
        // 滚动总次数（begin 的首次＋scrollAgain 数）≤6
        let scrolls = 1 + verdicts.filter { $0 == .scrollAgain }.count
        XCTAssertLessThanOrEqual(scrolls, 6)
        XCTAssertEqual(verdicts.last, .exhausted)
    }

    func testAbortStopsMachine() {
        var machine = SearchFocusConvergence()
        machine.begin()
        machine.abort()
        XCTAssertFalse(machine.isActive)
        XCTAssertEqual(machine.evaluate(shownPosition: 10), .exhausted)
    }

    func testConstantsMatchLedger() {
        XCTAssertEqual(SearchFocusConvergence.maxAttempts, 6)
        XCTAssertEqual(SearchFocusConvergence.tolerance, 1)
        XCTAssertEqual(SearchFocusConvergence.topGap, 12)
    }
}
