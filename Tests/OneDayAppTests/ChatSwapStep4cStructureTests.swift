import XCTest
@testable import OneDayApp
import OneDayCore

/// §374.6 结构钉测：抽屉动画期冻结删除的形态把
/// 守——①Core 开关口径（键名、缺省＝冻结已删、
/// 显式置假恢复冻结）；②控制器穿线在场（开关
/// 引用＋测试覆盖口＋删冻判定函数＋喂入冻结判
/// 据与落定拍两处判定点）；③冻结代码本体以开
/// 关包裹保留（运动窗信号读口／冻结记账旗／唤
/// 醒拍认领不许被物理删掉——回退口须真实可
/// 用）；④设置页回退开关同键在场
final class ChatSwapStep4cStructureTests: XCTestCase {

    private func source(_ relative: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let srcURL = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relative)
        return try String(contentsOf: srcURL, encoding: .utf8)
    }

    func testDrawerFreezeDropFeatureDefaultsToDropped() throws {
        XCTAssertEqual(
            ChatListDrawerFreezeDropFeature.defaultsKey,
            "chat.list.dropDrawerFreeze"
        )
        let defaults = UserDefaults(
            suiteName: "swap4c-structure-\(UUID().uuidString)"
        )!
        XCTAssertTrue(
            ChatListDrawerFreezeDropFeature.isEnabled(
                defaults: defaults
            ),
            "§374.6：抽屉冻结删除开关缺省（键不存在）须为冻结已删"
        )
        defaults.set(
            false,
            forKey: ChatListDrawerFreezeDropFeature
                .defaultsKey
        )
        XCTAssertFalse(
            ChatListDrawerFreezeDropFeature.isEnabled(
                defaults: defaults
            ),
            "§374.6：显式置假须恢复抽屉动画期冻结（回退口）"
        )
        defaults.set(
            true,
            forKey: ChatListDrawerFreezeDropFeature
                .defaultsKey
        )
        XCTAssertTrue(
            ChatListDrawerFreezeDropFeature.isEnabled(
                defaults: defaults
            )
        )
    }

    func testDrawerFreezeDropWiringAndFreezeBodyRetained() throws {
        let src = try source(
            "Sources/OneDayApp/ChatNativeList.swift"
        )
        for token in [
            "ChatListDrawerFreezeDropFeature",
            "var testDrawerFreezeDropOverride: Bool?",
            "func drawerFreezeDropped()",
            // 两处判定点：喂入冻结判据与落定拍
            // 冻结分支均以删冻判定为首位条件
            "drawerFreezeDropped()\n            ? false",
            "!drawerFreezeDropped()",
            // 冻结本体保留（开关包裹、未物理删
            // 除）：运动窗信号读口、冻结记账旗与
            // 唤醒拍认领仍在，回退口真实
            "drawerMotionInFlight",
            "drawerMotionDeadline",
            "settleDeferredDuringDrawer",
        ] {
            XCTAssertTrue(
                src.contains(token),
                "§374.6：ChatNativeList 应含 \(token)"
            )
        }
        let settings = try source(
            "Sources/OneDayApp/ChatDiagnosticsView.swift"
        )
        XCTAssertTrue(
            settings.contains(
                "ChatListDrawerFreezeDropFeature.defaultsKey"
            ),
            "§374.6：设置页回退开关须与控制器同键同源"
        )
    }
}
