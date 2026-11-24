import OneDayCore
import XCTest
@testable import OneDayApp

/// 点子删除确认收口（小尾巴包）：列表长按菜单与详
/// 情 sheet 两处确认路径共用 IdeasStore.delete 一个
/// 漏斗——本组钉漏斗出口的落点口径：回读确认消失
/// 才落删除回响（明示删了哪条）、未落定只留痕不报
/// 已删、新一次删除清旧回响、未连接早退不产生回
/// 响。落锤本身（确认钮首行 impact heavy）是 UIKit
/// 触感、无单测面，与文件/交付物/全部对话四面同式
/// 由代码形态保证、锤感归真机清单。
@MainActor
final class IdeasDeleteConfirmTests: XCTestCase {

    private func makeIdea(
        id: String = "idea-del-1", title: String = "周末去爬山"
    ) -> BridgeIdea {
        BridgeIdea(
            id: id, title: title, detail: "", goalId: nil,
            createdAt: 100, status: .pending, category: "interest"
        )
    }

    // MARK: - 回读落点（两处确认路径的共同出口）

    func testVerifiedDeleteOutcomeSetsNoticeEcho() {
        let store = IdeasStore()
        let idea = makeIdea()
        store.applyDeleteOutcome(idea: idea, stillPresent: false)
        XCTAssertEqual(
            store.deleteNotice,
            L10n.format("已删除「%@」。", idea.title)
        )
        XCTAssertTrue(
            store.deleteNotice?.contains(idea.title) ?? false
        )
        XCTAssertNil(store.notes[idea.id])
    }

    func testUnverifiedDeleteOutcomeLeavesTraceOnly() {
        let store = IdeasStore()
        let idea = makeIdea()
        store.applyDeleteOutcome(idea: idea, stillPresent: true)
        XCTAssertEqual(
            store.notes[idea.id],
            L10n.string("删除已发出，但列表里还在，请刷新核对。")
        )
        XCTAssertNil(store.deleteNotice)
    }

    /// 回响文案钉死三语目录值（键＝与文件页/交付物
    /// 页共用的「已删除「%@」。」，防目录漂移）
    func testNoticeCopyPinnedAcrossLocales() {
        XCTAssertEqual(
            L10n.format(
                "已删除「%@」。", locale: Locale(identifier: "zh-Hans"),
                "周末去爬山"
            ),
            "已删除「周末去爬山」。"
        )
        XCTAssertEqual(
            L10n.format(
                "已删除「%@」。", locale: Locale(identifier: "zh-Hant"),
                "周末去爬山"
            ),
            "已刪除「周末去爬山」。"
        )
        XCTAssertEqual(
            L10n.format(
                "已删除「%@」。", locale: Locale(identifier: "en"),
                "周末去爬山"
            ),
            "“周末去爬山” deleted."
        )
    }

    // MARK: - 删除入口（未连接早退）

    func testDeleteWithoutConnectionLeavesNoteAndClearsNotice() async {
        let store = IdeasStore()
        let idea = makeIdea()
        // 先落一条旧回响，验新一次删除动作把它清掉
        store.applyDeleteOutcome(idea: idea, stillPresent: false)
        XCTAssertNotNil(store.deleteNotice)

        await store.delete(appState: AppState(), idea: idea)

        XCTAssertEqual(
            store.notes[idea.id], L10n.string("尚未连接服务器。")
        )
        XCTAssertNil(store.deleteNotice)
        XCTAssertTrue(store.actingIDs.isEmpty)
    }
}
