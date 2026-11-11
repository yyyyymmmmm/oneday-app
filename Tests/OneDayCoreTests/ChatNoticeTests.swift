import OneDayCore
import XCTest

/// §131 提示纪律第一包钉测：分档自消口径（中性 5s／
/// 重要 8s）与呈现状态机的代号纪律（自清只清自己
/// 那一代、手关后旧计时不复活）。「成功不报」（重连
/// 提示摘除）在 App 侧是删除赋值点、无 Core 面可测，
/// 其防线是本状态机不为恢复类结果设任何入口这一形
/// 状＋代码评审 grep 零残留（见 DESIGN §131）。
final class ChatNoticeTests: XCTestCase {

    // MARK: 分档

    func testTierDurations() {
        XCTAssertEqual(
            ChatNoticeTier.brief.autoDismissSeconds, 5,
            accuracy: 0.001
        )
        XCTAssertEqual(
            ChatNoticeTier.extended.autoDismissSeconds, 8,
            accuracy: 0.001
        )
    }

    func testTierSetIsExactlyTwo() {
        // 档位只许两档：新增档位须先改纪律、再改这里
        XCTAssertEqual(ChatNoticeTier.allCases.count, 2)
    }

    // MARK: 呈现/换代

    func testPresentSetsCurrent() {
        var presentation = NoticePresentation()
        XCTAssertFalse(presentation.isPresenting)
        let notice = ChatNotice(text: "已停止生成。", tier: .brief)
        presentation.present(notice)
        XCTAssertEqual(presentation.current, notice)
        XCTAssertTrue(presentation.isPresenting)
    }

    func testPresentReplacesPreviousGeneration() {
        var presentation = NoticePresentation()
        let first = ChatNotice(text: "甲", tier: .brief)
        let second = ChatNotice(text: "乙", tier: .extended)
        presentation.present(first)
        presentation.present(second)
        XCTAssertEqual(presentation.current, second)
    }

    func testDefaultIDsAreUniquePerNotice() {
        // 代号须逐条唯一，否则自清会串代误清
        let a = ChatNotice(text: "同文案", tier: .brief)
        let b = ChatNotice(text: "同文案", tier: .brief)
        XCTAssertNotEqual(a.id, b.id)
    }

    // MARK: 自清代号纪律

    func testExpireWithMatchingIDClears() {
        var presentation = NoticePresentation()
        let notice = ChatNotice(text: "甲", tier: .brief)
        presentation.present(notice)
        XCTAssertTrue(presentation.expire(id: notice.id))
        XCTAssertNil(presentation.current)
    }

    func testExpireWithStaleIDKeepsNewerNotice() {
        // 旧条计时到期时新条已换代：不得误清新条
        var presentation = NoticePresentation()
        let old = ChatNotice(text: "旧", tier: .brief)
        let new = ChatNotice(text: "新", tier: .extended)
        presentation.present(old)
        presentation.present(new)
        XCTAssertFalse(presentation.expire(id: old.id))
        XCTAssertEqual(presentation.current, new)
    }

    func testExpireAfterManualDismissDoesNotResurrect() {
        // 手关后旧计时到期：条不复活、expire 空转
        var presentation = NoticePresentation()
        let notice = ChatNotice(text: "甲", tier: .brief)
        presentation.present(notice)
        presentation.dismiss()
        XCTAssertNil(presentation.current)
        XCTAssertFalse(presentation.expire(id: notice.id))
        XCTAssertNil(presentation.current)
    }

    func testExpireWithUnknownIDIsNoOp() {
        var presentation = NoticePresentation()
        let notice = ChatNotice(text: "甲", tier: .brief)
        presentation.present(notice)
        XCTAssertFalse(presentation.expire(id: UUID()))
        XCTAssertEqual(presentation.current, notice)
    }
}
