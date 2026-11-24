import XCTest
@testable import OneDayApp
import OneDayCore

/// §374.3 结构钉测：单 section 化的形态把守——
/// ①「布局失效不在 apply 同步链内执行」不变量
/// （§325.2/.66 崩溃链防线，自本步起改结构钉
/// 测永久把守）：全文件 .invalidateLayout() 调
/// 用点恰一处、且在落定拍 performSettleBeat 体
/// 内；喂入链（applyNow/applyChangesNow/重建
/// 路）与两布局构造体内不许出现；
/// ②高度账按键形态：布局匣以 heightByKey 按键
/// 存取＋rowOrder 行序，§329 平行四表（row-
/// Heights/provisionalFlags/rowKeys/rowRevi-
/// sions）不许回潮；
/// ③单 section 构造与开关穿线在场（防把构造改
/// 空的假绿）：makeSingleSection／条目级增量
/// 编辑原语／Core 开关三件
final class ChatSwapStep3StructureTests: XCTestCase {

    private func source(_ relative: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let srcURL = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relative)
        return try String(contentsOf: srcURL, encoding: .utf8)
    }

    private func body(
        of src: String, from startToken: String,
        to endToken: String
    ) throws -> String {
        let start = try XCTUnwrap(
            src.range(of: startToken),
            "\(startToken) 必须存在"
        )
        let end = try XCTUnwrap(
            src.range(
                of: endToken,
                range: start.upperBound..<src.endIndex
            ),
            "\(endToken) 必须在 \(startToken) 之后存在"
        )
        return String(src[start.lowerBound..<end.lowerBound])
    }

    func testLayoutInvalidationOnlyExecutesInSettleBeat()
        throws {
        let src = try source(
            "Sources/OneDayApp/ChatNativeList.swift"
        )
        // 全文件调用点恰一处
        let occurrences = src.components(
            separatedBy: ".invalidateLayout()"
        ).count - 1
        XCTAssertEqual(
            occurrences, 1,
            "§374.3：.invalidateLayout() 全文件只许落定拍一处，实测 \(occurrences) 处"
        )
        // 该处在 performSettleBeat 体内（以其后最近
        // 的滚动回调为界）
        let beat = try body(
            of: src,
            from: "private func performSettleBeat()",
            to: "func scrollViewDidScroll("
        )
        XCTAssertTrue(
            beat.contains(".invalidateLayout()"),
            "§374.3：布局失效施工点须在落定拍体内"
        )
        // 喂入链与布局构造体内不许出现调用形态
        for (start, end) in [
            ("private func applyNow(",
             "private func applyChangesNow("),
            ("private func applyChangesNow(",
             "private func applyChangesFullRebuild("),
            ("private func applyChangesFullRebuild(",
             "private func partitionSelectionStaged"),
            ("private static func makeRowSection(",
             "private static func makeSingleSection("),
            ("private static func makeSingleSection(",
             "override func viewDidLoad()"),
        ] {
            let slice = try body(
                of: src, from: start, to: end
            )
            XCTAssertFalse(
                slice.contains(".invalidateLayout()"),
                "§374.3：\(start) 内不许执行布局失效（只许记账、施工归落定拍）"
            )
        }
    }

    func testHeightLedgerIsKeyedByRowKey() throws {
        let src = try source(
            "Sources/OneDayApp/ChatNativeList.swift"
        )
        XCTAssertTrue(
            src.contains(
                "var heightByKey: [String: HeightEntry]"
            ),
            "§374.3：高度账须按键存取（heightByKey）"
        )
        XCTAssertTrue(
            src.contains("var rowOrder: [String]"),
            "§374.3：行序真源须只余行键一列（rowOrder）"
        )
        for token in [
            "var rowHeights: [CGFloat]",
            "var provisionalFlags: [Bool]",
            "var rowKeys: [String]",
            "var rowRevisions:",
        ] {
            XCTAssertFalse(
                src.contains(token),
                "§374.3：平行表 \(token) 已退役、不许回潮"
            )
        }
    }

    func testSingleSectionConstructionIsWired() throws {
        let src = try source(
            "Sources/OneDayApp/ChatNativeList.swift"
        )
        for token in [
            "makeSingleSection",
            "ChatListSingleSectionFeature",
            "snapshot.deleteItems(",
            "snapshot.insertItems(",
            "func refreshSingleSectionMode()",
            "var testSingleSectionOverride: Bool?",
        ] {
            XCTAssertTrue(
                src.contains(token),
                "§374.3：单 section 穿线应含 \(token)"
            )
        }
        // 开关本体口径（Core）：键名与缺省开（0.50.97 组版转正）
        XCTAssertEqual(
            ChatListSingleSectionFeature.defaultsKey,
            "chatListSingleSectionEnabled"
        )
        let defaults = UserDefaults(
            suiteName: "swap3-structure-\(UUID().uuidString)"
        )!
        XCTAssertTrue(
            ChatListSingleSectionFeature.isEnabled(
                defaults: defaults
            ),
            "§374.3/§377：单 section 开关缺省须开（0.50.97 组版转正、键不存在＝开）"
        )
        defaults.set(
            false,
            forKey: ChatListSingleSectionFeature.defaultsKey
        )
        XCTAssertFalse(
            ChatListSingleSectionFeature.isEnabled(
                defaults: defaults
            ),
            "§377：显式 false 须关（回退口完好）"
        )
        defaults.set(
            true,
            forKey: ChatListSingleSectionFeature.defaultsKey
        )
        XCTAssertTrue(
            ChatListSingleSectionFeature.isEnabled(
                defaults: defaults
            )
        )
    }
}
