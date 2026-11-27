import Foundation
import XCTest

/// §388 H6/H7 结构钉测：两条新面的接线形态在源码层把守——
/// 模板入口只许在定时任务页一处、目录入口只许在连接器面
/// 一处（一个功能一个家）；表单不许再回到 deliver 恒 nil
/// 的旧形态；五个新端点路径在客户端实现里各就一位。
final class H6H7StructureTests: XCTestCase {

    private func source(_ relativePath: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let url = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func occurrences(_ haystack: String, _ needle: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }

    func testCronViewHasSingleBlueprintEntryAndDeliveryWiring() throws {
        let src = try source("Sources/OneDayApp/CronViews.swift")
        // 模板挑选面入口恰一处（任务页 sheet）
        XCTAssertEqual(
            occurrences(src, "CronBlueprintPickerView {"), 1,
            "§388：蓝图挑选面入口应恰一处"
        )
        // 投递目标真接线：取数一次、保存透传，不许回恒 nil
        XCTAssertEqual(
            occurrences(src, "cronDeliveryTargets(config: config)"), 1
        )
        XCTAssertEqual(
            occurrences(src, "deliver: nil"), 0,
            "§388：建任务不许再恒传 deliver: nil（投递不可选的旧形态）"
        )
        XCTAssertTrue(src.contains("selectedDeliver"))
    }

    func testConnectorsViewHasSingleCatalogEntry() throws {
        let src = try source("Sources/OneDayApp/ConnectorsView.swift")
        XCTAssertEqual(
            occurrences(src, "MCPCatalogView(facade: facade)"), 1,
            "§388：MCP 目录入口应恰一处（连接器面可连接段）"
        )
    }

    func testClientImplementsNewEndpoints() throws {
        let mainSrc = try source("Sources/OneDayApp/HermesClient.swift")
        let extSrc = try source("Sources/OneDayApp/HermesClient+SessionsAndMemory.swift")
        let combined = mainSrc + extSrc
        for path in [
            "/api/cron/blueprints",
            "/api/cron/blueprints/instantiate",
            "/api/cron/delivery-targets",
            "/api/mcp/catalog",
            "/api/mcp/catalog/install",
        ] {
            XCTAssertTrue(
                combined.contains("path: \"\(path)\""),
                "§388：客户端缺端点实现 \(path)"
            )
        }
    }

    func testFacadeOwnsCatalogReadbackInstall() throws {
        let src = try source("Sources/OneDayApp/ConnectorsFacade.swift")
        // 安装落定靠回读目录 installed 对账，不认回执即成功
        XCTAssertTrue(src.contains("func installCatalogEntry"))
        XCTAssertTrue(src.contains("?.installed == true"))
        XCTAssertTrue(src.contains("receipt.background"))
    }
}
