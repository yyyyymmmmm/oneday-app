import XCTest
@testable import OneDayCore

/// 台账 161/164：timeline/around/learning 三口的宽
/// 容解码与猎取判定——响应体未被服务端冻结件钉
/// 死，解码宁可少拿信息、不可因键名漂移整面报废；
/// 猎取判定与 150 的摘要回找同口径（同针、同角色
/// 域），坐标换成服务端行号
final class HermesDeepModelsTests: XCTestCase {
    private func json(_ text: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }

    private func decode<T: Decodable>(_ type: T.Type, _ text: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(text.utf8))
    }

    // MARK: - 161 时间线提取

    func testTimelineExtractEntriesAndCursor() throws {
        let page = SessionTimelinePage.extract(from: try json("""
        {"session_id": "s1", "profile": "default",
         "entries": [
            {"row_id": 101, "timestamp": 1700000000, "text": "第一问"},
            {"row_id": 140, "timestamp": 1700000100, "preview": "第二问"}
         ],
         "next_cursor": 140}
        """))
        XCTAssertEqual(page.entries.map(\.rowID), [101, 140])
        XCTAssertEqual(page.entries.first?.text, "第一问")
        XCTAssertEqual(page.entries.last?.text, "第二问")
        XCTAssertEqual(page.nextCursor, 140)
    }

    func testTimelineExtractAlternateKeys() throws {
        // 条目列键名漂移（prompts）＋时刻字符串形态＋
        // row_id 字符串形态：都收，不报废
        let page = SessionTimelinePage.extract(from: try json("""
        {"prompts": [{"row_id": "55", "created_at": "1700000000", "content": "问"}],
         "nextCursor": "99"}
        """))
        XCTAssertEqual(page.entries.map(\.rowID), [55])
        XCTAssertEqual(page.entries.first?.timestamp, 1_700_000_000)
        XCTAssertEqual(page.nextCursor, 99)
    }

    func testTimelineExtractMissingPiecesDegrade() throws {
        // 无条目列 → 空页；无 row_id 的条目被丢（寻址
        // 坐标缺失不可用）；顶层非对象 → 空页
        let page = SessionTimelinePage.extract(from: try json("""
        {"entries": [{"text": "没有行号"}, {"row_id": 7}]}
        """))
        XCTAssertEqual(page.entries.map(\.rowID), [7])
        XCTAssertNil(page.nextCursor)
        let empty = SessionTimelinePage.extract(from: try json("[]"))
        XCTAssertTrue(empty.entries.isEmpty)
    }

    // MARK: - 161 around 页解码

    func testAroundPageDecodesProjectedMessages() throws {
        let page = try decode(SessionAroundPage.self, """
        {"session_id": "s1", "profile": "default",
         "messages": [
            {"id": 101, "role": "user", "content": "问"},
            {"id": 102, "role": "assistant", "content": "答"}
         ],
         "anchor_row_id": 101}
        """)
        XCTAssertEqual(page.sessionID, "s1")
        XCTAssertEqual(page.messages.map(\.id), [101, 102])
        XCTAssertEqual(page.messages.last?.content, "答")
    }

    func testAroundPageMissingMessagesIsEmpty() throws {
        let page = try decode(SessionAroundPage.self, #"{"session_id": "s1"}"#)
        XCTAssertTrue(page.messages.isEmpty)
    }

    // MARK: - 161 猎取判定

    private func stub(
        _ row: Int64, role: String, content: String
    ) -> AroundWindowHunt.MessageStub {
        AroundWindowHunt.MessageStub(rowID: row, role: role, content: content)
    }

    func testTargetRowIDMatchesBySnippetAndRole() {
        let messages = [
            stub(10, role: "user", content: "帮我看看服务器状态"),
            stub(11, role: "assistant", content: "服务器一切正常，内存 40%"),
            stub(12, role: "assistant", content: "另外磁盘也正常"),
        ]
        XCTAssertEqual(
            AroundWindowHunt.targetRowID(
                in: messages, snippet: "内存 40%", role: "assistant"
            ),
            11
        )
        // 角色域：同文在 user 行不许被 assistant 命中借走
        XCTAssertNil(
            AroundWindowHunt.targetRowID(
                in: messages, snippet: "帮我看看服务器状态", role: "assistant"
            )
        )
        // 摘要过短 → 无针 → nil（150 同口径）
        XCTAssertNil(
            AroundWindowHunt.targetRowID(
                in: messages, snippet: "内存", role: nil
            )
        )
    }

    func testDirectPromptRowIDOnlyForUserHits() {
        let entries = [
            SessionTimelineEntry(rowID: 10, timestamp: nil, text: "帮我看看服务器状态"),
            SessionTimelineEntry(rowID: 30, timestamp: nil, text: nil),
        ]
        XCTAssertEqual(
            AroundWindowHunt.directPromptRowID(
                entries: entries, snippet: "服务器状态", role: "user"
            ),
            10
        )
        // assistant 命中不走直达（命中不在 prompt 本体里）
        XCTAssertNil(
            AroundWindowHunt.directPromptRowID(
                entries: entries, snippet: "服务器状态", role: "assistant"
            )
        )
    }

    func testProbeOrderDirectFirstThenDescendingCapped() {
        let order = AroundWindowHunt.probeOrder(
            promptRowIDs: [10, 30, 20, 30], directRowID: 20
        )
        XCTAssertEqual(order, [20, 30, 10])
        let many = AroundWindowHunt.probeOrder(
            promptRowIDs: (1...40).map(Int64.init), directRowID: nil
        )
        XCTAssertEqual(many.count, AroundWindowHunt.maxProbes)
        XCTAssertEqual(many.first, 40)
    }

    // MARK: - 164 图谱解码

    func testLearningGraphDecodesNodesCardsEdges() throws {
        let graph = try decode(LearningGraph.self, """
        {"nodes": [
            {"id": "deep-research", "label": "deep-research", "kind": "skill",
             "timestamp": 1700000000, "category": "research", "useCount": 3,
             "state": "active", "createdBy": "agent", "pinned": false},
            {"id": "memory:profile:0", "label": "用户住在西安", "kind": "memory",
             "memorySource": "profile", "timestamp": 1700000001,
             "category": "memory", "useCount": 0, "state": "active",
             "createdBy": "memory", "pinned": false}
         ],
         "edges": [{"source": "memory:profile:0", "target": "deep-research"}],
         "memory": [
            {"source": "profile", "timestamp": 1700000001,
             "title": "用户住在西安", "body": "用户住在西安，通勤靠地铁。"}
         ],
         "clusters": [{"category": "research", "count": 1}],
         "stats": {"nodes": 1}}
        """)
        XCTAssertEqual(graph.skillNodes.map(\.id), ["deep-research"])
        XCTAssertEqual(graph.memoryNodes.map(\.id), ["memory:profile:0"])
        XCTAssertEqual(graph.edges.first?.target, "deep-research")
        let node = graph.memoryNodes[0]
        XCTAssertEqual(node.memoryCardIndex, 0)
        XCTAssertEqual(graph.card(for: node)?.body, "用户住在西安，通勤靠地铁。")
    }

    func testLearningGraphCardMismatchReturnsNil() throws {
        // 序号越界/来源对不上 → nil（呈现退回 label，
        // 不拿错卡冒充这一条的内容）
        let graph = try decode(LearningGraph.self, """
        {"nodes": [
            {"id": "memory:memory:5", "label": "x", "kind": "memory",
             "memorySource": "memory"}
         ],
         "memory": [{"source": "profile", "title": "t", "body": "b"}]}
        """)
        XCTAssertNil(graph.card(for: graph.memoryNodes[0]))
        let graph2 = try decode(LearningGraph.self, """
        {"nodes": [
            {"id": "memory:profile:0", "label": "x", "kind": "memory",
             "memorySource": "profile"}
         ],
         "memory": [{"source": "memory", "title": "t", "body": "b"}]}
        """)
        XCTAssertNil(graph2.card(for: graph2.memoryNodes[0]))
    }

    func testLearningGraphLenientDefaults() throws {
        // 字段大面积缺失也不报废：id 是唯一硬字段
        let graph = try decode(LearningGraph.self, """
        {"nodes": [{"id": "s1", "kind": "skill"}]}
        """)
        XCTAssertEqual(graph.nodes.count, 1)
        XCTAssertEqual(graph.nodes[0].useCount, 0)
        XCTAssertTrue(graph.memoryCards.isEmpty)
        XCTAssertTrue(graph.edges.isEmpty)
        let empty = try decode(LearningGraph.self, "{}")
        XCTAssertTrue(empty.nodes.isEmpty)
    }

    func testLearningEdgeTupleForm() throws {
        let graph = try decode(LearningGraph.self, """
        {"edges": [["a", "b"]]}
        """)
        XCTAssertEqual(graph.edges.first?.source, "a")
        XCTAssertEqual(graph.edges.first?.target, "b")
    }

    // MARK: - 164 节点全文提取

    func testNodeContentExtractForms() throws {
        let top = LearningNodeContent.extract(from: try json(
            #"{"id": "memory:memory:0", "content": "全文"}"#
        ))
        XCTAssertEqual(top.content, "全文")
        let nested = LearningNodeContent.extract(from: try json(
            #"{"node": {"id": "x", "text": "嵌套全文"}}"#
        ))
        XCTAssertEqual(nested.content, "嵌套全文")
        XCTAssertEqual(nested.id, "x")
        let missing = LearningNodeContent.extract(from: try json(
            #"{"id": "x", "ok": true}"#
        ))
        XCTAssertNil(missing.content)
    }
}
