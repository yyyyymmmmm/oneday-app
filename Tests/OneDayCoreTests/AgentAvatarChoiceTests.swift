import XCTest
@testable import OneDayCore

/// 头像呈现裁决（末写胜，2026-11-13 用户拍板）：AI
/// 档与用户选择各带写入时刻、后写者胜，不按写者身
/// 分分权重（§203「用户手动选过则锁压 AI」已作废）
/// ——纯逻辑全在此，存储层与同步层只许消费。
final class AgentAvatarChoiceTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private var t1: Date { t0.addingTimeInterval(3600) }
    private var t2: Date { t0.addingTimeInterval(7200) }

    // MARK: - AI 后写：覆盖先写的用户选择（事故主案）

    /// 2026-11-13 事故复刻：用户早先选过 paw，AI 其
    /// 后在服务器换上自生成图——末写胜下必须显 AI 图
    func testAILaterWriteBeatsEarlierUserSelection() {
        XCTAssertEqual(
            AgentAvatarChoice.resolve(
                ai: .image(itemID: "av_new", updatedAt: t2),
                user: .preset(id: "paw"),
                userSelectedAt: t1
            ),
            .custom
        )
        XCTAssertTrue(
            AgentAvatarChoice.aiImageWins(
                ai: .image(itemID: "av_new", updatedAt: t2),
                userSelectedAt: t1
            )
        )
    }

    func testAILaterPresetBeatsEarlierUserSelection() {
        XCTAssertEqual(
            AgentAvatarChoice.resolve(
                ai: .preset(id: "sparkles", updatedAt: t2),
                user: .preset(id: "paw"),
                userSelectedAt: t1
            ),
            .preset(id: "sparkles")
        )
    }

    // MARK: - 用户后写：覆盖先写的 AI 档

    func testUserLaterSelectionBeatsEarlierAIImage() {
        XCTAssertEqual(
            AgentAvatarChoice.resolve(
                ai: .image(itemID: "av_old", updatedAt: t0),
                user: .preset(id: "atom"),
                userSelectedAt: t1
            ),
            .preset(id: "atom")
        )
        XCTAssertFalse(
            AgentAvatarChoice.aiImageWins(
                ai: .image(itemID: "av_old", updatedAt: t0),
                userSelectedAt: t1
            )
        )
    }

    func testUserLaterCustomBeatsEarlierAIPreset() {
        XCTAssertEqual(
            AgentAvatarChoice.resolve(
                ai: .preset(id: "paw", updatedAt: t0),
                user: .custom,
                userSelectedAt: t1
            ),
            .custom
        )
        XCTAssertFalse(
            AgentAvatarChoice.aiImageWins(
                ai: .preset(id: "paw", updatedAt: t0),
                userSelectedAt: t1
            )
        )
    }

    // MARK: - 旧时间戳写入不得覆盖新值

    /// AI 档是旧时刻的同步残值（例如重选前的投影）：
    /// 哪怕内容更新，也不得压过时刻更晚的用户选择
    func testStaleAITimestampNeverBeatsNewerUserSelection() {
        XCTAssertEqual(
            AgentAvatarChoice.resolve(
                ai: .image(itemID: "av_stale", updatedAt: t0),
                user: .preset(id: "sparkles"),
                userSelectedAt: t2
            ),
            .preset(id: "sparkles")
        )
        XCTAssertFalse(
            AgentAvatarChoice.aiWins(
                ai: .preset(id: "paw", updatedAt: t0),
                userSelectedAt: t2
            )
        )
    }

    // MARK: - 用户从未选择（无时刻）：AI 档胜

    /// 缺省档案没有「写入时刻」可言，不许挡住 AI 的
    /// 真实写入（未碰过编辑器的用户自动跟随仓）
    func testAIWinsWhenUserNeverSelected() {
        XCTAssertEqual(
            AgentAvatarChoice.resolve(
                ai: .preset(id: "paw", updatedAt: t0),
                user: .default,
                userSelectedAt: nil
            ),
            .preset(id: "paw")
        )
        XCTAssertTrue(
            AgentAvatarChoice.aiImageWins(
                ai: .image(itemID: "av_9", updatedAt: t0),
                userSelectedAt: nil
            )
        )
    }

    // MARK: - 同刻：取服务器（多端同源）

    func testTieGoesToServer() {
        XCTAssertTrue(
            AgentAvatarChoice.aiWins(
                ai: .image(itemID: "av_tie", updatedAt: t1),
                userSelectedAt: t1
            )
        )
    }

    // MARK: - AI 档为空：回落用户选择（仓不可达同理）

    func testNoAIFallsBackToUserSelection() {
        XCTAssertEqual(
            AgentAvatarChoice.resolve(
                ai: nil, user: .custom, userSelectedAt: t1
            ),
            .custom
        )
        XCTAssertEqual(
            AgentAvatarChoice.resolve(
                ai: nil, user: .default, userSelectedAt: nil
            ),
            .preset(id: AgentAvatarPreset.defaultID)
        )
        XCTAssertFalse(
            AgentAvatarChoice.aiImageWins(ai: nil, userSelectedAt: t1)
        )
    }

    // MARK: - 脏 id 收敛：仓里来的预置 id 不在目录内回落缺省款

    func testUnknownAIPresetIDResolvesToDefault() {
        XCTAssertEqual(
            AgentAvatarChoice.resolve(
                ai: .preset(id: "no-such-preset", updatedAt: t1),
                user: .preset(id: "atom"),
                userSelectedAt: t0
            ),
            .preset(id: AgentAvatarPreset.defaultID)
        )
    }
}
