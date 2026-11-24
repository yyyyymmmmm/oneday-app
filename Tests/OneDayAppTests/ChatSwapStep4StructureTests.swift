import XCTest
@testable import OneDayApp
import OneDayCore

/// §374.4 结构钉测：时间窗合并删除的形态把
/// 守——①Core 开关口径（键名、缺省＝已删、显
/// 式置假恢复窗）；②控制器穿线在场（开关引
/// 用＋测试覆盖口＋删窗判定函数）；③窗代码本
/// 体以开关包裹保留（窗长常量与窗闸条件不许
/// 被物理删掉——回退口须真实可用）；④设置页
/// 回退开关同键在场
final class ChatSwapStep4StructureTests: XCTestCase {

    private func source(_ relative: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let srcURL = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relative)
        return try String(contentsOf: srcURL, encoding: .utf8)
    }

    func testDropFeatureDefaultsToDropped() throws {
        XCTAssertEqual(
            ChatListCoalesceWindowDropFeature.defaultsKey,
            "chat.list.dropCoalesceWindow"
        )
        let defaults = UserDefaults(
            suiteName: "swap4-structure-\(UUID().uuidString)"
        )!
        XCTAssertTrue(
            ChatListCoalesceWindowDropFeature.isEnabled(
                defaults: defaults
            ),
            "§374.4：删窗开关缺省（键不存在）须为已删"
        )
        defaults.set(
            false,
            forKey: ChatListCoalesceWindowDropFeature
                .defaultsKey
        )
        XCTAssertFalse(
            ChatListCoalesceWindowDropFeature.isEnabled(
                defaults: defaults
            ),
            "§374.4：显式置假须恢复时间窗合并（回退口）"
        )
        defaults.set(
            true,
            forKey: ChatListCoalesceWindowDropFeature
                .defaultsKey
        )
        XCTAssertTrue(
            ChatListCoalesceWindowDropFeature.isEnabled(
                defaults: defaults
            )
        )
    }

    func testWindowGateWiringAndWindowBodyRetained() throws {
        let src = try source(
            "Sources/OneDayApp/ChatNativeList.swift"
        )
        for token in [
            "ChatListCoalesceWindowDropFeature",
            "var testCoalesceWindowDropOverride: Bool?",
            "func coalesceWindowDropped()",
            // 窗本体保留（开关包裹、未物理删除）：
            // 窗长常量与窗闸条件仍在，回退口真实
            "layoutCoalesceWindow",
            "lastLayoutFlushAt",
        ] {
            XCTAssertTrue(
                src.contains(token),
                "§374.4：ChatNativeList 应含 \(token)"
            )
        }
        let settings = try source(
            "Sources/OneDayApp/ChatDiagnosticsView.swift"
        )
        XCTAssertTrue(
            settings.contains(
                "ChatListCoalesceWindowDropFeature.defaultsKey"
            ),
            "§374.4：设置页回退开关须与控制器同键同源"
        )
    }
}
