import Foundation
import OneDayCore
import SwiftData
import XCTest
@testable import OneDayApp

/// 本地库版本迁移地基（根治版包 3，DESIGN §332；
/// 待办第 122 条 G-05）验收钉测：
/// ①指纹＝两版存储属性全集钉死（V1 冻结副本与已
/// 发布库逐一一致、V3＝现行模型＝V2＋台账 154 一
/// 字段，原地改任一版模型必红）；
/// ②V1/V2 形态旧库经迁移链工厂打开、轻量迁移到现行版
/// 零丢失＋迁移前备份存在且可按 V1 打开；③备份
/// 轮转保留 2 组；
/// ④打开失败注入→降级明示＋留痕＋原文件与备份
/// 都保留，不许静默吞、不许装作空库；
/// ⑤侧账解码失败→留痕＋人话提示＋自愈标记，消
/// 费时真走重新发现（改认失效指针/目录不可达保
/// 留提示），键缺席不算失败、健康状态不误报。
/// §184 容器租约：本类全部容器经 SwiftDataTest-
/// Mount 进程级持有、永不释放（文件库落临时目录）
@MainActor
final class SchemaFoundationAppTests: XCTestCase {

    private var swiftDataMount = SwiftDataTestMount()
    private let queueKey = "sessionDeletions.pendingQueue"
    private var suites: [String] = []

    override func setUp() async throws {
        try await super.setUp()
        UserDefaults.standard.removeObject(forKey: queueKey)
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: queueKey)
        for suite in suites {
            UserDefaults.standard.removePersistentDomain(
                forName: suite
            )
        }
        suites = []
        await swiftDataMount.release()
        try await super.tearDown()
    }

    // MARK: - 装配辅助

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "schema-foundation-\(UUID().uuidString)"
            )
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true
        )
        return dir
    }

    private func scratchDefaults() -> UserDefaults {
        let suite = "schema-foundation-\(UUID().uuidString)"
        suites.append(suite)
        return UserDefaults(suiteName: suite)!
    }

    private func copyStoreSet(
        from source: URL, to destination: URL
    ) throws {
        for suffix in ["", "-wal", "-shm"] {
            let src = URL(
                fileURLWithPath: source.path + suffix
            )
            if FileManager.default.fileExists(atPath: src.path) {
                try FileManager.default.copyItem(
                    at: src,
                    to: URL(
                        fileURLWithPath: destination.path + suffix
                    )
                )
            }
        }
    }

    // MARK: - ① 指纹（V1 冻结＋V2 现行，两版全集钉死）

    func testSchemaFingerprintsPinnedForV1V2AndV3() {
        // 存储属性全集钉死：原地改任一版模型（加/删/
        // 改名字段）必然在此触发红——冻结的机械守卫
        let allowedExtras: Set<String> = [
            "entries", "thread",
            "toolCardCacheValue", "toolCardCacheSource",
        ]
        let expectedThread: Set<String> = [
            "id", "title", "createdAt", "updatedAt",
            "isPinned", "serverSessionID", "titleIsManual",
            "linkFailureCount", "linkLastError", "linkedModel",
            "serverSeeded", "historyUnsynced",
            "historyServerCount", "historyLoadedCount",
            "seedSyncStateRaw", "isPendingDeletion",
        ]
        let expectedEntryV1: Set<String> = [
            "id", "role", "content", "imageData",
            "imageDatasData", "quoteRole", "quoteContent",
            "feedPostID", "feedPostTitle", "feedPostBody",
            "feedPostSource", "ideaQuoteID", "ideaQuoteTitle",
            "ideaQuoteBody", "fileQuoteName", "fileQuotePath",
            "goalQuoteCategory", "reasoning", "reasoningSeconds",
            "toolCardData", "remoteImagePathsData",
            "remoteFilePathsData", "echoKey", "approvalKey",
            "traceKey", "traceEchoData", "sendFailed",
            "sendStateRaw", "deliveryState", "createdAt",
        ]
        // 台账 187：V2 在 V1 全集上只加两可选字段
        let expectedEntryV2 = expectedEntryV1.union([
            "serverRowID", "reactionsData",
        ])
        // 台账 154：V3 在 V2 全集上只加一可选字段
        let expectedEntryV3 = expectedEntryV2.union([
            "clientMessageID",
        ])

        // V1：冻结副本——实体名与已发布库一致（迁移
        // 按名对位、改名即灾难）、存储全集逐一钉死
        let v1 = Schema(versionedSchema: ChatSchemaV1.self)
        XCTAssertEqual(
            Set(v1.entities.map(\.name)),
            ["ChatThread", "ChatEntry"]
        )
        XCTAssertEqual(
            ChatSchemaV1.versionIdentifier, Schema.Version(1, 0, 0)
        )
        XCTAssertEqual(ChatSchemaV1.versionTag, "1.0.0")
        assertStoredSet(
            v1, entity: "ChatThread", expected: expectedThread,
            allowedExtras: allowedExtras
        )
        assertStoredSet(
            v1, entity: "ChatEntry", expected: expectedEntryV1,
            allowedExtras: allowedExtras
        )

        // V2：冻结副本（ChatSchemaV2Models.swift）——
        // 全集＝V1＋两新字段，逐字冻结永不再改
        let v2 = Schema(versionedSchema: ChatSchemaV2.self)
        XCTAssertEqual(
            ChatSchemaV2.versionIdentifier, Schema.Version(2, 0, 0)
        )
        XCTAssertEqual(ChatSchemaV2.versionTag, "2.0.0")
        assertStoredSet(
            v2, entity: "ChatThread", expected: expectedThread,
            allowedExtras: allowedExtras
        )
        assertStoredSet(
            v2, entity: "ChatEntry", expected: expectedEntryV2,
            allowedExtras: allowedExtras
        )

        // V3／现行：裸 Schema（现行模型）与 V3 逐实体
        // 逐属性一致、全集＝V2＋clientMessageID
        let plain = Schema([ChatThread.self, ChatEntry.self])
        let v3 = Schema(versionedSchema: ChatSchemaV3.self)
        XCTAssertEqual(
            Set(plain.entities.map(\.name)),
            Set(v3.entities.map(\.name))
        )
        for entity in plain.entities {
            let counterpart = v3.entities.first {
                $0.name == entity.name
            }
            XCTAssertNotNil(counterpart, entity.name)
            XCTAssertEqual(
                Set(entity.properties.map(\.name)),
                Set(counterpart?.properties.map(\.name) ?? []),
                entity.name
            )
        }
        XCTAssertEqual(
            ChatSchemaV3.versionIdentifier, Schema.Version(3, 0, 0)
        )
        XCTAssertEqual(ChatSchemaV3.versionTag, "3.0.0")
        assertStoredSet(
            v3, entity: "ChatThread", expected: expectedThread,
            allowedExtras: allowedExtras
        )
        assertStoredSet(
            v3, entity: "ChatEntry", expected: expectedEntryV3,
            allowedExtras: allowedExtras
        )

        // 迁移链：三版在册、V1→V2→V3 两段轻量迁移
        XCTAssertEqual(ChatMigrationPlan.schemas.count, 3)
        XCTAssertEqual(ChatMigrationPlan.stages.count, 2)
    }

    /// 存储属性全集断言（两版共用）：期望集须全在、
    /// 多出的只许是关系与瞬态缓存（allowedExtras）
    private func assertStoredSet(
        _ schema: Schema, entity name: String,
        expected: Set<String>, allowedExtras: Set<String>,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let props = Set(
            schema.entities
                .first { $0.name == name }?
                .properties.map(\.name) ?? []
        )
        XCTAssertTrue(
            expected.isSubset(of: props),
            "\(name) 缺属性：\(expected.subtracting(props))",
            file: file, line: line
        )
        XCTAssertTrue(
            props.subtracting(expected)
                .isSubset(of: allowedExtras),
            "\(name) 多出未登记属性：\(props.subtracting(expected))",
            file: file, line: line
        )
    }

    // MARK: - ② V1/V2 旧库经迁移链打开（轻量迁移到现行版）＋备份实证

    func testV1StoreOpensThroughMigrationChainWithZeroLoss()
        throws {
        let dir = try tempDir()
        let sourceURL = dir.appendingPathComponent("default.store")
        // V1 形态：以冻结 V1 schema 建库写数（模拟
        // 0.50.75 已发布库），模型用 V1 冻结副本
        let v1Schema = Schema(versionedSchema: ChatSchemaV1.self)
        let writer = try ModelContainer(
            for: v1Schema,
            configurations: [ModelConfiguration(
                schema: v1Schema, url: sourceURL
            )]
        )
        swiftDataMount.retain(writer)
        let writeContext = ModelContext(writer)
        let thread = ChatSchemaV1.ChatThread(title: "旧库主线")
        thread.serverSessionID = "srv-main-69"
        thread.isPinned = true
        thread.linkFailureCount = 2
        writeContext.insert(thread)
        writeContext.insert(
            ChatSchemaV1.ChatEntry(
                role: "user", content: "第一条", thread: thread
            )
        )
        writeContext.insert(
            ChatSchemaV1.ChatEntry(
                role: "assistant", content: "第二条", thread: thread
            )
        )
        try writeContext.save()

        // 旧库文件复制一份作演练面（文件本体即 V1
        // 库形态），经新工厂（备份＋迁移链）打开：
        // V1→V2→V3 轻量迁移在容器 init 内沿链走完
        let drillURL = dir.appendingPathComponent("drill.store")
        try copyStoreSet(from: sourceURL, to: drillURL)
        let bootstrap = ChatModelContainerBootstrapFactory
            .makePersistent(storeURL: drillURL)
        XCTAssertFalse(bootstrap.usesFallback)
        XCTAssertNil(bootstrap.failureMessage)
        let container = try XCTUnwrap(bootstrap.container)
        swiftDataMount.retain(container)

        let context = ModelContext(container)
        let threads = try context.fetch(
            FetchDescriptor<ChatThread>()
        )
        let entries = try context.fetch(
            FetchDescriptor<ChatEntry>()
        )
        XCTAssertEqual(threads.count, 1)
        XCTAssertEqual(entries.count, 2)
        let opened = try XCTUnwrap(threads.first)
        XCTAssertEqual(opened.title, "旧库主线")
        XCTAssertEqual(opened.serverSessionID, "srv-main-69")
        XCTAssertTrue(opened.isPinned)
        XCTAssertEqual(opened.linkFailureCount, 2)
        XCTAssertEqual(
            Set(entries.map(\.content)), ["第一条", "第二条"]
        )
        // 迁移落定：V2/V3 新字段在旧条目上为默认（未
        // 钉桩/无镜像/无幂等身份）——升版不造数据
        XCTAssertTrue(
            entries.allSatisfy {
                $0.serverRowID == nil && $0.reactionsData == nil
                    && $0.clientMessageID == nil
            },
            "V1 旧条目迁移后新字段须为默认 nil"
        )

        // 迁移前备份实证：备份在册（名带现行版本字
        // 面）且可按 V1 原库方式打开、数据完好
        let backupURL = try XCTUnwrap(bootstrap.backupStoreURL)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: backupURL.path)
        )
        XCTAssertTrue(
            backupURL.lastPathComponent
                .contains("drill.store.backup-3.0.0-")
        )
        let backupContainer = try ModelContainer(
            for: v1Schema,
            configurations: [ModelConfiguration(
                schema: v1Schema, url: backupURL
            )]
        )
        swiftDataMount.retain(backupContainer)
        let backupContext = ModelContext(backupContainer)
        XCTAssertEqual(
            try backupContext.fetch(
                FetchDescriptor<ChatSchemaV1.ChatThread>()
            ).count,
            1
        )
        XCTAssertEqual(
            try backupContext.fetch(
                FetchDescriptor<ChatSchemaV1.ChatEntry>()
            ).count,
            2
        )
    }

    /// §383（台账 154）：V2 旧库经迁移链打开（V2→V3
    /// 轻量迁移）——数据零丢失、clientMessageID 迁
    /// 移后为默认 nil、迁移前备份按 V2 原库可打开
    func testV2StoreOpensThroughMigrationChainWithZeroLoss()
        throws {
        let dir = try tempDir()
        let sourceURL = dir.appendingPathComponent("default.store")
        // V2 形态：以冻结 V2 schema 建库写数（模拟
        // 0.50.98 已发布库），模型用 V2 冻结副本
        let v2Schema = Schema(versionedSchema: ChatSchemaV2.self)
        let writer = try ModelContainer(
            for: v2Schema,
            configurations: [ModelConfiguration(
                schema: v2Schema, url: sourceURL
            )]
        )
        swiftDataMount.retain(writer)
        let writeContext = ModelContext(writer)
        let thread = ChatSchemaV2.ChatThread(title: "V2 库主线")
        thread.serverSessionID = "srv-main-98"
        writeContext.insert(thread)
        let userEntry = ChatSchemaV2.ChatEntry(
            role: "user", content: "V2 第一条", thread: thread
        )
        userEntry.serverRowID = 101
        writeContext.insert(userEntry)
        writeContext.insert(
            ChatSchemaV2.ChatEntry(
                role: "assistant", content: "V2 第二条",
                thread: thread
            )
        )
        try writeContext.save()

        let drillURL = dir.appendingPathComponent("drill2.store")
        try copyStoreSet(from: sourceURL, to: drillURL)
        let bootstrap = ChatModelContainerBootstrapFactory
            .makePersistent(storeURL: drillURL)
        XCTAssertFalse(bootstrap.usesFallback)
        XCTAssertNil(bootstrap.failureMessage)
        let container = try XCTUnwrap(bootstrap.container)
        swiftDataMount.retain(container)

        let context = ModelContext(container)
        let threads = try context.fetch(
            FetchDescriptor<ChatThread>()
        )
        let entries = try context.fetch(
            FetchDescriptor<ChatEntry>()
        )
        XCTAssertEqual(threads.count, 1)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(threads.first?.title, "V2 库主线")
        XCTAssertEqual(
            Set(entries.map(\.content)), ["V2 第一条", "V2 第二条"]
        )
        // V2 既有字段原样保留、V3 新字段为默认 nil
        let migratedUser = try XCTUnwrap(
            entries.first { $0.role == "user" }
        )
        XCTAssertEqual(migratedUser.serverRowID, 101)
        XCTAssertTrue(
            entries.allSatisfy { $0.clientMessageID == nil },
            "V2 旧条目迁移后 clientMessageID 须为默认 nil"
        )

        // 迁移前备份实证：名带现行版本字面、可按 V2
        // 原库方式打开、数据完好
        let backupURL = try XCTUnwrap(bootstrap.backupStoreURL)
        XCTAssertTrue(
            backupURL.lastPathComponent
                .contains("drill2.store.backup-3.0.0-")
        )
        let backupContainer = try ModelContainer(
            for: v2Schema,
            configurations: [ModelConfiguration(
                schema: v2Schema, url: backupURL
            )]
        )
        swiftDataMount.retain(backupContainer)
        let backupContext = ModelContext(backupContainer)
        XCTAssertEqual(
            try backupContext.fetch(
                FetchDescriptor<ChatSchemaV2.ChatEntry>()
            ).count,
            2
        )
    }

    // MARK: - ③ 备份轮转

    func testStoreBackupRotationKeepsNewestTwo() throws {
        let dir = try tempDir()
        let storeURL = dir.appendingPathComponent("default.store")
        // 首装无库：不备份、不建文件
        let absent = try ChatStoreBackup.backupStoreIfPresent(
            at: storeURL, versionTag: "1.0.0",
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )
        XCTAssertNil(absent)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: storeURL.path)
        )

        try Data("store-bytes".utf8).write(to: storeURL)
        var returned: [URL] = []
        for offset in [0, 60, 120] {
            let backup = try ChatStoreBackup
                .backupStoreIfPresent(
                    at: storeURL, versionTag: "1.0.0",
                    now: Date(
                        timeIntervalSince1970: 1_700_000_000
                            + TimeInterval(offset)
                    )
                )
            returned.append(try XCTUnwrap(backup))
        }
        // 保留最近 2 组：最旧一组已被轮转删净
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: returned[0].path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: returned[1].path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: returned[2].path
            )
        )
        let names = try FileManager.default
            .contentsOfDirectory(atPath: dir.path)
        XCTAssertEqual(
            names.filter { $0.contains(".backup-") }.count, 2
        )
        XCTAssertEqual(
            try Data(contentsOf: returned[2]),
            Data("store-bytes".utf8)
        )
    }

    // MARK: - ④ 打开失败注入

    func testCorruptStoreFallsBackKeepsOriginalAndBackup()
        throws {
        let dir = try tempDir()
        let storeURL = dir.appendingPathComponent("default.store")
        let garbage = Data("this-is-not-a-sqlite-store".utf8)
        try garbage.write(to: storeURL)

        let bootstrap = ChatModelContainerBootstrapFactory
            .makePersistent(storeURL: storeURL)

        // 降级明示：内存库在场能开界面、提示点名原
        // 记录没删＋备份已保留，不许静默装作空库
        XCTAssertTrue(bootstrap.usesFallback)
        let container = try XCTUnwrap(bootstrap.container)
        swiftDataMount.retain(container)
        let message = try XCTUnwrap(bootstrap.failureMessage)
        XCTAssertTrue(message.contains("原来的记录没有删除"))
        XCTAssertTrue(message.contains("打开前的备份已保留"))
        // 原文件保留不删、字节不动
        XCTAssertEqual(try Data(contentsOf: storeURL), garbage)
        // 备份在册（回滚点）
        let backupURL = try XCTUnwrap(bootstrap.backupStoreURL)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: backupURL.path)
        )
        // 失败留痕（痕文案为本包新增、全局查在册即证）
        XCTAssertTrue(
            ChatDiagTrace.snapshots.contains {
                $0.contains("本地库打开失败")
            }
        )
    }

    // MARK: - ⑤ 解码失败可见＋自愈触发

    func testCorruptClaimRecordSurfacesAndSchedulesRediscovery() {
        let defaults = scratchDefaults()
        defaults.set(
            Data("garbage".utf8), forKey: "sideChats.mainClaimRecord"
        )

        let ledger = SessionLedger(
            defaults: defaults,
            identityStore: MemoryIdentityValueStore()
        )

        XCTAssertNil(ledger.mainClaimRecord)
        let note = ledger.localStateReadFailureNote
        XCTAssertNotNil(note)
        XCTAssertTrue(note?.contains("本地状态读取失败") == true)
        XCTAssertTrue(ledger.stateReadFailurePendingRediscovery)
        XCTAssertTrue(
            ChatDiagTrace.snapshots.contains {
                $0.contains("本地状态读取失败")
                    && $0.contains("sideChats.mainClaimRecord")
            }
        )
    }

    func testCorruptAssociationTableSurfaces() {
        let defaults = scratchDefaults()
        defaults.set(
            Data("[not-a-dict".utf8),
            forKey: "sideChats.ideaThreadIDs"
        )
        let ledger = SessionLedger(
            defaults: defaults,
            identityStore: MemoryIdentityValueStore()
        )
        XCTAssertEqual(ledger.ideaThreadIDs, [:])
        XCTAssertNotNil(ledger.localStateReadFailureNote)
        XCTAssertTrue(ledger.stateReadFailurePendingRediscovery)
    }

    func testCorruptMainThreadIDStringSurfaces() {
        let defaults = scratchDefaults()
        defaults.set(
            "not-a-uuid", forKey: "sideChats.mainThreadID"
        )
        let ledger = SessionLedger(
            defaults: defaults,
            identityStore: MemoryIdentityValueStore()
        )
        XCTAssertNil(ledger.mainThreadID)
        XCTAssertNotNil(ledger.localStateReadFailureNote)
        XCTAssertTrue(ledger.stateReadFailurePendingRediscovery)
    }

    func testHealthyAndMissingStatesStayQuiet() throws {
        // 键缺席＝从未写过：不算失败、不误报
        let fresh = SessionLedger(
            defaults: scratchDefaults(),
            identityStore: MemoryIdentityValueStore()
        )
        XCTAssertNil(fresh.localStateReadFailureNote)
        XCTAssertFalse(fresh.stateReadFailurePendingRediscovery)

        // 健康在册值：正常读出、无提示无标记
        let defaults = scratchDefaults()
        let record = MainlineClaimRecord(
            sessionID: "srv-1", messageCount: 3,
            lastActivityAt: nil, isArchived: false,
            candidateCount: 1, claimedAt: 100
        )
        defaults.set(
            try JSONEncoder().encode(record),
            forKey: "sideChats.mainClaimRecord"
        )
        let ledger = SessionLedger(
            defaults: defaults,
            identityStore: MemoryIdentityValueStore()
        )
        XCTAssertEqual(ledger.mainClaimRecord?.sessionID, "srv-1")
        XCTAssertNil(ledger.localStateReadFailureNote)
        XCTAssertFalse(ledger.stateReadFailurePendingRediscovery)
    }

    // MARK: - 自愈消费（脚本目录）

    private func sessionJSON(
        id: String, title: String?, messageCount: Int?,
        archived: Bool
    ) -> String {
        var fields = ["\"id\":\"\(id)\""]
        if let title { fields.append("\"title\":\"\(title)\"") }
        if let messageCount {
            fields.append("\"message_count\":\(messageCount)")
        }
        fields.append("\"archived\":\(archived ? 1 : 0)")
        fields.append("\"started_at\":1000")
        return "{" + fields.joined(separator: ",") + "}"
    }

    private func makePage(
        sessions: [String], total: Int
    ) -> SessionsPage {
        let json = "{\"sessions\":["
            + sessions.joined(separator: ",")
            + "],\"total\":\(total)}"
        return try! JSONDecoder().decode(
            SessionsPage.self, from: Data(json.utf8)
        )
    }

    func testRediscoveryAfterFailureReclaimsStalePointer()
        async {
        let defaults = scratchDefaults()
        defaults.set(
            Data("garbage".utf8), forKey: "sideChats.mainClaimRecord"
        )
        defaults.set(
            "srv-stale", forKey: "sideChats.mainServerSessionID"
        )
        let ledger = SessionLedger(
            defaults: defaults,
            identityStore: MemoryIdentityValueStore()
        )
        XCTAssertTrue(ledger.stateReadFailurePendingRediscovery)
        XCTAssertEqual(ledger.mainServerSessionID, "srv-stale")

        var client = ScriptedSessionsClient()
        client.scriptedPages = [
            "include|0": makePage(
                sessions: [
                    sessionJSON(
                        id: "srv-real",
                        title: SideChatStore.mainTitle,
                        messageCount: 10, archived: false
                    ),
                ],
                total: 1
            ),
        ]
        let appState = AppState(
            client: client, demoMode: .connected
        )

        await ledger.rediscoverAfterStateReadFailure(
            appState: appState
        )

        // 失效指针被改认到目录里的真主线、认领记录
        // 重建、提示清除、标记消费——自愈全程实证
        XCTAssertEqual(ledger.mainServerSessionID, "srv-real")
        XCTAssertEqual(ledger.mainClaimRecord?.sessionID, "srv-real")
        XCTAssertNil(ledger.localStateReadFailureNote)
        XCTAssertFalse(ledger.stateReadFailurePendingRediscovery)
    }

    func testRediscoveryAfterFailureKeepsNoteWhenDirectoryDown()
        async {
        let defaults = scratchDefaults()
        defaults.set(
            Data("garbage".utf8), forKey: "sideChats.mainClaimRecord"
        )
        let ledger = SessionLedger(
            defaults: defaults,
            identityStore: MemoryIdentityValueStore()
        )
        XCTAssertTrue(ledger.stateReadFailurePendingRediscovery)

        // 无脚本页＝目录拉取失败（桩抛 unreachable）
        let appState = AppState(
            client: ScriptedSessionsClient(),
            demoMode: .connected
        )
        await ledger.rediscoverAfterStateReadFailure(
            appState: appState
        )

        // 标记已消费（不反复重拉），提示保留待下次
        // 启动再对账，失败原因另落链接错误位留痕
        XCTAssertFalse(ledger.stateReadFailurePendingRediscovery)
        XCTAssertNotNil(ledger.localStateReadFailureNote)
        XCTAssertNotNil(ledger.mainLinkLastError)
    }
}
