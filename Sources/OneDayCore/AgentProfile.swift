import Foundation

/// 智能体本地档案（0.36.22，枢纽页对齐包，用户点名学
/// Muse 智能体页的头像编辑）：用户在本机给智能体
/// 改的显示名与头像——纯本地呈现层数据，不回写服务
/// 端身份（soul/档案仍是服务端真源，本档案只决定
/// 「在这台手机上怎么称呼、用什么头像显示它」）。
///
/// 口径：
/// - 显示名是**覆盖值**：设了就赢过 soul 解析名，没
///   设（nil）就跟随既有解析链（AppState.identity-
///   Name → AgentName.fallback），不把服务端名抄一份
///   存本地（服务端改名后本地没设过覆盖的用户应自动
///   跟上）。
/// - 头像是**选择值**：预置形象（资产图/符号盘）或
///   相册自定义图（二值只记「自定义」标记，图数据本
///   体在 App 层文件，不进本模型）。
public struct AgentProfile: Equatable, Sendable {
    /// 显示名覆盖（nil＝跟随自动解析链）
    public var displayNameOverride: String?
    /// 头像选择
    public var avatar: AgentAvatarSelection

    public init(
        displayNameOverride: String? = nil,
        avatar: AgentAvatarSelection = .default
    ) {
        self.displayNameOverride = displayNameOverride
        self.avatar = avatar
    }

    public static let `default` = AgentProfile()
}

/// 头像选择：预置（按目录 id）或相册自定义图。
public enum AgentAvatarSelection: Equatable, Sendable {
    case preset(id: String)
    case custom

    /// 缺省＝搭档款预置（与 0.36.22 前全 App 唯一头像
    /// 资产同源，升级用户视觉零变化）
    public static let `default` = AgentAvatarSelection.preset(
        id: AgentAvatarPreset.defaultID
    )
}

/// 预置形象目录：资产图一款（自有 IP 三狗搭档款）＋
/// SF 符号盘三款（渲染成 pastel 色盘＋墨色 glyph，
/// 与活动行图标盒同语言）。符号盘的底色令牌在 App
/// 层按 id 映射（Core 不依赖设计层）。
public struct AgentAvatarPreset: Equatable, Sendable, Identifiable {
    public let id: String
    /// 选择器里给用户看的名
    public let displayName: String
    /// 资产图名（非 nil 时用资产图）
    public let assetName: String?
    /// SF 符号名（非 nil 时渲染符号盘）
    public let symbolName: String?

    public static let defaultID = "partner"

    public static let all: [AgentAvatarPreset] = [
        AgentAvatarPreset(
            id: "partner",
            displayName: "三狗搭档款",
            assetName: "SangouPartner",
            symbolName: nil
        ),
        AgentAvatarPreset(
            id: "paw",
            displayName: "爪印",
            assetName: nil,
            symbolName: "pawprint.fill"
        ),
        AgentAvatarPreset(
            id: "sparkles",
            displayName: "星光",
            assetName: nil,
            symbolName: "sparkles"
        ),
        AgentAvatarPreset(
            id: "atom",
            displayName: "原子",
            assetName: nil,
            symbolName: "atom"
        ),
    ]

    /// 按 id 查目录；查无此 id 回落缺省款（存量脏值不
    /// 让头像面空白）
    public static func resolve(id: String) -> AgentAvatarPreset {
        all.first(where: { $0.id == id })
            ?? all.first(where: { $0.id == defaultID })
            ?? all[0]
    }
}

/// 显示名解析：覆盖 → soul 解析名 → Hermes 回落。
/// 与 AgentName.resolve（soul 提取）分工：那边管「从
/// 服务端文档里读出名字」，这边管「多来源谁赢」。
public enum AgentDisplayName {
    public static func resolve(override: String?, soulName: String?) -> String {
        if let override, !override.isEmpty { return override }
        if let soulName, !soulName.isEmpty { return soulName }
        return AgentName.fallback
    }

    /// 编辑器输入净化：折叠全部空白为单空格、去首尾；
    /// 空串或超 20 字（与 AgentName 的名字长度口径同
    /// 值）回 nil（调用方据此判无效/恢复自动）
    public static func sanitizedOverride(_ raw: String) -> String? {
        let collapsed = raw
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !collapsed.isEmpty, collapsed.count <= 20 else {
            return nil
        }
        return collapsed
    }
}

/// 分享名片的服务器域名提取：只出 host——剥 scheme/
/// userinfo/端口/路径/查询，名片红线（不带任何凭据
/// 与完整连接串）的执行点。输入是本机存的服务器地
/// 址串（可无 scheme），解析不出回 nil（名片只出名
/// 不出域名，不猜）。
public enum AgentServerHost {
    public static func extract(from baseURLString: String?) -> String? {
        guard let raw = baseURLString?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !raw.isEmpty
        else { return nil }
        let withScheme = raw.contains("://") ? raw : "https://" + raw
        guard let host = URLComponents(string: withScheme)?.host,
              !host.isEmpty
        else { return nil }
        return host
    }
}

/// 分享名片文本：名称＋域名一行（头像在名片图里）。
/// 只吃名与 host 两入参——结构上不可能漏出密钥/令
/// 牌（它们根本进不了这个函数）。
public enum AgentShareCardText {
    public static func make(name: String, host: String?) -> String {
        if let host, !host.isEmpty {
            return "\(name) · \(host)"
        }
        return name
    }
}
