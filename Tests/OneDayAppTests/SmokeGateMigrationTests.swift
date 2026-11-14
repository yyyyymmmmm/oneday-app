import Foundation
import OneDayCore
import SwiftData
import XCTest

@testable import OneDayApp

/// 出厂冒烟门·A-2 升级存量迁移执行段（横扫
/// same-class-sweep-20261114.md A-2）。CI 恒为全新安装、
/// 迁移计划恒为空是本类事故的结构性漏网：本组四例全部
/// **先构造存量 fixture 再真执行迁移路径**，不走全新
/// 安装口径。写 UserDefaults.standard 的例在 tearDown
/// 逐键清回，避免污染同进程其他套件。
@MainActor
final class SmokeGateMigrationTests: XCTestCase {

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
        let schema = Schema([ChatThread.self, ChatEntry.self])
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(
                schema: schema, isStoredInMemoryOnly: true
            )]
        )
    }

    /// A-2① 全部对话迁移执行段：标题覆盖＋归档键存量在
    /// 账时，runMigration 必须逐项真回写；写口被拒
    /// （演示客户端恒 demoLimitReached）时失败逐项留痕、
    /// 本地存量一条不许清（迁移只发生一次、现场消失，
    /// 清错＝用户标题/归档永久丢失）。
    func testA2MigrationExecutionSegmentRetainsStockOnFailure()
        async throws
    {
        let appState = AppState(
            client: DemoHermesClient(), demoMode: .connected
        )
        appState.sideChats.setTitleOverride(
            "冒烟迁移标题", for: "oneday-smoke-mig-a"
        )
        appState.sideChats.archive(
            serverSessionID: "oneday-smoke-mig-b"
        )
        XCTAssertEqual(
            appState.sideChats.titleOverrides["oneday-smoke-mig-a"],
            "冒烟迁移标题"
        )
        XCTAssertTrue(appState.sideChats.archivedKeys.contains(
            SideChatArchive.serverKey("oneday-smoke-mig-b")
        ))

        let container = try makeContainer()
        let store = AllConversationsStore()
        await store.runMigration(
            appState: appState, localThreads: [],
            modelContext: container.mainContext
        )

        XCTAssertEqual(
            store.migrationFailures.count, 2,
            "两项存量都应被真执行且失败留痕："
                + store.migrationFailures.joined(separator: "；")
        )
        XCTAssertEqual(
            appState.sideChats.titleOverrides["oneday-smoke-mig-a"],
            "冒烟迁移标题", "失败项标题覆盖不许清"
        )
        XCTAssertTrue(
            appState.sideChats.archivedKeys.contains(
                SideChatArchive.serverKey("oneday-smoke-mig-b")
            ),
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

    /// A-2④ 旁聊主线双旗存量回读：升级用户的主线服务
    /// 端 id＋seeded/confirmed 双旗在账时，
    /// SideChatStore(persisted:) init 应整份回读不断链
    /// （双旗分支错位＝主线重绑/重复播种）。
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

        let store = SideChatStore(persisted: true)

        XCTAssertEqual(
            store.mainServerSessionID, "oneday-smoke-main-session"
        )
        XCTAssertTrue(store.mainServerSeeded)
        XCTAssertTrue(store.mainServerConfirmed)
        XCTAssertEqual(
            store.titleOverrides["oneday-smoke-mig-a"], "存量标题"
        )
        XCTAssertTrue(store.archivedKeys.contains(
            "server:oneday-smoke-mig-b"
        ))
    }
}
