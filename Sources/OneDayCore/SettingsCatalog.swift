import Foundation

/// 设置目录（设置页重塑，DESIGN §164）：设置首页分组
/// 与顶部搜索共用同一份条目清单——浏览态按组排、搜
/// 索态按本清单过滤，「搜得到的＝平时点得到的」只有
/// 一份真源，对账表（§164.2）逐项以本清单 id 为锚。
/// 条目只记标题／搜索副行／关键词／目的地；图标与呈
/// 现留 App 层。标题与副行是中文源串（App 侧经
/// SwiftUI 本地化键取词，三语词条与源串同字面）。

/// 设置分组（IA 顺序即声明序）：身份卡不在任何组内
/// （.top，浏览态以卡片形态居首、搜索态可命中）
/// prototype-2（DESIGN §164 升级）：连接组改服务与工作区
/// serverAndWorkspace、app 组改偏好与权限 preferences、
/// workspace 旧组退役（改为二级枢纽页）
public enum SettingsGroupID: String, CaseIterable, Sendable {
    case top
    case agent
    case serverAndWorkspace  // 原 connection 改组（服务与工作区）
    case preferences         // 原 app 改组（偏好与权限）
    case support
}

/// 条目目的地：与 App 层 SettingsRoute／管理 sheet
/// 一一对应（映射在 SettingsView.activate），Core 只
/// 记语义、不依赖 App 层类型
/// prototype-2（DESIGN §164 升级）：新增四个二级枢纽页
/// （agentConfig/serverManagement/sessionManagement/
/// workspaceHub）、主线会话（mainSession）、重启网关页
/// （restartGateway）
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
    /// 审批规则（§244 归位，大厂九项⑦）：规则是长期
    /// 设置、归设置页权限区；台账只留审批记录
    case approvalRules
    case gateway
    case logs
    case overview
    case computer
    case serverFiles
    case appearance
    /// 侧边栏分区管理面（§198，抽屉包题二新建）
    case sidebar
    /// 全部对话页（管理收口包补件，用户 2026-11-13
    /// 18:57 拍板）：入口自抽屉迁入设置页——它不是
    /// 设置栈内页，点按走 ContentView 根级全屏呈现
    /// （与原抽屉入口同一呈现路），故 route 映射为
    /// nil、由 SettingsView 动作行分流
    case allConversations
    case help
    case about
    case privacy
    case terms
    // prototype-2 新增
    case agentConfig        // 智能体配置枢纽页
    case serverManagement   // 服务器管理枢纽页
    case sessionManagement  // 会话管理枢纽页
    case workspaceHub       // 工作区枢纽页
    case mainSession        // 主线会话详情页
    case restartGateway     // 重启网关页
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
        // 智能体（prototype-2：只剩 models/agentConfig/cron，profiles/memory/skills 移入 agentConfig 枢纽页）
        SettingsCatalogEntry(
            id: "models", group: .agent,
            title: "模型与服务商",
            summary: "默认模型、服务商与辅助模型",
            keywords: ["默认模型", "服务商", "辅助模型", "model", "models"],
            destination: .models
        ),
        SettingsCatalogEntry(
            id: "agentConfig", group: .agent,
            title: "智能体配置",
            summary: "配置档案、记忆与技能",
            keywords: ["配置", "档案", "记忆", "技能", "agent config"],
            destination: .agentConfig
        ),
        SettingsCatalogEntry(
            id: "cron", group: .agent,
            title: "定时任务",
            summary: "按计划自动执行的任务",
            keywords: ["计划", "定时", "自动", "cron"],
            destination: .cron
        ),
        // 智能体配置页内子项（不在根页显示）
        SettingsCatalogEntry(
            id: "profiles", group: .agent,
            title: "配置档案",
            summary: "决定人设与系统提示，保存在服务器",
            keywords: ["档案", "人设", "系统提示", "profile", "soul"],
            destination: .profiles, showsInBrowse: false
        ),
        SettingsCatalogEntry(
            id: "memory", group: .agent,
            title: "记忆",
            summary: "长期偏好与记忆条目",
            keywords: ["长期记忆", "用户档案", "偏好", "memory"],
            destination: .memory, showsInBrowse: false
        ),
        SettingsCatalogEntry(
            id: "skills", group: .agent,
            title: "技能",
            summary: "智能体可用的能力，可启停",
            keywords: ["技能商店", "能力", "skill", "skills"],
            destination: .skills, showsInBrowse: false
        ),
        // 服务与工作区（prototype-2 新组）
        SettingsCatalogEntry(
            id: "serverManagement", group: .serverAndWorkspace,
            title: "服务器管理",
            summary: "连接、诊断与维护",
            keywords: ["服务器", "连接", "诊断", "维护", "server", "断开连接"],
            destination: .serverManagement
        ),
        SettingsCatalogEntry(
            id: "sessionManagement", group: .serverAndWorkspace,
            title: "会话管理",
            summary: "主线对话与服务端历史",
            keywords: ["会话", "对话", "历史", "session"],
            destination: .sessionManagement
        ),
        SettingsCatalogEntry(
            id: "workspace", group: .serverAndWorkspace,
            title: "工作区",
            summary: "总览、电脑与资源库",
            keywords: ["工作区", "总览", "电脑", "文件", "资源库", "workspace"],
            destination: .workspaceHub
        ),
        // 服务器管理页内子项（不在根页显示）
        SettingsCatalogEntry(
            id: "server", group: .serverAndWorkspace,
            title: "当前服务器",
            summary: "地址、密钥与连接状态",
            keywords: ["服务器地址", "密钥", "连接", "server"],
            destination: .serverDetail, showsInBrowse: false
        ),
        SettingsCatalogEntry(
            id: "gateway", group: .serverAndWorkspace,
            title: "网关状态",
            summary: "网关运行状态与重启",
            keywords: ["网关", "重启", "gateway"],
            destination: .gateway, showsInBrowse: false
        ),
        SettingsCatalogEntry(
            id: "logs", group: .serverAndWorkspace,
            title: "日志",
            summary: "服务端运行日志",
            keywords: ["运行日志", "log", "logs"],
            destination: .logs, showsInBrowse: false
        ),
        SettingsCatalogEntry(
            id: "usage", group: .serverAndWorkspace,
            title: "用量",
            summary: "模型用量统计",
            keywords: ["统计", "消耗", "token", "usage"],
            destination: .usage, showsInBrowse: false
        ),
        SettingsCatalogEntry(
            id: "envVars", group: .serverAndWorkspace,
            title: "密钥",
            summary: "保存在服务器上的密钥",
            keywords: ["环境变量", "key", "env"],
            destination: .envVars, showsInBrowse: false
        ),
        SettingsCatalogEntry(
            id: "restartGateway", group: .serverAndWorkspace,
            title: "重启网关",
            summary: "服务器管理 · 维护",
            keywords: ["重启", "维护", "restart gateway"],
            destination: .restartGateway, showsInBrowse: false
        ),
        // 会话管理页内子项（不在根页显示）
        SettingsCatalogEntry(
            id: "mainSession", group: .serverAndWorkspace,
            title: "主线会话",
            summary: "主要对话、会话 ID",
            keywords: ["主线", "当前会话", "main session"],
            destination: .mainSession, showsInBrowse: false
        ),
        SettingsCatalogEntry(
            id: "serverSessions", group: .serverAndWorkspace,
            title: "服务端会话",
            summary: "在网页端等其他入口产生的会话",
            keywords: ["会话", "网页端", "session", "sessions"],
            destination: .serverSessions, showsInBrowse: false
        ),
        // 工作区枢纽页内子项（不在根页显示）
        SettingsCatalogEntry(
            id: "overview", group: .serverAndWorkspace,
            title: "总览",
            summary: "状态与最近活动",
            keywords: ["状态", "活动", "overview"],
            destination: .overview, showsInBrowse: false
        ),
        SettingsCatalogEntry(
            id: "computer", group: .serverAndWorkspace,
            title: "电脑",
            summary: "智能体使用的电脑",
            keywords: ["云电脑", "桌面", "computer"],
            destination: .computer, showsInBrowse: false
        ),
        SettingsCatalogEntry(
            id: "serverFiles", group: .serverAndWorkspace,
            title: "服务器文件",
            summary: "服务器上的文件",
            keywords: ["文件", "files"],
            destination: .serverFiles, showsInBrowse: false
        ),
        // 偏好与权限（prototype-2 新组）
        SettingsCatalogEntry(
            id: "appearance", group: .preferences,
            title: "外观",
            summary: "聊天配色、形象大小、模式与语言",
            keywords: ["主题", "配色", "形象大小", "语言", "深色", "浅色", "theme", "language"],
            destination: .appearance
        ),
        SettingsCatalogEntry(
            id: "sidebar", group: .preferences,
            title: "侧边栏",
            summary: "抽屉各分区的显示与隐藏",
            keywords: ["抽屉", "分区", "显示", "隐藏", "sidebar", "drawer"],
            destination: .sidebar
        ),
        // 管理收口包补件（用户 2026-11-13 18:57 拍
        // 板）：全部对话入口自抽屉迁入本组、紧邻侧边
        // 栏行（同属对话/抽屉管理家族）；行名用页面
        // 自身标题「全部对话」，不带「管理」二字
        SettingsCatalogEntry(
            id: "allConversations", group: .preferences,
            title: "全部对话",
            summary: "全量会话名单、搜索、批量与清理",
            keywords: ["全部对话", "会话", "批量", "清理", "归档", "all conversations", "sessions"],
            destination: .allConversations
        ),
        SettingsCatalogEntry(
            id: "connectors", group: .preferences,
            title: "连接器",
            summary: "外部服务与设备能力",
            keywords: ["外部服务", "设备", "mcp", "connector"],
            destination: .connectors
        ),
        SettingsCatalogEntry(
            id: "devicePermissions", group: .preferences,
            title: "设备与权限",
            summary: "本机数据授权与同步",
            keywords: ["权限", "授权", "同步", "设备", "隐私"],
            destination: .devicePermissions
        ),
        SettingsCatalogEntry(
            id: "approvalRules", group: .preferences,
            title: "审批规则",
            summary: "「总是允许」的规则与撤销",
            keywords: ["审批", "规则", "总是允许", "撤销", "approval", "rules"],
            destination: .approvalRules
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
    /// 关键词做包含匹配；标题命中排在副行／关键词命中
    /// 之前（按标题搜先达标题页，如搜「记忆」先达记忆
    /// 页、枢纽页「智能体配置」以副行含「记忆」随后），
    /// 同层内按清单序（清单序即 IA 序）；空查询返回
    /// 全部条目
    public static func search(_ query: String) -> [SettingsCatalogEntry] {
        let needle = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !needle.isEmpty else { return entries }
        let titleHits = entries.filter {
            $0.title.lowercased().contains(needle)
        }
        let otherHits = entries.filter { entry in
            !entry.title.lowercased().contains(needle)
                && (entry.summary.lowercased().contains(needle)
                    || entry.keywords.contains {
                        $0.lowercased().contains(needle)
                    })
        }
        return titleHits + otherHits
    }
}
