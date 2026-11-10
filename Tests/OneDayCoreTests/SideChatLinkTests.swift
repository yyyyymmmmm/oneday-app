import OneDayCore
import XCTest

/// 旁聊真会话链接状态机（0.21.0）：相位派生、发送
/// 计划、载荷取形、模型重锁判定与「链接状态→标题
/// 解析」的验收组合——全部纯判定，链接的网络动作
/// 在 ChatView/HermesClient（施工期零生产写请求，
/// 状态机只以 fixture 验）
final class SideChatLinkTests: XCTestCase {

    // MARK: - 相位派生

    func testPhaseUnlinkedWhenNoSessionAndNoFailures() {
        XCTAssertEqual(
            SideChatLink.phase(serverSessionID: nil, linkFailureCount: 0),
            .unlinked
        )
    }

    func testPhaseLinkFailedCarriesAttemptCount() {
        XCTAssertEqual(
            SideChatLink.phase(serverSessionID: nil, linkFailureCount: 2),
            .linkFailed(attempts: 2)
        )
    }

    func testPhaseLinkedWinsOverStaleFailureCount() {
        XCTAssertEqual(
            SideChatLink.phase(
                serverSessionID: "oneday-side-x", linkFailureCount: 3
            ),
            .linked(sessionID: "oneday-side-x")
        )
    }

    func testPhaseEmptySessionIDCountsAsUnlinked() {
        XCTAssertEqual(
            SideChatLink.phase(serverSessionID: "", linkFailureCount: 0),
            .unlinked
        )
    }

    func testPhaseAfterAttemptSuccessIsLinked() {
        XCTAssertEqual(
            SideChatLink.phase(afterAttemptSuccess: "s-1"),
            .linked(sessionID: "s-1")
        )
    }

    func testPhaseAfterAttemptFailureIncrements() {
        XCTAssertEqual(
            SideChatLink.phase(afterAttemptFailure: 0),
            .linkFailed(attempts: 1)
        )
        XCTAssertEqual(
            SideChatLink.phase(afterAttemptFailure: 2),
            .linkFailed(attempts: 3)
        )
    }

    func testNewSessionIDFormat() {
        let id = SideChatLink.newSessionID()
        XCTAssertTrue(id.hasPrefix("oneday-side-"))
        let suffix = String(id.dropFirst("oneday-side-".count))
        XCTAssertNotNil(UUID(uuidString: suffix))
        XCTAssertEqual(id, id.lowercased())
    }

    // MARK: - 发送计划

    // 0.27.0 改判：计划只看绑定与种子位（主线由调用
    // 方代入钦定 id＋Store 双位，与旁聊同口径）；无
    // 头重放计划（legacyReplay）已整类删除——下列
    // 用例同时是「任何状态都不许产出无头发送」的闸

    func testSendPlanOwnSeededSessionIsSessionMode() {
        XCTAssertEqual(
            SideChatLink.sendPlan(
                serverSessionID: "oneday-main-x", serverSeeded: true
            ),
            .session(sessionID: "oneday-main-x")
        )
        XCTAssertEqual(
            SideChatLink.sendPlan(
                serverSessionID: "oneday-side-x", serverSeeded: true
            ),
            .session(sessionID: "oneday-side-x")
        )
    }

    func testSendPlanUnlinkedIsLinkAndSeed() {
        // 未链接与失败留痕同计划：下次发送照样先试链接
        XCTAssertEqual(
            SideChatLink.sendPlan(
                serverSessionID: nil, serverSeeded: false
            ),
            .linkAndSeed
        )
        XCTAssertEqual(
            SideChatLink.sendPlan(
                serverSessionID: "", serverSeeded: true
            ),
            .linkAndSeed
        )
    }

    func testSendPlanOwnUnseededIsLinkAndSeed() {
        // 自有会话已建但种子未落：先补种子，不许带
        // 头空发（服务端历史为空、上下文会断）
        XCTAssertEqual(
            SideChatLink.sendPlan(
                serverSessionID: "oneday-side-x", serverSeeded: false
            ),
            .linkAndSeed
        )
    }

    func testSendPlanImportedForeignSessionIsSessionMode() {
        // 续聊导入线程出生即带服务端历史：种子位语
        // 义由出生方式满足（落盘时置 true），计划走
        // 会话模式——此处以 seeded=true 的等价形态验
        XCTAssertEqual(
            SideChatLink.sendPlan(
                serverSessionID: "sess-foreign-1", serverSeeded: true
            ),
            .session(sessionID: "sess-foreign-1")
        )
    }

    // MARK: - 载荷取形

    func testPayloadSessionModeSendsOnlyLatestMessage() {
        let context = ["一问", "一答", "二问"]
        XCTAssertEqual(
            SideChatLink.payload(
                plan: .session(sessionID: "s-1"), fullContext: context
            ),
            ["二问"]
        )
    }

    func testPayloadAfterLinkSendsOnlyLatestMessage() {
        // 0.27.0：历史由种子导入承载——链接完成后的
        // 本轮发送同样只带尾条，linkAndSeed 相位若被
        // 误当发送形态取形，也只许尾条（防全量重放
        // 带上头重演服务端合并）
        let context = ["一问", "一答", "二问"]
        XCTAssertEqual(
            SideChatLink.payload(
                plan: .linkAndSeed, fullContext: context
            ),
            ["二问"]
        )
    }

    func testPayloadEmptyContextStaysEmpty() {
        XCTAssertTrue(
            SideChatLink.payload(
                plan: .session(sessionID: "s-1"),
                fullContext: [String]()
            ).isEmpty
        )
    }

    // MARK: - 模型重锁

    func testRelockOnlyForOwnLockThatDiverged() {
        // 导入线程：锁非我方所设、永不代推
        XCTAssertFalse(
            SideChatLink.needsModelRelock(
                linkedModel: nil, capsuleModel: "deepseek-flash"
            )
        )
        // 我方落锁且与胶囊一致：不推
        XCTAssertFalse(
            SideChatLink.needsModelRelock(
                linkedModel: "deepseek-flash",
                capsuleModel: "deepseek-flash"
            )
        )
        // 我方落锁、胶囊已改选：推一次
        XCTAssertTrue(
            SideChatLink.needsModelRelock(
                linkedModel: "deepseek-flash",
                capsuleModel: "deepseek-v4-pro"
            )
        )
    }

    // MARK: - 验收组合：链接状态 → 标题解析（简报第四项三态）

    func testUnlinkedThreadTitleStaysDerived() {
        // 未链接：服务端标题无从查（serverTitle=nil）
        // → 恒本地首消息派生标题
        let phase = SideChatLink.phase(
            serverSessionID: nil, linkFailureCount: 0
        )
        XCTAssertEqual(phase, .unlinked)
        XCTAssertEqual(
            DrawerThreadTitle.resolve(
                localTitle: "帮我看看这份合同",
                titleIsManual: false,
                serverTitle: nil
            ),
            "帮我看看这份合同"
        )
    }

    func testLinkedThreadTitleUpgradesToLLMTitle() {
        // 已链接＋llm 标题到手 → AI 标题压过本地派生
        let phase = SideChatLink.phase(
            serverSessionID: "oneday-side-x", linkFailureCount: 0
        )
        XCTAssertEqual(phase, .linked(sessionID: "oneday-side-x"))
        XCTAssertEqual(
            DrawerThreadTitle.resolve(
                localTitle: "帮我看看这份合同",
                titleIsManual: false,
                serverTitle: "劳动合同条款审阅"
            ),
            "劳动合同条款审阅"
        )
    }

    func testManualTitleSurvivesLinkAndLLMTitle() {
        // 手改名最高优先：链接与 llm 标题都不许覆盖
        XCTAssertEqual(
            DrawerThreadTitle.resolve(
                localTitle: "我的合同专线",
                titleIsManual: true,
                serverTitle: "劳动合同条款审阅"
            ),
            "我的合同专线"
        )
    }
}
