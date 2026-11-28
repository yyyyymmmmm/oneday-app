import XCTest
@testable import OneDayApp
@testable import OneDayCore

/// 登记交付元数据拉取失败重试（件4，自动重试并入对方失败卡）：
/// 失败落独立计数表＋.task 触发键含计数驱动重试，上限 5 次
@MainActor
final class DeliveryStoreRetryTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
    }

    override func tearDown() async throws {
        try await super.tearDown()
    }

    /// 首拉网络失败→次拉成功：失败计数推进触发 .task 重跑
    func testNetworkFailureThenSuccessRetries() async {
        let store = DeliveryStore()
        let client = MockFailingBridgeClient()
        let appState = AppState(client: DemoHermesClient(), demoMode: .connected)

        let testID = "test-delivery-123"
        let expectedMeta = BridgeDelivery(
            id: testID,
            status: .ok,
            name: "test.pdf",
            path: "/files/test.pdf",
            size: 1024,
            mime: "application/pdf",
            kind: "file",
            width: nil,
            height: nil,
            sha256: nil,
            registeredAt: "2026-11-26T00:00:00Z",
            cover: BridgeDelivery.Cover(thumb: false, cover: false)
        )

        client.failureCount = 1
        client.deliveryToReturn = expectedMeta

        // 首拉失败→落 .failed(文案)＋计数=1
        await store.loadMeta(id: testID, client: client, appState: appState)

        if case .failed(let message) = store.metaResult(for: testID) {
            XCTAssertFalse(message.isEmpty, "Failure message should not be empty")
            XCTAssertEqual(store.metaFailureCount(for: testID), 1, "First failure should record count=1")
        } else {
            XCTFail("Expected .failed result after first attempt, got \(String(describing: store.metaResult(for: testID)))")
        }

        // 次拉成功→落 .loaded＋计数清零
        await store.loadMeta(id: testID, client: client, appState: appState)

        if case .loaded(let meta) = store.metaResult(for: testID) {
            XCTAssertEqual(meta.id, testID)
            XCTAssertEqual(meta.name, "test.pdf")
            XCTAssertEqual(store.metaFailureCount(for: testID), 0, "Success should clear count")
        } else {
            XCTFail("Expected .loaded result after second attempt")
        }
    }

    /// 404 查无此号→落 .notFound，不再重试
    func testNotFoundDoesNotRetry() async {
        let store = DeliveryStore()
        let client = MockFailingBridgeClient()
        let appState = AppState(client: DemoHermesClient(), demoMode: .connected)

        let testID = "missing-delivery-404"
        client.shouldReturnNotFound = true

        await store.loadMeta(id: testID, client: client, appState: appState)
        XCTAssertEqual(store.metaResult(for: testID), .notFound)
        XCTAssertEqual(store.metaFailureCount(for: testID), 0, ".notFound should clear count")

        let callCountAfterFirst = client.callCount

        // 第二次调用不应重试已落定的 .notFound
        await store.loadMeta(id: testID, client: client, appState: appState)
        XCTAssertEqual(client.callCount, callCountAfterFirst, "Should not retry .notFound")
    }

    /// 持续失败→重试上限 5 次后停止
    func testRetryBoundedAtFiveAttempts() async {
        let store = DeliveryStore()
        let client = MockFailingBridgeClient()
        let appState = AppState(client: DemoHermesClient(), demoMode: .connected)

        let testID = "perpetual-failure"
        client.failureCount = 100

        // 前 5 次：每次都会调用 client
        for attempt in 1...5 {
            await store.loadMeta(id: testID, client: client, appState: appState)

            if case .failed = store.metaResult(for: testID) {
                XCTAssertEqual(store.metaFailureCount(for: testID), attempt, "Attempt \(attempt) should record count=\(attempt)")
            } else {
                XCTFail("Attempt \(attempt) should be .failed, got \(String(describing: store.metaResult(for: testID)))")
            }
        }

        XCTAssertEqual(client.callCount, 5, "Should attempt exactly 5 times")

        // 第 6 次及以后：guard 拦住，不再调用 client
        for _ in 6...8 {
            await store.loadMeta(id: testID, client: client, appState: appState)
        }

        XCTAssertEqual(client.callCount, 5, "Should stop after 5 attempts")
        XCTAssertEqual(store.metaFailureCount(for: testID), 5, "Final count should remain 5")

        if case .failed = store.metaResult(for: testID) {
            // OK, still failed
        } else {
            XCTFail("Should remain in .failed state")
        }
    }

    /// 成功后失败计数清零：同一 store 不同 id 独立计数
    func testSuccessClearsFailureCount() async {
        let store = DeliveryStore()
        let client = MockFailingBridgeClient()
        let appState = AppState(client: DemoHermesClient(), demoMode: .connected)

        let idA = "delivery-a"
        let idB = "delivery-b"

        let metaA = BridgeDelivery(
            id: idA, status: .ok, name: "a.pdf", path: "/a.pdf",
            size: 100, mime: "application/pdf", kind: "file",
            width: nil, height: nil, sha256: nil, registeredAt: nil,
            cover: BridgeDelivery.Cover(thumb: false, cover: false)
        )

        // idA: 失败 2 次后成功
        client.failureCount = 2
        client.deliveryToReturn = metaA

        await store.loadMeta(id: idA, client: client, appState: appState)
        XCTAssertTrue(store.metaResult(for: idA) == .failed("网络请求失败"))
        XCTAssertEqual(store.metaFailureCount(for: idA), 1)

        await store.loadMeta(id: idA, client: client, appState: appState)
        XCTAssertTrue(store.metaResult(for: idA) == .failed("网络请求失败"))
        XCTAssertEqual(store.metaFailureCount(for: idA), 2)

        await store.loadMeta(id: idA, client: client, appState: appState)
        if case .loaded = store.metaResult(for: idA) {
            XCTAssertEqual(store.metaFailureCount(for: idA), 0, "Success should clear count")
        } else {
            XCTFail("idA should be .loaded after third attempt")
        }

        // idB: 独立计数
        client.failureCount = 100
        await store.loadMeta(id: idB, client: client, appState: appState)
        XCTAssertEqual(store.metaFailureCount(for: idB), 1)
        XCTAssertEqual(store.metaFailureCount(for: idA), 0, "idA count should remain 0")
    }

    /// .task 触发键：计数变化引发键变化
    func testMetaTaskIDChangesWithFailureCount() {
        let id = "test-123"

        XCTAssertEqual(
            AssistantDeliveryItem.metaTaskID(for: id, failureCount: 0),
            id,
            "count=0 should return plain id"
        )

        XCTAssertEqual(
            AssistantDeliveryItem.metaTaskID(for: id, failureCount: 1),
            "test-123-1",
            "count=1 should append suffix"
        )

        XCTAssertEqual(
            AssistantDeliveryItem.metaTaskID(for: id, failureCount: 5),
            "test-123-5",
            "count=5 should append suffix"
        )
    }

    /// ingest 预灌成功→清零计数
    func testIngestClearsFailureCount() async {
        let store = DeliveryStore()
        let client = MockFailingBridgeClient()
        let appState = AppState(client: DemoHermesClient(), demoMode: .connected)

        let testID = "test-456"
        client.failureCount = 100

        // 先失败一次
        await store.loadMeta(id: testID, client: client, appState: appState)
        XCTAssertEqual(store.metaFailureCount(for: testID), 1)

        // ingest 预灌同一 id
        let delivery = BridgeDelivery(
            id: testID, status: .ok, name: "ingested.pdf", path: "/ingested.pdf",
            size: 2048, mime: "application/pdf", kind: "file",
            width: nil, height: nil, sha256: nil, registeredAt: nil,
            cover: BridgeDelivery.Cover(thumb: false, cover: false)
        )
        store.ingest([delivery])

        XCTAssertEqual(store.metaResult(for: testID), .loaded(delivery))
        XCTAssertEqual(store.metaFailureCount(for: testID), 0, "ingest should clear count")
    }

    /// retryMeta 手点重试→清零计数，给新预算
    func testRetryMetaClearsFailureCount() async {
        let store = DeliveryStore()
        let client = MockFailingBridgeClient()
        let appState = AppState(client: DemoHermesClient(), demoMode: .connected)

        let testID = "test-789"
        client.failureCount = 100

        // 失败 3 次
        for _ in 1...3 {
            await store.loadMeta(id: testID, client: client, appState: appState)
        }
        XCTAssertEqual(store.metaFailureCount(for: testID), 3)

        // 手点重试
        await store.retryMeta(id: testID, client: client, appState: appState)

        // 重试后又失败，但计数从 1 重新开始
        XCTAssertEqual(store.metaFailureCount(for: testID), 1, "retryMeta should reset count before retry")
    }
}

// MARK: - Mock Client

/// 假桥客户端：可配置失败次数与返回值，用于重试测试
@MainActor
final class MockFailingBridgeClient: OneDayBridgeClientProtocol {
    var callCount = 0
    var failureCount = 0
    var shouldReturnNotFound = false
    var deliveryToReturn: BridgeDelivery?

    func delivery(config: ServerConfig, id: String) async throws -> BridgeDelivery {
        callCount += 1

        if shouldReturnNotFound {
            throw OneDayBridgeError.recordGone
        }

        if callCount <= failureCount {
            throw NSError(domain: "test", code: -1, userInfo: nil)
        }

        guard let meta = deliveryToReturn else {
            throw NSError(domain: "test", code: -2, userInfo: nil)
        }

        return meta
    }

    // MARK: - 桩方法（协议要求，不实现）

    func feedPosts(config: ServerConfig) async throws -> [BridgeFeedPost] {
        fatalError("Stub not implemented")
    }

    func feedGeneration(config: ServerConfig) async throws -> BridgeFeedGeneration {
        fatalError("Stub not implemented")
    }

    func feedBrief(config: ServerConfig) async throws -> BridgeBriefDoc {
        fatalError("Stub not implemented")
    }

    func generateFeed(config: ServerConfig) async throws {
        fatalError("Stub not implemented")
    }
    func generateIdeas(config: ServerConfig) async throws {
        fatalError("Stub not implemented")
    }

    func saveFeedText(config: ServerConfig, text: String) async throws -> BridgeBriefDoc {
        fatalError("Stub not implemented")
    }

    func markFeedPostRead(config: ServerConfig, id: String) async throws -> BridgeFeedPost {
        fatalError("Stub not implemented")
    }

    func setFeedPostLiked(config: ServerConfig, id: String, liked: Bool) async throws -> BridgeFeedPost {
        fatalError("Stub not implemented")
    }

    func ideas(config: ServerConfig) async throws -> [BridgeIdea] {
        fatalError("Stub not implemented")
    }

    func createIdea(config: ServerConfig, request body: BridgeIdeaCreateRequest) async throws -> BridgeIdea {
        fatalError("Stub not implemented")
    }

    func deleteIdea(config: ServerConfig, id: String) async throws {
        fatalError("Stub not implemented")
    }

    func patchIdea(config: ServerConfig, id: String, request body: BridgeIdeaPatchRequest) async throws -> BridgeIdea {
        fatalError("Stub not implemented")
    }

    func generationInfo(config: ServerConfig) async throws -> BridgeGenerationInfo {
        fatalError("Stub not implemented")
    }

    func goals(config: ServerConfig) async throws -> [BridgeGoal] {
        fatalError("Stub not implemented")
    }

    func createGoal(config: ServerConfig, request body: BridgeGoalCreateRequest) async throws -> BridgeGoal {
        fatalError("Stub not implemented")
    }

    func patchGoal(config: ServerConfig, id: String, request body: BridgeGoalPatchRequest) async throws -> BridgeGoal {
        fatalError("Stub not implemented")
    }

    func deleteGoal(config: ServerConfig, id: String) async throws {
        fatalError("Stub not implemented")
    }

    func patchGoalStatus(config: ServerConfig, id: String, status: GoalStatus) async throws -> BridgeGoal {
        fatalError("Stub not implemented")
    }

    func goalEntries(config: ServerConfig, goalID: String) async throws -> [BridgeGoalEntry] {
        fatalError("Stub not implemented")
    }

    func createGoalEntry(config: ServerConfig, goalID: String, request body: BridgeGoalEntryCreateRequest) async throws -> BridgeGoalEntry {
        fatalError("Stub not implemented")
    }

    func deleteGoalEntry(config: ServerConfig, goalID: String, entryID: String) async throws {
        fatalError("Stub not implemented")
    }

    func goalBriefings(config: ServerConfig, goalID: String) async throws -> [BridgeBriefing] {
        fatalError("Stub not implemented")
    }

    func markBriefingOpened(config: ServerConfig, goalID: String, briefingID: String) async throws -> BridgeBriefing {
        fatalError("Stub not implemented")
    }

    func goalTasks(config: ServerConfig, goalID: String) async throws -> [BridgeGoalTask] {
        fatalError("Stub not implemented")
    }

    func ungroupedTasks(config: ServerConfig) async throws -> BridgeUngroupedTasksResponse {
        fatalError("Stub not implemented")
    }

    func patchGoalCategory(config: ServerConfig, id: String, category: GoalCategory?) async throws -> BridgeGoal {
        fatalError("Stub not implemented")
    }

    func delegateGoalTask(config: ServerConfig, goalID: String, request body: BridgeGoalDelegateRequest) async throws -> BridgeGoalDelegateResponse {
        fatalError("Stub not implemented")
    }

    func setTaskGoal(config: ServerConfig, taskID: String, request body: BridgeTaskGoalWrite) async throws -> BridgeTaskGoalAssignment {
        fatalError("Stub not implemented")
    }
}
