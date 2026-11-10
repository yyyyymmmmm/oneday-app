import XCTest
@testable import OneDayCore

/// 连接器目录闸（0.28.0）：状态真实口径由本组测
/// 钉——①目录完整性（每条字段齐、分类齐）②已连
/// 接必带证据档位（构造口唯一、恒 liveVerified）
/// ③状态文案映射④搜索真过滤（名称/分类/说明）
/// ⑤已连接占名从可连接目录扣除，防两边口径打架。
final class ConnectorCatalogTests: XCTestCase {

    private func server(
        _ name: String, enabled: Bool = true,
        source: String? = nil, plugin: String? = nil,
        transport: String? = "http"
    ) -> MCPServerItem {
        MCPServerItem(
            name: name, transport: transport,
            url: "https://example.com/mcp", command: nil,
            enabled: enabled, source: source, plugin: plugin
        )
    }

    // MARK: - 目录完整性

    func testCatalogIntegrity() {
        let catalog = ConnectorDirectory.catalog
        XCTAssertEqual(catalog.count, 8)
        XCTAssertEqual(Set(catalog.map(\.id)).count, catalog.count, "id 唯一")
        for entry in catalog {
            XCTAssertFalse(entry.name.isEmpty, entry.id)
            XCTAssertFalse(entry.blurb.isEmpty, entry.id)
            XCTAssertFalse(entry.tileGlyph.isEmpty, entry.id)
            XCTAssertFalse(entry.accessSummary.isEmpty, entry.id)
            XCTAssertTrue(
                entry.accessDetail.contains("尚未接入"),
                "未接入条目必须直说未接入：\(entry.id)"
            )
        }
        XCTAssertEqual(
            Set(catalog.map(\.category)),
            Set(ConnectorCategory.allCases),
            "四分类齐备"
        )
    }

    func testCatalogIDsMatchBrief() {
        XCTAssertEqual(
            ConnectorDirectory.catalog.map(\.id),
            ["gmail", "google-calendar", "google-drive",
             "google-sheets", "notion", "github",
             "spotify", "instagram"]
        )
    }

    // MARK: - 已连接与证据档位

    func testConnectedAlwaysCarriesLiveEvidence() {
        let connected = ConnectorDirectory.connectedEntries(from: [
            server("box", source: "plugin", plugin: "box"),
            server("custom", enabled: false, transport: "stdio"),
        ])
        XCTAssertEqual(connected.count, 2)
        for entry in connected {
            XCTAssertEqual(
                entry.evidence, .liveVerified,
                "端点读到的已连接必带实活档位：\(entry.id)"
            )
            XCTAssertEqual(entry.evidence.label, "服务端实时读取")
        }
    }

    func testKnownServerPresentationMapping() {
        let box = ConnectorDirectory.connectedEntries(from: [
            server("box", source: "plugin", plugin: "box"),
        ])[0]
        XCTAssertEqual(box.displayName, "Simular Box")
        XCTAssertEqual(box.tileGlyph, "B")
        XCTAssertTrue(box.blurb.contains("云电脑"))
    }

    func testUnknownServerFallsBackToRawName() {
        let entry = ConnectorDirectory.connectedEntries(from: [
            server("my-tool", source: "plugin", plugin: "p"),
        ])[0]
        XCTAssertEqual(entry.displayName, "my-tool")
        XCTAssertEqual(entry.tileGlyph, "M")
        XCTAssertEqual(entry.blurb, "插件预置的 MCP 连接")
        let manual = ConnectorDirectory.connectedEntries(from: [
            server("hand", source: nil),
        ])[0]
        XCTAssertEqual(manual.blurb, "手动配置的 MCP 连接")
    }

    // MARK: - 状态文案映射

    func testStatusLabelMapping() {
        let on = ConnectorDirectory.connectedEntries(from: [
            server("box"),
        ])[0]
        let off = ConnectorDirectory.connectedEntries(from: [
            server("box", enabled: false),
        ])[0]
        XCTAssertEqual(on.statusLabel, "已连接 · 已启用")
        XCTAssertEqual(off.statusLabel, "已连接 · 已停用")
        XCTAssertEqual(ConnectorEvidence.configuredOnly.label, "仅配置在册 · 未验活")
        XCTAssertEqual(ConnectorEvidence.none.label, "无连接证据")
    }

    // MARK: - 搜索过滤

    func testSearchMatchesNameBlurbCategory() {
        let all = ConnectorDirectory.catalog
        XCTAssertEqual(
            ConnectorDirectory.filteredCatalog(all, query: "gmail").map(\.id),
            ["gmail"], "拉丁名不分大小写"
        )
        XCTAssertEqual(
            ConnectorDirectory.filteredCatalog(all, query: "邮件").map(\.id),
            ["gmail"], "说明命中"
        )
        XCTAssertEqual(
            ConnectorDirectory.filteredCatalog(all, query: "开发").map(\.id),
            ["github"], "分类命中"
        )
        XCTAssertEqual(
            ConnectorDirectory.filteredCatalog(all, query: "表格").map(\.id),
            ["google-sheets"]
        )
        XCTAssertEqual(
            ConnectorDirectory.filteredCatalog(all, query: "").count, 8,
            "空查询回全集"
        )
        XCTAssertTrue(
            ConnectorDirectory.filteredCatalog(all, query: "不存在的服务").isEmpty
        )
    }

    func testSearchConnectedEntries() {
        let connected = ConnectorDirectory.connectedEntries(from: [
            server("box", source: "plugin", plugin: "box"),
            server("other", enabled: false),
        ])
        XCTAssertEqual(
            ConnectorDirectory.filteredConnected(connected, query: "Simular").map(\.id),
            ["box"], "显示名命中"
        )
        XCTAssertEqual(
            ConnectorDirectory.filteredConnected(connected, query: "已停用").map(\.id),
            ["other"], "状态文案命中"
        )
        XCTAssertEqual(
            ConnectorDirectory.filteredConnected(connected, query: "云电脑").map(\.id),
            ["box"], "说明命中"
        )
    }

    // MARK: - 占名扣除与分组

    func testAvailableExcludesConnectedNames() {
        let connected = ConnectorDirectory.connectedEntries(from: [
            server("notion"),
        ])
        let available = ConnectorDirectory.availableEntries(connected: connected)
        XCTAssertFalse(available.contains { $0.id == "notion" })
        XCTAssertEqual(available.count, 7)
        let none = ConnectorDirectory.availableEntries(connected: [])
        XCTAssertEqual(none.count, 8)
    }

    func testGroupingPreservesCategoryOrder() {
        let groups = ConnectorDirectory.grouped(ConnectorDirectory.catalog)
        XCTAssertEqual(
            groups.map(\.category),
            [.productivity, .office, .development, .life]
        )
        XCTAssertEqual(groups[0].entries.map(\.id), ["gmail", "google-calendar"])
        XCTAssertEqual(groups[1].entries.map(\.id), ["google-drive", "google-sheets", "notion"])
    }
}
