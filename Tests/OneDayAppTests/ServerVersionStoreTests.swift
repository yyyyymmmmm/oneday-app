import OneDayCore
import XCTest
@testable import OneDayApp

/// 台账 36「版本与更新」段（DESIGN §360，案 A 只读
/// 感知）：Store 三路隔离/回执分型/会话过期口径＋
/// 装配钉测（段在位、托管态无执行钮——§4.5 关键口
/// 径钉成测试）。样本口径同 Core 契约套件（探活报
/// 告 §4.1 定形＋2026-11-22 生产实测）。
@MainActor
final class ServerVersionStoreTests: XCTestCase {

    private let decoder = JSONDecoder()

    private func status(_ json: String) throws -> ServerStatus {
        try decoder.decode(ServerStatus.self, from: Data(json.utf8))
    }

    private func check(_ json: String) throws -> UpdateCheckResponse {
        try decoder.decode(UpdateCheckResponse.self, from: Data(json.utf8))
    }

    private func receipt(_ json: String) throws -> UpdateReceiptResponse {
        try decoder.decode(UpdateReceiptResponse.self, from: Data(json.utf8))
    }

    private var testConfig: ServerConfig {
        ServerConfig(rawInput: "https://hermes.didichou.site")!
    }

    private var productionStatusJSON: String {
        """
        {"version": "0.23.0", "release_date": "2026.9.24",
         "config_version": 52, "latest_config_version": 52,
         "can_update_hermes": false,
         "gateway_running": true, "gateway_state": "running",
         "gateway_platforms": {}}
        """
    }

    private var managedCheckJSON: String {
        """
        {"install_method": "managed-runtime", "current_version": "0.23.0",
         "behind": null, "update_available": false, "can_apply": false,
         "update_command": ""}
        """
    }

    /// 生产形态全景：三路各就各位——版本事实齐、回执
    /// 404 落 absent（常态空态，不是失败）
    func testLoadProductionShape() async throws {
        let store = ServerVersionStore()
        await store.load(
            config: testConfig,
            fetchers: .init(
                status: { _ in try self.status(self.productionStatusJSON) },
                updateCheck: { try self.check(self.managedCheckJSON) },
                updateReceipt: { throw UpdateReceiptError.absent }
            )
        )
        XCTAssertTrue(store.hasLoaded)
        XCTAssertFalse(store.statusFailed)
        XCTAssertFalse(store.sessionExpired)
        XCTAssertEqual(store.receiptState, .absent)
        XCTAssertEqual(store.facts.versionText, "0.23.0")
        XCTAssertEqual(store.facts.releaseDateText, "2026.9.24")
        XCTAssertEqual(store.facts.configVersionText, "52 / 52")
        XCTAssertEqual(
            store.facts.managedNote, ServerVersionBuilder.managedNoteText
        )
    }

    /// 回执在位：摘要原话直达 present
    func testLoadReceiptPresent() async throws {
        let store = ServerVersionStore()
        await store.load(
            config: testConfig,
            fetchers: .init(
                status: { _ in try self.status(self.productionStatusJSON) },
                updateCheck: { try self.check(self.managedCheckJSON) },
                updateReceipt: {
                    try self.receipt(
                        #"{"receipt": {"outcome": "success"}, "summary": "Updated to 0.24.0"}"#
                    )
                }
            )
        )
        XCTAssertEqual(store.receiptState, .present("Updated to 0.24.0"))
    }

    /// 回执普通失败落 .failed，与 404 空态严格分型
    func testLoadReceiptFailureIsNotAbsent() async throws {
        let store = ServerVersionStore()
        await store.load(
            config: testConfig,
            fetchers: .init(
                status: { _ in try self.status(self.productionStatusJSON) },
                updateCheck: { try self.check(self.managedCheckJSON) },
                updateReceipt: {
                    throw HermesError.unexpectedStatus(
                        endpoint: "更新回执", status: 500
                    )
                }
            )
        )
        XCTAssertEqual(store.receiptState, .failed)
    }

    /// 状态面失败被隔离：检查面照常落地、版本走回落
    func testLoadStatusFailureIsolated() async throws {
        let store = ServerVersionStore()
        await store.load(
            config: testConfig,
            fetchers: .init(
                status: { _ in throw HermesError.unreachable("离线") },
                updateCheck: { try self.check(self.managedCheckJSON) },
                updateReceipt: { throw UpdateReceiptError.absent }
            )
        )
        XCTAssertTrue(store.statusFailed)
        XCTAssertNotNil(store.check)
        XCTAssertEqual(store.facts.versionText, "0.23.0")
        XCTAssertEqual(store.receiptState, .absent)
    }

    /// 会话过期：check 与 receipt 两路同落过期口径，
    /// 状态面（免登录）不受拖累
    func testLoadSessionExpired() async throws {
        let store = ServerVersionStore()
        await store.load(
            config: testConfig,
            fetchers: .init(
                status: { _ in try self.status(self.productionStatusJSON) },
                updateCheck: { throw HermesError.sessionExpired },
                updateReceipt: { throw HermesError.sessionExpired }
            )
        )
        XCTAssertTrue(store.sessionExpired)
        XCTAssertEqual(store.receiptState, .sessionExpired)
        XCTAssertFalse(store.statusFailed)
        XCTAssertEqual(store.facts.versionText, "0.23.0")
    }

    /// 未连接：整段如实不可用，不冒充空数据
    func testLoadUnavailableWithoutConfig() async {
        let appState = AppState(
            client: DemoHermesClient(), demoMode: .connectPage
        )
        let store = ServerVersionStore()
        await store.load(appState: appState)
        XCTAssertNotNil(store.unavailableMessage)
        XCTAssertTrue(store.hasLoaded)
    }

    // MARK: - 装配钉测（源码层）

    private func sectionCode() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let repositoryRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = repositoryRoot.appendingPathComponent(
            "Sources/OneDayApp/ServerVersionSection.swift"
        )
        return Self.stripComments(
            try String(contentsOf: url, encoding: .utf8)
        )
    }

    /// 案 A 红线钉死：段内不许有任何按钮与「检查更
    /// 新/立即更新/执行更新」形态——托管态做可点入
    /// 口即僵尸功能（§360）
    func testSectionHasNoActionAffordance() throws {
        let code = try sectionCode()
        XCTAssertFalse(code.contains("Button"), "版本与更新段不许有按钮")
        XCTAssertFalse(code.contains("检查更新"))
        XCTAssertFalse(code.contains("立即更新"))
        XCTAssertFalse(code.contains("执行更新"))
        XCTAssertFalse(code.contains("updateHermes"))
    }

    /// 段已挂上服务器详情页（装配在位）
    func testSectionMountedInServerDetail() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let repositoryRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = repositoryRoot.appendingPathComponent(
            "Sources/OneDayApp/ServerDetailView.swift"
        )
        let code = Self.stripComments(
            try String(contentsOf: url, encoding: .utf8)
        )
        XCTAssertTrue(code.contains("ServerVersionSection()"))
    }

    /// 去注释（与 ChatComposerQuote332Tests 同式状态
    /// 机：字符串内的 // 不误伤）
    private static func stripComments(_ source: String) -> String {
        var result = ""
        var index = source.startIndex
        var inLineComment = false
        var inBlockComment = false
        var inString = false
        while index < source.endIndex {
            let char = source[index]
            let next = source.index(after: index)
            let peek: Character? = next < source.endIndex ? source[next] : nil
            if inLineComment {
                if char == "\n" {
                    inLineComment = false
                    result.append(char)
                }
            } else if inBlockComment {
                if char == "*", peek == "/" {
                    inBlockComment = false
                    index = source.index(after: next)
                    continue
                }
            } else if inString {
                result.append(char)
                if char == "\\", let peek {
                    result.append(peek)
                    index = source.index(after: next)
                    continue
                } else if char == "\"" {
                    inString = false
                }
            } else if char == "/", peek == "/" {
                inLineComment = true
                index = source.index(after: next)
                continue
            } else if char == "/", peek == "*" {
                inBlockComment = true
                index = source.index(after: next)
                continue
            } else {
                if char == "\"" { inString = true }
                result.append(char)
            }
            index = next
        }
        return result
    }
}
