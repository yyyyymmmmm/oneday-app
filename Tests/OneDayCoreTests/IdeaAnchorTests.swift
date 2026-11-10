import OneDayCore
import XCTest

/// 锚点模型钉测（0.39.0，规格 three-pages-mechanism-v2
/// 第二章）：evidenceRef（轮内编号）与 anchorId（跨轮锚点）
/// 的解析口径——五源齐全、形状不对一律不认不猜；来源瓷砖
/// S/G/M 与 0.32.0 既有映射逐一对齐、K/R 新增各自符号。
final class IdeaAnchorTests: XCTestCase {
    func testParsesAllFiveSources() {
        XCTAssertEqual(IdeaAnchor(evidenceRef: "S3")?.kind, .session)
        XCTAssertEqual(IdeaAnchor(evidenceRef: "S3")?.index, 3)
        XCTAssertEqual(IdeaAnchor(evidenceRef: "G1")?.kind, .goal)
        XCTAssertEqual(IdeaAnchor(evidenceRef: "M2")?.kind, .monitor)
        XCTAssertEqual(IdeaAnchor(evidenceRef: "K12")?.kind, .kanban)
        XCTAssertEqual(IdeaAnchor(evidenceRef: "K12")?.index, 12)
        XCTAssertEqual(IdeaAnchor(evidenceRef: "R2")?.kind, .memory)
    }

    func testRejectsMisshapedRefs() {
        XCTAssertNil(IdeaAnchor(evidenceRef: nil))
        XCTAssertNil(IdeaAnchor(evidenceRef: ""))
        XCTAssertNil(IdeaAnchor(evidenceRef: "X9"))
        XCTAssertNil(IdeaAnchor(evidenceRef: "S"))
        XCTAssertNil(IdeaAnchor(evidenceRef: "Sabc"))
        XCTAssertNil(IdeaAnchor(evidenceRef: "s1"))
        XCTAssertNil(IdeaAnchor(evidenceRef: "12"))
    }

    func testParsesAnchorIdKindOnly() {
        let k = IdeaAnchor(anchorId: "K:t_blocked")
        XCTAssertEqual(k?.kind, .kanban)
        XCTAssertNil(k?.index)
        XCTAssertEqual(
            IdeaAnchor(anchorId: "R:mem_abc")?.kind, .memory
        )
        XCTAssertEqual(
            IdeaAnchor(anchorId: "S:sess-1")?.kind, .session
        )
        XCTAssertEqual(
            IdeaAnchor(anchorId: "M:c_9")?.kind, .monitor
        )
        XCTAssertEqual(
            IdeaAnchor(anchorId: "G:g_1")?.kind, .goal
        )
    }

    func testRejectsMisshapedAnchorIds() {
        XCTAssertNil(IdeaAnchor(anchorId: nil))
        XCTAssertNil(IdeaAnchor(anchorId: ""))
        XCTAssertNil(IdeaAnchor(anchorId: "nocolon"))
        XCTAssertNil(IdeaAnchor(anchorId: "X:1"))
        XCTAssertNil(IdeaAnchor(anchorId: "KK:t_1"))
        XCTAssertNil(IdeaAnchor(anchorId: ":t_1"))
    }

    func testTileSymbolsKeepLegacyMappingAndAddKR() {
        // 0.32.0 既有三源逐一对齐（不回退）
        XCTAssertEqual(
            IdeaMaterialKind.session.tileSymbol, "text.bubble"
        )
        XCTAssertEqual(IdeaMaterialKind.goal.tileSymbol, "target")
        XCTAssertEqual(
            IdeaMaterialKind.monitor.tileSymbol,
            "dot.radiowaves.left.and.right"
        )
        // 本包新增两源
        XCTAssertEqual(
            IdeaMaterialKind.kanban.tileSymbol, "checklist"
        )
        XCTAssertEqual(IdeaMaterialKind.memory.tileSymbol, "brain")
        XCTAssertEqual(
            IdeaMaterialKind.unknown.tileSymbol, "lightbulb"
        )
        // 五源符号两两不同（瓷砖能分辨来源）
        let symbols = [
            IdeaMaterialKind.session.tileSymbol,
            IdeaMaterialKind.goal.tileSymbol,
            IdeaMaterialKind.monitor.tileSymbol,
            IdeaMaterialKind.kanban.tileSymbol,
            IdeaMaterialKind.memory.tileSymbol,
        ]
        XCTAssertEqual(Set(symbols).count, 5)
    }
}
