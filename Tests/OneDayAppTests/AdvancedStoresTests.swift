import OneDayCore
@testable import OneDayApp
import XCTest

/// H8/H9/H11/H13 状态机钉测（DESIGN §390）：操作口注入
/// 脚本，只验状态机本身——加载三态、写后回读对账（确
/// 认/未确认两路）、预检拦截不出门、一次性密钥只存内
/// 存、平台开启 needs_restart 如实交代、策展跑一次先
/// 指名当前档案。端点真形态在 OneDayCoreTests
/// .HermesAdvancedModelsTests 钉
@MainActor
final class AdvancedStoresTests: XCTestCase {

    // MARK: - 夹具

    private func routingFixture(configured: String = "local") -> DelegationRouting {
        DelegationRouting(
            configured: configured,
            backends: [
                DelegationBackendInfo(name: "local", available: true),
                DelegationBackendInfo(
                    name: "docker", available: false, reason: "未装 Docker"
                ),
            ],
            profiles: ["default"]
        )
    }

    private func moaFixture() -> MoaConfig {
        var preset = MoaPreset()
        preset.referenceModels = [MoaSlot(provider: "custom", model: "m1")]
        preset.aggregator = MoaSlot(provider: "custom", model: "agg")
        return MoaConfig(
            defaultPreset: "careful", activePreset: "",
            presets: ["careful": preset]
        )
    }

    private func webhooksPage(
        enabled: Bool = true, names: [String] = []
    ) -> WebhooksPage {
        let subs = names.map { name in
            """
            {"name": "\(name)", "description": "", "events": [],
             "deliver": "log", "deliver_only": false, "prompt": "",
             "url": "https://example.com/webhooks/\(name)",
             "secret_set": true, "enabled": true}
            """
        }.joined(separator: ",")
        let json = """
        {"enabled": \(enabled), "base_url": "https://example.com",
         "subscriptions": [\(subs)]}
        """
        return try! JSONDecoder().decode(
            WebhooksPage.self, from: Data(json.utf8)
        )
    }

    // MARK: - H8 委派路由

    func testDelegationLoadReadyAndNotLoggedIn() async {
        let store = DelegationRoutingStore()
        let okOps = DelegationRoutingOperations(
            load: { self.routingFixture() },
            setBackend: { _ in }, setModelMap: { _, _ in },
            setProfileRoutes: { _, _ in }
        )
        await store.load(ops: okOps)
        XCTAssertEqual(store.routing?.configured, "local")

        let expiredOps = DelegationRoutingOperations(
            load: { throw HermesError.sessionExpired },
            setBackend: { _ in }, setModelMap: { _, _ in },
            setProfileRoutes: { _, _ in }
        )
        await store.load(ops: expiredOps)
        guard case .notLoggedIn = store.state else {
            return XCTFail("401 应落未登录态，实际 \(store.state)")
        }
    }

    func testDelegationSelectBackendConfirmsByReadback() async {
        let store = DelegationRoutingStore()
        var current = routingFixture()
        let ops = DelegationRoutingOperations(
            load: { current },
            setBackend: { name in current = self.routingFixture(configured: name) },
            setModelMap: { _, _ in }, setProfileRoutes: { _, _ in }
        )
        await store.load(ops: ops)
        await store.selectBackend(ops: ops, backend: "docker")
        XCTAssertEqual(store.routing?.configured, "docker")
        XCTAssertFalse(store.noteIsProblem)
    }

    func testDelegationSelectBackendUnconfirmedKeepsProblemNote() async {
        let store = DelegationRoutingStore()
        let current = routingFixture()
        let ops = DelegationRoutingOperations(
            load: { current },
            setBackend: { _ in },  // 受理了但回读没变
            setModelMap: { _, _ in }, setProfileRoutes: { _, _ in }
        )
        await store.load(ops: ops)
        await store.selectBackend(ops: ops, backend: "docker")
        XCTAssertEqual(store.routing?.configured, "local")
        XCTAssertTrue(store.noteIsProblem)
    }

    func testDelegationSaveModelMapPrecheckBlocksInvalid() async {
        let store = DelegationRoutingStore()
        var saveCalls = 0
        let ops = DelegationRoutingOperations(
            load: { self.routingFixture() },
            setBackend: { _ in },
            setModelMap: { _, _ in saveCalls += 1 },
            setProfileRoutes: { _, _ in }
        )
        await store.load(ops: ops)
        await store.saveModelMap(
            ops: ops,
            routes: [DelegationModelRoute(name: "x")],
            defaultRoute: nil
        )
        XCTAssertEqual(saveCalls, 0)
        XCTAssertTrue(store.noteIsProblem)
    }

    // MARK: - H9 MoA

    func testMoaSaveAdoptsNormalizedReceipt() async {
        let store = MoaStore()
        let fixture = moaFixture()
        let ops = MoaOperations(load: { fixture }, save: { edited in edited })
        await store.load(ops: ops)
        var edited = fixture
        edited.defaultPreset = "careful"
        await store.save(ops: ops, edited: edited)
        XCTAssertEqual(store.config?.presetNames, ["careful"])
        XCTAssertFalse(store.noteIsProblem)
    }

    func testMoaSavePrecheckBlocksIncompletePreset() async {
        let store = MoaStore()
        var saveCalls = 0
        let ops = MoaOperations(
            load: { self.moaFixture() },
            save: { edited in saveCalls += 1; return edited }
        )
        await store.load(ops: ops)
        var edited = moaFixture()
        edited.presets["broken"] = MoaPreset()
        await store.save(ops: ops, edited: edited)
        XCTAssertEqual(saveCalls, 0)
        XCTAssertTrue(store.noteIsProblem)
    }

    // MARK: - H11 Webhooks

    func testWebhookCreateStoresOneTimeSecretAndConfirms() async {
        let store = WebhooksStore()
        var page = webhooksPage(names: [])
        let receiptJSON = """
        {"name": "alerts", "description": "", "events": [],
         "deliver": "log", "deliver_only": false, "prompt": "",
         "url": "https://example.com/webhooks/alerts",
         "secret_set": true, "enabled": true, "secret": "whsec-123"}
        """
        let receipt = try! JSONDecoder().decode(
            WebhookCreateReceipt.self, from: Data(receiptJSON.utf8)
        )
        let ops = WebhooksOperations(
            load: { page },
            create: { _ in
                page = self.webhooksPage(names: ["alerts"])
                return receipt
            },
            delete: { _ in }, setEnabled: { _, _ in },
            enablePlatform: {
                WebhooksEnableReceipt(jsonValue: .object([
                    "ok": .bool(true), "enabled": .bool(true),
                    "needs_restart": .bool(false),
                ]))
            }
        )
        await store.load(ops: ops)
        await store.create(ops: ops, input: WebhookCreateInput(name: "alerts"))
        XCTAssertEqual(store.oneTimeSecret?.secret, "whsec-123")
        XCTAssertEqual(store.page?.subscriptions.first?.name, "alerts")
        XCTAssertFalse(store.noteIsProblem)
        store.dismissOneTimeSecret()
        XCTAssertNil(store.oneTimeSecret)
    }

    func testWebhookEnablePlatformReportsRestartHonestly() async {
        let store = WebhooksStore()
        let page = webhooksPage(enabled: false)
        let ops = WebhooksOperations(
            load: { page },
            create: { _ in throw HermesError.unreachable("不用") },
            delete: { _ in }, setEnabled: { _, _ in },
            enablePlatform: {
                WebhooksEnableReceipt(jsonValue: .object([
                    "ok": .bool(true), "enabled": .bool(true),
                    "needs_restart": .bool(true),
                ]))
            }
        )
        await store.load(ops: ops)
        await store.enablePlatform(ops: ops)
        XCTAssertTrue(store.noteIsProblem)
        XCTAssertTrue(store.note?.contains("重启") ?? false)
    }

    func testWebhookDeleteUnconfirmedKeepsProblemNote() async {
        let store = WebhooksStore()
        let page = webhooksPage(names: ["alerts"])
        let ops = WebhooksOperations(
            load: { page },
            create: { _ in throw HermesError.unreachable("不用") },
            delete: { _ in },  // 受理了但回读还在
            setEnabled: { _, _ in },
            enablePlatform: {
                WebhooksEnableReceipt(jsonValue: .object([:]))
            }
        )
        await store.load(ops: ops)
        await store.delete(ops: ops, name: "alerts")
        XCTAssertTrue(store.noteIsProblem)
        XCTAssertEqual(store.page?.subscriptions.count, 1)
    }

    // MARK: - H13 策展

    private func curatorFixture(paused: Bool) -> CuratorStatus {
        CuratorStatus(jsonValue: .object([
            "enabled": .bool(true), "paused": .bool(paused),
            "interval_hours": .number(24),
            "last_run_at": .string("2026-11-22T04:00:00Z"),
        ]))
    }

    func testCuratorPauseConfirmsByReadback() async {
        let store = ServerInternalsStore()
        var paused = false
        let ops = ServerInternalsOperations(
            curatorStatus: { self.curatorFixture(paused: paused) },
            setCuratorPaused: { paused = $0 },
            activeProfileName: { "default" },
            runCurator: { _ in
                OpsSpawnResponse(ok: true, pid: 42, name: "curator", archive: nil)
            },
            sessionStats: { throw HermesError.unreachable("不用") },
            opsHooks: { throw HermesError.unreachable("不用") }
        )
        await store.loadCurator(ops: ops)
        await store.setCuratorPaused(ops: ops, paused: true)
        XCTAssertEqual(store.curator?.paused, true)
        XCTAssertFalse(store.noteIsProblem)
    }

    func testCuratorRunNamesActiveProfile() async {
        let store = ServerInternalsStore()
        var runProfile: String??
        let ops = ServerInternalsOperations(
            curatorStatus: { self.curatorFixture(paused: false) },
            setCuratorPaused: { _ in },
            activeProfileName: { "researcher" },
            runCurator: { profile in
                runProfile = profile
                return OpsSpawnResponse(ok: true, pid: 7, name: "curator", archive: nil)
            },
            sessionStats: { throw HermesError.unreachable("不用") },
            opsHooks: { throw HermesError.unreachable("不用") }
        )
        await store.runCuratorNow(ops: ops)
        XCTAssertEqual(runProfile, "researcher")
        XCTAssertFalse(store.noteIsProblem)
    }
}
