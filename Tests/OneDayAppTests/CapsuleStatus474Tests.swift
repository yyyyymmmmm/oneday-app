import XCTest

/// §474 源码钉（2026-11-24 用户 10:16 亲令「胶囊里
/// 面的在线删了，小字改为 muse 内部的工作状态」＋
/// 「胶囊下面还有个胶囊」）：①各面身份胶囊小字单
/// 源＝AppState.liveActivityPhrase，连接状态词不
/// 进胶囊领地；②聊天面第二胶囊（进展胶囊）呈现
/// 点摘除，台账活动归中枢同源派生呈现。行为终判
/// 归真机门，本钉只守接线形态
final class CapsuleStatus474Tests: XCTestCase {

    private func source(_ relative: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let srcURL = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relative)
        return try String(contentsOf: srcURL, encoding: .utf8)
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    /// 胶囊小字单源：聊天胶囊与资源库锚点都只传活动
    /// 短语（资源库 §498 起经 ContentPageHeader 共同
    /// 簇同传）；胶囊本体状态词为可选（无活动不呈现）
    func testCapsuleStatusWordSingleSource() throws {
        let chat = try source("Sources/OneDayApp/ChatView.swift")
        let capsule = try source(
            "Sources/OneDayApp/HubIdentityCapsule.swift"
        )
        // §498 改钉：资源库自写 identityHeader 已收编入
        // ContentPageHeader 共同簇，胶囊小字字面随之迁至
        // 共同簇的 HubIdentityCapsule 调用（行为不丢反
        // 收编）；资源库页头本体另钉经共同簇收编
        let header = try source(
            "Sources/OneDayApp/ContentPageHeader.swift"
        )
        let library = try source(
            "Sources/OneDayApp/DeliverablesView.swift"
        )
        XCTAssertTrue(
            chat.contains("statusWord: appState.liveActivityPhrase,"),
            "§474：聊天胶囊第二行应只传活动短语单源"
        )
        XCTAssertTrue(
            capsule.contains("var statusWord: String?"),
            "§474：胶囊状态词应为可选，无活动不呈现第二行"
        )
        XCTAssertTrue(
            header.contains("statusWord: appState.liveActivityPhrase,"),
            "§474＋§498：共同簇胶囊小字应同传活动短语单源（原资源库锚点字面随 §498 收编迁入）"
        )
        XCTAssertTrue(
            library.contains("ContentPageHeader("),
            "§498：资源库页头应经 ContentPageHeader 共同簇收编，不再自写页头"
        )
    }

    /// 「在线」零命中（胶囊领地）：资源库页头不得再
    /// 出现在线字面；中枢状态词源不得再产「在线」与
    /// 「在线 · N 条待审批」；锚点组件状态词改可选、
    /// 状态点随词同生同灭
    func testNoOnlineWordInCapsuleTerritory() throws {
        let library = try source(
            "Sources/OneDayApp/DeliverablesView.swift"
        )
        let hubStore = try source(
            "Sources/OneDayApp/AgentHubStore.swift"
        )
        let anchor = try source(
            "Sources/OneDayDesign/Components.swift"
        )
        // 断言口径＝UI 字符串字面（注释里说明旧词
        // 的「在线」不在此列，与全仓源码钉惯例一致）
        XCTAssertFalse(
            library.contains("\"在线\""),
            "§474：资源库页头不得再以「在线」为 UI 文案"
        )
        XCTAssertFalse(
            library.contains("\"未连接\""),
            "§474：资源库页头不得再以「未连接」为 UI 文案"
        )
        XCTAssertFalse(
            hubStore.contains("在线 · %lld 条待审批"),
            "§474：中枢状态词不得再拼「在线 · 」前缀"
        )
        XCTAssertFalse(
            hubStore.contains("return L10n.string(\"在线\")"),
            "§474：中枢状态词不得再单独产「在线」"
        )
        XCTAssertTrue(
            anchor.contains("name: String, statusWord: String?"),
            "§474：IdentityAnchor 状态词应改可选"
        )
    }

    /// 第二胶囊摘除：聊天顶簇不再实例化进展胶囊、
    /// 呈现件本体退役；台账活动派生保留在中枢（归
    /// 中枢呈现的证据）
    /// 组版 0.50.116 改钉注记：第三断言原钉 AgentHubView
    /// 直调 ProgressCapsule.derive；§477 中枢全抄已把活
    /// 动语义改判为 liveActivityPhrase 单源（码内注「与
    /// §474 胶囊线同源收口」），状态行仍活动优先呈现、
    /// §474 实质不变，断言随之改钉新单源字面。
    func testSecondCapsuleRemovedFromChatSurface() throws {
        let chat = try source("Sources/OneDayApp/ChatView.swift")
        let hub = try source("Sources/OneDayApp/AgentHubView.swift")
        XCTAssertFalse(
            chat.contains("ProgressCapsuleView("),
            "§474：聊天面不得再有第二胶囊呈现点"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: repoRoot()
                    .appendingPathComponent(
                        "Sources/OneDayApp/ProgressCapsuleView.swift"
                    ).path
            ),
            "§474：进展胶囊呈现件本体应退役"
        )
        XCTAssertTrue(
            hub.contains("liveActivityPhrase"),
            "§474：活动派生应保留在中枢状态行（活动归中枢；派生源随 §477 改判 liveActivityPhrase 单源）"
        )
    }
}
