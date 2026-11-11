import Foundation

/// 设置目录（设置页重塑，DESIGN §160）：设置首页分组
/// 与顶部搜索共用同一份条目清单——浏览态按组排、搜
/// 索态按本清单过滤，「搜得到的＝平时点得到的」只有
/// 一份真源，对账表（§160.2）逐项以本清单 id 为锚。
/// 条目只记标题／搜索副行／关键词／目的地；图标与呈
/// 现留 App 层。标题与副行是中文源串（App 侧经
/// SwiftUI 本地化键取词，三语词条与源串同字面）。

/// 设置分组（IA 顺序即声明序）：身份卡不在任何组内
/// （.top，浏览态以卡片形态居首、搜索态可命中）
public enum SettingsGroupID: String, CaseIterable, Sendable {
    case top
    case agent
    case connection
    case workspace
    case app
    case support
}

/// 条目目的地：与 App 层 SettingsRoute／管理 sheet
/// 一一对应（映射在 SettingsView.activate），Core 只
/// 记语义、不依赖 App 层类型
public enum SettingsDestination: Equatable, Sendable {
    case identity
    case profiles
    case memory
    case skills
    case cron
    case serverSessions
    case models
    case envVars
    case usage
    case serverDetail
    case connectors
    case devicePermissions
    case gateway
    case logs
    case overview
    case computer
    case serverFiles
    case appearance
    case help
    case about
    case privacy
    case terms
}

public struct SettingsCatalogEntry: Equatable, Sendable, Identifiable {
    /// 稳定 id（对账表与测试锚点，改名不改 id）
    public let id: String
    public let group: SettingsGroupID
    /// 行题（中文源串）
    public let title: String
    /// 搜索副行兼关键词主串（中文源串）
    public let summary: String
    /// 补充关键词（中英混排，搜索命中面）
    public let keywords: [String]
    public let destination: SettingsDestination
    /// 浏览态是否以行形态出现在所属组内：身份（卡片
    /// 形态单列）与隐私/协议（关于页内二级）为 false，
    /// 只进搜索索引
    public let showsInBrowse: Bool

    public init(
        id: String,
        group: SettingsGroupID,
        title: String,
        summary: String,
        keywords: [String],
        destination: SettingsDestination,
        showsInBrowse: Bool = true
    ) {
        self.id = id
        self.group = group
        self.title = title
        self.summary = summary
        self.keywords = keywords
        self.destination = destination
        self.showsInBrowse = showsInBrowse
    }
}

public enum SettingsCatalog {
    public static let entries: [SettingsCatalogEntry] = [
        // 身份（卡片单列，只进搜索）
        SettingsCatalogEntry(
            id: "identity", group: .top,
            title: "形象与名称",
            summary: "头像、显示名",
            keywords: ["头像", "名称", "显示名", "avatar", "name"],
            destination: .identity, showsInBrowse: false
        ),
        // 智能体
        SettingsCatalogEntry(
            id: "profiles", group: .agent,
            title: "配置档案",
            summary: "决定人设与系统提示，保存在服务器",
            keywords: ["档案", "人设", "系统提示", "profile", "soul"],
            destination: .profiles
        ),
        SettingsCatalogEntry(
            id: "memory", group: .agent,
            title: "记忆",
            summary: "长期偏好与记忆条目",
            keywords: ["长期记忆", "用户档案", "偏好", "memory"],
            destination: .memory
        ),
        SettingsCatalogEntry(
            id: "skills", group: .agent,
            title: "技能",
            summary: "智能体可用的能力，可启停",
            keywords: ["技能商店", "能力", "skill", "skills"],
            destination: .skills
        ),
        SettingsCatalogEntry(
            id: "models", group: .agent,
            title: "模型与服务商",
            summary: "默认模型、服务商与辅助模型",
            keywords: ["默认模型", "服务商", "辅助模型", "model", "models"],
            destination: .models
        ),
        SettingsCatalogEntry(
            id: "cron", group: .agent,
            title: "定时任务",
            summary: "按计划自动执行的任务",
            keywords: ["计划", "定时", "自动", "cron"],
            destination: .cron
        ),
        SettingsCatalogEntry(
            id: "serverSessions", group: .agent,
            title: "服务端会话",
            summary: "在网页端等其他入口产生的会话",
            keywords: ["会话", "网页端", "session", "sessions"],
            destination: .serverSessions
        ),
        // 连接
        SettingsCatalogEntry(
            id: "server", group: .connection,
            title: "当前服务器",
            summary: "地址、密钥与连接状态",
            keywords: ["服务器地址", "密钥", "连接", "server"],
            destination: .serverDetail
        ),
        SettingsCatalogEntry(
            id: "connectors", group: .connection,
            title: "连接器",
            summary: "外部服务与设备能力",
            keywords: ["外部服务", "设备", "mcp", "connector"],
            destination: .connectors
        ),
        SettingsCatalogEntry(
            id: "devicePermissions", group: .connection,
            title: "设备与权限",
            summary: "本机数据授权与同步",
            keywords: ["权限", "授权", "同步", "设备", "隐私"],
            destination: .devicePermissions
        ),
        SettingsCatalogEntry(
            id: "gateway", group: .connection,
            title: "网关状态",
            summary: "网关运行状态与重启",
            keywords: ["网关", "重启", "gateway"],
            destination: .gateway
        ),
        SettingsCatalogEntry(
            id: "logs", group: .connection,
            title: "日志",
            summary: "服务端运行日志",
            keywords: ["运行日志", "log", "logs"],
            destination: .logs
        ),
        SettingsCatalogEntry(
            id: "envVars", group: .connection,
            title: "密钥",
            summary: "保存在服务器上的密钥",
            keywords: ["环境变量", "key", "env"],
            destination: .envVars
        ),
        SettingsCatalogEntry(
            id: "usage", group: .connection,
            title: "用量",
            summary: "模型用量统计",
            keywords: ["统计", "消耗", "token", "usage"],
            destination: .usage
        ),
        // 工作区（原「管理」组三件整面工作区）
        SettingsCatalogEntry(
            id: "overview", group: .workspace,
            title: "总览",
            summary: "状态与最近活动",
            keywords: ["状态", "活动", "overview"],
            destination: .overview
        ),
        SettingsCatalogEntry(
            id: "computer", group: .workspace,
            title: "电脑",
            summary: "智能体使用的电脑",
            keywords: ["云电脑", "桌面", "computer"],
            destination: .computer
        ),
        SettingsCatalogEntry(
            id: "serverFiles", group: .workspace,
            title: "服务器文件",
            summary: "服务器上的文件",
            keywords: ["文件", "files"],
            destination: .serverFiles
        ),
        // 应用
        SettingsCatalogEntry(
            id: "appearance", group: .app,
            title: "外观",
            summary: "聊天配色、形象大小、模式与语言",
            keywords: ["主题", "配色", "形象大小", "语言", "深色", "浅色", "theme", "language"],
            destination: .appearance
        ),
        // 支持
        SettingsCatalogEntry(
            id: "help", group: .support,
            title: "帮助与反馈",
            summary: "连接帮助与问题反馈",
            keywords: ["反馈", "问题", "帮助", "help"],
            destination: .help
        ),
        SettingsCatalogEntry(
            id: "about", group: .support,
            title: "关于 OneDay",
            summary: "版本、隐私与开源",
            keywords: ["版本", "隐私", "协议", "开源", "about"],
            destination: .about
        ),
        SettingsCatalogEntry(
            id: "privacy", group: .support,
            title: "隐私政策",
            summary: "我们如何处理你的数据",
            keywords: ["隐私", "政策", "privacy"],
            destination: .privacy, showsInBrowse: false
        ),
        SettingsCatalogEntry(
            id: "terms", group: .support,
            title: "用户协议",
            summary: "使用 OneDay 的条款",
            keywords: ["协议", "条款", "terms"],
            destination: .terms, showsInBrowse: false
        ),
    ]

    /// 某组在浏览态出现的行（清单序）
    public static func browseEntries(
        in group: SettingsGroupID
    ) -> [SettingsCatalogEntry] {
        entries.filter { $0.group == group && $0.showsInBrowse }
    }

    /// 搜索：查询去空白并折叠大小写后，对标题／副行／
    /// 关键词做包含匹配，命中按清单序返回（清单序即
    /// IA 序，不另排序）；空查询返回全部条目
    public static func search(_ query: String) -> [SettingsCatalogEntry] {
        let needle = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !needle.isEmpty else { return entries }
        return entries.filter { entry in
            entry.title.lowercased().contains(needle)
                || entry.summary.lowercased().contains(needle)
                || entry.keywords.contains {
                    $0.lowercased().contains(needle)
                }
        }
    }
}
