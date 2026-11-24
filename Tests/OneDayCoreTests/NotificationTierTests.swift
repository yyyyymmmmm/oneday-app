import XCTest
@testable import OneDayCore

/// 通知分级矩阵钉测（总表 162，DESIGN §385）：分类
/// 只认结构信号、矩阵口径钉死、偏好同键回读一致、
/// 提醒规划的基线/去重/开关/分级四闸逐个把守
final class NotificationTierTests: XCTestCase {

    private func item(
        id: String, kind: String, read: Bool = false
    ) -> OverviewNotification {
        OverviewNotification(
            id: id, kind: kind, title: "标题", body: "正文",
            createdAt: "2026-11-23T00:00:00Z", read: read
        )
    }

    // MARK: - 分类（结构信号）

    func testCategoryFromStructuralSignals() {
        XCTAssertEqual(
            NotificationTier.category(
                for: item(id: "1", kind: "write_gate_decision")
            ),
            .approval
        )
        XCTAssertEqual(
            NotificationTier.category(
                for: item(id: "2", kind: "task_completed")
            ),
            .runCompleted
        )
        XCTAssertEqual(
            NotificationTier.category(
                for: item(id: "3", kind: "monitor_change")
            ),
            .system
        )
        XCTAssertEqual(
            NotificationTier.category(
                for: item(id: "4", kind: "something_unknown")
            ),
            .system
        )
    }

    /// 失败类预留口（§385 缺口 G1）：服务端补出失败
    /// kind 后，含 fail/error 信号者自动归失败类
    func testCategoryFailureReservedSignals() {
        XCTAssertEqual(
            NotificationTier.category(
                for: item(id: "1", kind: "task_failed")
            ),
            .failure
        )
        XCTAssertEqual(
            NotificationTier.category(
                for: item(id: "2", kind: "run_error")
            ),
            .failure
        )
    }

    // MARK: - 矩阵

    func testTierMatrix() {
        XCTAssertEqual(
            NotificationTier.tier(for: .approval), .interrupt
        )
        XCTAssertEqual(
            NotificationTier.tier(for: .failure), .interrupt
        )
        XCTAssertEqual(
            NotificationTier.tier(for: .runCompleted), .inbox
        )
        XCTAssertEqual(
            NotificationTier.tier(for: .system), .badgeOnly
        )
    }

    // MARK: - 偏好（同键回读）

    func testPreferenceKeysAreStable() {
        XCTAssertEqual(
            NotificationTier.Category.approval.preferenceKey,
            "notify.category.approval.enabled"
        )
        XCTAssertEqual(
            NotificationTier.Category.runCompleted.preferenceKey,
            "notify.category.runCompleted.enabled"
        )
        XCTAssertEqual(
            NotificationTier.Category.failure.preferenceKey,
            "notify.category.failure.enabled"
        )
        XCTAssertEqual(
            NotificationTier.Category.system.preferenceKey,
            "notify.category.system.enabled"
        )
    }

    func testPreferenceDefaultsOnAndReadsBackWrites() {
        let defaults = UserDefaults(
            suiteName: "tier-prefs-\(UUID().uuidString)"
        )!
        for category in NotificationTier.Category.allCases {
            XCTAssertTrue(
                NotificationTierPreferences.isEnabled(
                    category, defaults: defaults
                ),
                "\(category) 缺省须为开"
            )
        }
        NotificationTierPreferences.setEnabled(
            .approval, false, defaults: defaults
        )
        // 回读以同一 UserDefaults 实值为准
        XCTAssertFalse(
            defaults.bool(
                forKey: NotificationTier.Category.approval
                    .preferenceKey
            )
        )
        XCTAssertFalse(
            NotificationTierPreferences.isEnabled(
                .approval, defaults: defaults
            )
        )
        XCTAssertTrue(
            NotificationTierPreferences.isEnabled(
                .system, defaults: defaults
            ),
            "关一类不许牵动他类"
        )
        NotificationTierPreferences.setEnabled(
            .approval, true, defaults: defaults
        )
        XCTAssertTrue(
            NotificationTierPreferences.isEnabled(
                .approval, defaults: defaults
            )
        )
    }

    // MARK: - 提醒规划

    func testPlannerBaselineSeedsWithoutAlerting() {
        let items = [
            item(id: "a", kind: "write_gate_decision"),
            item(id: "b", kind: "task_completed"),
        ]
        let plan = NotificationAlertPlanner.plan(
            items: items, seenIDs: [],
            isCategoryEnabled: { _ in true }
        )
        XCTAssertTrue(
            plan.directives.isEmpty,
            "首见基线只登记不发，防积压补发成风暴"
        )
        XCTAssertEqual(plan.seenIDs, ["a", "b"])
    }

    func testPlannerAlertsOnlyNewUnreadEnabledNonBadge() {
        let seen: Set<String> = ["old"]
        let items = [
            // 已提醒过：不再发
            item(id: "old", kind: "write_gate_decision"),
            // 新到未读审批：即时打断，发
            item(id: "n1", kind: "write_gate_decision"),
            // 新到未读完成：静默入盒，发
            item(id: "n2", kind: "task_completed"),
            // 新到未读系统：仅角标，不发
            item(id: "n3", kind: "monitor_change"),
            // 新到已读：不发
            item(id: "n4", kind: "write_gate_decision", read: true),
        ]
        let plan = NotificationAlertPlanner.plan(
            items: items, seenIDs: seen,
            isCategoryEnabled: { _ in true }
        )
        XCTAssertEqual(
            plan.directives.map(\.notificationID), ["n1", "n2"]
        )
        XCTAssertEqual(plan.directives[0].tier, .interrupt)
        XCTAssertEqual(plan.directives[1].tier, .inbox)
        XCTAssertEqual(
            plan.seenIDs, ["old", "n1", "n2", "n3", "n4"],
            "不发的也要登记，下轮不重复判"
        )
    }

    func testPlannerRespectsCategorySwitch() {
        let items = [
            item(id: "n1", kind: "write_gate_decision"),
            item(id: "n2", kind: "task_completed"),
        ]
        let plan = NotificationAlertPlanner.plan(
            items: items, seenIDs: ["seed"],
            isCategoryEnabled: { $0 != .approval }
        )
        XCTAssertEqual(
            plan.directives.map(\.notificationID), ["n2"],
            "关掉的类不发提醒，但仍登记已见"
        )
        XCTAssertEqual(plan.seenIDs, ["seed", "n1", "n2"])
    }
}
