import OneDayCore
import XCTest
@testable import OneDayApp

/// 台账 154 发件箱动作面组装验收（DESIGN §336）：
/// 发件箱条目项集（重新发送/编辑居首、回复/旁聊
/// 不组装、撤回居末且破坏性）与落定条目旧项集逐
/// 项不变，两态同钉——组装是单源（ChatRowAction-
/// SheetData.actionItems），呈现层不再另判
@MainActor
final class OutboxActionSheetTests: XCTestCase {

    private func makeData(
        plainText: String = "没发出去的内容",
        outbox: Bool
    ) -> ChatRowActionSheetData {
        ChatRowActionSheetData(
            plainText: plainText,
            canReact: false, ownEmoji: nil,
            onPickReaction: { _ in },
            onReply: {}, onFork: {},
            onSelect: {}, onShare: {},
            onResend: outbox ? {} : nil,
            onEditUnsent: outbox ? {} : nil,
            onWithdrawUnsent: outbox ? {} : nil
        )
    }

    func testOutboxItemSetAndOrder() {
        let items = makeData(outbox: true).actionItems()
        XCTAssertEqual(
            items.map(\.kind),
            [.resend, .editUnsent, .copy, .select, .share,
             .withdrawUnsent]
        )
        XCTAssertEqual(
            items.map(\.title),
            ["重新发送", "编辑", "复制", "选择", "分享", "撤回"]
        )
    }

    func testOutboxWithdrawIsDestructiveOnly() {
        let items = makeData(outbox: true).actionItems()
        XCTAssertEqual(
            items.filter(\.isDestructive).map(\.kind),
            [.withdrawUnsent]
        )
    }

    func testOutboxEmptyTextDropsTextItems() {
        // 无正文（纯附件失败）：复制/选择/分享是假
        // 动作、不组装；发件箱三项恒在
        let items = makeData(
            plainText: "", outbox: true
        ).actionItems()
        XCTAssertEqual(
            items.map(\.kind),
            [.resend, .editUnsent, .withdrawUnsent]
        )
    }

    func testSettledItemSetUnchanged() {
        // 落定条目（onResend 为 nil）：项集与 187
        // 旧口径逐项同、无破坏性项混入
        let items = makeData(outbox: false).actionItems()
        XCTAssertEqual(
            items.map(\.kind),
            [.reply, .fork, .copy, .select, .share]
        )
        XCTAssertTrue(items.allSatisfy { !$0.isDestructive })
    }
}
