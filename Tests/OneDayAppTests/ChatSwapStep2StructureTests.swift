import XCTest

/// §374.2 结构钉测：控制器去对账的形态把守——
/// applyChangesNow（增量路本体）源码内不许出现
/// 整表对账形态（整表行字典构建/全量修订比较/
/// 修订账整表重建）；整笔重建只许在具名重建路
/// applyChangesFullRebuild 内。另把守穿线三件：
/// Representable 按 changeSet 有无分路、Chat-
/// View 交付追踪器变更集、EntryChangeSet 载
/// §374.2 两字段与合成函数。源码级把守的理由
/// 同 §371/§373：全量对账是性能病、运行期断言
/// 测不出「又把整表算了一遍」
final class ChatSwapStep2StructureTests: XCTestCase {

    private func source(_ relative: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let srcURL = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relative)
        return try String(contentsOf: srcURL, encoding: .utf8)
    }

    func testApplyChangesNowHasNoFullReconciliation()
        throws {
        let src = try source(
            "Sources/OneDayApp/ChatNativeList.swift"
        )
        let start = try XCTUnwrap(
            src.range(of: "private func applyChangesNow("),
            "applyChangesNow 必须存在"
        )
        let end = try XCTUnwrap(
            src.range(
                of: "private func applyChangesFullRebuild(",
                range: start.upperBound..<src.endIndex
            ),
            "applyChangesFullRebuild 必须紧随其后（重建路具名隔离）"
        )
        let body = String(
            src[start.lowerBound..<end.lowerBound]
        )
        for token in [
            "newByKey",
            "revisionMismatchKeys",
            "uniqueKeysWithValues: newRows",
            "revisionsByKey = Dictionary",
        ] {
            XCTAssertFalse(
                body.contains(token),
                "§374.2：applyChangesNow 不许出现整表对账形态 \(token)"
            )
        }
        // 正面断言：增量原语在场（防把函数改空的假绿）
        for token in [
            "deleteSections",
            "insertSections",
            "reconfigureItems",
            "applySnapshot",
        ] {
            XCTAssertTrue(
                body.contains(token),
                "§374.2：applyChangesNow 应含增量原语 \(token)"
            )
        }
    }

    func testIncrementalRoutingIsWired() throws {
        let list = try source(
            "Sources/OneDayApp/ChatNativeList.swift"
        )
        XCTAssertTrue(
            list.contains("controller.applyChanges("),
            "§374.2：Representable 须按 changeSet 分路 applyChanges"
        )
        XCTAssertTrue(
            list.contains("var changeSet: EntryChangeSet?"),
            "§374.2：Representable 须有 changeSet 交付口"
        )
        let chatView = try source(
            "Sources/OneDayApp/ChatView.swift"
        )
        XCTAssertTrue(
            chatView.contains(
                "feedChangeTracker.lastChangeSet"
            ),
            "§374.2：ChatView 须把追踪器变更集交付列表面"
        )
    }

    func testChangeSetCarriesStep2Fields() throws {
        let tracker = try source(
            "Sources/OneDayApp/ChatFeedChangeTracker.swift"
        )
        for token in [
            "var heightChanged: Set<String>",
            "var orderChanged: Bool",
            "func composing(_ next: EntryChangeSet)",
        ] {
            XCTAssertTrue(
                tracker.contains(token),
                "§374.2：EntryChangeSet/追踪器应含 \(token)"
            )
        }
    }
}
