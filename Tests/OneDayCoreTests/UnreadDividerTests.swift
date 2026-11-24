import XCTest
@testable import OneDayCore

/// 台账 148（NEW 未读分界线）：锚点解析全集——
/// 无水位无锚（首次开会话不画线）、只有对方消息
/// 开未读段、工具卡不算、水位条目被删按时刻回落
final class UnreadDividerTests: XCTestCase {
    private func stub(
        _ id: String, role: String, at t: TimeInterval,
        tool: Bool = false
    ) -> UnreadDivider.EntryStub {
        UnreadDivider.EntryStub(
            id: UUID(uuidString: id)!,
            role: role,
            createdAt: Date(timeIntervalSince1970: t),
            isToolCard: tool
        )
    }

    private let u1 = "00000000-0000-0000-0000-000000000001"
    private let a1 = "00000000-0000-0000-0000-000000000002"
    private let a2 = "00000000-0000-0000-0000-000000000003"
    private let u2 = "00000000-0000-0000-0000-000000000004"
    private let t1 = "00000000-0000-0000-0000-000000000005"
    private let a3 = "00000000-0000-0000-0000-000000000006"

    private func thread() -> [UnreadDivider.EntryStub] {
        [
            stub(u1, role: "user", at: 100),
            stub(a1, role: "assistant", at: 110),
            stub(t1, role: "assistant", at: 120, tool: true),
            stub(a2, role: "assistant", at: 130),
            stub(u2, role: "user", at: 140),
            stub(a3, role: "assistant", at: 150),
        ]
    }

    func testNoWatermarkNoAnchor() {
        XCTAssertNil(
            UnreadDivider.anchorEntryID(
                entries: thread(), watermark: nil
            )
        )
    }

    func testAnchorIsFirstAssistantAfterWatermark() {
        let mark = UnreadDivider.Watermark(
            entryID: UUID(uuidString: a1)!,
            date: Date(timeIntervalSince1970: 110)
        )
        // 水位后先是工具卡（跳过）、再是 a2
        XCTAssertEqual(
            UnreadDivider.anchorEntryID(
                entries: thread(), watermark: mark
            ),
            UUID(uuidString: a2)!
        )
    }

    func testOnlyOwnMessagesAfterWatermarkNoAnchor() {
        let mark = UnreadDivider.Watermark(
            entryID: UUID(uuidString: a3)!,
            date: Date(timeIntervalSince1970: 150)
        )
        XCTAssertNil(
            UnreadDivider.anchorEntryID(
                entries: thread(), watermark: mark
            )
        )
    }

    func testWatermarkEntryDeletedFallsBackToDate() {
        // 水位条目 a1 已被删：按时刻回落到 110 之后
        var entries = thread()
        entries.removeAll { $0.id.uuidString == a1 }
        let mark = UnreadDivider.Watermark(
            entryID: UUID(uuidString: a1)!,
            date: Date(timeIntervalSince1970: 110)
        )
        XCTAssertEqual(
            UnreadDivider.anchorEntryID(
                entries: entries, watermark: mark
            ),
            UUID(uuidString: a2)!
        )
    }

    func testWatermarkAtUserEntryNextAssistantAnchors() {
        let mark = UnreadDivider.Watermark(
            entryID: UUID(uuidString: u2)!,
            date: Date(timeIntervalSince1970: 140)
        )
        XCTAssertEqual(
            UnreadDivider.anchorEntryID(
                entries: thread(), watermark: mark
            ),
            UUID(uuidString: a3)!
        )
    }

    func testEmptyEntriesNoAnchor() {
        let mark = UnreadDivider.Watermark(
            entryID: UUID(uuidString: a1)!,
            date: Date(timeIntervalSince1970: 110)
        )
        XCTAssertNil(
            UnreadDivider.anchorEntryID(
                entries: [], watermark: mark
            )
        )
    }
}
