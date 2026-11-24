import XCTest
@testable import OneDayCore

/// 台账 187 消息反应包·Core 层验收：DTO 解码（反
/// 应随 messages 投影下发/回执同形）、RichItem 钉
/// 桩与镜像的带穿、乐观组装口径、落定段行 id 提
/// 取（user 锚行恒精确、assistant 单行成文才钉）
final class MessageReactions187CoreTests: XCTestCase {
    private func messages(_ json: String) throws -> [SessionMessage] {
        try JSONDecoder()
            .decode(
                SessionMessagesResponse.self,
                from: Data(json.utf8)
            )
            .messages
    }

    func testSessionMessageDecodesReactions() throws {
        let loaded = try messages("""
        {"messages": [
          {"id": 11, "role": "assistant", "content": "答",
           "timestamp": 1762000000,
           "reactions": [
             {"emoji": "👍", "author": "user", "at": 1762000100.5, "seen": true},
             {"emoji": "🔥", "author": "agent", "at": 1762000200}
           ]},
          {"id": 12, "role": "user", "content": "问",
           "timestamp": 1762000300}
        ]}
        """)
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(
            loaded[0].reactions.map(\.emoji), ["👍", "🔥"]
        )
        XCTAssertEqual(
            loaded[0].reactions.map(\.author), ["user", "agent"]
        )
        XCTAssertEqual(loaded[0].reactions[0].seen, true)
        XCTAssertNil(loaded[0].reactions[1].seen)
        XCTAssertTrue(
            loaded[1].reactions.isEmpty,
            "缺 reactions 键须解为空集（旧服务端/无反应行）"
        )
    }

    func testReactionUpdateDecodes() throws {
        let update = try JSONDecoder().decode(
            ReactionUpdate.self,
            from: Data("""
            {"row_id": 42, "reactions": [
              {"emoji": "❤️", "author": "user", "at": 1762000100}
            ]}
            """.utf8)
        )
        XCTAssertEqual(update.rowID, 42)
        XCTAssertEqual(update.reactions.map(\.emoji), ["❤️"])
        let empty = try JSONDecoder().decode(
            ReactionUpdate.self,
            from: Data(#"{"row_id": 42, "reactions": []}"#.utf8)
        )
        XCTAssertTrue(empty.reactions.isEmpty)
    }

    func testRichItemsCarryRowIDAndReactions() throws {
        let loaded = try messages("""
        {"messages": [
          {"id": 21, "role": "user", "content": "问题",
           "timestamp": 1762000000,
           "reactions": [{"emoji": "😂", "author": "agent", "at": 1}]},
          {"id": 22, "role": "assistant", "content": "回答",
           "timestamp": 1762000001},
          {"id": 0, "role": "assistant", "content": "异常行",
           "timestamp": 1762000002}
        ]}
        """)
        let items = SessionHistoryImport.richItems(from: loaded)
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items[0].serverRowID, 21)
        XCTAssertEqual(items[0].reactions.map(\.emoji), ["😂"])
        XCTAssertEqual(items[1].serverRowID, 22)
        XCTAssertTrue(items[1].reactions.isEmpty)
        XCTAssertNil(
            items[2].serverRowID,
            "id 非正整数不成钉桩（宁可不可反应也不钉错行）"
        )
    }

    func testApplyingOwnReactionSemantics() {
        let agent = MessageReaction(
            emoji: "🔥", author: "agent", at: 1
        )
        // 新点：自己的追加在后、助手段保留
        var next = MessageReactions.applying(
            own: "👍", to: [agent], at: 2
        )
        XCTAssertEqual(next.map(\.emoji), ["🔥", "👍"])
        XCTAssertEqual(
            MessageReactions.ownEmoji(in: next), "👍"
        )
        // 异点替换：自己的旧值被新值替掉、仍一条
        next = MessageReactions.applying(
            own: "❤️", to: next, at: 3
        )
        XCTAssertEqual(next.map(\.emoji), ["🔥", "❤️"])
        // 撤回：只去自己的、助手段不动
        next = MessageReactions.applying(
            own: nil, to: next
        )
        XCTAssertEqual(next.map(\.emoji), ["🔥"])
        XCTAssertNil(MessageReactions.ownEmoji(in: next))
    }

    func testPaletteIsApprovedEight() {
        XCTAssertEqual(
            MessageReactions.palette,
            ["👍", "❤️", "😂", "😮", "😢", "🙏", "🔥", "🎉"],
            "反应排固定集是用户拍板的样板 8 个、单排无展开层"
        )
    }

    func testSettleCarriesRowIDs() throws {
        let loaded = try messages("""
        {"messages": [
          {"id": 31, "role": "user", "content": "上一问", "timestamp": 1762000000},
          {"id": 32, "role": "assistant", "content": "上一答", "timestamp": 1762000001},
          {"id": 33, "role": "user", "content": "本轮问", "timestamp": 1762000002},
          {"id": 34, "role": "assistant", "content": "本轮答", "timestamp": 1762000003}
        ]}
        """)
        let settled = RunTranscriptSettle.settle(messages: loaded)
        XCTAssertTrue(settled.found)
        XCTAssertEqual(
            settled.userRowID, 33,
            "锚点 user 行＝transcript 末条 user 行、恒精确"
        )
        XCTAssertEqual(
            settled.assistantRowID, 34,
            "正文恰出自一条 assistant 行时钉该行"
        )
    }

    func testSettleMultiRowTextDoesNotPinAssistant() throws {
        let loaded = try messages("""
        {"messages": [
          {"id": 41, "role": "user", "content": "问", "timestamp": 1762000000},
          {"id": 42, "role": "assistant", "content": "前半", "timestamp": 1762000001},
          {"id": 43, "role": "assistant", "content": "后半", "timestamp": 1762000002}
        ]}
        """)
        let settled = RunTranscriptSettle.settle(messages: loaded)
        XCTAssertTrue(settled.found)
        XCTAssertEqual(settled.userRowID, 41)
        XCTAssertNil(
            settled.assistantRowID,
            "多行拼接成文钉任一行都是错址、恒 nil"
        )
    }
}
