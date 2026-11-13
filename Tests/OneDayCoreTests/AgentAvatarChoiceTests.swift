import XCTest
@testable import OneDayCore

/// 头像呈现裁决（P1 身份包）：用户手动选过的优先、
/// AI 只动 AI 档、仓不可达不参与裁决（AI 档为空回
/// 落）——纯逻辑全在此，存储层与同步层只许消费。
final class AgentAvatarChoiceTests: XCTestCase {

    // MARK: - 用户锁：AI 永远压不过手动选择

    func testLockedUserPresetBeatsAIPreset() {
        XCTAssertEqual(
            AgentAvatarChoice.resolve(
                userLocked: true,
                ai: .preset(id: "paw"),
                user: .preset(id: "sparkles")
            ),
            .preset(id: "sparkles")
        )
    }

    func testLockedUserCustomBeatsAIImage() {
        XCTAssertEqual(
            AgentAvatarChoice.resolve(
                userLocked: true,
                ai: .image(itemID: "av_1"),
                user: .custom
            ),
            .custom
        )
        XCTAssertFalse(
            AgentAvatarChoice.aiImageWins(
                userLocked: true, ai: .image(itemID: "av_1")
            )
        )
    }

    // MARK: - 未锁：AI 档赢过档案选择值

    func testUnlockedAIPresetWins() {
        XCTAssertEqual(
            AgentAvatarChoice.resolve(
                userLocked: false,
                ai: .preset(id: "paw"),
                user: .default
            ),
            .preset(id: "paw")
        )
    }

    func testUnlockedAIImageWinsAsCustom() {
        XCTAssertEqual(
            AgentAvatarChoice.resolve(
                userLocked: false,
                ai: .image(itemID: "av_9"),
                user: .preset(id: "atom")
            ),
            .custom
        )
        XCTAssertTrue(
            AgentAvatarChoice.aiImageWins(
                userLocked: false, ai: .image(itemID: "av_9")
            )
        )
    }

    func testAIPresetWinsButImageDoesNot() {
        XCTAssertFalse(
            AgentAvatarChoice.aiImageWins(
                userLocked: false, ai: .preset(id: "paw")
            )
        )
    }

    // MARK: - AI 档为空：回落用户选择（仓不可达同理）

    func testNoAIFallsBackToUserSelection() {
        XCTAssertEqual(
            AgentAvatarChoice.resolve(
                userLocked: false, ai: nil, user: .custom
            ),
            .custom
        )
        XCTAssertEqual(
            AgentAvatarChoice.resolve(
                userLocked: true, ai: nil, user: .default
            ),
            .preset(id: AgentAvatarPreset.defaultID)
        )
        XCTAssertFalse(
            AgentAvatarChoice.aiImageWins(userLocked: false, ai: nil)
        )
    }

    // MARK: - 脏 id 收敛：仓里来的预置 id 不在目录内回落缺省款

    func testUnknownAIPresetIDResolvesToDefault() {
        XCTAssertEqual(
            AgentAvatarChoice.resolve(
                userLocked: false,
                ai: .preset(id: "no-such-preset"),
                user: .preset(id: "atom")
            ),
            .preset(id: AgentAvatarPreset.defaultID)
        )
    }
}
