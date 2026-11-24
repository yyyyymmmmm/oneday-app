import XCTest

/// §449.9 源码钉（2026-11-24 用户令「工具活动进胶
/// 囊、不进流」）：聊天流内不再实例化工具卡视图；
/// 活动短语由运行驱动单点写 AppState、胶囊第二行
/// 与中枢状态行同读。行为终判归真机门，本钉只把
/// 守接线形态，防后人把卡塞回流内或把短语改成两
/// 面两源
final class HubActivity449Tests: XCTestCase {

    private func source(_ relative: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let srcURL = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relative)
        return try String(contentsOf: srcURL, encoding: .utf8)
    }

    func testChatStreamNoLongerInstantiatesToolCards() throws {
        let chat = try source("Sources/OneDayApp/ChatView.swift")
        XCTAssertFalse(
            chat.contains("ToolCardGroupView("),
            "§449.9：工具组卡不得再进聊天流"
        )
        XCTAssertFalse(
            chat.contains("ToolCardView("),
            "§449.9：工具单卡不得再进聊天流"
        )
        XCTAssertTrue(
            chat.contains(".map(EntryRenderItem.entry)"),
            "§449.9：渲染计划层应过滤工具条目"
        )
    }

    func testActivityPhraseSingleSourceWiring() throws {
        let chat = try source("Sources/OneDayApp/ChatView.swift")
        let hub = try source("Sources/OneDayApp/AgentHubView.swift")
        let state = try source("Sources/OneDayApp/AppState.swift")
        XCTAssertTrue(
            state.contains("var liveActivityPhrase: String?"),
            "§449.9：活动短语单源应在 AppState"
        )
        XCTAssertTrue(
            chat.contains(
                "ToolCardClassifier.activityPhrase("
            ),
            "§449.9：短语应由 Core 映射表单点派生"
        )
        // §474 改钉（2026-11-24 用户亲令）：胶囊第
        // 二行只许工作状态——回落连接状态词的旧钉
        // 随 §474 作废，改钉「只传活动短语单源」
        XCTAssertTrue(
            chat.contains(
                "statusWord: appState.liveActivityPhrase,"
            ),
            "§474：胶囊第二行只传活动短语单源"
        )
        XCTAssertFalse(
            chat.contains("?? overviewStatusWord"),
            "§474：胶囊第二行不得回落连接状态词"
        )
        XCTAssertTrue(
            hub.contains("appState.liveActivityPhrase"),
            "§449.9：中枢状态行应同读活动短语单源"
        )
    }
}
