import XCTest
@testable import OneDayCore

/// 抽屉旁聊区未收养行现算闸（2026-11-13 P2 真机判
/// 红修复）：AI 经伴生门面自开的旁聊（oneday-ai-）
/// 在服务端出生、本地无线程——分类进 .mine 却只有
/// 全部对话页消费，抽屉纯本地行源永不显。本闸钉住
/// 抽屉侧的现算口径：.mine 且未关联才入选、已关联
/// 防双出、频道/系统/主线/合并桶一律不漏入、两路
/// 拉取并集以新鲜页覆盖、活动时间倒序。
final class DrawerUnadoptedSideChatsTests: XCTestCase {

    private let mainSession = "oneday-main-11111111-2222-3333-4444-555555555555"
    /// 判红本尊形态：AI 16:39 铸的旁聊
    private let aiSession = "oneday-ai-bb04dce92e7a19a9b52421aa0f22d4ad"

    private func session(
        id: String,
        source: String? = nil,
        sessionKey: String? = nil,
        serverTitle: String? = nil,
        startedAt: Double? = nil,
        endedAt: Double? = nil
    ) -> ServerSession {
        ServerSession(
            id: id, source: source, sessionKey: sessionKey,
            displayName: nil, serverTitle: serverTitle,
            titleSource: nil,
            isArchived: nil, isPinned: nil, model: nil, profile: nil,
            startedAt: startedAt, endedAt: endedAt, endReason: nil,
            messageCount: nil, toolCallCount: nil,
            inputTokens: nil, outputTokens: nil
        )
    }

    private func pick(
        catalog: [ServerSession] = [],
        latestPage: [ServerSession] = [],
        linked: Set<String> = []
    ) -> [ServerSession] {
        DrawerUnadoptedSideChats.sessions(
            catalog: catalog,
            latestPage: latestPage,
            mainServerSessionID: mainSession,
            linkedThreadSessionIDs: linked
        )
    }

    // MARK: - 本尊归位

    func testAICastSessionIsPickedFromCatalog() {
        // 存量「爱的定义」：目录里现算即归位，不重建
        let rows = pick(catalog: [
            session(id: aiSession, source: "api_server",
                    serverTitle: "爱的定义", startedAt: 1_700_000_000)
        ])
        XCTAssertEqual(rows.map(\.id), [aiSession])
    }

    func testAICastSessionIsPickedFromLatestPageOnly() {
        // 目录冷缓存未含（刚建）：只在开抽屉刚拉的
        // 第一页里也必须入选（新鲜路兜底）
        let rows = pick(latestPage: [
            session(id: aiSession, source: "api_server",
                    serverTitle: "爱的定义", startedAt: 1_700_000_000)
        ])
        XCTAssertEqual(rows.map(\.id), [aiSession])
    }

    func testAppCastSessionWithoutLocalThreadIsPicked() {
        // R3 同口径：App 铸旁聊本地线程已删，与管理
        // 页「我的对话」段一致入选
        let orphan = "oneday-side-b3a5393d-0000-0000-0000-000000000000"
        let rows = pick(catalog: [
            session(id: orphan, source: "api_server", startedAt: 10)
        ])
        XCTAssertEqual(rows.map(\.id), [orphan])
    }

    // MARK: - 防双出与漏入

    func testLinkedSessionIsNotPicked() {
        // 已关联本地线程（收养完成）：本地行承载，
        // 未收养行剔除防双行
        let rows = pick(
            catalog: [
                session(id: aiSession, source: "api_server",
                        startedAt: 1_700_000_000)
            ],
            linked: [aiSession]
        )
        XCTAssertTrue(rows.isEmpty)
    }

    func testMainSessionIsNotPicked() {
        let rows = pick(catalog: [
            session(id: mainSession, source: "api_server",
                    startedAt: 1_700_000_000),
            session(
                id: "oneday-main-99999999-8888-7777-6666-555555555555",
                source: "api_server", startedAt: 1_700_000_000
            ),
        ])
        XCTAssertTrue(rows.isEmpty)
    }

    func testChannelAndSystemSessionsAreNotPicked() {
        let rows = pick(catalog: [
            // Hermes 频道：网页端自由形态会话
            session(id: "20261113_120000_abcd", source: "dashboard",
                    startedAt: 1_700_000_000),
            // 平台频道
            session(id: "tg-123", source: "telegram",
                    startedAt: 1_700_000_000),
            // 系统：结构性系统源
            session(id: "job-1", source: "kanban",
                    startedAt: 1_700_000_000),
            // 系统：runs 铸造
            session(id: "run_deadbeef", source: "api_server",
                    startedAt: 1_700_000_000),
            // 系统：部署侧铸 oneday-（非 main/side/ai）
            session(id: "oneday-ideas-gen", source: "api_server",
                    startedAt: 1_700_000_000),
            // 合并桶钦定两条之一
            session(id: "api-592647b9ae21ec54", source: "api_server",
                    startedAt: 1_700_000_000),
        ])
        XCTAssertTrue(rows.isEmpty)
    }

    // MARK: - 并集与排序

    func testLatestPageOverridesCatalogCopy() {
        // 同 id 两路都有：只出一条、取第一页的新鲜值
        let stale = session(
            id: aiSession, source: "api_server",
            serverTitle: nil, startedAt: 100
        )
        let fresh = session(
            id: aiSession, source: "api_server",
            serverTitle: "爱的定义", startedAt: 100
        )
        let rows = pick(catalog: [stale], latestPage: [fresh])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.serverTitle, "爱的定义")
    }

    func testSortedByActivityDescendingWithDatelessLast() {
        let older = "oneday-ai-00000000000000000000000000000001"
        let newer = "oneday-ai-00000000000000000000000000000002"
        let ended = "oneday-ai-00000000000000000000000000000003"
        let dateless = "oneday-ai-00000000000000000000000000000004"
        let rows = pick(catalog: [
            session(id: older, source: "api_server", startedAt: 100),
            // 活动时间取 endedAt（2000）而非 startedAt
            session(id: ended, source: "api_server",
                    startedAt: 50, endedAt: 2_000),
            session(id: dateless, source: "api_server"),
            session(id: newer, source: "api_server", startedAt: 500),
        ])
        XCTAssertEqual(
            rows.map(\.id), [ended, newer, older, dateless]
        )
    }

    func testActivityDatePrefersEndedAt() {
        let s = session(
            id: aiSession, source: "api_server",
            startedAt: 100, endedAt: 200
        )
        XCTAssertEqual(
            DrawerUnadoptedSideChats.activityDate(of: s),
            Date(timeIntervalSince1970: 200)
        )
        let running = session(
            id: aiSession, source: "api_server", startedAt: 100
        )
        XCTAssertEqual(
            DrawerUnadoptedSideChats.activityDate(of: running),
            Date(timeIntervalSince1970: 100)
        )
    }
}
