import XCTest
@testable import OneDayApp
import OneDayCore

/// §374.8 结构钉测：选区保护简化的形态把守——
/// ①Core 开关口径（键名、缺省＝单键暂缓在场、
/// 显式置假＝暂缓停用）；②触摸序列门全套机
/// 构在生产源码零残留（状态机／观察识别器／
/// 暂存旧名／双击间隔／hitTest 判读／0.3s 续
/// 排，禁词普查 Sources 两目录全部 Swift 文
/// 件）；③单键规则穿线在场（开关引用＋测试
/// 覆盖口＋分流函数＋待补账＋flush 落写口＋
/// 设置页同键开关）
final class ChatSwapStep5StructureTests: XCTestCase {

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func source(_ relative: String) throws -> String {
        try String(
            contentsOf: repoRoot()
                .appendingPathComponent(relative),
            encoding: .utf8
        )
    }

    func testSelectionKeyGuardFeatureDefaultsToArmed() {
        XCTAssertEqual(
            ChatListSelectionKeyGuardFeature.defaultsKey,
            "chat.list.selectionKeyGuard"
        )
        let defaults = UserDefaults(
            suiteName: "swap5-structure-\(UUID().uuidString)"
        )!
        XCTAssertTrue(
            ChatListSelectionKeyGuardFeature.isEnabled(
                defaults: defaults
            ),
            "§374.8：选区单键暂缓开关缺省（键不存在）须为在场"
        )
        defaults.set(
            false,
            forKey: ChatListSelectionKeyGuardFeature
                .defaultsKey
        )
        XCTAssertFalse(
            ChatListSelectionKeyGuardFeature.isEnabled(
                defaults: defaults
            ),
            "§374.8：显式置假须停用暂缓（应急档）"
        )
        defaults.set(
            true,
            forKey: ChatListSelectionKeyGuardFeature
                .defaultsKey
        )
        XCTAssertTrue(
            ChatListSelectionKeyGuardFeature.isEnabled(
                defaults: defaults
            )
        )
    }

    /// 禁词普查：§332 序列门机构不许以任何代码
    /// 形态回潮生产源码（注释里的历史 prose 不
    /// 在禁列、禁的是类型/属性/函数/常量本体）
    func testTouchSequenceGateMachineryAbsentFromSources()
        throws
    {
        let banned = [
            "TouchSequenceGate",
            "touchSequence",
            "TouchObserver",
            "touchObserver",
            "touchStaged",
            "TouchStaged",
            "doubleTapInterval",
            "hitTestLandsOnTextView",
            "scheduleSettle(delay: 0.3)",
        ]
        var scanned = 0
        for dir in ["Sources/OneDayApp", "Sources/OneDayCore"] {
            let dirURL = repoRoot()
                .appendingPathComponent(dir)
            let fileURLs = FileManager.default
                .enumerator(
                    at: dirURL,
                    includingPropertiesForKeys: nil
                )?.allObjects as? [URL] ?? []
            for fileURL in fileURLs
            where fileURL.pathExtension == "swift" {
                scanned += 1
                let text = try String(
                    contentsOf: fileURL, encoding: .utf8
                )
                for token in banned {
                    XCTAssertFalse(
                        text.contains(token),
                        "\(fileURL.lastPathComponent) 不许残留序列门机构 token：\(token)"
                    )
                }
            }
        }
        XCTAssertGreaterThan(
            scanned, 30,
            "普查须真扫到生产文件（防空转假绿）"
        )
    }

    func testSelectionKeyWiringPresent() throws {
        let list = try source(
            "Sources/OneDayApp/ChatNativeList.swift"
        )
        for token in [
            "ChatListSelectionKeyGuardFeature",
            "var testSelectionKeyGuardOverride: Bool?",
            "func partitionSelectionStaged(",
            "selectionStagedReconfigureKeys",
            "func flushSelectionStagedReconfigures()",
            "func selectionProtectionEnded()",
            "var selectionActiveRowKey: String?",
        ] {
            XCTAssertTrue(
                list.contains(token),
                "ChatNativeList.swift 缺单键规则穿线：\(token)"
            )
        }
        let settings = try source(
            "Sources/OneDayApp/ChatDiagnosticsView.swift"
        )
        XCTAssertTrue(
            settings.contains(
                "ChatListSelectionKeyGuardFeature.defaultsKey"
            ),
            "设置页须有选区单键暂缓同键回退开关"
        )
    }
}
