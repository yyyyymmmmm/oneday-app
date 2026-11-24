import XCTest
import OneDayCore
@testable import OneDayApp

/// 工具集治理数据层钉测（DESIGN §358）：执行口注入
/// ScriptedToolsetsClient 脚本盒，只验 Store 状态机
/// 本身——装载三态、附带真源各自降级、stt 的 config
/// 真值通路、启停写后回读确认/未确认、未知集良性、
/// 密钥被拒、细调三写回读、详情分开成败、终端后端
/// 确认与未就绪本地拦截。契约形态在 OneDayCoreTests
/// .ToolsetsContractTests 钉。
@MainActor
final class ToolsetsStoreTests: XCTestCase {

    // MARK: - 夹具

    private func makeScript() -> ToolsetsScript {
        let script = ToolsetsScript()
        script.listResponse = ToolsetsListResponse(data: [
            ToolsetRow(
                name: "web", label: "Web", enabled: true,
                configured: true, tools: ["web_search", "web_extract"]
            ),
            ToolsetRow(
                name: "image_gen", label: "Image Generation",
                enabled: true, configured: true,
                tools: ["image_generate"]
            ),
            ToolsetRow(
                name: "video_gen", label: "Video Generation",
                enabled: false, configured: false,
                tools: ["video_generate"]
            ),
            ToolsetRow(
                name: "stt", label: "Speech to Text",
                enabled: false, configured: true,
                tools: ["transcribe"]
            ),
        ])
        script.rawConfigValue = try? JSONDecoder().decode(
            [String: JSONValue].self,
            from: Data(
                """
                {"stt": {"enabled": true, "provider": "local"},
                 "web": {"backend": "tavily"}}
                """.utf8
            )
        )
        script.backendsValue = TerminalBackends(active: "local", backends: [
            TerminalBackend(
                name: "local", label: "本机", active: true,
                status: .ready
            ),
            TerminalBackend(
                name: "ssh", label: "SSH", active: false,
                status: .ready
            ),
            TerminalBackend(
                name: "docker", label: "Docker", active: false,
                status: .needsSetup, detail: "镜像未拉取"
            ),
        ])
        return script
    }

    private func makeAppState(script: ToolsetsScript) -> AppState {
        var client = ScriptedToolsetsClient()
        client.toolsetsScript = script
        return AppState(client: client, demoMode: .connected)
    }

    private func webPanel(active: String = "tavily") -> ToolsetConfigPanel {
        ToolsetConfigPanel(
            name: "web", hasCategory: true,
            providers: [
                ToolsetProvider(
                    name: "tavily", badge: "推荐",
                    envVars: [
                        ToolsetEnvVar(
                            key: "TAVILY_API_KEY", isSet: true
                        )
                    ],
                    isActive: active == "tavily", status: "ready"
                ),
                ToolsetProvider(
                    name: "brave",
                    envVars: [
                        ToolsetEnvVar(
                            key: "BRAVE_API_KEY", isSet: false
                        )
                    ],
                    isActive: active == "brave"
                ),
            ],
            activeProvider: active
        )
    }

    private func imageCatalog(
        current: String = "dall-e-3"
    ) -> ToolsetModelCatalog {
        ToolsetModelCatalog(
            name: "image_gen", hasModels: true, provider: "openai",
            models: [
                ToolsetModelOption(id: "dall-e-3", display: "DALL·E 3"),
                ToolsetModelOption(id: "gpt-image-1"),
            ],
            current: current, defaultModel: "dall-e-3"
        )
    }

    // MARK: - 装载

    func testLoadReadyWithListConfigTruthAndBackends() async {
        let script = makeScript()
        let store = ToolsetsStore()
        await store.load(appState: makeAppState(script: script))

        guard case .ready = store.state else {
            XCTFail("应为 ready，实际 \(store.state)")
            return
        }
        XCTAssertEqual(store.list?.data.count, 4)
        // config 承托真值：只有 stt 节带 enabled 键入表
        XCTAssertEqual(store.configEnabled, ["stt": true])
        XCTAssertFalse(store.configUnread)
        // 有效启用计数：web、image_gen＋stt（经 config）
        XCTAssertEqual(
            ToolsetStateResolution.enabledCount(
                in: store.list!, configEnabled: store.configEnabled
            ),
            3
        )
        XCTAssertEqual(store.backends?.active, "local")
        XCTAssertFalse(store.backendsUnread)
    }

    func testLoadUnavailableWhenNotConnected() async {
        let store = ToolsetsStore()
        let appState = AppState(
            client: ScriptedToolsetsClient(), demoMode: .connectPage
        )
        await store.load(appState: appState)
        guard case .unavailable = store.state else {
            XCTFail("未连接应为 unavailable，实际 \(store.state)")
            return
        }
        XCTAssertNil(store.list)
    }

    func testLoadFailedWhenListThrows() async {
        let script = makeScript()
        script.listResponse = nil
        let store = ToolsetsStore()
        await store.load(appState: makeAppState(script: script))
        guard case .failed = store.state else {
            XCTFail("清单抛错应为 failed，实际 \(store.state)")
            return
        }
    }

    func testLoadConfigUnreadDegradesOnlyConfigTruth() async {
        let script = makeScript()
        script.rawConfigValue = nil
        let store = ToolsetsStore()
        await store.load(appState: makeAppState(script: script))
        guard case .ready = store.state else {
            XCTFail("config 读不到不拖垮清单，实际 \(store.state)")
            return
        }
        XCTAssertTrue(store.configUnread)
        XCTAssertEqual(store.configEnabled, [:])
        XCTAssertEqual(store.list?.data.count, 4)
    }

    func testLoadBackendsUnreadDegradesOnlyBackends() async {
        let script = makeScript()
        script.backendsValue = nil
        let store = ToolsetsStore()
        await store.load(appState: makeAppState(script: script))
        guard case .ready = store.state else {
            XCTFail("后端读不到不拖垮清单，实际 \(store.state)")
            return
        }
        XCTAssertTrue(store.backendsUnread)
        XCTAssertNil(store.backends)
        XCTAssertFalse(store.configUnread)
    }

    // MARK: - 启停

    func testToggleNormalSetConfirmedByReadback() async {
        let script = makeScript()
        let appState = makeAppState(script: script)
        let store = ToolsetsStore()
        await store.load(appState: appState)
        let row = store.list!.row(named: "image_gen")!
        await store.toggle(row, to: false, appState: appState)
        XCTAssertNil(store.note)
        XCTAssertEqual(
            store.list?.row(named: "image_gen")?.enabled, false
        )
        XCTAssertEqual(script.toggleCalls.count, 1)
        XCTAssertEqual(script.toggleCalls.first?.name, "image_gen")
        XCTAssertEqual(script.toggleCalls.first?.enabled, false)
    }

    func testToggleUnconfirmedLeavesProblemNote() async {
        let script = makeScript()
        script.toggleApplies = false
        let appState = makeAppState(script: script)
        let store = ToolsetsStore()
        await store.load(appState: appState)
        let row = store.list!.row(named: "image_gen")!
        await store.toggle(row, to: false, appState: appState)
        // 回读没变：如实留问题话，清单保持服务端原样
        XCTAssertTrue(store.noteIsProblem)
        XCTAssertNotNil(store.note)
        XCTAssertEqual(
            store.list?.row(named: "image_gen")?.enabled, true
        )
    }

    func testToggleSttFlipsConfigTruthNotListRow() async {
        let script = makeScript()
        let appState = makeAppState(script: script)
        let store = ToolsetsStore()
        await store.load(appState: appState)
        // 装载后 stt 有效态以 config 为准＝开
        let stt = store.list!.row(named: "stt")!
        XCTAssertTrue(
            ToolsetStateResolution.effectiveEnabled(
                stt, configEnabled: store.configEnabled
            )
        )
        await store.toggle(stt, to: false, appState: appState)
        XCTAssertNil(store.note)
        // 真值翻在 config 节；清单行读面保持恒 false 原样
        XCTAssertEqual(store.configEnabled, ["stt": false])
        XCTAssertEqual(store.list?.row(named: "stt")?.enabled, false)
    }

    func testToggleUnknownToolsetIsBenignRefresh() async {
        let script = makeScript()
        script.toggleError = .serverError(
            endpoint: "PUT /v1/toolsets/ghost",
            status: 400, code: "unknown_toolset"
        )
        let appState = makeAppState(script: script)
        let store = ToolsetsStore()
        await store.load(appState: appState)
        let row = store.list!.row(named: "web")!
        await store.toggle(row, to: false, appState: appState)
        XCTAssertFalse(store.noteIsProblem)
        XCTAssertNotNil(store.note)
        // 良性刷新后清单仍在
        XCTAssertEqual(store.list?.data.count, 4)
    }

    func testToggleUnauthorizedLeavesProblemNote() async {
        let script = makeScript()
        script.toggleError = .apiKeyRejected
        let appState = makeAppState(script: script)
        let store = ToolsetsStore()
        await store.load(appState: appState)
        let row = store.list!.row(named: "web")!
        await store.toggle(row, to: false, appState: appState)
        XCTAssertTrue(store.noteIsProblem)
        XCTAssertNotNil(store.note)
        XCTAssertEqual(store.list?.row(named: "web")?.enabled, true)
    }

    func testToggleInvalidRequestLeavesProblemNote() async {
        let script = makeScript()
        script.toggleError = .serverError(
            endpoint: "PUT /v1/toolsets/web",
            status: 400, code: "invalid_enabled"
        )
        let appState = makeAppState(script: script)
        let store = ToolsetsStore()
        await store.load(appState: appState)
        let row = store.list!.row(named: "web")!
        await store.toggle(row, to: false, appState: appState)
        XCTAssertTrue(store.noteIsProblem)
        XCTAssertNotNil(store.note)
    }

    // MARK: - 详情细调

    func testDetailLoadSplitsPanelAndCatalogOutcomes() async {
        let script = makeScript()
        script.panels["web"] = webPanel()
        // catalogs 故意缺席：目录一面失败不拖垮面板
        let appState = makeAppState(script: script)
        let store = ToolsetsStore()
        await store.loadDetail(name: "web", appState: appState)
        XCTAssertEqual(store.detail.panel?.activeProvider, "tavily")
        XCTAssertFalse(store.detail.panelFailed)
        XCTAssertNil(store.detail.catalog)
        XCTAssertTrue(store.detail.catalogFailed)
    }

    func testSelectProviderConfirmedByReadback() async {
        let script = makeScript()
        script.panels["web"] = webPanel()
        let appState = makeAppState(script: script)
        let store = ToolsetsStore()
        await store.loadDetail(name: "web", appState: appState)
        let brave = store.detail.panel!.provider(named: "brave")!
        await store.selectProvider(brave, appState: appState)
        XCTAssertNil(store.detailNote)
        XCTAssertEqual(store.detail.panel?.activeProvider, "brave")
    }

    func testSelectProviderUnconfirmedLeavesProblemNote() async {
        let script = makeScript()
        script.panels["web"] = webPanel()
        script.providerApplies = false
        let appState = makeAppState(script: script)
        let store = ToolsetsStore()
        await store.loadDetail(name: "web", appState: appState)
        let brave = store.detail.panel!.provider(named: "brave")!
        await store.selectProvider(brave, appState: appState)
        XCTAssertTrue(store.detailNoteIsProblem)
        XCTAssertNotNil(store.detailNote)
        XCTAssertEqual(store.detail.panel?.activeProvider, "tavily")
    }

    func testSelectModelConfirmedByReadback() async {
        let script = makeScript()
        script.catalogs["image_gen"] = imageCatalog()
        let appState = makeAppState(script: script)
        let store = ToolsetsStore()
        await store.loadDetail(name: "image_gen", appState: appState)
        let model = store.detail.catalog!.models[1]
        await store.selectModel(model, appState: appState)
        XCTAssertNil(store.detailNote)
        XCTAssertEqual(store.detail.catalog?.current, "gpt-image-1")
    }

    func testSelectModelUnconfirmedLeavesProblemNote() async {
        let script = makeScript()
        script.catalogs["image_gen"] = imageCatalog()
        script.modelApplies = false
        let appState = makeAppState(script: script)
        let store = ToolsetsStore()
        await store.loadDetail(name: "image_gen", appState: appState)
        let model = store.detail.catalog!.models[1]
        await store.selectModel(model, appState: appState)
        XCTAssertTrue(store.detailNoteIsProblem)
        XCTAssertEqual(store.detail.catalog?.current, "dall-e-3")
    }

    // MARK: - 终端后端

    func testSelectBackendConfirmedByReadback() async {
        let script = makeScript()
        let appState = makeAppState(script: script)
        let store = ToolsetsStore()
        await store.load(appState: appState)
        let ssh = store.backends!.backend(named: "ssh")!
        await store.selectBackend(ssh, appState: appState)
        XCTAssertNil(store.note)
        XCTAssertEqual(store.backends?.active, "ssh")
        XCTAssertEqual(script.backendSelectCalls, ["ssh"])
    }

    func testSelectBackendNotReadyIsInterceptedLocally() async {
        let script = makeScript()
        let appState = makeAppState(script: script)
        let store = ToolsetsStore()
        await store.load(appState: appState)
        let docker = store.backends!.backend(named: "docker")!
        await store.selectBackend(docker, appState: appState)
        // 未就绪：本地拦截、不发写口、active 不变
        XCTAssertTrue(store.noteIsProblem)
        XCTAssertNotNil(store.note)
        XCTAssertEqual(script.backendSelectCalls, [])
        XCTAssertEqual(store.backends?.active, "local")
    }

    func testSelectBackendUnconfirmedLeavesProblemNote() async {
        let script = makeScript()
        script.backendApplies = false
        let appState = makeAppState(script: script)
        let store = ToolsetsStore()
        await store.load(appState: appState)
        let ssh = store.backends!.backend(named: "ssh")!
        await store.selectBackend(ssh, appState: appState)
        XCTAssertTrue(store.noteIsProblem)
        XCTAssertNotNil(store.note)
        XCTAssertEqual(store.backends?.active, "local")
    }
}
