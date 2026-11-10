import XCTest
@testable import OneDayCore

/// 抽屉单一选择政策闸（0.36.7，频道规格 §10.2/
/// §10.4）：五场景逐一钉——全抽屉任一时刻至多一
/// 枚胶囊。Tab 以 String 代（政策对页签类型泛型，
/// App 侧以 ContentView.MainTab 实例化）。0.36.29
/// 补频道两场景（§10.4 的 ④⑤）。
final class DrawerSelectionTests: XCTestCase {

    private let mainID = UUID()
    private let sideID = UUID()
    private let otherID = UUID()

    private func resolve(
        tab: String,
        object: DrawerCurrentObject?,
        landing: UUID? = nil
    ) -> DrawerSelection<String> {
        DrawerSelectionPolicy.resolve(
            currentTab: tab, chatTab: "chat",
            currentObject: object,
            landingThreadID: landing,
            mainThreadID: mainID
        )
    }

    // 场景一：看主线——只有主线聊天行带胶囊
    func testWatchingMainSelectsMain() {
        XCTAssertEqual(resolve(tab: "chat", object: .main), .main)
    }

    // 场景二：看旁聊——只有该旁聊行带胶囊、主线行无
    // （报障原图：双胶囊同框）
    func testWatchingSideSelectsOnlyThatSide() {
        let selection = resolve(tab: "chat", object: .side(sideID))
        XCTAssertEqual(selection, .side(sideID))
        XCTAssertNotEqual(selection, .main)
    }

    // 场景三：在非聊天页签开抽屉——胶囊归该导航行、
    // 所有会话行无胶囊（当前对象休眠不画假当前）
    func testNonChatSurfaceSelectsSurfaceAndSleepsObject() {
        XCTAssertEqual(
            resolve(tab: "feed", object: .side(sideID)),
            .surface("feed")
        )
        XCTAssertEqual(
            resolve(tab: "goals", object: .main),
            .surface("goals")
        )
    }

    // 场景四：从旁聊经抽屉回主线——引用改位后胶囊
    // 随之归主线行
    func testReturningToMainFromSideMovesSelection() {
        XCTAssertEqual(resolve(tab: "chat", object: .side(sideID)), .side(sideID))
        XCTAssertEqual(resolve(tab: "chat", object: .main), .main)
    }

    // 场景五：切页签再回聊天——页签上引用不清、回
    // 聊天时原对象恢复带胶囊
    func testTabRoundTripRestoresObjectSelection() {
        XCTAssertEqual(
            resolve(tab: "files", object: .side(sideID)),
            .surface("files")
        )
        XCTAssertEqual(
            resolve(tab: "chat", object: .side(sideID)),
            .side(sideID)
        )
    }

    // 无显式引用时按落点派生（§10.2 优先级 3）：落
    // 主线→.main、落旁聊→.side，与落点解析同果
    func testNoObjectDerivesFromLanding() {
        XCTAssertEqual(
            resolve(tab: "chat", object: nil, landing: mainID), .main
        )
        XCTAssertEqual(
            resolve(tab: "chat", object: nil, landing: otherID),
            .side(otherID)
        )
    }

    // 显式引用优先于落点派生（优先级 2 在 3 之前）
    func testObjectWinsOverLanding() {
        XCTAssertEqual(
            resolve(tab: "chat", object: .side(sideID), landing: mainID),
            .side(sideID)
        )
    }

    // 皆无从派生→.none，不画假当前
    func testNothingDerivableIsNone() {
        XCTAssertEqual(resolve(tab: "chat", object: nil), .none)
    }

    // 场景六（§10.4-④，0.36.29）：从频道页看会话
    // ——只有频道行带胶囊，主线聊天行与旁聊行皆无
    func testWatchingChannelSelectsOnlyChannelRow() {
        let selection = resolve(tab: "chat", object: .channel("hermes"))
        XCTAssertEqual(selection, .channel("hermes"))
        XCTAssertNotEqual(selection, .main)
        XCTAssertNotEqual(selection, .side(sideID))
    }

    // 场景七（§10.4-⑤，0.36.29）：收养后改从旁聊
    // 区进入同一条——对象引用由导航动作改位 .side，
    // 胶囊随之归旁聊行、频道行无胶囊
    func testReenteringAdoptedThreadFromSideListMovesSelection() {
        XCTAssertEqual(
            resolve(tab: "chat", object: .channel("hermes")),
            .channel("hermes")
        )
        XCTAssertEqual(
            resolve(tab: "chat", object: .side(sideID)), .side(sideID)
        )
    }

    // 频道引用在非聊天表面同样休眠（.surface 优先
    // 级 1 不因加值改变）
    func testChannelObjectSleepsOnNonChatSurface() {
        XCTAssertEqual(
            resolve(tab: "feed", object: .channel("hermes")),
            .surface("feed")
        )
    }

    // 线程 id → 对象引用派生（ChatView 同步点）
    func testObjectDerivationFromThreadID() {
        XCTAssertEqual(
            DrawerSelectionPolicy.object(
                forThreadID: mainID, mainThreadID: mainID
            ),
            .main
        )
        XCTAssertEqual(
            DrawerSelectionPolicy.object(
                forThreadID: sideID, mainThreadID: mainID
            ),
            .side(sideID)
        )
        XCTAssertNil(
            DrawerSelectionPolicy.object(
                forThreadID: nil, mainThreadID: mainID
            )
        )
    }
}
