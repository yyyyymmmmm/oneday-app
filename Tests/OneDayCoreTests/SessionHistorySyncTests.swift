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
}
