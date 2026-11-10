import Foundation

/// 连接器目录（0.28.0，连接器目录页）：状态真实为
/// 第一纪律——「已连接」只来自服务端端点的实时读取
/// （GET /api/mcp/servers，与既有 MCP 数据链同源、
/// 不另造第二套状态口径），每条强制带证据档位；
/// 「可连接」是静态目录，全部如实标未接入＋接入路
/// 径，App 内不设假的连接按钮。内部桥（write-gate/
/// overview/oneday/box-bridge）是 OneDay 自身设施，
/// 不列作用户连接器。
///
/// 2026-11-10 实查（只读，证据全表见 DESIGN-V4
/// §55.1）：服务器内存 51%（红线 80% 内）；config
/// .yaml 的 mcp_servers 整段是注释模板——手动配置
/// 的 MCP 服务器 0 条；端点登录实测 200、在册仅
/// box 一条（http、enabled=true、source=plugin）；
/// channel_directory.platforms 为空集——消息平台
/// 连接 0 条。

/// 证据档位：如实分级——「配置里写过」不许说成
/// 「活着连着」
public enum ConnectorEvidence: String, Sendable, Equatable, CaseIterable {
    /// 端点实活：本次经服务端端点读到在册、启用
    /// 状态可读
    case liveVerified
    /// 仅配置：配置里有记录，未经端点验活（预留
    /// 档：将来若有只读配置面来源，按此档如实标，
    /// 不许冒充实活）
    case configuredOnly
    /// 无证据
    case none

    public var label: String {
        switch self {
        case .liveVerified: return "服务端实时读取"
        case .configuredOnly: return "仅配置在册 · 未验活"
        case .none: return "无连接证据"
        }
    }
}

/// 目录分类（参考图口径落四类）
public enum ConnectorCategory: String, Sendable, Equatable, CaseIterable {
    case productivity = "效率提升"
    case office = "办公协作"
    case development = "开发工具"
    case life = "生活"
}

/// 可连接目录条目（静态数据）：名称/说明/分类/接
/// 入说明全在 Core 单一真源，视图只渲染。tileGlyph
/// ＋tileColorHex 是近似品牌瓷砖（彩色底＋白字形），
/// 不是官方品牌图标——市面无授权素材可用，宁可近
/// 似、不拿错图标冒充（§55 登记）。
public struct ConnectorCatalogEntry: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    /// 一句说明（列表行与详情共用）
    public let blurb: String
    public let category: ConnectorCategory
    public let tileGlyph: String
    public let tileColorHex: UInt32
    /// 接入路径一句话（详情状态区）
    public let accessSummary: String
    /// 接入说明全文（详情 sheet）：未接入就直说未
    /// 接入、接入要在哪儿做什么，不许含糊
    public let accessDetail: String

    public init(
        id: String, name: String, blurb: String,
        category: ConnectorCategory,
        tileGlyph: String, tileColorHex: UInt32,
        accessSummary: String, accessDetail: String
    ) {
        self.id = id
        self.name = name
        self.blurb = blurb
        self.category = category
        self.tileGlyph = tileGlyph
        self.tileColorHex = tileColorHex
        self.accessSummary = accessSummary
        self.accessDetail = accessDetail
    }
}

/// 已连接条目：由端点返回的 MCPServerItem 构成。
/// 构造口只有一个——端点读到的才算已连接，evidence
/// 恒为 liveVerified；不给「无证据的已连接」留构造
/// 路径（数据完整性由 ConnectorCatalogTests 闸钉）。
public struct ConnectedConnector: Identifiable, Sendable {
    public let server: MCPServerItem
    public let evidence: ConnectorEvidence

    public var id: String { server.id }

    public init(server: MCPServerItem) {
        self.server = server
        self.evidence = .liveVerified
    }

    /// 已知在册名的展示映射；未知名的走原名＋来源
    /// 口径兜底（如实显示服务端名，不编造产品名）
    private var known: ConnectorServerPresentation? {
        ConnectorDirectory.knownServers[server.name]
    }

    public var displayName: String {
        known?.name ?? server.name
    }

    public var blurb: String {
        if let known { return known.blurb }
        return server.isPluginProvided
            ? "插件预置的 MCP 连接"
            : "手动配置的 MCP 连接"
    }

    public var tileGlyph: String {
        if let known { return known.glyph }
        return String(server.name.prefix(1)).uppercased()
    }

    public var tileColorHex: UInt32 {
        known?.colorHex ?? 0x8A94A6
    }

    /// 状态文案单一映射（列表行与详情共用一处）
    public var statusLabel: String {
        server.enabled ? "已连接 · 已启用" : "已连接 · 已停用"
    }
}

/// 已知服务端名的展示资料（只收实查在册者）
public struct ConnectorServerPresentation: Equatable, Sendable {
    public let name: String
    public let blurb: String
    public let glyph: String
    public let colorHex: UInt32

    public init(name: String, blurb: String, glyph: String, colorHex: UInt32) {
        self.name = name
        self.blurb = blurb
        self.glyph = glyph
        self.colorHex = colorHex
    }
}

public enum ConnectorDirectory {
    /// 2026-11-10 实查在册仅 box（Simular 官方插件
    /// 预置）：显示产品名与人话说明，服务端名 box
    /// 本身对用户无意义
    public static let knownServers: [String: ConnectorServerPresentation] = [
        "box": ConnectorServerPresentation(
            name: "Simular Box",
            blurb: "云电脑 · 智能体可操作一台云端电脑",
            glyph: "B", colorHex: 0x5B7DB1
        ),
    ]

    /// 可连接目录（静态全集）：主流服务八家，全为
    /// 未接入＋接入路径如实标注
    public static let catalog: [ConnectorCatalogEntry] = [
        ConnectorCatalogEntry(
            id: "gmail", name: "Gmail",
            blurb: "收发、搜索与整理你的 Gmail 邮件",
            category: .productivity,
            tileGlyph: "M", tileColorHex: 0xD93025,
            accessSummary: "需服务器端配置 MCP 并完成 Google 授权",
            accessDetail: "尚未接入。接入路径：在 Hermes 服务器端配置 Gmail 的 MCP 服务器，并以你的 Google 账号完成 OAuth 授权。Google 未提供面向个人的一键接入，需要自备 Google Cloud 项目的授权凭据，全程在服务器端完成，App 内暂不能直接连接。"
        ),
        ConnectorCatalogEntry(
            id: "google-calendar", name: "Google 日历",
            blurb: "查看日程、创建与修改日历活动",
            category: .productivity,
            tileGlyph: "31", tileColorHex: 0x4285F4,
            accessSummary: "需服务器端配置 MCP 并完成 Google 授权",
            accessDetail: "尚未接入。接入路径与 Gmail 相同：在 Hermes 服务器端配置日历的 MCP 服务器并完成 Google 账号 OAuth 授权，需要自备 Google Cloud 项目的授权凭据，App 内暂不能直接连接。"
        ),
        ConnectorCatalogEntry(
            id: "google-drive", name: "Google 云端硬盘",
            blurb: "查找、读取与整理云端硬盘文件",
            category: .office,
            tileGlyph: "D", tileColorHex: 0x1FA463,
            accessSummary: "需服务器端配置 MCP 并完成 Google 授权",
            accessDetail: "尚未接入。接入路径与 Gmail 相同：在 Hermes 服务器端配置云端硬盘的 MCP 服务器并完成 Google 账号 OAuth 授权，需要自备 Google Cloud 项目的授权凭据，App 内暂不能直接连接。"
        ),
        ConnectorCatalogEntry(
            id: "google-sheets", name: "Google 表格",
            blurb: "读取与编辑 Google 表格数据",
            category: .office,
            tileGlyph: "S", tileColorHex: 0x188038,
            accessSummary: "需服务器端配置 MCP 并完成 Google 授权",
            accessDetail: "尚未接入。接入路径与 Gmail 相同：在 Hermes 服务器端配置表格的 MCP 服务器并完成 Google 账号 OAuth 授权，需要自备 Google Cloud 项目的授权凭据，App 内暂不能直接连接。"
        ),
        ConnectorCatalogEntry(
            id: "notion", name: "Notion",
            blurb: "搜索与编辑 Notion 页面和数据库",
            category: .office,
            tileGlyph: "N", tileColorHex: 0x1B1B1B,
            accessSummary: "有官方远程 MCP · 需服务器端添加并授权",
            accessDetail: "尚未接入。Notion 提供官方远程 MCP（mcp.notion.com），接入路径：在 Hermes 服务器配置中添加该地址，并完成一次 Notion 账号授权。是目录里接入成本较低的一家，但仍需在服务器端操作，App 内暂不能直接连接。"
        ),
        ConnectorCatalogEntry(
            id: "github", name: "GitHub",
            blurb: "查看仓库、议题与拉取请求",
            category: .development,
            tileGlyph: "G", tileColorHex: 0x24292F,
            accessSummary: "有官方远程 MCP · 需服务器端添加并授权",
            accessDetail: "尚未接入。GitHub 提供官方远程 MCP，接入路径：在 Hermes 服务器配置中添加，并以 GitHub 授权（OAuth 或访问令牌）完成接入。是目录里接入成本较低的一家，但仍需在服务器端操作，App 内暂不能直接连接。"
        ),
        ConnectorCatalogEntry(
            id: "spotify", name: "Spotify",
            blurb: "搜索音乐、管理歌单与播放",
            category: .life,
            tileGlyph: "♪", tileColorHex: 0x1DB954,
            accessSummary: "无官方 MCP · 需开发者凭据＋社区服务器",
            accessDetail: "尚未接入。Spotify 没有官方 MCP；社区服务器需要在 Spotify 开发者平台自建应用、取得凭据后在服务器端配置。门槛高于官方路径，App 内暂不能直接连接。"
        ),
        ConnectorCatalogEntry(
            id: "instagram", name: "Instagram",
            blurb: "查看主页动态与帖子互动",
            category: .life,
            tileGlyph: "IG", tileColorHex: 0xC13584,
            accessSummary: "官方暂无 MCP 接入路径",
            accessDetail: "尚未接入。Meta 未提供官方 MCP 接入，第三方方案的稳定性与账号风险都不可控，何时能接取决于官方支持，目前没有可靠的接入路径。"
        ),
    ]

    /// 端点名单 → 已连接条目（顺序从端点）
    public static func connectedEntries(
        from servers: [MCPServerItem]
    ) -> [ConnectedConnector] {
        servers.map(ConnectedConnector.init(server:))
    }

    /// 可连接名单：静态目录扣除已被真实连接占名的
    /// 条目（防同一服务两边同时出现、口径打架——
    /// 如将来 notion 真以 MCP 名 notion 在册）
    public static func availableEntries(
        connected: [ConnectedConnector]
    ) -> [ConnectorCatalogEntry] {
        let taken = Set(connected.map { $0.server.name })
        return catalog.filter { !taken.contains($0.id) }
    }

    // MARK: - 搜索（真过滤：名称＋分类＋说明，纯函数）

    private static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public static func matches(
        _ entry: ConnectorCatalogEntry, query: String
    ) -> Bool {
        let q = normalized(query)
        if q.isEmpty { return true }
        let fields = [entry.name, entry.id, entry.blurb, entry.category.rawValue]
        return fields.contains { normalized($0).contains(q) }
    }

    public static func matches(
        _ entry: ConnectedConnector, query: String
    ) -> Bool {
        let q = normalized(query)
        if q.isEmpty { return true }
        let fields = [
            entry.displayName, entry.server.name,
            entry.blurb, entry.statusLabel,
        ]
        return fields.contains { normalized($0).contains(q) }
    }

    public static func filteredCatalog(
        _ entries: [ConnectorCatalogEntry], query: String
    ) -> [ConnectorCatalogEntry] {
        entries.filter { matches($0, query: query) }
    }

    public static func filteredConnected(
        _ entries: [ConnectedConnector], query: String
    ) -> [ConnectedConnector] {
        entries.filter { matches($0, query: query) }
    }

    /// 分类分组（保持分类声明序与目录原序）
    public static func grouped(
        _ entries: [ConnectorCatalogEntry]
    ) -> [ConnectorCategoryGroup] {
        ConnectorCategory.allCases.compactMap { category in
            let items = entries.filter { $0.category == category }
            return items.isEmpty
                ? nil
                : ConnectorCategoryGroup(category: category, entries: items)
        }
    }
}

/// 分类分组（视图 ForEach 与单测共用形态）
public struct ConnectorCategoryGroup: Identifiable, Equatable, Sendable {
    public let category: ConnectorCategory
    public let entries: [ConnectorCatalogEntry]

    public var id: String { category.rawValue }

    public init(category: ConnectorCategory, entries: [ConnectorCatalogEntry]) {
        self.category = category
        self.entries = entries
    }
}
