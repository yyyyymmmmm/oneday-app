import OneDayCore
import XCTest
@testable import OneDayApp

/// §216 点子/文件「重发同型后门」收口的 App 层钉
/// 测：点子存量预填清扫（SideChatStore）——判定逻
/// 辑在 Core 纯函数层（SourceQuoteTests 已钉），
/// 本组钉存储层的落点与亲笔零误伤，与动态清扫
/// （FeedDiscussQuoteAppTests）同式。文件重发无
/// 关联账、无清扫面，本组不设文件清扫用例（报
/// 告明示），只钉「文件引用不经草稿口」由全仓
/// grep 对账承担（见报告）
@MainActor
final class SourceQuoteAppTests: XCTestCase {

    private func idea(
        id: String = "i_1", title: String = "囤课清单"
    ) -> BridgeIdea {
        BridgeIdea(
            id: id, title: title,
            detail: "把想报的课列一张表。",
            goalId: nil, createdAt: 100,
            source: .generated,
            evidence: "对话里提过预算"
        )
    }

    func testIdeaPurgeClearsVerbatimMachineDraft() {
        let store = SideChatStore(persisted: false)
        let thread = UUID()
        let target = idea()
        store.linkThread(thread, forIdeaID: "i_1")
        store.setDraft(
            IdeaChatPrefill.make(idea: target), for: thread
        )
        let cleared = store.purgeLegacyIdeaDrafts(
            ideas: [target]
        )
        XCTAssertEqual(cleared, 1)
        XCTAssertNil(store.draft(for: thread))
        // 幂等：复跑恒 0、点子关联本体保留不动
        XCTAssertEqual(
            store.purgeLegacyIdeaDrafts(ideas: [target]), 0
        )
        XCTAssertEqual(
            store.threadID(forIdeaID: "i_1"), thread
        )
    }

    func testIdeaPurgeKeepsEditedDraft() {
        // 用户改过一字＝亲笔，清扫不许动
        let store = SideChatStore(persisted: false)
        let thread = UUID()
        let target = idea()
        store.linkThread(thread, forIdeaID: "i_1")
        let edited = IdeaChatPrefill.make(idea: target)
            .replacingOccurrences(of: "一张表", with: "两张表")
        store.setDraft(edited, for: thread)
        XCTAssertEqual(
            store.purgeLegacyIdeaDrafts(ideas: [target]), 0
        )
        XCTAssertEqual(store.draft(for: thread), edited)
    }

    func testIdeaPurgeKeepsHandwrittenDrafts() {
        // 亲笔保活零误伤：点子线程里的亲笔、无关联
        // 线程的亲笔，都不是机器预填、都不许清
        let store = SideChatStore(persisted: false)
        let ideaThread = UUID()
        let plainThread = UUID()
        let target = idea()
        store.linkThread(ideaThread, forIdeaID: "i_1")
        store.setDraft("我自己写了一半的话", for: ideaThread)
        store.setDraft("另一条线的亲笔草稿", for: plainThread)
        XCTAssertEqual(
            store.purgeLegacyIdeaDrafts(ideas: [target]), 0
        )
        XCTAssertEqual(
            store.draft(for: ideaThread), "我自己写了一半的话"
        )
        XCTAssertEqual(
            store.draft(for: plainThread), "另一条线的亲笔草稿"
        )
    }

    func testIdeaPurgeSkipsDraftWhenIdeaUnavailable() {
        // 原点子已不在名单（删除/过期）：无从逐字核
        // 验，不清
        let store = SideChatStore(persisted: false)
        let thread = UUID()
        store.linkThread(thread, forIdeaID: "i_gone")
        let machine = IdeaChatPrefill.make(idea: idea())
        store.setDraft(machine, for: thread)
        XCTAssertEqual(
            store.purgeLegacyIdeaDrafts(ideas: [
                idea(id: "i_other", title: "别的点子"),
            ]),
            0
        )
        XCTAssertEqual(store.draft(for: thread), machine)
    }

    func testIdeaPurgeEmptyListIsNoOp() {
        let store = SideChatStore(persisted: false)
        let thread = UUID()
        store.linkThread(thread, forIdeaID: "i_1")
        store.setDraft(
            IdeaChatPrefill.make(idea: idea()), for: thread
        )
        XCTAssertEqual(store.purgeLegacyIdeaDrafts(ideas: []), 0)
        XCTAssertNotNil(store.draft(for: thread))
    }
}
