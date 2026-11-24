import Foundation
import OneDayCore
import SwiftData
import XCTest

@testable import OneDayApp

/// 出厂冒烟门·A-2 升级存量迁移执行段（横扫
/// same-class-sweep-20261114.md A-2；2026-11-23 按
/// 现行面重做，DESIGN §401）。CI 恒为全新安装、迁移
/// 计划恒为空是本类事故的结构性漏网：本组四例全部
/// **先构造存量 fixture 再真执行迁移路径**，不走全新
/// 安装口径。写 UserDefaults.standard 的例在 tearDown
/// 逐键清回，避免污染同进程其他套件。
///
/// 重做三态（详 §401）：②③迁移（播种逻辑与 API 未
/// 动）；①④改写——迁移执行段与主线身份账已自
/// AllConversationsStore／SideChatStore 迁入
/// SessionLedger（标题覆盖仍在 SideChatStore）：①改
/// 对 SessionLedger.runMigration 执行、失败留痕读
/// ledger.migrationFailures；④的主线双旗＋归档键改
/// 对 SessionLedger 回读、标题覆盖仍对 SideChatStore
/// 回读（两店分工即现行形态）。
@MainActor
final class SmokeGateMigrationTests: XCTestCase {

    private var swiftDataMount = SwiftDataTestMount()

    private let touchedDefaultsKeys = [
        "chatModelID", "chatModelMigrated149", "chatModelBySession",
        "sideChats.mainThreadID", "sideChats.mainServerSessionID",
        "sideChats.mainServerConfirmed", "sideChats.mainServerSeeded",
        "sideChats.titleOverrides", "sideChats.archivedKeys",
        "agentProfile.displayNameOverride",
        "agentProfile.displayNameOverrideProvenance",
        "agentProfile.lastKnownSoulName",
        "agentProfile.lastKnownSoulUpdatedAt",
        "agentProfile.avatarPresetID",
        "agentProfile.usesCustomAvatar",
        "agentProfile.aiAvatarItemID", "agentProfile.aiAvatarPresetID",
        "agentProfile.aiAvatarUpdatedAt", "agentProfile.avatarSelectedAt",
        "agentProfile.userAvatarLocked",
        "identity.nameCache", "identity.avatarCache",
        "identity.namePushPending", "identity.avatarPushPending",
    ]

    override func tearDown() {
        let defaults = UserDefaults.standard
        for key in touchedDefaultsKeys {
            defaults.removeObject(forKey: key)
        }
        // 非演示连接在本机钥匙串落了假凭据，逐件清回
        for account in [
            CredentialKey.baseURL, CredentialKey.apiKey,
            CredentialKey.password, CredentialKey.username,
        ] {
            KeychainStore.delete(account: account)
        }
        super.tearDown()
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: CurrentChatSchema.self)
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(
                schema: schema, isStoredInMemoryOnly: true
            )]
        )
        swiftDataMount.retain(container)
        return container
    }

    /// A-2① 存量迁移执行段：标题覆盖＋归档键存量在
    /// 账时，runMigration 必须逐项真回写；写口被拒
    /// （演示客户端恒 demoLimitReached）时失败逐项留
    /// 痕、本地存量一条不许清（迁移只发生一次、现场
    /// 消失，清错＝用户标题/归档永久丢失）。
    /// 改写注（§401）：执行段现居 SessionLedger（自
    /// AllConversationsStore 迁入、语义逐字）；归档
    /// 键由 ledger 自持（init 自落盘回读），故 fixture
    /// 改走「先落盘、再建 ledger 回读」——与升级用户
    /// 真实路径同形；标题覆盖仍经 sideChats 活口设入。
    func testA2MigrationExecutionSegmentRetainsStockOnFailure()
        async throws
    {
        let defaults = UserDefaults.standard
        defaults.set(
            ["server:oneday-smoke-mig-b"],
            forKey: "sideChats.archivedKeys"
        )
        let appState = AppState(
            client: DemoHermesClient(), demoMode: .connected
        )
        appState.sideChats.setTitleOverride(
            "冒烟迁移标题", for: "oneday-smoke-mig-a"
        )
        XCTAssertEqual(
            appState.sideChats.titleOverrides["oneday-smoke-mig-a"],
            "冒烟迁移标题"
        )
        let ledger = SessionLedger(
            defaults: defaults,
            identityStore: MemoryIdentityValueStore()
        )
        XCTAssertTrue(
            ledger.archivedKeys.contains("server:oneday-smoke-mig-b"),
            "fixture 归档键应先被 ledger 回读入账"
        )

        let container = try makeContainer()
        await ledger.runMigration(
            appState: appState, localThreads: [],
            modelContext: container.mainContext
        )

        XCTAssertEqual(
            ledger.migrationFailures.count, 2,
            "两项存量都应被真执行且失败留痕："
                + ledger.migrationFailures.joined(separator: "；")
        )
        XCTAssertEqual(
            appState.sideChats.titleOverrides["oneday-smoke-mig-a"],
            "冒烟迁移标题", "失败项标题覆盖不许清"
        )
        XCTAssertTrue(
            ledger.archivedKeys.contains("server:oneday-smoke-mig-b"),
            "失败项归档键不许清"
        )
    }

    /// A-2② 旧全局模型选择一次性播种：存量 chatModelID
    /// 在首次目录刷新时播种给主线会话键且只播一次——
    /// 播种后用户改选不许被二次刷新顶掉。
    func testA2LegacyChatModelSeededExactlyOnce() async throws {
        let defaults = UserDefaults.standard
        defaults.set("deepseek-v4-pro", forKey: "chatModelID")
        defaults.removeObject(forKey: "chatModelMigrated149")
        defaults.removeObject(forKey: "chatModelBySession")

        // 非演示态（播种段有 !isDemo 闸）＋演示客户端
        // （health/models 假回执成功）：真走 connectDirect
        // 把 phase 推到 connected，再真跑目录刷新执行播种
        let state = AppState(
            client: DemoHermesClient(), demoMode: .off
        )
        let config = try XCTUnwrap(
            ServerConfig(rawInput: "hermes.didichou.site")
        )
        try await state.connectDirect(config: config, apiKey: "smoke")
        await state.refreshModelCatalog()

        XCTAssertTrue(
            defaults.bool(forKey: "chatModelMigrated149"),
            "播种后迁移标记应落账"
        )
        XCTAssertEqual(
            state.sessionModelChoice(
                serverSessionID: nil, threadID: nil
            ).model,
            "deepseek-v4-pro",
            "旧全局选择应播种给主线会话"
        )

        state.selectSessionModel(
            ChatModelChoice(
                model: "deepseek-flash", providerField: "custom"
            ),
            serverSessionID: nil, threadID: nil
        )
        await state.refreshModelCatalog()
        XCTAssertEqual(
            state.sessionModelChoice(
                serverSessionID: nil, threadID: nil
            ).model,
            "deepseek-flash",
            "一次性播种不许在后续刷新里顶掉用户新选择"
        )
    }

    /// A-2③ 身份旧账迁移：旧头像预置＋旧魂名在账时，
    /// AgentProfileStore init 应完成最后一判→播种新缓存
    /// →旧账键全清（读后即删，留着会二次迁移翻账）。
    func testA2AgentProfileLegacyMigrationSeedsAndClears()
        throws
    {
        let defaults = UserDefaults.standard
        for key in touchedDefaultsKeys {
            defaults.removeObject(forKey: key)
        }
        let presetID = try XCTUnwrap(
            AgentAvatarPreset.all.first {
                $0.id != AgentAvatarPreset.defaultID
            }?.id,
            "需要一个非默认预置头像作存量 fixture"
        )
        defaults.set("存量魂名", forKey: "agentProfile.lastKnownSoulName")
        defaults.set(
            Date().timeIntervalSince1970 - 86_400,
            forKey: "agentProfile.lastKnownSoulUpdatedAt"
        )
        defaults.set(presetID, forKey: "agentProfile.avatarPresetID")
        defaults.set(false, forKey: "agentProfile.usesCustomAvatar")

        let store = AgentProfileStore()

        XCTAssertEqual(
            store.nameCache?.name, "存量魂名",
            "旧魂名应播种进新名字缓存"
        )
        XCTAssertEqual(
            store.avatarCache?.selection, .preset(id: presetID),
            "旧预置头像应播种进新头像缓存"
        )
        for key in [
            "agentProfile.lastKnownSoulName",
            "agentProfile.avatarPresetID",
            "agentProfile.usesCustomAvatar",
        ] {
            XCTAssertNil(
                defaults.object(forKey: key),
                "迁移后旧账键应清：\(key)"
            )
        }
        XCTAssertNotNil(defaults.data(forKey: "identity.nameCache"))
        XCTAssertNotNil(defaults.data(forKey: "identity.avatarCache"))
    }

    /// A-2④ 主线身份存量回读：升级用户的主线服务端
    /// id＋seeded/confirmed 双旗＋归档键在账时，建店
    /// 应整份回读不断链（双旗分支错位＝主线重绑/重
    /// 复播种）；标题覆盖同批回读。
    /// 改写注（§401）：主线身份账已迁 SessionLedger
    /// （落盘键仍为 sideChats.* 前缀、旧账直读），标
    /// 题覆盖仍居 SideChatStore——本例按现行两店分
    /// 工分别回读，覆盖物与原例逐项对应。
    func testA2SideChatStoreReloadsLegacyMainFlags() throws {
        let defaults = UserDefaults.standard
        defaults.set(
            "oneday-smoke-main-session",
            forKey: "sideChats.mainServerSessionID"
        )
        defaults.set(true, forKey: "sideChats.mainServerSeeded")
        defaults.set(true, forKey: "sideChats.mainServerConfirmed")
        let overrides = try JSONEncoder().encode(
            ["oneday-smoke-mig-a": "存量标题"]
        )
        defaults.set(overrides, forKey: "sideChats.titleOverrides")
        defaults.set(
            ["server:oneday-smoke-mig-b"],
            forKey: "sideChats.archivedKeys"
        )

        let ledger = SessionLedger(
            defaults: defaults,
            identityStore: MemoryIdentityValueStore()
        )
        XCTAssertEqual(
            ledger.mainServerSessionID, "oneday-smoke-main-session"
        )
        XCTAssertTrue(ledger.mainServerSeeded)
        XCTAssertTrue(ledger.mainServerConfirmed)
        XCTAssertTrue(ledger.archivedKeys.contains(
            "server:oneday-smoke-mig-b"
        ))

        let sideChats = SideChatStore(persisted: true)
        XCTAssertEqual(
            sideChats.titleOverrides["oneday-smoke-mig-a"], "存量标题"
        )
    }
}
