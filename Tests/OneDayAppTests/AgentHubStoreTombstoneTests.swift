import XCTest
@testable import OneDayApp
@testable import OneDayCore

/// 墓碑竞态保护测试（2026-11-26 闪退修复 bcc03891）
///
/// 验证要点：
/// 1. 裁决成功后落墓碑，防轮询带回已决记录
/// 2. 记录连续两次快照不含→解除墓碑
/// 3. 墓碑超时 60 秒→解除（无论记录是否再现）
/// 注：渲染层过滤已决记录由 ChatApprovalRenderingTests 覆盖
@MainActor
final class AgentHubStoreTombstoneTests: XCTestCase {

    private func makeTestRecord(id: String) -> WriteGateRecord {
        WriteGateRecord(
            id: id,
            subsystem: .skills,
            action: "edit",
            summary: "测试记录 \(id)",
            origin: "test_origin",
            createdAt: Date(),
            anchor: nil
        )
    }

    // MARK: - 裁决成功落墓碑 + 轮询带回被过滤

    func testDecideSuccessCreatesTombstoneAndRefreshFiltersRecord() async {
        let appState = AppState(client: DemoHermesClient(), demoMode: .connected)
        let mockClient = MockWriteGateClient()
        let store = AgentHubStore(appState: appState, gateClient: mockClient)

        let record = makeTestRecord(id: "test-1")

        // 模拟裁决成功
        mockClient.approveResponse = WriteGateDecisionResponse(
            success: true,
            output: nil,
            decision: "approved"
        )
        mockClient.gateStatusResponse = WriteGateStatus(
            supported: true,
            memoryGateEnabled: false,
            skillsGateEnabled: true,
            memoryCount: 0,
            skillsCount: 1
        )
        mockClient.pendingListResponse = WriteGatePendingList(
            records: [record],
            supported: true
        )
        await store.loadApproval(force: true)
        await store.decide(record, approve: true)

        // 验证裁决后记录被 removeRecord 移除
        if case .ready(let records) = store.approvalState {
            XCTAssertFalse(records.contains(where: { $0.id == "test-1" }),
                          "裁决成功后记录应从待批列表移除（decide 自带的 removeRecord）")
        } else {
            XCTFail("approvalState 应为 ready")
        }

        // 模拟轮询带回同一记录（桥侧数据未一致）
        mockClient.gateStatusResponse = WriteGateStatus(
            supported: true,
            memoryGateEnabled: false,
            skillsGateEnabled: true,
            memoryCount: 0,
            skillsCount: 1
        )
        mockClient.pendingListResponse = WriteGatePendingList(
            records: [record],
            supported: true
        )

        await store.refreshApprovalForChat()

        // 验证记录被墓碑过滤，不在 approvalState 中
        // 删掉墓碑过滤逻辑（applyTombstoneFilter）会变红
        if case .ready(let records) = store.approvalState {
            XCTAssertFalse(records.contains(where: { $0.id == "test-1" }),
                          "墓碑保护窗口内的记录应被过滤")
        } else {
            XCTFail("approvalState 应为 ready")
        }
    }

    // MARK: - 连续两次不含解除墓碑

    func testTombstoneReleasedAfterTwoMisses() async {
        let appState = AppState(client: DemoHermesClient(), demoMode: .connected)
        let mockClient = MockWriteGateClient()
        let store = AgentHubStore(appState: appState, gateClient: mockClient)

        let record = makeTestRecord(id: "test-3")

        // 1. 裁决成功（创建墓碑）
        mockClient.approveResponse = WriteGateDecisionResponse(
            success: true,
            output: nil,
            decision: "approved"
        )
        mockClient.gateStatusResponse = WriteGateStatus(
            supported: true,
            memoryGateEnabled: false,
            skillsGateEnabled: true,
            memoryCount: 0,
            skillsCount: 1
        )
        mockClient.pendingListResponse = WriteGatePendingList(
            records: [record],
            supported: true
        )
        await store.loadApproval(force: true)
        await store.decide(record, approve: true)

        // 2. 第一次轮询：记录不在列表中（未见计数 +1）
        mockClient.gateStatusResponse = WriteGateStatus(
            supported: true,
            memoryGateEnabled: false,
            skillsGateEnabled: true,
            memoryCount: 0,
            skillsCount: 0
        )
        mockClient.pendingListResponse = WriteGatePendingList(
            records: [],
            supported: true
        )

        await store.refreshApprovalForChat()

        // 3. 第二次轮询：记录仍不在列表中（未见计数 +1 → 2，解除墓碑）
        await store.refreshApprovalForChat()

        // 4. 第三次轮询：记录再次出现，应该通过过滤（墓碑已解除）
        // 删掉墓碑解除逻辑（applyTombstoneFilter 中 newMissCount >= 2 的 removeValue）会变红
        mockClient.pendingListResponse = WriteGatePendingList(
            records: [record],
            supported: true
        )
        await store.refreshApprovalForChat()

        if case .ready(let records) = store.approvalState {
            XCTAssertTrue(records.contains(where: { $0.id == "test-3" }),
                         "连续两次不含后墓碑应解除，记录应通过过滤")
        } else {
            XCTFail("approvalState 应为 ready")
        }
    }

    // MARK: - 60 秒超时解除墓碑（记录再现分支）

    func testTombstoneReleasedAfter60SecondsEvenIfRecordReappears() async {
        let appState = AppState(client: DemoHermesClient(), demoMode: .connected)
        let mockClient = MockWriteGateClient()
        let store = AgentHubStore(appState: appState, gateClient: mockClient)

        let record = makeTestRecord(id: "test-4")

        // 注入可控时钟
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        var currentTime = t0
        store.nowProvider = { currentTime }

        // 1. 裁决成功（创建墓碑，时刻 = t0）
        mockClient.approveResponse = WriteGateDecisionResponse(
            success: true,
            output: nil,
            decision: "approved"
        )
        mockClient.gateStatusResponse = WriteGateStatus(
            supported: true,
            memoryGateEnabled: false,
            skillsGateEnabled: true,
            memoryCount: 0,
            skillsCount: 1
        )
        mockClient.pendingListResponse = WriteGatePendingList(
            records: [record],
            supported: true
        )
        await store.loadApproval(force: true)
        await store.decide(record, approve: true)

        // 2. 推进时间到 65 秒后
        currentTime = t0.addingTimeInterval(65)

        // 3. 模拟轮询带回记录（桥侧异常一直返回已决记录）
        mockClient.gateStatusResponse = WriteGateStatus(
            supported: true,
            memoryGateEnabled: false,
            skillsGateEnabled: true,
            memoryCount: 0,
            skillsCount: 1
        )
        mockClient.pendingListResponse = WriteGatePendingList(
            records: [record],
            supported: true
        )

        await store.refreshApprovalForChat()

        // 4. 验证墓碑已超时解除，记录通过过滤
        // 删掉超时解除逻辑（applyTombstoneFilter 中 elapsed > 60.0 的 removeValue 和 return true）会变红
        if case .ready(let records) = store.approvalState {
            XCTAssertTrue(records.contains(where: { $0.id == "test-4" }),
                         "60 秒超时后墓碑应解除，即使记录再现也应通过过滤")
        } else {
            XCTFail("approvalState 应为 ready")
        }
    }

    // MARK: - 60 秒超时解除（记录未见分支）

    func testTombstoneReleasedAfter60SecondsWhenMissing() async {
        let appState = AppState(client: DemoHermesClient(), demoMode: .connected)
        let mockClient = MockWriteGateClient()
        let store = AgentHubStore(appState: appState, gateClient: mockClient)

        let record = makeTestRecord(id: "test-5")

        // 注入可控时钟
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        var currentTime = t0
        store.nowProvider = { currentTime }

        // 1. 裁决成功（创建墓碑，时刻 = t0）
        mockClient.approveResponse = WriteGateDecisionResponse(
            success: true,
            output: nil,
            decision: "approved"
        )
        mockClient.gateStatusResponse = WriteGateStatus(
            supported: true,
            memoryGateEnabled: false,
            skillsGateEnabled: true,
            memoryCount: 0,
            skillsCount: 1
        )
        mockClient.pendingListResponse = WriteGatePendingList(
            records: [record],
            supported: true
        )
        await store.loadApproval(force: true)
        await store.decide(record, approve: true)

        // 2. 第一次轮询：记录不在列表中（未见计数 +1）
        mockClient.gateStatusResponse = WriteGateStatus(
            supported: true,
            memoryGateEnabled: false,
            skillsGateEnabled: true,
            memoryCount: 0,
            skillsCount: 0
        )
        mockClient.pendingListResponse = WriteGatePendingList(
            records: [],
            supported: true
        )

        await store.refreshApprovalForChat()

        // 3. 推进时间到 65 秒后
        currentTime = t0.addingTimeInterval(65)

        // 4. 第二次轮询：记录仍不在列表中，但已超时 60 秒
        await store.refreshApprovalForChat()

        // 5. 第三次轮询：记录再现，应通过过滤（墓碑已被超时解除）
        // 本用例覆盖「超时＋未见后记录最终能回来」的系统行为；
        // 未见分支的 elapsed 解除在 approvalState 层不可隔离观察（记录再现必经 filter 的 elapsed 复判）
        mockClient.pendingListResponse = WriteGatePendingList(
            records: [record],
            supported: true
        )
        await store.refreshApprovalForChat()

        if case .ready(let records) = store.approvalState {
            XCTAssertTrue(records.contains(where: { $0.id == "test-5" }),
                         "60 秒超时后墓碑应解除，即使之前记录未见也应通过过滤")
        } else {
            XCTFail("approvalState 应为 ready")
        }
    }

    // MARK: - 真机时序测试：loadApproval 路径墓碑过滤

    /// 真机时序 ①：load → decide → loadApproval（滞后快照仍含已决记录）→ 断言不在待批列表
    func testLoadApprovalFiltersDecidedRecordInStaleSnapshot() async {
        let appState = AppState(client: DemoHermesClient(), demoMode: .connected)
        let mockClient = MockWriteGateClient()
        let store = AgentHubStore(appState: appState, gateClient: mockClient)

        let record = makeTestRecord(id: "real-seq-1")

        // 1. loadApproval：初始加载待批记录
        mockClient.gateStatusResponse = WriteGateStatus(
            supported: true,
            memoryGateEnabled: false,
            skillsGateEnabled: true,
            memoryCount: 0,
            skillsCount: 1
        )
        mockClient.pendingListResponse = WriteGatePendingList(
            records: [record],
            supported: true
        )
        await store.loadApproval(force: true)

        // 验证记录在待批列表
        if case .ready(let records) = store.approvalState {
            XCTAssertTrue(records.contains(where: { $0.id == "real-seq-1" }),
                         "初始 loadApproval 应加载待批记录")
        } else {
            XCTFail("approvalState 应为 ready")
        }

        // 2. decide：裁决成功（创建墓碑）
        mockClient.approveResponse = WriteGateDecisionResponse(
            success: true,
            output: nil,
            decision: "approved"
        )
        await store.decide(record, approve: true)

        // 验证裁决后记录被移除
        if case .ready(let records) = store.approvalState {
            XCTAssertFalse(records.contains(where: { $0.id == "real-seq-1" }),
                          "裁决成功后记录应从待批列表移除")
        } else {
            XCTFail("approvalState 应为 ready")
        }

        // 3. loadApproval：模拟滞后快照仍含已决记录（桥侧数据未一致）
        mockClient.gateStatusResponse = WriteGateStatus(
            supported: true,
            memoryGateEnabled: false,
            skillsGateEnabled: true,
            memoryCount: 0,
            skillsCount: 1
        )
        mockClient.pendingListResponse = WriteGatePendingList(
            records: [record],  // 滞后快照：服务端仍返回已决记录
            supported: true
        )
        await store.loadApproval(force: true)

        // 4. 断言：已决记录被墓碑过滤，不在待批列表
        // 删掉 loadApproval 的 applyTombstoneFilter 调用会变红
        if case .ready(let records) = store.approvalState {
            XCTAssertFalse(records.contains(where: { $0.id == "real-seq-1" }),
                          "loadApproval 路径应过滤墓碑保护窗口内的已决记录")
        } else {
            XCTFail("approvalState 应为 ready")
        }
    }

    /// 真机时序 ②：decide → loadApproval → refreshApprovalForChat → 断言仍不在
    func testDecideThenLoadThenRefreshKeepsRecordFiltered() async {
        let appState = AppState(client: DemoHermesClient(), demoMode: .connected)
        let mockClient = MockWriteGateClient()
        let store = AgentHubStore(appState: appState, gateClient: mockClient)

        let record = makeTestRecord(id: "real-seq-2")

        // 1. 初始加载
        mockClient.gateStatusResponse = WriteGateStatus(
            supported: true,
            memoryGateEnabled: false,
            skillsGateEnabled: true,
            memoryCount: 0,
            skillsCount: 1
        )
        mockClient.pendingListResponse = WriteGatePendingList(
            records: [record],
            supported: true
        )
        await store.loadApproval(force: true)

        // 2. decide：裁决成功
        mockClient.approveResponse = WriteGateDecisionResponse(
            success: true,
            output: nil,
            decision: "approved"
        )
        await store.decide(record, approve: true)

        // 3. loadApproval：滞后快照带回已决记录
        mockClient.gateStatusResponse = WriteGateStatus(
            supported: true,
            memoryGateEnabled: false,
            skillsGateEnabled: true,
            memoryCount: 0,
            skillsCount: 1
        )
        mockClient.pendingListResponse = WriteGatePendingList(
            records: [record],
            supported: true
        )
        await store.loadApproval(force: true)

        // 验证 loadApproval 过滤成功
        if case .ready(let records) = store.approvalState {
            XCTAssertFalse(records.contains(where: { $0.id == "real-seq-2" }),
                          "loadApproval 应过滤已决记录")
        } else {
            XCTFail("approvalState 应为 ready")
        }

        // 4. refreshApprovalForChat：滞后快照再次带回
        mockClient.gateStatusResponse = WriteGateStatus(
            supported: true,
            memoryGateEnabled: false,
            skillsGateEnabled: true,
            memoryCount: 0,
            skillsCount: 1
        )
        mockClient.pendingListResponse = WriteGatePendingList(
            records: [record],
            supported: true
        )
        await store.refreshApprovalForChat()

        // 5. 断言：两条路径都过滤，记录仍不在
        if case .ready(let records) = store.approvalState {
            XCTAssertFalse(records.contains(where: { $0.id == "real-seq-2" }),
                          "refreshApprovalForChat 应继续过滤墓碑保护窗口内的记录")
        } else {
            XCTFail("approvalState 应为 ready")
        }
    }

    /// 真机时序 ③：墓碑解除条件达成后 loadApproval 可重新显示
    func testLoadApprovalShowsRecordAfterTombstoneReleased() async {
        let appState = AppState(client: DemoHermesClient(), demoMode: .connected)
        let mockClient = MockWriteGateClient()
        let store = AgentHubStore(appState: appState, gateClient: mockClient)

        let record = makeTestRecord(id: "real-seq-3")

        // 注入可控时钟
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        var currentTime = t0
        store.nowProvider = { currentTime }

        // 1. 初始加载
        mockClient.gateStatusResponse = WriteGateStatus(
            supported: true,
            memoryGateEnabled: false,
            skillsGateEnabled: true,
            memoryCount: 0,
            skillsCount: 1
        )
        mockClient.pendingListResponse = WriteGatePendingList(
            records: [record],
            supported: true
        )
        await store.loadApproval(force: true)

        // 2. decide：裁决成功（创建墓碑，时刻 = t0）
        mockClient.approveResponse = WriteGateDecisionResponse(
            success: true,
            output: nil,
            decision: "approved"
        )
        await store.decide(record, approve: true)

        // 3. 推进时间到 65 秒后（超过 60 秒墓碑超时）
        currentTime = t0.addingTimeInterval(65)

        // 4. loadApproval：滞后快照带回记录，但墓碑已超时
        mockClient.gateStatusResponse = WriteGateStatus(
            supported: true,
            memoryGateEnabled: false,
            skillsGateEnabled: true,
            memoryCount: 0,
            skillsCount: 1
        )
        mockClient.pendingListResponse = WriteGatePendingList(
            records: [record],
            supported: true
        )
        await store.loadApproval(force: true)

        // 5. 断言：墓碑已解除，记录通过过滤重新显示
        if case .ready(let records) = store.approvalState {
            XCTAssertTrue(records.contains(where: { $0.id == "real-seq-3" }),
                         "墓碑超时解除后，loadApproval 应允许记录重新显示")
        } else {
            XCTFail("approvalState 应为 ready")
        }
    }
}

// MARK: - Mock WriteGateClient

final class MockWriteGateClient: WriteGateClientProtocol, @unchecked Sendable {
    var gateStatusResponse: WriteGateStatus?
    var pendingListResponse: WriteGatePendingList?
    var approveResponse: WriteGateDecisionResponse?
    var rejectResponse: WriteGateDecisionResponse?
    var decisionsResponse: [WriteGateDecisionRecord] = []

    func gateStatus(config: ServerConfig) async throws -> WriteGateStatus {
        gateStatusResponse ?? WriteGateStatus(
            supported: false,
            memoryGateEnabled: false,
            skillsGateEnabled: false,
            memoryCount: 0,
            skillsCount: 0
        )
    }

    func pendingList(config: ServerConfig) async throws -> WriteGatePendingList {
        pendingListResponse ?? WriteGatePendingList(records: [], supported: false)
    }

    func detail(config: ServerConfig, subsystem: WriteGateSubsystem, id: String) async throws -> WriteGateDetail {
        fatalError("Not implemented in mock")
    }

    func approve(config: ServerConfig, subsystem: WriteGateSubsystem, id: String) async throws -> WriteGateDecisionResponse {
        approveResponse ?? WriteGateDecisionResponse(
            success: false,
            output: nil,
            decision: "approved"
        )
    }

    func reject(config: ServerConfig, subsystem: WriteGateSubsystem, id: String) async throws -> WriteGateDecisionResponse {
        rejectResponse ?? WriteGateDecisionResponse(
            success: false,
            output: nil,
            decision: "rejected"
        )
    }

    func decisions(config: ServerConfig, limit: Int) async throws -> [WriteGateDecisionRecord] {
        decisionsResponse
    }

    func decisionsForAnchor(config: ServerConfig, limit: Int) async throws -> [WriteGateDecisionRecord] {
        decisionsResponse
    }

    func rules(config: ServerConfig) async throws -> [WriteGateRule] {
        []
    }

    func createRule(config: ServerConfig, subsystem: WriteGateSubsystem, origin: String) async throws -> WriteGateRule {
        fatalError("Not implemented in mock")
    }

    func deleteRule(config: ServerConfig, id: String) async throws {
        fatalError("Not implemented in mock")
    }
}
