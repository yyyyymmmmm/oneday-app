import XCTest
@testable import OneDayCore

/// 设置目录钉测（DESIGN §164）：清单完整性（id/目的
/// 地唯一、对账锚点齐全）与搜索口径（清单序、空查询
/// 全量、中英关键词命中、无命中为空）
final class SettingsCatalogTests: XCTestCase {

    func testIDsAndDestinationsAreUnique() {
        let ids = SettingsCatalog.entries.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "条目 id 必须唯一")
        let destinations = SettingsCatalog.entries.map(\.destination)
        XCTAssertEqual(
            Set(destinations).count, destinations.count,
            "每个目的地只许一个条目（点达不许双门）"
        )
    }

    func testEntriesCarrySearchMaterial() {
        for entry in SettingsCatalog.entries {
            XCTAssertFalse(entry.title.isEmpty, "\(entry.id) 缺标题")
            XCTAssertFalse(entry.summary.isEmpty, "\(entry.id) 缺副行")
            XCTAssertFalse(entry.keywords.isEmpty, "\(entry.id) 缺关键词")
        }
    }

    /// 原型搜索索引（prototype-2，29 项）在清单里逐项有锚
    func testPrototypeIndexIsCovered() {
        let ids = Set(SettingsCatalog.entries.map(\.id))
        for id in [
            "agentConfig", "serverManagement", "sessionManagement", "workspace",
            "privacy", "terms",
            "identity", "profiles", "memory", "skills", "models", "cron",
            "mainSession", "serverSessions",
            "server", "gateway", "restartGateway", "logs", "envVars", "usage",
            "connectors", "devicePermissions",
            "overview", "computer", "serverFiles",
            "appearance", "sidebar", "help", "about",
        ] {
            XCTAssertTrue(ids.contains(id), "原型索引缺条目 \(id)")
        }
    }

    /// 现行主页全部目的地在清单里有锚（零丢失对账的
    /// 机器面：目的地集合与 SettingsDestination 全集
    /// 逐一对应）
    func testEveryDestinationIsCovered() {
        let covered = Set(SettingsCatalog.entries.map(\.destination))
        let all: [SettingsDestination] = [
            .identity, .profiles, .memory, .skills, .cron,
            .serverSessions, .models, .envVars, .usage,
            .serverDetail, .connectors, .devicePermissions,
            .approvalRules,
            .gateway, .logs, .overview, .computer, .serverFiles,
            .appearance, .sidebar, .allConversations, .help, .about, .privacy, .terms,
            // prototype-2 新增
            .agentConfig, .serverManagement, .sessionManagement,
            .workspaceHub, .mainSession, .restartGateway,
        ]
        XCTAssertEqual(covered, Set(all))
    }

    /// prototype-2：agent 组只剩 models/agentConfig/cron 三行
    func testAgentGroupBrowseOrder() {
        XCTAssertEqual(
            SettingsCatalog.browseEntries(in: .agent).map(\.id),
            ["models", "agentConfig", "cron"]
        )
    }

    /// prototype-2：serverAndWorkspace 组三个枢纽页
    func testServerAndWorkspaceGroupBrowseOrder() {
        XCTAssertEqual(
            SettingsCatalog.browseEntries(in: .serverAndWorkspace).map(\.id),
            ["serverManagement", "sessionManagement", "workspace"]
        )
    }

    /// prototype-2：preferences 组四行（§198 侧边栏行
    /// 插在 appearance 与 connectors 之间）；管理收
    /// 口包补件起五行——全部对话行紧随侧边栏之后
    /// （用户 2026-11-13 18:57 拍板挪进设置页）
    func testPreferencesGroupBrowseOrder() {
        XCTAssertEqual(
            SettingsCatalog.browseEntries(in: .preferences).map(\.id),
            ["appearance", "sidebar", "allConversations", "connectors", "devicePermissions", "approvalRules"]
        )
    }

    /// 全部对话行（管理收口包补件，用户 2026-11-13
    /// 18:57 拍板）：行在偏好组内、与侧边栏行同组相
    /// 邻（侧边栏在其上、连接器在其下），行名用页面
    /// 自身标题「全部对话」不带「管理」二字，目的地
    /// 是专设的 .allConversations（设置页据此渲动作
    /// 行、走原抽屉入口同一根级呈现路）
    func testAllConversationsEntrySitsNextToSidebar() {
        let browse = SettingsCatalog.browseEntries(in: .preferences)
        guard let idx = browse.firstIndex(where: { $0.id == "allConversations" })
        else {
            XCTFail("偏好组缺全部对话行")
            return
        }
        XCTAssertEqual(browse[idx].title, "全部对话")
        XCTAssertEqual(browse[idx].destination, .allConversations)
        XCTAssertEqual(browse[idx - 1].id, "sidebar")
        XCTAssertEqual(browse[idx + 1].id, "connectors")
        // 搜索点达同源：标题直搜命中本行
        XCTAssertTrue(
            SettingsCatalog.search("全部对话").contains {
                $0.id == "allConversations"
            }
        )
    }

    /// prototype-2：隐藏条目（不在根页显示）——identity/privacy/terms
    /// ＋移入枢纽页的子项（profiles/memory/skills 等）
    func testHiddenFromBrowseEntries() {
        let hidden = SettingsCatalog.entries
            .filter { !$0.showsInBrowse }.map(\.id)
        XCTAssertEqual(
            Set(hidden),
            [
                "identity", "privacy", "terms",
                // agentConfig 页内
                "profiles", "memory", "skills",
                // serverManagement 页内
                "server", "gateway", "logs", "usage", "envVars", "restartGateway",
                // sessionManagement 页内
                "mainSession", "serverSessions",
                // workspace 页内
                "overview", "computer", "serverFiles",
            ]
        )
    }

    func testSearchByChineseTitle() {
        let hits = SettingsCatalog.search("记忆")
        XCTAssertEqual(hits.first?.id, "memory")
        // 标题命中优先；枢纽页「智能体配置」副行含「记忆」
        // 仍须命中（零丢失），只是排在标题页之后
        XCTAssertTrue(hits.contains { $0.id == "agentConfig" })
    }

    func testSearchMatchesSummaryAndKeywords() {
        // 「服务器」命中服务器管理（标题）、配置档案
        // （副行含「服务器」）等多条，按清单序返回
        let hits = SettingsCatalog.search("服务器")
        XCTAssertTrue(hits.contains { $0.id == "serverManagement" })
        XCTAssertTrue(hits.contains { $0.id == "profiles" })
        // 英文关键词大小写不敏感
        XCTAssertEqual(
            SettingsCatalog.search("MEMORY").map(\.id), ["memory"]
        )
        XCTAssertEqual(
            SettingsCatalog.search("mcp").map(\.id), ["connectors"]
        )
        // prototype-2 监工纠正④：断开连接搜索命中服务器管理
        let disconnectHits = SettingsCatalog.search("断开连接")
        XCTAssertTrue(
            disconnectHits.contains { $0.id == "serverManagement" },
            "断开连接应命中服务器管理（关键词含「断开连接」）"
        )
    }

    func testSearchTrimsAndEmptyReturnsAll() {
        XCTAssertEqual(
            SettingsCatalog.search("  外观 ").map(\.id), ["appearance"]
        )
        XCTAssertEqual(
            SettingsCatalog.search("").count,
            SettingsCatalog.entries.count
        )
        XCTAssertEqual(
            SettingsCatalog.search("   ").count,
            SettingsCatalog.entries.count
        )
    }

    func testSearchNoHitIsEmpty() {
        XCTAssertTrue(SettingsCatalog.search("不存在的词条xyz").isEmpty)
    }
}
