import XCTest
@testable import OneDayCore

/// 0.4.0（审计 §3.4）：服务端会话历史导入口径——只取
/// user/assistant 有正文者、保原序；工具/系统消息与
/// 空正文不进本地线程（不渲染、不进上下文重放）。
final class SessionHistoryImportTests: XCTestCase {
    private func messages(_ json: String) throws -> [SessionMessage] {
        let data = Data(json.utf8)
        return try JSONDecoder()
            .decode(SessionMessagesResponse.self, from: data)
            .messages
    }

    func testKeepsOnlyUserAssistantWithContentInOrder() throws {
        let loaded = try messages("""
        {"messages": [
          {"id": 1, "role": "user", "content": "你好", "timestamp": 1762000000},
          {"id": 2, "role": "tool", "content": "{\\"a\\":1}", "timestamp": 1762000001},
          {"id": 3, "role": "assistant", "content": "在的", "timestamp": 1762000002},
          {"id": 4, "role": "system", "content": "sys", "timestamp": 1762000003},
          {"id": 5, "role": "assistant", "content": "  ", "timestamp": 1762000004},
          {"id": 6, "role": "user", "content": "", "timestamp": 1762000005},
          {"id": 7, "role": "assistant", "content": "继续", "timestamp": 1762000006}
        ]}
        """)
        let entries = SessionHistoryImport.importableEntries(from: loaded)
        XCTAssertEqual(entries.map(\.role), ["user", "assistant", "assistant"])
        XCTAssertEqual(entries.map(\.content), ["你好", "在的", "继续"])
        XCTAssertEqual(
            entries.first?.date,
            Date(timeIntervalSince1970: 1762000000)
        )
    }

    func testEmptyWhenNothingImportable() throws {
        let loaded = try messages("""
        {"messages": [
          {"id": 1, "role": "tool", "content": "{}", "timestamp": 1762000000}
        ]}
        """)
        XCTAssertTrue(
            SessionHistoryImport.importableEntries(from: loaded).isEmpty
        )
    }

    func testThreadTitleFallsBackWithoutSession() {
        let entries = [
            SessionHistoryImport.Entry(
                role: "user", content: "帮我看看明天的安排", date: nil
            ),
        ]
        XCTAssertEqual(
            SessionHistoryImport.threadTitle(session: nil, entries: entries),
            "帮我看看明天的安排"
        )
        XCTAssertEqual(
            SessionHistoryImport.threadTitle(session: nil, entries: []),
            "未命名会话"
        )
    }
}
