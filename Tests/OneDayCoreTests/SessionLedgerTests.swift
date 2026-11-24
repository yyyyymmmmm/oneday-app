import Foundation
import XCTest
@testable import OneDayCore

/// 第 67 条会话账本包一（2026-11-15）Core 钉测：
/// 合并名单＋投影纯函数。核心锚点是「与旧实现逐面
/// 等值」——抽屉本地行/未收养行以旧口径（Drawer-
/// SideChatFilter/DrawerUnadoptedSideChats/归档键）
/// 在同夹具上现算对照；另钉：出生证明规则号与分
/// 类层的一致性矩阵、归档列双来源、标题两管线口
/// 径、管理页两段与频道投影
final class SessionLedgerTests: XCTestCase {

    // MARK: - 夹具

    private func makeSession(
        id: String, source: String? = nil,
        title: String? = nil, displayName: String? = nil,
        startedAt: Double? = nil, endedAt: Double? = nil
    ) -> ServerSession {
        var fields: [String] = ["\"id\":\"\(id)\""]
        if let source { fields.append("\"source\":\"\(source)\"") }
        if let title { fields.append("\"title\":\"\(title)\"") }
        if let displayName {
            fields.append("\"display_name\":\"\(displayName)\"")
        }
        if let startedAt {
            fields.append("\"started_at\":\(startedAt)")
        }
        if let endedAt { fields.append("\"ended_at\":\(endedAt)") }
        let json = "{" + fields.joined(separator: ",") + "}"
        return try! JSONDecoder().decode(
            ServerSession.self, from: Data(json.utf8)
        )
    }

    private func makeThread(
        title: String = "本地标题", titleIsManual: Bool = false,
        sessionID: String? = nil, pending: Bool = false,
        updatedAt: Date = Date(timeIntervalSince1970: 1_000),
        linkFailures: Int = 0
    ) -> LedgerLocalThread {
        LedgerLocalThread(
            id: UUID(), title: title,
            titleIsManual: titleIsManual,
            serverSessionID: sessionID,
            isPendingDeletion: pending, isPinned: false,
            updatedAt: updatedAt,
            createdAt: updatedAt.addingTimeInterval(-60),
            linkFailureCount: linkFailures, linkLastError: nil
        )
    }

    private func makeInputs(
        mainThreadID: UUID? = nil,
        mainServerSessionID: String? = nil,
        archivedKeys: Set<String> = [],
        pending: Set<String> = [],
        firstUserMessages: [String: String] = [:]
    ) -> SessionLedgerMerge.Inputs {
        SessionLedgerMerge.Inputs(
            mainThreadID: mainThreadID,
            mainServerSessionID: mainServerSessionID,
            archivedKeys: archivedKeys,
            pendingDeletionIDs: pending,
            firstUserMessages: firstUserMessages
        )
    }

    // MARK: - 合并形态

    /// 线程＋其关联会话合并为一条记录（不双出）
    func testMergeLinksThreadAndSessionIntoOneRecord() {
        let session = makeSession(
            id: "s-1", source: "api_server", title: "服务端名"
        )
        let thread = makeThread(sessionID: "s-1")
        let records = SessionLedgerMerge.records(
            visible: [session], archived: [],
            localThreads: [thread], inputs: makeInputs()
        )
        XCTAssertEqual(records.count, 1)
        let record = records[0]
        XCTAssertEqual(record.localThreadID, thread.id)
        XCTAssertEqual(record.serverSessionID, "s-1")
        XCTAssertEqual(record.segment, .visible)
        XCTAssertEqual(record.title, "服务端名")
        XCTAssertEqual(record.linkPhase, .linked)
        XCTAssertEqual(record.ledgerID, "local:\(thread.id.uuidString)")
    }

    /// 纯本地线程：本地出生即证明（origin 恒 mine），
    /// 链接失败留痕进 linkPhase 列不丢
    func testMergePureLocalThreadRecord() {
        let plain = makeThread()
        let failed = makeThread(linkFailures: 2)
        let records = SessionLedgerMerge.records(
            visible: [], archived: [],
            localThreads: [plain, failed], inputs: makeInputs()
        )
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records[0].origin, .mine)
        XCTAssertEqual(records[0].linkPhase, .unlinked)
        XCTAssertNil(records[0].session)
        XCTAssertEqual(records[0].segment, .none)
        XCTAssertEqual(records[1].linkPhase, .failed(count: 2))
    }

    /// 未收养的 AI 铸旁聊（R3b）：server 形态入账
    func testMergeUnadoptedAICastSession() {
        let session = makeSession(
            id: "oneday-ai-abc", source: "api_server"
        )
        let records = SessionLedgerMerge.records(
            visible: [session], archived: [],
            localThreads: [], inputs: makeInputs()
        )
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].origin, .mine)
        XCTAssertEqual(records[0].birthRule, "R3b")
        XCTAssertEqual(records[0].ledgerID, "server:oneday-ai-abc")
        XCTAssertNil(records[0].localThreadID)
    }

    // MARK: - 出生证明规则↔分类层一致性矩阵

    func testBirthRuleMatchesClassifierLayer() {
        let mainID = "oneday-main-abc"
        let linked: Set<String> = ["s-linked"]
        let cases: [(id: String, source: String?,
                     rule: String, layer: SessionLayer)] = [
            ("oneday-main-abc", "api_server", "R0", .main),
            ("api-592647b9ae21ec54", "api_server", "R1",
             .mergeBucket),
            ("s-linked", "api_server", "R2", .mine),
            ("oneday-side-xyz", "api_server", "R3", .mine),
            ("oneday-ai-xyz", "api_server", "R3b", .mine),
            ("oneday-ideas-gen", "api_server", "R4", .system),
            ("run_abc123", "api_server", "R4b", .system),
            ("api_123456", "api_server", "R4b", .system),
            ("s-cron", "cron", "R5", .system),
            ("s-wa", "whatsapp", "R6", .channel("whatsapp")),
            ("s-dash", "dashboard", "R7",
             .channel(ChannelRegistry.hermesChannelID)),
            ("550e8400-e29b-41d4-a716-446655440000",
             "api_server", "R8/R9",
             .channel(ChannelRegistry.hermesChannelID)),
        ]
        for entry in cases {
            let layer = SessionClassifier.classify(
                id: entry.id, source: entry.source,
                sessionKey: nil, mainServerSessionID: mainID,
                linkedThreadSessionIDs: linked
            )
            let rule = SessionLedgerMerge.birthRule(
                id: entry.id, source: entry.source,
                sessionKey: nil, mainServerSessionID: mainID,
                linkedThreadSessionIDs: linked
            )
            XCTAssertEqual(layer, entry.layer, "层：\(entry.id)")
            XCTAssertEqual(rule, entry.rule, "规则：\(entry.id)")
        }
    }

    // MARK: - 抽屉行集等值（旧口径同夹具现算对照）

    /// 旧抽屉本地行口径现算（drawerItems＋side-
    /// Threads 两段过滤，source 取同批名单映射；
    /// 夹具取 §233 对齐后状态——归档键与服务端段
    /// 一致）
    private func legacyDrawerThreadIDs(
        threads: [LedgerLocalThread],
        sessions: [ServerSession],
        inputs: SessionLedgerMerge.Inputs
    ) -> [UUID] {
        let sources = Dictionary(
            uniqueKeysWithValues: sessions.map {
                ($0.id, $0.source ?? "")
            }
        )
        return threads
            .filter {
                !$0.isPendingDeletion
                    && !SideChatArchive.isArchived(
                        localThreadID: $0.id,
                        archivedKeys: inputs.archivedKeys
                    )
            }
            .filter {
                DrawerSideChatFilter.threadListed(
                    isMainThread: SideChatClassifier.isMain(
                        localThreadID: $0.id,
                        linkedServerSessionID: $0.serverSessionID,
                        mainThreadID: inputs.mainThreadID,
                        mainServerSessionID: inputs
                            .mainServerSessionID
                    ),
                    isLocallyArchived: false,
                    linkedSource: $0.serverSessionID.flatMap {
                        sources[$0]
                    }
                )
            }
            .map(\.id)
    }

    func testDrawerLocalRowsMatchLegacy() {
        let mainThread = makeThread(sessionID: "oneday-main-abc")
        let normal = makeThread(sessionID: "s-normal")
        let kanban = makeThread(sessionID: "s-kanban")
        let archivedLocal = makeThread()
        let pendingThread = makeThread(
            sessionID: "s-pending", pending: true
        )
        let pureLocal = makeThread()
        let threads = [mainThread, normal, kanban,
                       archivedLocal, pendingThread, pureLocal]
        let sessions = [
            makeSession(id: "oneday-main-abc", source: "api_server"),
            makeSession(id: "s-normal", source: "api_server"),
            makeSession(id: "s-kanban", source: "kanban"),
            makeSession(id: "s-pending", source: "api_server"),
        ]
        let inputs = makeInputs(
            mainThreadID: mainThread.id,
            mainServerSessionID: "oneday-main-abc",
            archivedKeys: [
                SideChatArchive.localKey(archivedLocal.id)
            ]
        )
        let records = SessionLedgerMerge.records(
            visible: sessions, archived: [],
            localThreads: threads, inputs: inputs
        )
        let projected = LedgerProjection
            .drawerLocalRows(records)
            .compactMap(\.localThreadID)
        let legacy = legacyDrawerThreadIDs(
            threads: threads, sessions: sessions, inputs: inputs
        )
        XCTAssertEqual(projected, legacy)
        XCTAssertEqual(
            projected, [normal.id, pureLocal.id]
        )
    }

    func testDrawerUnadoptedRowsMatchLegacy() {
        let adopted = makeSession(
            id: "oneday-side-ddd", source: "api_server",
            startedAt: 1_700_000_500
        )
        let sessions = [
            makeSession(
                id: "s-dash", source: "dashboard",
                startedAt: 1_700_000_400
            ),
            makeSession(
                id: "oneday-ai-aaa", source: "api_server",
                startedAt: 1_700_000_300
            ),
            makeSession(
                id: "oneday-side-bbb", source: "api_server",
                startedAt: 1_700_000_200
            ),
            adopted,
            makeSession(
                id: "oneday-main-abc", source: "api_server",
                startedAt: 1_700_000_600
            ),
        ]
        let thread = makeThread(sessionID: "oneday-side-ddd")
        let inputs = makeInputs(
            mainServerSessionID: "oneday-main-abc"
        )
        let records = SessionLedgerMerge.records(
            visible: sessions, archived: [],
            localThreads: [thread], inputs: inputs
        )
        let projected = LedgerProjection
            .drawerUnadoptedRows(records)
            .compactMap(\.serverSessionID)
        let legacy = DrawerUnadoptedSideChats.sessions(
            catalog: sessions, latestPage: sessions,
            mainServerSessionID: "oneday-main-abc",
            linkedThreadSessionIDs: ["oneday-side-ddd"]
        ).map(\.id)
        XCTAssertEqual(projected, legacy)
        XCTAssertEqual(
            projected, ["oneday-ai-aaa", "oneday-side-bbb"]
        )
    }

    /// 合并行序：活动时间倒序、本地与未收养同区平铺
    func testDrawerSideRowsMergeOrder() {
        let older = makeThread(
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let newer = makeThread(
            updatedAt: Date(timeIntervalSince1970: 300)
        )
        let unadopted = makeSession(
            id: "oneday-ai-mid", source: "api_server",
            startedAt: 200
        )
        let records = SessionLedgerMerge.records(
            visible: [unadopted], archived: [],
            localThreads: [older, newer], inputs: makeInputs()
        )
        let rows = LedgerProjection.drawerSideRows(records)
        XCTAssertEqual(
            rows.map(\.ledgerID),
            ["local:\(newer.id.uuidString)",
             "server:oneday-ai-mid",
             "local:\(older.id.uuidString)"]
        )
    }

    // MARK: - 管理页两段与频道投影

    func testManagementProjectionsExcludePendingKeepOrder() {
        let visible = [
            makeSession(id: "a"), makeSession(id: "b"),
            makeSession(id: "c"),
        ]
        let archived = [makeSession(id: "d")]
        let records = SessionLedgerMerge.records(
            visible: visible, archived: archived,
            localThreads: [],
            inputs: makeInputs(pending: ["b"])
        )
        XCTAssertEqual(
            LedgerProjection.managementVisible(records)
                .map(\.id),
            ["a", "c"]
        )
        XCTAssertEqual(
            LedgerProjection.managementArchived(records)
                .map(\.id),
            ["d"]
        )
        XCTAssertEqual(
            LedgerProjection.hubSessions(records).map(\.id),
            ["a", "c"]
        )
    }

    func testChannelListHermesIncludesMergeBucket() {
        let sessions = [
            makeSession(id: "s-dash", source: "dashboard"),
            makeSession(
                id: "api-592647b9ae21ec54", source: "api_server"
            ),
            makeSession(id: "s-wa", source: "whatsapp"),
        ]
        let records = SessionLedgerMerge.records(
            visible: sessions, archived: [],
            localThreads: [], inputs: makeInputs()
        )
        XCTAssertEqual(
            LedgerProjection.channelList(
                records,
                channelID: ChannelRegistry.hermesChannelID
            ).map(\.id),
            ["s-dash", "api-592647b9ae21ec54"]
        )
        XCTAssertEqual(
            LedgerProjection.channelList(
                records, channelID: "whatsapp"
            ).map(\.id),
            ["s-wa"]
        )
    }

    // MARK: - 归档列双来源

    func testArchiveColumnSources() {
        // 过回写闸的绑定线程在已归档段：服务端为准
        let bound = makeThread(sessionID: "s-arch")
        // 主线线程：本地键为准（不在回写闸内）
        let mainThread = makeThread(sessionID: "oneday-main-abc")
        // 纯本地线程：本地键为准
        let pureLocal = makeThread()
        let inputs = makeInputs(
            mainThreadID: mainThread.id,
            mainServerSessionID: "oneday-main-abc",
            archivedKeys: [
                SideChatArchive.localKey(pureLocal.id)
            ]
        )
        let records = SessionLedgerMerge.records(
            visible: [],
            archived: [
                makeSession(id: "s-arch", source: "api_server"),
                makeSession(
                    id: "oneday-main-abc", source: "api_server"
                ),
            ],
            localThreads: [bound, mainThread, pureLocal],
            inputs: inputs
        )
        let byThread = Dictionary(
            uniqueKeysWithValues: records.compactMap {
                record in
                record.localThreadID.map { ($0, record) }
            }
        )
        XCTAssertEqual(byThread[bound.id]?.archived, true)
        XCTAssertEqual(
            byThread[bound.id]?.archiveSource, .server
        )
        XCTAssertEqual(byThread[mainThread.id]?.archived, false)
        XCTAssertEqual(
            byThread[mainThread.id]?.archiveSource, .local
        )
        XCTAssertEqual(byThread[pureLocal.id]?.archived, true)
        XCTAssertEqual(
            byThread[pureLocal.id]?.archiveSource, .local
        )
    }

    // MARK: - 标题口径（两管线收归属、不改呈现）

    func testTitlePipelines() {
        let named = makeSession(
            id: "s-named", source: "api_server", title: "服务端名"
        )
        let manual = makeThread(
            title: "手改名", titleIsManual: true,
            sessionID: "s-named"
        )
        let follower = makeThread(
            title: "本地快照", sessionID: "s-named"
        )
        let records = SessionLedgerMerge.records(
            visible: [named], archived: [],
            localThreads: [manual], inputs: makeInputs()
        )
        XCTAssertEqual(records[0].title, "手改名")
        let records2 = SessionLedgerMerge.records(
            visible: [named], archived: [],
            localThreads: [follower], inputs: makeInputs()
        )
        XCTAssertEqual(records2[0].title, "服务端名")

        // 服务端行：resolvedTitle 管线（派生回落）
        let untitled = makeSession(
            id: "s-untitled", source: "api_server"
        )
        let derived = SessionLedgerMerge.records(
            visible: [untitled], archived: [],
            localThreads: [],
            inputs: makeInputs(
                firstUserMessages: ["s-untitled": "第一条消息"]
            )
        )
        XCTAssertEqual(derived[0].title, "第一条消息")
        let unnamed = SessionLedgerMerge.records(
            visible: [untitled], archived: [],
            localThreads: [], inputs: makeInputs()
        )
        XCTAssertEqual(unnamed[0].title, "未命名会话")
    }
}
