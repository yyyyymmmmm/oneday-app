import XCTest
@testable import OneDayCore

/// 审批卡动作栈规格钉测（样式二期 S2-01/S2-03）：三
/// 档裁决钮的几何落值、栈构成与主次角色只许 Core
/// ApprovalCardSpec 单源——聊天就地卡与枢纽待批卡共
/// 用同一卡面组件，视图层若各写各的高/距/次序，两面
/// 立刻分叉。渲染通道（自绘胶囊背景满宽）单测钉不
/// 住，验收靠真机看三钮等宽满宽（同 §116 验收口径）。
final class ApprovalCardSpecTests: XCTestCase {

    /// 几何落值：钮高 48、钮距 10（参照 Muse 审批
    /// 卡真机量测带内，审计 S2-01 落值）；D10 定
    /// 版④文字级高 36、栈总高按角色合成（全栈
    /// 48＋48＋36＋距 10×2＝152、防呆单驳回＝
    /// 36、空栈＝0）
    func testButtonGeometry() {
        XCTAssertEqual(ApprovalCardSpec.buttonHeight, 48)
        XCTAssertEqual(ApprovalCardSpec.buttonSpacing, 10)
        XCTAssertEqual(ApprovalCardSpec.textButtonHeight, 36)
        XCTAssertEqual(
            ApprovalCardSpec.buttonHeight(for: .approve), 48
        )
        XCTAssertEqual(
            ApprovalCardSpec.buttonHeight(for: .alwaysAllow), 48
        )
        XCTAssertEqual(
            ApprovalCardSpec.buttonHeight(for: .reject), 36
        )
        XCTAssertEqual(
            ApprovalCardSpec.actionStackHeight(
                [.approve, .alwaysAllow, .reject]
            ),
            152
        )
        XCTAssertEqual(
            ApprovalCardSpec.actionStackHeight([.reject]), 36
        )
        XCTAssertEqual(
            ApprovalCardSpec.actionStackHeight([]), 0
        )
    }

    /// D10 定版④形态角色单源：批准填充主钮／总
    /// 是允许描边次钮／驳回文字级
    func testButtonRoles() {
        XCTAssertEqual(
            ApprovalCardAction.approve.buttonRole,
            .filledPrimary
        )
        XCTAssertEqual(
            ApprovalCardAction.alwaysAllow.buttonRole,
            .outlinedSecondary
        )
        XCTAssertEqual(
            ApprovalCardAction.reject.buttonRole, .text
        )
    }

    /// 栈构成：可裁决恒三档全栈、自上而下批准／总是
    /// 允许这一类／驳回；主钮恒一只（批准）
    func testActionStackWhenDecidable() {
        let stack = ApprovalCardSpec.actionStack(canDecide: true)
        XCTAssertEqual(stack, [.approve, .alwaysAllow, .reject])
        XCTAssertEqual(stack.filter(\.isPrimary), [.approve])
    }

    /// 不可裁决零钮：卡面只留说明与去向，不摆假按钮
    func testActionStackWhenUndecidable() {
        XCTAssertEqual(
            ApprovalCardSpec.actionStack(canDecide: false), []
        )
        XCTAssertEqual(
            ApprovalCardSpec.actionStack(canDecide: false, blocked: true),
            []
        )
    }

    /// §245 防呆栈：批不了的记录只留驳回一档——批准
    /// 与总是允许都必败，不许摆出来让用户白点
    func testActionStackWhenBlocked() {
        XCTAssertEqual(
            ApprovalCardSpec.actionStack(canDecide: true, blocked: true),
            [.reject]
        )
    }

    /// §245 工具图标单源：与全 App 既有同名符号一致
    /// （记忆 brain／技能 puzzlepiece.extension）
    func testToolIconNames() {
        XCTAssertEqual(
            ApprovalCardSpec.toolIconName(for: .memory), "brain"
        )
        XCTAssertEqual(
            ApprovalCardSpec.toolIconName(for: .skills),
            "puzzlepiece.extension"
        )
        XCTAssertEqual(
            ApprovalCardSpec.toolIconName(for: .unknown),
            "questionmark.circle"
        )
    }

    /// 钮面文案与既有确认弹窗口径一致（三语目录键）
    func testActionTitles() {
        let zh = Locale(identifier: "zh-Hans")
        XCTAssertEqual(
            ApprovalCardAction.approve.title(locale: zh), "批准"
        )
        XCTAssertEqual(
            ApprovalCardAction.alwaysAllow.title(locale: zh),
            "总是允许这一类"
        )
        XCTAssertEqual(
            ApprovalCardAction.reject.title(locale: zh), "驳回"
        )
    }

    /// D10 定版②队列派生：无待批时无活卡无收纳
    func testZoneQueueWhenEmpty() {
        let queue = ApprovalZoneQueue.derive(
            recordIDs: [], anchoredIDs: []
        )
        XCTAssertNil(queue.activeRecordID)
        XCTAssertEqual(queue.queuedCount, 0)
        XCTAssertEqual(queue.pendingCount, 0)
    }

    /// D10 定版②队列派生：单条即活卡、不收纳
    func testZoneQueueSingle() {
        let queue = ApprovalZoneQueue.derive(
            recordIDs: ["a"], anchoredIDs: []
        )
        XCTAssertEqual(queue.activeRecordID, "a")
        XCTAssertEqual(queue.queuedCount, 0)
        XCTAssertEqual(queue.pendingCount, 1)
    }

    /// D10 定版②队列派生：多条只活第一条（桥
    /// 序），其余全收纳——裁决落定后首条移出、
    /// 次条顶上靠的正是此序
    func testZoneQueueMultipleKeepsFirstOnly() {
        let queue = ApprovalZoneQueue.derive(
            recordIDs: ["a", "b", "c"], anchoredIDs: []
        )
        XCTAssertEqual(queue.activeRecordID, "a")
        XCTAssertEqual(queue.queuedCount, 2)
        XCTAssertEqual(queue.pendingCount, 3)
    }

    /// D10 定版②队列派生：锚定记录先排除（锚
    /// 定行自承载、本包豁免）——首条已锚时次条
    /// 顶上；全锚时流末区无活卡不收纳；锚定集
    /// 含无关 id 不影响
    func testZoneQueueSkipsAnchored() {
        var queue = ApprovalZoneQueue.derive(
            recordIDs: ["a", "b", "c"], anchoredIDs: ["a"]
        )
        XCTAssertEqual(queue.activeRecordID, "b")
        XCTAssertEqual(queue.queuedCount, 1)
        XCTAssertEqual(queue.pendingCount, 2)
        queue = ApprovalZoneQueue.derive(
            recordIDs: ["a", "b"], anchoredIDs: ["a", "b"]
        )
        XCTAssertNil(queue.activeRecordID)
        XCTAssertEqual(queue.queuedCount, 0)
        XCTAssertEqual(queue.pendingCount, 0)
        queue = ApprovalZoneQueue.derive(
            recordIDs: ["a", "b"], anchoredIDs: ["zzz"]
        )
        XCTAssertEqual(queue.activeRecordID, "a")
        XCTAssertEqual(queue.queuedCount, 1)
    }
}
