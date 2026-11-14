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
    /// 卡真机量测带内，审计 S2-01 落值）
    func testButtonGeometry() {
        XCTAssertEqual(ApprovalCardSpec.buttonHeight, 48)
        XCTAssertEqual(ApprovalCardSpec.buttonSpacing, 10)
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

    /// §234 防呆栈：批不了的记录只留驳回一档——批准
    /// 与总是允许都必败，不许摆出来让用户白点
    func testActionStackWhenBlocked() {
        XCTAssertEqual(
            ApprovalCardSpec.actionStack(canDecide: true, blocked: true),
            [.reject]
        )
    }

    /// §234 工具图标单源：与全 App 既有同名符号一致
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
}
