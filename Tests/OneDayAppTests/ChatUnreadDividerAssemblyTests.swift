import OneDayCore
import OneDayDesign
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// 台账 148 装配层：未读分界的修订/行高/账本/水
/// 位店四处接线——锚翻转必须进修订（行重托管）、
/// 进量高（分界槽）、动画只演一次（账本）、水位
/// 推进落盘可读回。锚点解析本身在 Core 测
/// （UnreadDividerTests）
@MainActor
final class ChatUnreadDividerAssemblyTests: XCTestCase {
    private func makeComposer() -> ChatNativeRowHeightComposer {
        ChatNativeRowHeightComposer(
            screenWidth: 402,
            horizontalPadding: OneDayMetrics.pageGutter,
            sizeCategory: .large,
            boldText: false,
            displayScale: 3,
            ledger: ChatRowStateLedger(),
            hubStore: AppState().sharedHubStore(),
            agentDisplayName: "Hermes",
            emptyStateAvatarSize: 72
        )
    }

    func testRevisionChangesWithUnreadFlag() {
        let entry = ChatEntry(
            role: "assistant", content: "一条回复", thread: nil
        )
        let plain = ChatNativeRowRevision.entry(
            entry, dividerText: nil, highlighted: false,
            styleKey: "s"
        )
        let flagged = ChatNativeRowRevision.entry(
            entry, dividerText: nil, highlighted: false,
            styleKey: "s",
            showsUnreadDivider: true
        )
        XCTAssertNotEqual(
            plain, flagged,
            "未读分界翻转必须进修订账（否则行不重托管、线画不出）"
        )
    }

    func testHeightIncludesDividerSlot() {
        let composer = makeComposer()
        let entry = ChatEntry(
            role: "assistant", content: "一条回复", thread: nil
        )
        let snapshot = ChatEntryHeightSnapshot(entry)
        let plain = composer.entryHeightCore(
            snapshot, dividerText: nil
        )
        let flagged = composer.entryHeightCore(
            snapshot, dividerText: nil,
            showsUnreadDivider: true
        )
        XCTAssertGreaterThan(
            flagged, plain + 10,
            "带分界行高须含分界槽（一行字高＋间距），"
                + "实测差 \(flagged - plain)"
        )
    }

    func testLedgerPlaysAnimationOnce() {
        let ledger = ChatRowStateLedger()
        let key = ChatRowStateKeys.unreadDivider(UUID())
        XCTAssertFalse(
            ledger.hasAnimatedUnreadDivider(forKey: key)
        )
        ledger.markUnreadDividerAnimated(forKey: key)
        XCTAssertTrue(
            ledger.hasAnimatedUnreadDivider(forKey: key)
        )
    }

    func testReadMarkStoreRoundTrips() {
        let store = ThreadReadMarkStore()
        let threadID = UUID()
        let entryID = UUID()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertNil(store.watermark(for: threadID))
        store.advance(for: threadID, entryID: entryID, date: date)
        let mark = store.watermark(for: threadID)
        XCTAssertEqual(mark?.entryID, entryID)
        XCTAssertEqual(mark?.date, date)
        // 再推进覆盖旧水位
        let newer = UUID()
        let newerDate = date.addingTimeInterval(60)
        store.advance(for: threadID, entryID: newer, date: newerDate)
        XCTAssertEqual(store.watermark(for: threadID)?.entryID, newer)
    }
}
