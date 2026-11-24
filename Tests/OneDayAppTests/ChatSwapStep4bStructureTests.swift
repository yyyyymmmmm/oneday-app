import XCTest
@testable import OneDayApp
import OneDayCore

/// §374.5 结构钉测：停滚结清单拍结清的形态把
/// 守——①Core 开关口径（键名、缺省＝单拍结
/// 清、显式置假恢复拆拍）；②控制器穿线在场
/// （开关引用＋测试覆盖口＋单拍判定函数＋停
/// 滚落写口的武装分支）；③拆拍代码本体以开
/// 关包裹保留（阶段变量与拆拍顺延常量不许被
/// 物理删掉——回退口须真实可用）；④设置页
/// 回退开关同键在场
final class ChatSwapStep4bStructureTests: XCTestCase {

    private func source(_ relative: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let srcURL = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relative)
        return try String(contentsOf: srcURL, encoding: .utf8)
    }

    func testSettleSingleBeatFeatureDefaultsToSingleBeat() throws {
        XCTAssertEqual(
            ChatListSettleSingleBeatFeature.defaultsKey,
            "chat.list.settleSingleBeat"
        )
        let defaults = UserDefaults(
            suiteName: "swap4b-structure-\(UUID().uuidString)"
        )!
        XCTAssertTrue(
            ChatListSettleSingleBeatFeature.isEnabled(
                defaults: defaults
            ),
            "§374.5：单拍结清开关缺省（键不存在）须为单拍结清"
        )
        defaults.set(
            false,
            forKey: ChatListSettleSingleBeatFeature
                .defaultsKey
        )
        XCTAssertFalse(
            ChatListSettleSingleBeatFeature.isEnabled(
                defaults: defaults
            ),
            "§374.5：显式置假须恢复停滚结清拆拍（回退口）"
        )
        defaults.set(
            true,
            forKey: ChatListSettleSingleBeatFeature
                .defaultsKey
        )
        XCTAssertTrue(
            ChatListSettleSingleBeatFeature.isEnabled(
                defaults: defaults
            )
        )
    }

    func testSingleBeatWiringAndSplitBodyRetained() throws {
        let src = try source(
            "Sources/OneDayApp/ChatNativeList.swift"
        )
        for token in [
            "ChatListSettleSingleBeatFeature",
            "var testSettleSingleBeatOverride: Bool?",
            "func settleSingleBeat()",
            "settleSingleBeat() ? 2 : 1",
            // 拆拍本体保留（开关包裹、未物理删
            // 除）：阶段变量与拆拍顺延常量仍在，
            // 回退口真实
            "settleClearingStage",
            "settleSplitBeatDelay",
        ] {
            XCTAssertTrue(
                src.contains(token),
                "§374.5：ChatNativeList 应含 \(token)"
            )
        }
        let settings = try source(
            "Sources/OneDayApp/ChatDiagnosticsView.swift"
        )
        XCTAssertTrue(
            settings.contains(
                "ChatListSettleSingleBeatFeature.defaultsKey"
            ),
            "§374.5：设置页回退开关须与控制器同键同源"
        )
    }
}
