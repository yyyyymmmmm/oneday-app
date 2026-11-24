import OneDayCore
import XCTest

/// 历史双向同步的纯判定钉测（根治版包 2，DESIGN
/// §331）：稳定 request_id 派生、种子同步态口径、
/// 回补指纹去重、进度文案单位口径
final class SessionHistorySyncTests: XCTestCase {

    // MARK: - 稳定 request_id（幂等第一层）

    private func seed(_ pairs: [(String, String, Double?)]) -> [SeedEntry] {
        pairs.map {
            SeedEntry(role: $0.0, content: $0.1, timestamp: $0.2)
        }
    }

    func testSeedRequestIDIsStableForSameSeed() {
        let messages = seed([
            ("user", "你好", 1000), ("assistant", "你好，我在", 1001),
        ])
        let first = SideChatLink.seedRequestID(
            sessionID: "oneday-side-x", messages: messages
        )
        let second = SideChatLink.seedRequestID(
            sessionID: "oneday-side-x", messages: messages
        )
        // 同种子重试恒同 id：围栏按 id 重放收据、不
        // 二次落种——这是后台重试敢重试的前提
        XCTAssertEqual(first, second)
        XCTAssertTrue(first.hasPrefix("import-oneday-side-x-"))
    }

    func testSeedRequestIDChangesWithSeedOrSession() {
        let base = seed([("user", "你好", 1000)])
        let baseID = SideChatLink.seedRequestID(
            sessionID: "oneday-side-x", messages: base
        )
        // 内容变（本地又攒了历史）→ 新 id，不撞旧收据
        let grown = seed([("user", "你好", 1000), ("user", "再问", 1002)])
        XCTAssertNotEqual(
            baseID,
            SideChatLink.seedRequestID(
                sessionID: "oneday-side-x", messages: grown
            )
        )
        // 时间戳参与摘要：同文不同刻是两份种子
        let retimed = seed([("user", "你好", 2000)])
        XCTAssertNotEqual(
            baseID,
            SideChatLink.seedRequestID(
                sessionID: "oneday-side-x", messages: retimed
            )
        )
        // 目标会话不同 → id 不同
        XCTAssertNotEqual(
            baseID,
            SideChatLink.seedRequestID(
                sessionID: "oneday-side-y", messages: base
            )
        )
        // 空种子也有确定值（摘要定义域完整）
        XCTAssertEqual(
            SideChatLink.seedRequestID(
                sessionID: "oneday-side-x", messages: []
            ),
            SideChatLink.seedRequestID(
                sessionID: "oneday-side-x", messages: []
            )
        )
    }

    // MARK: - 种子同步态

    func testSeedSyncStateStoredValueFallback() {
        XCTAssertEqual(SeedSyncState(storedValue: "pending"), .pending)
        XCTAssertEqual(
            SeedSyncState(storedValue: "syncedTextOnly"), .syncedTextOnly
        )
        // 未知原文/缺失一律回 notOwed：不许凭空造义务
        XCTAssertEqual(SeedSyncState(storedValue: "garbage"), .notOwed)
        XCTAssertEqual(SeedSyncState(storedValue: nil), .notOwed)
    }

    func testSeedSyncStateNeedsSyncAttempt() {
        XCTAssertTrue(SeedSyncState.pending.needsSyncAttempt)
        XCTAssertTrue(SeedSyncState.failed.needsSyncAttempt)
        for state in [
            SeedSyncState.notOwed, .importing, .syncedTextOnly,
            .serverHeld, .localOnly,
        ] {
            XCTAssertFalse(state.needsSyncAttempt)
        }
    }

    // MARK: - 回补指纹去重

    private func item(
        role: String, content: String, at epoch: Double
    ) -> SessionHistoryImport.RichItem {
        SessionHistoryImport.RichItem(
            role: role, content: content,
            date: Date(timeIntervalSince1970: epoch),
            imagePaths: [], toolCard: nil
        )
    }

    func testUnseenItemsDedupAgainstExistingAndWithinBatch() {
        let existing = SessionHistorySync.fingerprint(
            of: item(role: "user", content: "一问", at: 1000)
        )
        let batch = [
            item(role: "user", content: "一问", at: 1000),
            item(role: "assistant", content: "一答", at: 1001),
            item(role: "assistant", content: "一答", at: 1001),
            item(role: "user", content: "二问", at: 1002),
        ]
        let unseen = SessionHistorySync.unseenItems(
            batch, existing: [existing]
        )
        // 已落的一问剔除、批内自重的一答只留一条
        XCTAssertEqual(unseen.map(\.content), ["一答", "二问"])
    }

    func testFingerprintDistinguishesRoleAndTime() {
        let base = SessionHistorySync.fingerprint(
            of: item(role: "user", content: "同文", at: 1000)
        )
        XCTAssertNotEqual(
            base,
            SessionHistorySync.fingerprint(
                of: item(role: "assistant", content: "同文", at: 1000)
            )
        )
        XCTAssertNotEqual(
            base,
            SessionHistorySync.fingerprint(
                of: item(role: "user", content: "同文", at: 1001)
            )
        )
    }

    // MARK: - 进度文案

    func testProgressTextKeepsUnitsSeparate() {
        // 分子分母不同单位（本地条目 vs 服务端原始
        // 消息）：分开报、不许拼成比例
        XCTAssertEqual(
            SessionHistorySync.progressText(loaded: 12, serverTotal: 30),
            "已载入 12 条（服务端共 30 条）"
        )
        XCTAssertEqual(
            SessionHistorySync.progressText(loaded: 12, serverTotal: 0),
            "已载入 12 条"
        )
    }

    // MARK: - 收敛包：指纹单源（P4-1）

    /// 同一条带引用消息：拉回项（线格式经 richItems
    /// 拆解）与本地条目零件（干净正文＋引用槽位）经
    /// 同一组装点必须同指纹——旧口径两边各喂原文恒
    /// 不等、回补必再插一行
    func testFingerprintMatchesAcrossWireAndLocalParts() {
        let items = SessionHistoryImport.richItems(from: [
            SessionMessage(
                id: 21, role: "user",
                content: "[引用 Hermes 的消息]\n旧回复\n\n就这条展开",
                timestamp: 1762000200, displayKind: nil
            ),
        ])
        XCTAssertEqual(items.count, 1)
        let itemPrint = SessionHistorySync.fingerprint(of: items[0])
        let localPrint = SessionHistorySync.fingerprint(
            role: "user",
            date: Date(timeIntervalSince1970: 1762000200),
            content: "就这条展开",
            quote: MessageQuote(role: "assistant", content: "旧回复"),
            attachmentPaths: [], toolCardID: nil
        )
        XCTAssertEqual(itemPrint, localPrint)
    }

    /// 引用参与同一性：同正文、引用有无/不同 → 指纹
    /// 不同，不许只比正文把两条不同的消息判成一条
    func testFingerprintDistinguishesQuote() {
        let date = Date(timeIntervalSince1970: 1000)
        let plain = SessionHistorySync.fingerprint(
            role: "user", date: date, content: "正文",
            quote: nil, attachmentPaths: [], toolCardID: nil
        )
        let quoted = SessionHistorySync.fingerprint(
            role: "user", date: date, content: "正文",
            quote: MessageQuote(role: "user", content: "被引"),
            attachmentPaths: [], toolCardID: nil
        )
        let otherQuoted = SessionHistorySync.fingerprint(
            role: "user", date: date, content: "正文",
            quote: MessageQuote(role: "user", content: "另一条"),
            attachmentPaths: [], toolCardID: nil
        )
        XCTAssertNotEqual(plain, quoted)
        XCTAssertNotEqual(quoted, otherQuoted)
    }

    /// unseenItems 判同回归钉：本地已有带引用条目
    /// （其指纹以本地零件组装、在 existing 里）时，
    /// 线格式拉回项判已在、不再入选
    func testUnseenItemsTreatsQuotedWireItemAsSeen() {
        let localPrint = SessionHistorySync.fingerprint(
            role: "user",
            date: Date(timeIntervalSince1970: 1762000300),
            content: "展开讲讲",
            quote: MessageQuote(role: "assistant", content: "原回答"),
            attachmentPaths: [], toolCardID: nil
        )
        let items = SessionHistoryImport.richItems(from: [
            SessionMessage(
                id: 31, role: "user",
                content: "[引用 Hermes 的消息]\n原回答\n\n展开讲讲",
                timestamp: 1762000300, displayKind: nil
            ),
        ])
        let unseen = SessionHistorySync.unseenItems(
            items, existing: [localPrint]
        )
        XCTAssertTrue(unseen.isEmpty)
    }

}
