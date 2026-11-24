import OneDayCore
import XCTest
@testable import OneDayApp

/// 缓存 C1 新鲜度门钉测（§367.6）：门纯值判定＋三
/// 店假客户端请求计数——首拉 1 轮、TTL 内二次读触
/// 发＝0 请求、过期＝1 轮、写后回读不经门仍全量
@MainActor
final class CacheFreshnessGateC1Tests: XCTestCase {

    private func makeAppState() -> AppState {
        AppState(client: DemoHermesClient(), demoMode: .connected)
    }

    // MARK: - 门纯值判定

    func testGateNeverLoadedIsNotFresh() {
        let gate = FreshnessGate(ttl: 60)
        XCTAssertFalse(
            gate.isFresh(configKey: "https://a", now: Date())
        )
    }

    func testGateFreshWithinTTLAndStaleAtBoundary() {
        var gate = FreshnessGate(ttl: 60)
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        gate.stamp(configKey: "https://a", now: t0)
        XCTAssertTrue(gate.isFresh(
            configKey: "https://a", now: t0.addingTimeInterval(59)
        ))
        XCTAssertFalse(gate.isFresh(
            configKey: "https://a", now: t0.addingTimeInterval(60)
        ))
    }

    func testGateConfigKeyChangeOrNilIsNotFresh() {
        var gate = FreshnessGate(ttl: 60)
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        gate.stamp(configKey: "https://a", now: t0)
        XCTAssertFalse(gate.isFresh(
            configKey: "https://b", now: t0.addingTimeInterval(5)
        ))
        XCTAssertFalse(gate.isFresh(
            configKey: nil, now: t0.addingTimeInterval(5)
        ))
    }

    // MARK: - 动态店计数

    func testFeedGateCountsRequests() async {
        let script = BridgeScript()
        let store = FeedStore(
            client: ScriptedBridgeClient(script: script)
        )
        let appState = makeAppState()
        let t0 = Date()

        await store.loadIfNeeded(appState: appState, now: t0)
        XCTAssertEqual(script.feedPostsCount, 1)
        XCTAssertEqual(store.loadState, .ready)

        // TTL 内二次读触发：零请求
        await store.loadIfNeeded(
            appState: appState, now: t0.addingTimeInterval(30)
        )
        XCTAssertEqual(script.feedPostsCount, 1)

        // 过期：再付一轮
        await store.loadIfNeeded(
            appState: appState, now: t0.addingTimeInterval(61)
        )
        XCTAssertEqual(script.feedPostsCount, 2)
    }

    // MARK: - 点子店计数＋写后回读不经门

    func testIdeasGateCountsAndWriteRefetchBypassesGate() async {
        let script = BridgeScript()
        let store = IdeasStore(
            client: ScriptedBridgeClient(script: script)
        )
        let appState = makeAppState()
        let t0 = Date()

        await store.loadIfNeeded(appState: appState, now: t0)
        XCTAssertEqual(script.ideasCount, 1)
        XCTAssertEqual(script.goalsCount, 1)

        await store.loadIfNeeded(
            appState: appState, now: t0.addingTimeInterval(30)
        )
        XCTAssertEqual(script.ideasCount, 1)
        XCTAssertEqual(script.goalsCount, 1)

        // 写路径不经门：门内仍走 create→整表回读确认
        let created = await store.create(
            appState: appState, title: "新点子", detail: "",
            goalId: nil, category: nil
        )
        XCTAssertTrue(created)
        XCTAssertEqual(script.createIdeaCount, 1)
        XCTAssertEqual(script.ideasCount, 2)
        XCTAssertEqual(script.goalsCount, 2)

        // 回读已落账新鲜度：过期点再触发才再付一轮
        await store.loadIfNeeded(
            appState: appState, now: t0.addingTimeInterval(61)
        )
        XCTAssertEqual(script.ideasCount, 3)
    }

    // MARK: - 目标店计数＋写后回读不经门

    func testGoalsGateCountsAndWriteRefetchBypassesGate() async {
        let script = BridgeScript()
        let store = GoalsStore(
            client: ScriptedBridgeClient(script: script)
        )
        let appState = makeAppState()
        let t0 = Date()

        await store.loadIfNeeded(appState: appState, now: t0)
        XCTAssertEqual(script.goalsCount, 1)
        XCTAssertEqual(store.loadState, .ready)

        await store.loadIfNeeded(
            appState: appState, now: t0.addingTimeInterval(30)
        )
        XCTAssertEqual(script.goalsCount, 1)

        let created = await store.create(
            appState: appState, title: "新目标", note: "",
            parentId: nil, category: nil
        )
        XCTAssertTrue(created)
        XCTAssertEqual(script.createGoalCount, 1)
        XCTAssertEqual(script.goalsCount, 2)

        await store.loadIfNeeded(
            appState: appState, now: t0.addingTimeInterval(61)
        )
        XCTAssertEqual(script.goalsCount, 3)
    }
}
