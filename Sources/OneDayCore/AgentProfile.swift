import Foundation

/// 智能体身份呈现基件（§245 身份包收敛后）：名字与
/// 头像的真值只有服务端一份（名字＝SOUL、头像＝伴
/// 生头像仓），App 只存带时间戳的缓存副本（值型在
/// IdentityCache.swift）。本文件只留呈现基件：头像
/// 选择值、预置目录、显示名解析（缓存→回落）。
///
/// 历史口径（已退役，勿复活）：0.36.22 的本机档案
/// （改名覆盖＋用户/AI 双槽头像）靠末写胜裁决
/// （AgentNameLWW/AgentAvatarChoice）维持多账一致，
/// 是复杂化审计 C-2 点名的多账病灶——裁决与覆盖语
/// 义已随 §245 全量退役，仅升级迁移裁决
/// （IdentityLegacyMigration）保留最后一判的逻辑。
public enum AgentDisplayName {
    /// 显示名解析：身份名缓存 → Hermes 回落。缓存是
    /// 服务端现行名的副本（刷新整份替换），呈现只读
    /// 这一处，不再有覆盖层短路解析链。
    public static func resolve(cachedName: String?) -> String {
        if let cachedName,
           !cachedName.trimmingCharacters(
               in: .whitespacesAndNewlines
           ).isEmpty {
            return cachedName
        }
        return AgentName.fallback
    }
}

/// 头像选择：预置（按目录 id）或相册自定义图。缓存
/// 副本与编辑器选择共用此值型（二值只记形态，图字
/// 节本体在 App 层文件/头像仓，不进本模型）。
public enum AgentAvatarSelection: Equatable, Sendable {
    case preset(id: String)
    case custom

    /// 缺省＝搭档款预置（与 0.36.22 前全 App 唯一头像
    /// 资产同源，升级用户视觉零变化）。仅作「服务端
    /// 从未设过当前头像」时的呈现回落，不是存量真值。
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
