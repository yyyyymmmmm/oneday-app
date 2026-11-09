import XCTest
@testable import OneDayCore

/// 0.7.0 旁聊语义单测：主线钦定解析、分区归类、归档过滤、
/// 回告只入主线判定、建会话回执解码逐项把守
final class SideChatTests: XCTestCase {

    private let mainID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let sideID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

    // MARK: 主线钦定解析

    func testMainResolveKeepsStoredIDWhenThreadExists() {
        let resolution = MainThreadDesignation.resolve(storedID: mainID, existingIDs: [mainID, sideID])
        XCTAssertEqual(resolution, .existing(mainID))
    }

    func testMainResolveCreatesWhenNoStoredID() {
        let resolution = MainThreadDesignation.resolve(storedID: nil, existingIDs: [sideID])
        XCTAssertEqual(resolution, .needsCreation)
    }

    func testMainResolveCreatesWhenStoredThreadGone() {
        // 钦定 id 还在档里但线程已被删净 → 重新钦定，不悬挂
        let resolution = MainThreadDesignation.resolve(storedID: mainID, existingIDs: [sideID])
        XCTAssertEqual(resolution, .needsCreation)
    }

    func testServerEnsureSkipsAfterConfirmed() {
        XCTAssertEqual(MainThreadDesignation.serverEnsure(confirmed: true), .skip)
        XCTAssertEqual(MainThreadDesignation.serverEnsure(confirmed: false), .verifyOrCreate)
    }

    // MARK: 分区归类

    func testClassifierMarksMainLocalThread() {
        XCTAssertEqual(SideChatClassifier.zone(localThreadID: mainID, mainThreadID: mainID), .main)
        XCTAssertEqual(SideChatClassifier.zone(localThreadID: sideID, mainThreadID: mainID), .side)
    }

    func testClassifierWithoutDesignationAllSide() {
        XCTAssertEqual(SideChatClassifier.zone(localThreadID: mainID, mainThreadID: nil), .side)
    }

    func testClassifierMarksMainServerSession() {
        XCTAssertEqual(
            SideChatClassifier.zone(serverSessionID: "oneday-main-x", mainServerSessionID: "oneday-main-x"),
            .main
        )
        XCTAssertEqual(
            SideChatClassifier.zone(serverSessionID: "other", mainServerSessionID: "oneday-main-x"),
            .side
        )
        XCTAssertEqual(
            SideChatClassifier.zone(serverSessionID: "other", mainServerSessionID: nil),
            .side
        )
        XCTAssertEqual(
            SideChatClassifier.zone(serverSessionID: "other", mainServerSessionID: ""),
            .side
        )
    }

    // MARK: 归档过滤

    func testArchiveKeysAreNamespaced() {
        XCTAssertEqual(SideChatArchive.localKey(mainID), "local:11111111-1111-1111-1111-111111111111")
        XCTAssertEqual(SideChatArchive.serverKey("sess-1"), "server:sess-1")
    }

    func testArchivePartitionKeepsOrderAndSplits() {
        let items = ["a", "b", "c", "d"]
        let keys: Set<String> = ["server:b", "server:d"]
        let result = SideChatArchive.partition(items, key: { "server:\($0)" }, archivedKeys: keys)
        XCTAssertEqual(result.visible, ["a", "c"])
        XCTAssertEqual(result.archived, ["b", "d"])
    }

    func testArchivePartitionEmptyArchive() {
        let result = SideChatArchive.partition([1, 2], key: { "local:\($0)" }, archivedKeys: [])
        XCTAssertEqual(result.visible, [1, 2])
        XCTAssertTrue(result.archived.isEmpty)
    }

    func testIsArchivedChecks() {
        let keys: Set<String> = [SideChatArchive.localKey(mainID), SideChatArchive.serverKey("s9")]
        XCTAssertTrue(SideChatArchive.isArchived(localThreadID: mainID, archivedKeys: keys))
        XCTAssertFalse(SideChatArchive.isArchived(localThreadID: sideID, archivedKeys: keys))
        XCTAssertTrue(SideChatArchive.isArchived(serverSessionID: "s9", archivedKeys: keys))
        XCTAssertFalse(SideChatArchive.isArchived(serverSessionID: "s8", archivedKeys: keys))
    }

    // MARK: 回告只入主线

    private func notification(_ id: String, read: Bool) -> OverviewNotification {
        OverviewNotification(id: id, kind: "write_gate_decision", title: "t", body: "b", createdAt: "", read: read)
    }

    func testReportCardsEmptyOffMainThread() {
        let cards = ReportCardPolicy.cards(
            notifications: [notification("1", read: false)], isMainThread: false
        )
        XCTAssertTrue(cards.isEmpty)
    }

    func testReportCardsOnlyUnreadOnMainThread() {
        let cards = ReportCardPolicy.cards(
            notifications: [notification("1", read: true), notification("2", read: false)],
            isMainThread: true
        )
        XCTAssertEqual(cards.map(\.id), ["2"])
    }

    func testReportCardsRespectLimitAndOrder() {
        let items = (1...5).map { notification("\($0)", read: false) }
        let cards = ReportCardPolicy.cards(notifications: items, isMainThread: true, limit: 3)
        XCTAssertEqual(cards.map(\.id), ["1", "2", "3"])
    }

    // MARK: 建会话回执解码

    func testCreatedSessionDecodesWrappedShape() throws {
        let json = #"{"session": {"id": "oneday-main-1", "source": "api_server"}}"#
        let created = try JSONDecoder().decode(CreatedSession.self, from: Data(json.utf8))
        XCTAssertEqual(created.session.id, "oneday-main-1")
    }

    func testCreatedSessionDecodesBareShape() throws {
        let json = #"{"id": "oneday-main-2", "source": "api_server"}"#
        let created = try JSONDecoder().decode(CreatedSession.self, from: Data(json.utf8))
        XCTAssertEqual(created.session.id, "oneday-main-2")
    }
}
