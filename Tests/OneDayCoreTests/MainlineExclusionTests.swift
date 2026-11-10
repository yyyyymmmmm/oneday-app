import XCTest
@testable import OneDayCore

/// 主线排除闸（0.29.0，用户 12:31 点名「主线聊天不
/// 需要出现在旁聊里面」）：一切以旁聊名义呈现的名
/// 单，主线判定只许过 SideChatClassifier.isMain 双信
/// 号单一函数。本组测钉：①本地线程——钦定 id 命中
/// 是主线②本地线程——钦定不是它、但它绑着主线会
/// 话（钦定 id 或 oneday-main- 前缀）也必须判主线
/// （单信号缺口的回归闸）③普通旁聊（无关联/绑自有
/// oneday-side-/绑服务端派生桶）恒非主线，旁聊集非
/// 空性不回归④服务端会话——钦定命中与前缀命中是
/// 主线、其余非主线⑤无钦定时的行为（本地恒非主
/// 线、服务端只剩前缀信号）。
final class MainlineExclusionTests: XCTestCase {

    private let mainThread = UUID()
    private let sideA = UUID()
    private let sideB = UUID()
    private let mainSession = "oneday-main-11111111-2222-3333-4444-555555555555"
    private let sideSession = "oneday-side-11111111-2222-3333-4444-555555555555"

    // MARK: - 本地线程判定

    func testDesignatedLocalThreadIsMain() {
        XCTAssertTrue(SideChatClassifier.isMain(
            localThreadID: mainThread, linkedServerSessionID: mainSession,
            mainThreadID: mainThread, mainServerSessionID: mainSession
        ))
    }

    /// 回归闸：钦定 id 指向他条时，绑着主线会话的那
    /// 条真主线对话不许漏进旁聊集
    func testThreadBoundToMainSessionIsMainEvenWhenNotDesignated() {
        XCTAssertTrue(SideChatClassifier.isMain(
            localThreadID: sideA, linkedServerSessionID: mainSession,
            mainThreadID: mainThread, mainServerSessionID: mainSession
        ))
    }

    /// 钦定会话 id 本地未存（nil）时，前缀信号兜底
    func testThreadBoundToPrefixedMainSessionIsMain() {
        XCTAssertTrue(SideChatClassifier.isMain(
            localThreadID: sideA,
            linkedServerSessionID: "oneday-main-99999999-8888-7777-6666-555555555555",
            mainThreadID: mainThread, mainServerSessionID: nil
        ))
    }

    func testOrdinarySideThreadsAreNotMain() {
        // 无关联会话的本地旁聊
        XCTAssertFalse(SideChatClassifier.isMain(
            localThreadID: sideA, linkedServerSessionID: nil,
            mainThreadID: mainThread, mainServerSessionID: mainSession
        ))
        // 绑自有 oneday-side- 会话的旁聊
        XCTAssertFalse(SideChatClassifier.isMain(
            localThreadID: sideA, linkedServerSessionID: sideSession,
            mainThreadID: mainThread, mainServerSessionID: mainSession
        ))
        // 绑服务端派生桶（api-）的导入线程：是合并历
        // 史、不是主线本体，仍按旁聊集成员论（其处置
        // 口径在 0.27.0 删除闸，不在本判定）
        XCTAssertFalse(SideChatClassifier.isMain(
            localThreadID: sideB,
            linkedServerSessionID: "api-592647b9ae21ec54",
            mainThreadID: mainThread, mainServerSessionID: mainSession
        ))
        // 空串关联按无关联论
        XCTAssertFalse(SideChatClassifier.isMain(
            localThreadID: sideB, linkedServerSessionID: "",
            mainThreadID: mainThread, mainServerSessionID: mainSession
        ))
    }

    func testNoDesignationMeansNoLocalMain() {
        XCTAssertFalse(SideChatClassifier.isMain(
            localThreadID: sideA, linkedServerSessionID: nil,
            mainThreadID: nil, mainServerSessionID: nil
        ))
    }

    /// 旁聊集组装（与抽屉行源同式：isMain 剔主线后
    /// 再过 DrawerSideChatFilter 行显）：主线两形态
    /// 全剔、真旁聊留全、集非空
    func testSideRosterExcludesEveryMainShapeAndKeepsSides() {
        struct Row {
            let id: UUID
            let linked: String?
            let source: String?
        }
        let rows = [
            Row(id: mainThread, linked: mainSession, source: "api_server"),
            Row(id: sideA, linked: mainSession, source: "api_server"),
            Row(id: sideB, linked: sideSession, source: "api_server"),
            Row(id: UUID(), linked: nil, source: nil),
        ]
        let sideSet = rows.filter { row in
            !SideChatClassifier.isMain(
                localThreadID: row.id, linkedServerSessionID: row.linked,
                mainThreadID: mainThread, mainServerSessionID: mainSession
            ) && DrawerSideChatFilter.threadListed(
                isMainThread: false, isLocallyArchived: false,
                linkedSource: row.source
            )
        }
        XCTAssertEqual(sideSet.map(\.id), [sideB, rows[3].id])
        XCTAssertFalse(sideSet.isEmpty, "旁聊集不许被误杀至空")
    }

    // MARK: - 服务端会话判定（管理页站内/已归档段同式）

    func testDesignatedServerSessionIsMain() {
        XCTAssertTrue(SideChatClassifier.isMain(
            serverSessionID: mainSession, mainServerSessionID: mainSession
        ))
    }

    func testPrefixedServerSessionIsMain() {
        XCTAssertTrue(SideChatClassifier.isMain(
            serverSessionID: "oneday-main-aaaaaaa1-bbbb-cccc-dddd-eeeeeeeeeeee",
            mainServerSessionID: mainSession
        ))
        // 无钦定存值时前缀仍判主线（如换机后钦定未回存）
        XCTAssertTrue(SideChatClassifier.isMain(
            serverSessionID: mainSession, mainServerSessionID: nil
        ))
    }

    func testOrdinaryServerSessionsAreNotMain() {
        for id in [
            sideSession,
            "api-592647b9ae21ec54",
            "api-e8c923beeaebed9c",
            "oneday-probe-20261110",
            "combo-smoke-pro-1109",
        ] {
            XCTAssertFalse(
                SideChatClassifier.isMain(
                    serverSessionID: id, mainServerSessionID: mainSession
                ),
                id
            )
        }
    }
}
