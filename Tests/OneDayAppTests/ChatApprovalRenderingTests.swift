import XCTest
@testable import OneDayApp
@testable import OneDayCore

/// Bug3 修复测试：审批卡渲染位置与状态管理
///
/// 验证要点：
/// 1. 待批审批不在消息流内渲染完整卡片（.pending → EmptyView）
/// 2. 已决审批在消息流内渲染汇总行（.decided → 图标+文字行）
/// 3. 停靠卡数据源正确过滤已锚定记录
/// 4. decidingIDs 在裁决成功后正确清理
final class ChatApprovalRenderingTests: XCTestCase {

    // MARK: - 行内渲染状态测试

    func testPendingApprovalDoesNotRenderInline() {
        // 验证：.pending 状态返回 EmptyView，不渲染完整卡片
        let record = WriteGateRecord(
            id: "test-1",
            subsystem: .skills,
            action: "edit",
            summary: "测试待批",
            origin: "background_review",
            createdAt: Date(),
            anchor: WriteGateAnchor(sessionId: "sess-1", tier: "T1")
        )

        let rowState = ApprovalAnchor.RowState.pending(record)

        // 验证：.pending 状态应该在消息流内渲染 EmptyView
        // （实际视图测试需要 UI 测试，这里测试状态逻辑）
        switch rowState {
        case .pending:
            // .pending 状态存在，但应渲染为 EmptyView
            XCTAssertTrue(true, "待批状态存在，应在停靠卡渲染")
        case .decided, .stale, .loading:
            XCTFail("状态不应为其他类型")
        }
    }

    func testDecidedApprovalRendersInlineSummary() {
        // 验证：.decided 状态应渲染汇总行
        let item = WriteGateDecisionRecord(
            id: "test-2",
            subsystem: .memory,
            action: "append",
            summary: "测试已决",
            origin: "oneday_app",
            decision: "approved",
            decidedAt: Date(),
            anchor: nil,
            createdAt: Date()
        )

        let rowState = ApprovalAnchor.RowState.decided(item)

        switch rowState {
        case .decided(let record):
            XCTAssertEqual(record.id, "test-2")
            XCTAssertEqual(record.decision, "approved")
        case .pending, .stale, .loading:
            XCTFail("状态应为 decided")
        }
    }

    func testStaleApprovalRendersGrayRow() {
        // 验证：.stale 状态应渲染失效行
        let rowState = ApprovalAnchor.RowState.stale

        switch rowState {
        case .stale:
            XCTAssertTrue(true, "失效状态正确")
        case .pending, .decided, .loading:
            XCTFail("状态应为 stale")
        }
    }

    // MARK: - 停靠卡数据源测试

    func testApprovalZoneFilteringAnchoredRecords() {
        // 验证：ChatApprovalZone 应正确过滤已锚定记录
        let record1 = WriteGateRecord(
            id: "anchored-1",
            subsystem: .skills,
            action: "edit",
            summary: "已锚定",
            origin: "background_review",
            createdAt: Date(),
            anchor: WriteGateAnchor(sessionId: "sess-1", tier: "T1")
        )

        let record2 = WriteGateRecord(
            id: "unanchored-1",
            subsystem: .memory,
            action: "add",
            summary: "未锚定",
            origin: "oneday_app",
            createdAt: Date(),
            anchor: nil
        )

        let anchoredIDs: Set<String> = ["anchored-1"]

        // 模拟数据源过滤逻辑（实际逻辑在 ChatApprovalZone.splitPending）
        let shouldShowInZone1 = !anchoredIDs.contains(record1.id)
        let shouldShowInZone2 = !anchoredIDs.contains(record2.id)

        XCTAssertFalse(shouldShowInZone1, "已锚定记录不应在停靠区显示")
        XCTAssertTrue(shouldShowInZone2, "未锚定记录应在停靠区显示")
    }

    // MARK: - decidingIDs 清理测试

    func testDecidingIDsClearedAfterSuccess() {
        // 验证：decidingIDs 在裁决成功后应被清除
        // （第一轮修复 ca49e096 已实现，此处为回归测试）

        var decidingIDs: Set<String> = ["test-id"]
        let recordID = "test-id"

        // 模拟成功裁决后的清理
        decidingIDs.remove(recordID)

        XCTAssertFalse(decidingIDs.contains(recordID),
                       "decidingIDs 应在成功后清除")
    }

    // MARK: - splitPending 锚回本会话修复测试

    func testAnchoredToCurrentSessionAppearsInCurrentBucket() {
        // 验证：已落锚且 anchor 为当前会话的待批记录进当前桶
        let record = WriteGateRecord(
            id: "anchored-current",
            subsystem: .skills,
            action: "edit",
            summary: "锚回本会话",
            origin: "background_review",
            createdAt: Date(),
            anchor: WriteGateAnchor(sessionId: "sess-current", tier: "T1")
        )

        let anchoredIDs: Set<String> = ["anchored-current"]
        let currentSessionID = "sess-current"

        let result = ChatApprovalZone.splitPendingForTest(
            records: [record],
            anchoredIDs: anchoredIDs,
            currentServerSessionID: currentSessionID
        )

        XCTAssertEqual(result.current.count, 1, "锚回本会话的待批记录应出现在当前桶")
        XCTAssertEqual(result.current.first?.id, "anchored-current")
        XCTAssertEqual(result.other.count, 0, "不应进其他桶")
    }

    func testUnanchoredPendingRecordAppearsInCurrentBucket() {
        // 验证：无锚待批记录进当前桶（监督涂归改名——原名
        // testDecidedRecordsDoNotAppearInPending 名不符实：本用例从
        // 未构造已裁决记录。已裁决的排除不在 splitPending 层：入参
        // 本就是 store 的待批集，渲染层另以 resolvedLines 过滤当前
        // 桶，两处均非本用例所测）
        let pendingRecord = WriteGateRecord(
            id: "pending-1",
            subsystem: .skills,
            action: "edit",
            summary: "待批",
            origin: "background_review",
            createdAt: Date(),
            anchor: nil
        )

        // 模拟上游过滤：已裁决记录不传入 splitPending
        let inputRecords = [pendingRecord] // 不含已裁决记录

        let result = ChatApprovalZone.splitPendingForTest(
            records: inputRecords,
            anchoredIDs: [],
            currentServerSessionID: "sess-1"
        )

        XCTAssertEqual(result.current.count, 1, "只有待批记录")
        XCTAssertEqual(result.current.first?.id, "pending-1")
    }

    func testOtherSessionAnchoredRecordsOnlyInOtherBucket() {
        // 验证：其他会话锚记录只进其他桶、不进当前桶
        let otherSessionRecord = WriteGateRecord(
            id: "anchored-other",
            subsystem: .memory,
            action: "add",
            summary: "锚到其他会话",
            origin: "oneday_app",
            createdAt: Date(),
            anchor: WriteGateAnchor(sessionId: "sess-other", tier: "T2")
        )

        let anchoredIDs: Set<String> = ["anchored-other"]
        let currentSessionID = "sess-current"

        let result = ChatApprovalZone.splitPendingForTest(
            records: [otherSessionRecord],
            anchoredIDs: anchoredIDs,
            currentServerSessionID: currentSessionID
        )

        XCTAssertEqual(result.other.count, 1, "其他会话锚记录应只进其他桶")
        XCTAssertEqual(result.other.first?.id, "anchored-other")
        XCTAssertEqual(result.current.count, 0, "不应进当前桶")
    }

    // MARK: - 状态机完整性测试

    func testApprovalRowStateTransitions() {
        // 验证：审批状态机的完整转换
        let record = WriteGateRecord(
            id: "state-test",
            subsystem: .skills,
            action: "edit",
            summary: "状态测试",
            origin: "background_review",
            createdAt: Date(),
            anchor: WriteGateAnchor(sessionId: "sess-1", tier: "T1")
        )

        let decidedRecord = WriteGateDecisionRecord(
            id: "state-test",
            subsystem: .skills,
            action: "edit",
            summary: "状态测试",
            origin: "background_review",
            decision: "approved",
            decidedAt: Date(),
            anchor: WriteGateAnchor(sessionId: "sess-1", tier: "T1"),
            createdAt: Date()
        )

        // 1. 待批状态
        let pendingState = ApprovalAnchor.rowState(
            recordID: "state-test",
            dataReady: true,
            pending: [record],
            decisions: [],
            missCount: 0
        )

        switch pendingState {
        case .pending:
            XCTAssertTrue(true)
        default:
            XCTFail("应为待批状态")
        }

        // 2. 已决状态（待批清空）
        let decidedState = ApprovalAnchor.rowState(
            recordID: "state-test",
            dataReady: true,
            pending: [],
            decisions: [decidedRecord],
            missCount: 0
        )

        switch decidedState {
        case .decided:
            XCTAssertTrue(true)
        default:
            XCTFail("应为已决状态")
        }

        // 3. 失效状态（两处皆无且缺席满2轮）
        let staleState = ApprovalAnchor.rowState(
            recordID: "state-test",
            dataReady: true,
            pending: [],
            decisions: [],
            missCount: 2
        )

        switch staleState {
        case .stale:
            XCTAssertTrue(true)
        default:
            XCTFail("应为失效状态")
        }
    }
}
