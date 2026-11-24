import XCTest
@testable import OneDayApp
import OneDayCore

/// §374.7 结构钉测：滚动闸记账降级的形态把
/// 守——①Core 开关口径（键名、缺省＝已降级、
/// 显式置假恢复现行闸）；②控制器穿线在场（开
/// 关引用＋测试覆盖口＋降级判定函数＋停滚落
/// 写口的降级分支）；③现行闸本体以开关包裹
/// 保留（武装结清阶段行／记账槽／入槽合成不
/// 许被物理删掉——回退口须真实可用）；④设
/// 置页回退开关同键在场
final class ChatSwapStep4dStructureTests: XCTestCase {

    private func source(_ relative: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let srcURL = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relative)
        return try String(contentsOf: srcURL, encoding: .utf8)
    }

    func testScrollLedgerFeatureDefaultsToDowngraded() throws {
        XCTAssertEqual(
            ChatListScrollLedgerFeature.defaultsKey,
            "chat.list.scrollLedger"
        )
        let defaults = UserDefaults(
            suiteName: "swap4d-structure-\(UUID().uuidString)"
        )!
        XCTAssertTrue(
            ChatListScrollLedgerFeature.isEnabled(
                defaults: defaults
            ),
            "§374.7：滚动闸降级开关缺省（键不存在）须为已降级"
        )
        defaults.set(
            false,
            forKey: ChatListScrollLedgerFeature
                .defaultsKey
        )
        XCTAssertFalse(
            ChatListScrollLedgerFeature.isEnabled(
                defaults: defaults
            ),
            "§374.7：显式置假须恢复现行滚动闸（回退口）"
        )
        defaults.set(
            true,
            forKey: ChatListScrollLedgerFeature
                .defaultsKey
        )
        XCTAssertTrue(
            ChatListScrollLedgerFeature.isEnabled(
                defaults: defaults
            )
        )
    }

    func testScrollLedgerWiringAndGateBodyRetained() throws {
        let src = try source(
            "Sources/OneDayApp/ChatNativeList.swift"
        )
        for token in [
            "ChatListScrollLedgerFeature",
            "var testScrollLedgerOverride: Bool?",
            "func scrollLedgerDowngraded()",
            // 降级分支：停滚落写口以判定为首位条
            // 件、回调点当场应用记账槽
            "if scrollLedgerDowngraded() {",
            // 现行闸本体保留（开关包裹、未物理删
            // 除）：武装结清阶段行、记账槽、入槽
            // 合成与槽消费口仍在，回退口真实
            "settleClearingStage = settleSingleBeat() ? 2 : 1",
            "private var pendingApply: PendingApply?",
            "func storePendingFeed(",
            "func applyPendingFeed(",
        ] {
            XCTAssertTrue(
                src.contains(token),
                "§374.7：ChatNativeList 应含 \(token)"
            )
        }
        let settings = try source(
            "Sources/OneDayApp/ChatDiagnosticsView.swift"
        )
        XCTAssertTrue(
            settings.contains(
                "ChatListScrollLedgerFeature.defaultsKey"
            ),
            "§374.7：设置页回退开关须与控制器同键同源"
        )
    }
}
