import OneDayCore
import OneDayDesign
import XCTest
@testable import OneDayApp

/// §432 AI 自反应包·App 层验收：角标渲染判定
/// （有 agent 反应才出、用户自有反应不误触、两
/// 面分工不合并）、开关四象限（能力位有无×开关
/// 开闭→行显隐与角标显隐）、能力协商三态、行高
/// 预留随开关两态。真机观感（角标悬挂位置/开关
/// 行实际显隐）CI 无信号、归用户真机（交卷清单）
@MainActor
final class AISelfReaction432Tests: XCTestCase {

    private func makeComposer() -> ChatNativeRowHeightComposer {
        ChatNativeRowHeightComposer(
            screenWidth: 402,
            horizontalPadding: OneDayMetrics.pageGutter,
            sizeCategory: .large,
            boldText: false,
            displayScale: 3,
            ledger: ChatRowStateLedger(),
            hubStore: AppState().sharedHubStore(),
            agentDisplayName: "Hermes",
            emptyStateAvatarSize: 72
        )
    }

    private func capabilities(
        _ json: String
    ) throws -> CapabilitiesResponse {
        try JSONDecoder().decode(
            CapabilitiesResponse.self,
            from: Data(json.utf8)
        )
    }

    // MARK: 特性键缺省口径

    func testFeatureDefaultsOnUnlessExplicitlyOff() {
        let suite = UserDefaults(
            suiteName: "AISelfReaction432Tests"
        )!
        suite.removePersistentDomain(
            forName: "AISelfReaction432Tests"
        )
        XCTAssertTrue(
            ChatReactionsAISelfFeature.isEnabled(defaults: suite),
            "键缺省＝开（与浮排特性同口径）"
        )
        suite.set(false, forKey: ChatReactionsAISelfFeature.defaultsKey)
        XCTAssertFalse(
            ChatReactionsAISelfFeature.isEnabled(defaults: suite),
            "显式 false 才关"
        )
        suite.set(true, forKey: ChatReactionsAISelfFeature.defaultsKey)
        XCTAssertTrue(
            ChatReactionsAISelfFeature.isEnabled(defaults: suite)
        )
        XCTAssertEqual(
            ChatReactionsAISelfFeature.defaultsKey,
            "chat.reactions.aiSelf",
            "键名与施工图 §4 定版一致"
        )
    }

    // MARK: 能力协商三态

    func testSelfReactionsNegotiation() throws {
        let advertised = try capabilities(
            #"{"features":{"self_reactions":true},"endpoints":{}}"#
        )
        XCTAssertEqual(
            CapabilityNegotiation.selfReactionsAvailability(advertised),
            .available, "广告 true＝available"
        )
        let silent = try capabilities(
            #"{"features":{},"endpoints":{}}"#
        )
        XCTAssertEqual(
            CapabilityNegotiation.selfReactionsAvailability(silent),
            .unavailable,
            "能力面已取到而旗标缺失＝未发布（非未知）"
        )
        let refused = try capabilities(
            #"{"features":{"self_reactions":false},"endpoints":{}}"#
        )
        XCTAssertEqual(
            CapabilityNegotiation.selfReactionsAvailability(refused),
            .unavailable, "广告 false＝unavailable"
        )
        XCTAssertEqual(
            CapabilityNegotiation.selfReactionsAvailability(nil),
            .unknown, "没取到能力面＝unknown、不往好处猜"
        )
    }

    // MARK: 角标判定（有 agent 才出、own 不误触）

    func testBadgeDecisionMatrix() {
        let own = MessageReaction(emoji: "👍", author: "user", at: 1)
        let agent = MessageReaction(emoji: "❤️", author: "agent", at: 2)

        XCTAssertNil(
            AISelfReactionDecision.badgeEmoji(
                reactions: [], featureEnabled: true
            ), "无反应不出"
        )
        XCTAssertNil(
            AISelfReactionDecision.badgeEmoji(
                reactions: [own], featureEnabled: true
            ), "只有用户自己的反应不误触角标（归 pill）"
        )
        XCTAssertEqual(
            AISelfReactionDecision.badgeEmoji(
                reactions: [agent], featureEnabled: true
            ), "❤️", "有 agent 反应才出、值即其 emoji"
        )
        XCTAssertNil(
            AISelfReactionDecision.badgeEmoji(
                reactions: [agent], featureEnabled: false
            ), "开关关＝角标不在场（数据还在）"
        )
        XCTAssertEqual(
            AISelfReactionDecision.badgeEmoji(
                reactions: [own, agent], featureEnabled: true
            ), "❤️", "双 author 并存时角标只认 agent 段"
        )
        // 分工：pill 只承 own 段、两面不合并
        XCTAssertEqual(
            MessageReactions.ownReactions(in: [own, agent]),
            [own], "pill 输入只含用户段"
        )
        XCTAssertEqual(
            MessageReactions.agentEmoji(in: [own, agent]),
            "❤️"
        )
        XCTAssertNil(
            MessageReactions.agentEmoji(in: [own])
        )
    }

    // MARK: 四象限（能力位×开关→行/角标）

    func testRowAndBadgeQuadrants() {
        let agent = MessageReaction(emoji: "🎉", author: "agent", at: 1)
        // 行显隐只看能力位：available 才出，开关开闭不影响行在场
        for availability in [
            CapabilityAvailability.available,
            .unavailable, .unknown,
        ] {
            for enabled in [true, false] {
                XCTAssertEqual(
                    SelfReactionsSettingsRowPolicy.isRowVisible(
                        availability: availability
                    ),
                    availability == .available,
                    "行显隐＝能力位 available（\(availability)/开关\(enabled)）"
                )
                // 角标显隐只看开关与数据：能力位不进角标判定
                // （数据在即服务端已支持，呈现不二次门控）
                let badge = AISelfReactionDecision.badgeEmoji(
                    reactions: [agent], featureEnabled: enabled
                )
                XCTAssertEqual(
                    badge != nil, enabled,
                    "角标＝开关开且有 agent 反应（\(availability)/开关\(enabled)）"
                )
            }
        }
    }

    // MARK: 行高预留随开关两态

    func testHeightReserveFollowsFeatureForAgentOnlyRow() {
        let composer = makeComposer()
        let user = ChatEntry(
            role: "user", content: "一条提问", thread: nil
        )
        let plain = composer.entryHeightCore(
            ChatEntryHeightSnapshot(user), dividerText: nil
        )
        user.applyReactions([
            MessageReaction(emoji: "👀", author: "agent", at: 1),
        ])
        let onHeight = composer.entryHeightCore(
            ChatEntryHeightSnapshot(
                user, aiSelfReactionsEnabled: true
            ),
            dividerText: nil
        )
        XCTAssertEqual(
            onHeight - plain, ChatReactionMetrics.rowReserve,
            accuracy: 0.001,
            "开关开：仅 agent 反应的用户行恰多一笔角标悬出预留"
        )
        let offHeight = composer.entryHeightCore(
            ChatEntryHeightSnapshot(
                user, aiSelfReactionsEnabled: false
            ),
            dividerText: nil
        )
        XCTAssertEqual(
            offHeight - plain, 0, accuracy: 0.001,
            "开关关：角标隐藏、预留同步归零（不留死空间）"
        )
        // own 段不受开关影响：关时 pill 照常在场、预留照旧
        user.applyReactions([
            MessageReaction(emoji: "👍", author: "user", at: 2),
            MessageReaction(emoji: "👀", author: "agent", at: 1),
        ])
        let ownOffHeight = composer.entryHeightCore(
            ChatEntryHeightSnapshot(
                user, aiSelfReactionsEnabled: false
            ),
            dividerText: nil
        )
        XCTAssertEqual(
            ownOffHeight - plain, ChatReactionMetrics.rowReserve,
            accuracy: 0.001,
            "开关关但有 own 段：pill 在场、预留照旧一笔（不双算）"
        )
    }
}
