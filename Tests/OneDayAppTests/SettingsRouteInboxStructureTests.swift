import XCTest
@testable import OneDayApp
import OneDayCore

/// §400 总表 73「设置路由信箱归并」独立核实的把守钉：
/// 归并本体由 §305（A-03/A-28）落码、本套只钉形态防
/// 回潮——①信箱五件（pendingAgentRoute／pending-
/// SettingsRoute／settingsSheetRequested／mainTab-
/// SwitchRequest／fileRevealPath）声明只在 AppRouter、
/// AppState 零声明（防第二信箱再长出来）；②Settings-
/// Route／AgentRoute 两枚举全仓单定义且同在
/// AppRouter.swift、AppRoutes.swift 不复活；
/// ③ManageSheet 已于 §493 随设置行 sheet 呈现整
/// 套退役——全仓零定义、零 SettingsView.ManageSheet
/// 反向借用（防自创呈现槽回潮）；
/// ④行为钉：五件在 AppRouter 上互为独立槽、消费
/// 清零一件不扰其他四件（补 AppRouterTests 独立槽
/// 测只覆盖两件的缺口）
@MainActor
final class SettingsRouteInboxStructureTests: XCTestCase {

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func source(_ relative: String) throws -> String {
        try String(
            contentsOf: repoRoot()
                .appendingPathComponent(relative),
            encoding: .utf8
        )
    }

    /// 代码行视图：剔除整行注释（/// 与 //）——历史
    /// prose 提及旧形态不在禁列，禁的是代码本体回潮
    private func codeLines(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { line in
                let t = line.trimmingCharacters(
                    in: .whitespaces
                )
                return !t.hasPrefix("///") && !t.hasPrefix("//")
            }
            .joined(separator: "\n")
    }

    private func allAppSources() throws -> [(name: String, code: String)] {
        let dir = repoRoot()
            .appendingPathComponent("Sources/OneDayApp")
        let files = try FileManager.default
            .contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasSuffix(".swift") }
            .sorted()
        return try files.map { name in
            (
                name,
                try codeLines(source("Sources/OneDayApp/\(name)"))
            )
        }
    }

    private let mailboxFive = [
        "pendingAgentRoute",
        "pendingSettingsRoute",
        "settingsSheetRequested",
        "mainTabSwitchRequest",
        "fileRevealPath",
    ]

    func testMailboxFiveDeclaredOnlyInAppRouter() throws {
        let router = try codeLines(source(
            "Sources/OneDayApp/AppRouter.swift"
        ))
        let appState = try codeLines(source(
            "Sources/OneDayApp/AppState.swift"
        ))
        for field in mailboxFive {
            XCTAssertTrue(
                router.contains("var \(field)"),
                "AppRouter 缺信箱件 \(field)"
            )
            XCTAssertFalse(
                appState.contains("var \(field)"),
                "AppState 又长出信箱件 \(field)——第二信箱回潮"
            )
        }
    }

    func testRouteEnumsSingleDefinitionInAppRouter() throws {
        let all = try allAppSources()
        for enumName in ["SettingsRoute", "AgentRoute"] {
            let hits = all
                .filter { $0.code.contains("enum \(enumName)") }
                .map(\.name)
            XCTAssertEqual(
                hits, ["AppRouter.swift"],
                "\(enumName) 定义点不是单点／AppRouter：\(hits)"
            )
        }
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: repoRoot()
                    .appendingPathComponent(
                        "Sources/OneDayApp/AppRoutes.swift"
                    ).path
            ),
            "AppRoutes.swift 复活——路由枚举与信箱须单归 AppRouter"
        )
    }

    func testManageSheetRetiredNoReverseBorrow() throws {
        let all = try allAppSources()
        let defs = all
            .filter { $0.code.contains("enum ManageSheet") }
            .map(\.name)
        XCTAssertEqual(
            defs, [],
            "ManageSheet 已于 §493 退役、不许复活：\(defs)"
        )
        for (name, code) in all {
            XCTAssertFalse(
                code.contains("SettingsView.ManageSheet"),
                "\(name) 仍反向借用 SettingsView.ManageSheet"
            )
        }
    }

    func testSettingsMailboxSlotsAreIndependent() {
        let router = AppRouter()
        router.pendingAgentRoute = .memory
        router.pendingSettingsRoute = .models
        router.settingsSheetRequested = true
        router.mainTabSwitchRequest = .files
        router.fileRevealPath = "/tmp/x.pdf"
        XCTAssertEqual(router.pendingAgentRoute, .memory)
        XCTAssertEqual(router.pendingSettingsRoute, .models)
        XCTAssertTrue(router.settingsSheetRequested)
        XCTAssertEqual(router.mainTabSwitchRequest, .files)
        XCTAssertEqual(router.fileRevealPath, "/tmp/x.pdf")
        // 消费清零一件不扰其他四件
        router.pendingSettingsRoute = nil
        XCTAssertEqual(router.pendingAgentRoute, .memory)
        XCTAssertTrue(router.settingsSheetRequested)
        XCTAssertEqual(router.mainTabSwitchRequest, .files)
        XCTAssertEqual(router.fileRevealPath, "/tmp/x.pdf")
    }
}
