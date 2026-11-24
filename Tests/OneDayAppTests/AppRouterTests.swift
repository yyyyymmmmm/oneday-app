import XCTest
@testable import OneDayApp
@testable import OneDayCore

/// AppRouter 收口对拍（§305，横扫 A-03 router-unify）：
/// 信箱群自 AppState 迁入唯一 router 后，逐项钉住迁
/// 移前行为——①通知落点拆包（requestHubDestination）
/// 七个 case 的字段落点与返回值与旧 AppState 实现逐
/// 项一致；②各跨页意图是独立槽、同置不互扰（防日后
/// 误并成单槽引入覆盖竞态）；③线程待发引用两表独立、
/// 按线程寻址、后入覆盖。
@MainActor
final class AppRouterTests: XCTestCase {

    // MARK: - ① 通知落点拆包

    func testHubDestinationApprovalDecision() {
        let router = AppRouter()
        let ok = router.requestHubDestination(.approvalDecision(id: "d1"))
        XCTAssertTrue(ok)
        XCTAssertEqual(router.hubApprovalFocusID, "d1")
        XCTAssertEqual(router.hubDestinationRequest, .approvalDecision(id: "d1"))
        XCTAssertNil(router.monitorDeepLink)
        XCTAssertNil(router.approvalAnchorRequest)
    }

    func testHubDestinationApprovalHome() {
        let router = AppRouter()
        let ok = router.requestHubDestination(.approvalHome)
        XCTAssertTrue(ok)
        XCTAssertEqual(router.hubDestinationRequest, .approvalHome)
        XCTAssertNil(router.hubApprovalFocusID)
        XCTAssertNil(router.monitorDeepLink)
        XCTAssertNil(router.approvalAnchorRequest)
    }

    func testHubDestinationMonitorChange() {
        let router = AppRouter()
        let ok = router.requestHubDestination(
            .monitorChange(monitorID: "m1", changeID: "c1")
        )
        XCTAssertTrue(ok)
        XCTAssertEqual(router.monitorDeepLink?.monitorID, "m1")
        XCTAssertEqual(router.monitorDeepLink?.changeID, "c1")
        XCTAssertEqual(
            router.hubDestinationRequest,
            .monitorChange(monitorID: "m1", changeID: "c1")
        )
    }

    func testHubDestinationMonitorChangeWithoutChangeID() {
        let router = AppRouter()
        let ok = router.requestHubDestination(
            .monitorChange(monitorID: "m2", changeID: nil)
        )
        XCTAssertTrue(ok)
        XCTAssertEqual(router.monitorDeepLink?.monitorID, "m2")
        XCTAssertNil(router.monitorDeepLink?.changeID ?? nil)
    }

    func testHubDestinationMonitorsHome() {
        let router = AppRouter()
        let ok = router.requestHubDestination(.monitorsHome)
        XCTAssertTrue(ok)
        XCTAssertEqual(router.hubDestinationRequest, .monitorsHome)
        XCTAssertNil(router.monitorDeepLink)
    }

    func testHubDestinationApprovalAnchorBypassesHub() {
        let router = AppRouter()
        let threadID = UUID()
        let ok = router.requestHubDestination(
            .approvalAnchor(threadID: threadID, approvalKey: "k1")
        )
        XCTAssertTrue(ok)
        XCTAssertEqual(router.approvalAnchorRequest?.threadID, threadID)
        XCTAssertEqual(router.approvalAnchorRequest?.approvalKey, "k1")
        // §165：锚点落点不进 hubDestinationRequest、不走枢纽接力
        XCTAssertNil(router.hubDestinationRequest)
    }

    func testHubDestinationApprovalThreadBypassesHub() {
        let router = AppRouter()
        let threadID = UUID()
        let ok = router.requestHubDestination(.approvalThread(threadID: threadID))
        XCTAssertTrue(ok)
        XCTAssertEqual(router.approvalAnchorRequest?.threadID, threadID)
        XCTAssertNil(router.approvalAnchorRequest?.approvalKey ?? nil)
        XCTAssertNil(router.hubDestinationRequest)
    }

    func testHubDestinationNone() {
        let router = AppRouter()
        let ok = router.requestHubDestination(.none)
        XCTAssertFalse(ok)
        XCTAssertNil(router.hubDestinationRequest)
        XCTAssertNil(router.hubApprovalFocusID)
        XCTAssertNil(router.monitorDeepLink)
        XCTAssertNil(router.approvalAnchorRequest)
    }

    // MARK: - ② 意图独立槽

    func testIntentsAreIndependentSlots() {
        let router = AppRouter()
        let threadID = UUID()
        router.pendingChatSessionID = "s1"
        router.pendingChatChannelID = "hermes"
        router.feedOpenPostRequest = "p1"
        router.ideaOpenRequest = "i1"
        router.drawerThreadSelection = threadID
        router.mainTabSwitchRequest = .feed
        router.settingsSheetRequested = true
        router.cronCreateRequested = true
        // 同置后逐项仍在位——任一意图不许覆盖另一意图
        XCTAssertEqual(router.pendingChatSessionID, "s1")
        XCTAssertEqual(router.pendingChatChannelID, "hermes")
        XCTAssertEqual(router.feedOpenPostRequest, "p1")
        XCTAssertEqual(router.ideaOpenRequest, "i1")
        XCTAssertEqual(router.drawerThreadSelection, threadID)
        XCTAssertEqual(router.mainTabSwitchRequest, .feed)
        XCTAssertTrue(router.settingsSheetRequested)
        XCTAssertTrue(router.cronCreateRequested)
        // 消费一项不清其他项
        router.pendingChatSessionID = nil
        router.pendingChatChannelID = nil
        XCTAssertEqual(router.feedOpenPostRequest, "p1")
        XCTAssertEqual(router.drawerThreadSelection, threadID)
    }

    func testAppStateExposesSingleRouterAndQuotes() {
        let appState = AppState(client: DemoHermesClient(), demoMode: .connected)
        appState.router.pendingChatSessionID = "s9"
        XCTAssertEqual(appState.router.pendingChatSessionID, "s9")
        XCTAssertNil(appState.router.hubDestinationRequest)
    }

    // MARK: - ③ 线程待发引用

    func testPendingQuotesTablesAreIndependentAndOverwritePerThread() {
        let quotes = PendingThreadQuotes()
        let threadA = UUID()
        let threadB = UUID()
        let feedQuote = FeedPostQuote(
            postID: "p1", title: "t", body: "b", sourceLine: ""
        )
        let ideaQuote = SourceQuote.idea(
            IdeaQuote(ideaID: "i1", title: "t", body: "b")
        )
        quotes.feedQuotesByThread[threadA] = feedQuote
        quotes.sourceQuotesByThread[threadB] = ideaQuote
        XCTAssertEqual(quotes.feedQuotesByThread[threadA], feedQuote)
        XCTAssertEqual(quotes.sourceQuotesByThread[threadB], ideaQuote)
        XCTAssertNil(quotes.feedQuotesByThread[threadB])
        XCTAssertNil(quotes.sourceQuotesByThread[threadA])
        // 同线程后入覆盖（槽位单一在场）
        let feedQuote2 = FeedPostQuote(
            postID: "p2", title: "t2", body: "b2", sourceLine: ""
        )
        quotes.feedQuotesByThread[threadA] = feedQuote2
        XCTAssertEqual(quotes.feedQuotesByThread[threadA], feedQuote2)
        XCTAssertEqual(quotes.feedQuotesByThread.count, 1)
    }
}
