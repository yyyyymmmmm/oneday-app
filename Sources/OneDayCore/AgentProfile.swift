import Foundation

/// 智能体本地档案（0.36.22，枢纽页对齐包，用户点名学
/// Muse 智能体页的头像编辑）：用户在本机给智能体
/// 改的显示名与头像——纯本地呈现层数据，不回写服务
/// 端身份（soul/档案仍是服务端真源，本档案只决定
/// 「在这台手机上怎么称呼、用什么头像显示它」）。
///
/// 口径：
/// - 显示名是**带时刻的候选值**：覆盖与 soul 解析名
///   各带写入时刻，呈现取较晚写下的一方（末写胜，
///   2026-11-13 用户拍板，§203「按修改者分权重」口
///   径作废；裁决在 AgentNameLWW）；没设覆盖（nil）
///   就跟随既有解析链（AppState.identityName →
///   AgentName.fallback），不把服务端名抄一份存本地。
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

/// AI 档头像（P1 身份包）：智能体经伴生头像仓给自己选的
/// 头像，在本机只是一份投影——仓是真源、本机存上次同步
/// 值。预置引用按目录 id；图片记仓内条目 id（字节本体在
/// App 层 avatar-ai.jpg，与用户自定义图分文件不相扰）。
/// 每档同带 updatedAt：仓当前指针最后一次被设定的时刻
/// （服务器收到写入的时刻），是末写胜裁决的唯一凭据。
public enum AgentAIAvatar: Equatable, Sendable {
    case preset(id: String, updatedAt: Date)
    case image(itemID: String, updatedAt: Date)

    /// 本档写入时刻（服务器侧收到写入的时刻）
    public var updatedAt: Date {
        switch self {
        case .preset(_, let at), .image(_, let at): return at
        }
    }
}

/// 头像呈现裁决（末写胜，2026-11-13 用户拍板，覆盖
/// §203「用户手动选过则锁压 AI」旧口径）：AI 档与用
/// 户选择各带写入时刻，**后写者胜**，不问写者是用户
/// 还是 AI；来源只作留痕、不参与裁决。细则：
/// - AI 档为空（仓未同步、仓里没设当前头像）→ 用户
///   选择胜（仓不可达同理：AI 档保持上次同步值，呈
///   现不因断网变化、更不空白）。
/// - 用户从未留下带时刻的选择（userSelectedAt 为
///   nil，即从未碰过编辑器、档案是缺省值）→ AI 档
///   胜：缺省值没有「写入」可言，不许挡住真写入。
/// - 两边时刻同刻 → 服务器（AI 档）胜：服务器是多
///   端共享真源，同刻取它保各端一致。
/// 裁决只管选择值；.custom 胜出时图本体是用户图还是
/// AI 图由 aiImageWins 分。
public enum AgentAvatarChoice {
    /// AI 档是否胜出（末写胜总闸，resolve/aiImageWins
    /// 同源，不许两处各判一套）
    public static func aiWins(
        ai: AgentAIAvatar?, userSelectedAt: Date?
    ) -> Bool {
        guard let ai else { return false }
        guard let userSelectedAt else { return true }
        return ai.updatedAt >= userSelectedAt
    }

    public static func resolve(
        ai: AgentAIAvatar?,
        user: AgentAvatarSelection,
        userSelectedAt: Date?
    ) -> AgentAvatarSelection {
        guard aiWins(ai: ai, userSelectedAt: userSelectedAt),
              let ai
        else { return user }
        switch ai {
        case .preset(let id, _):
            return .preset(id: AgentAvatarPreset.resolve(id: id).id)
        case .image:
            return .custom
        }
    }

    /// AI 图是否胜出：AI 档是图片且末写胜总闸判 AI
    /// 胜时，呈现的「自定义图」本体取 AI 图文件而非
    /// 用户图文件
    public static func aiImageWins(
        ai: AgentAIAvatar?, userSelectedAt: Date?
    ) -> Bool {
        guard let ai, case .image = ai else { return false }
        return aiWins(ai: ai, userSelectedAt: userSelectedAt)
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

/// 改名覆盖的来源记录（身份反映修复，2026-11-13）：
/// 覆盖写入时同记「写入时刻」与「写入时服务器身份
/// 名」。没有这份记录，覆盖只是一串裸文本——分不清
/// 是用户深思熟虑的定名，还是随手打的测试字，更无
/// 从判断它与服务器改名谁先谁后（2026-11-13 真机事
/// 故：本机残留「测试」静默压住用户当面令 AI 改的
/// 「三狗」，各面无任何披露）。
public struct AgentNameOverrideProvenance: Codable, Equatable, Sendable {
    /// 覆盖写入时刻
    public var writtenAt: Date
    /// 写入那一刻 App 已知的服务器身份名（soul 解
    /// 析结果）；从未解析成功过时为 nil——无从对账，
    /// 按无来源处理
    public var soulNameAtWrite: String?

    public init(writtenAt: Date, soulNameAtWrite: String?) {
        self.writtenAt = writtenAt
        self.soulNameAtWrite = soulNameAtWrite
    }
}

/// 覆盖存续裁决（末写胜，2026-11-13 用户拍板，覆
/// 盖身份反映修复的旧裁决）：本机覆盖与服务器名各带
/// 写入时刻，后写者胜，不按写者身份分权重——
/// - 覆盖为空，或与服务器现行名相同：无冲突，不清。
/// - 两边时刻都已知（覆盖看来源记录的 writtenAt，
///   服务器看桥报的 updatedAt＝服务器收到写入的时
///   刻）：纯比时间——覆盖更晚则留，服务器更晚或同
///   刻则清（同刻取服务器，多端同源）。
/// - 覆盖没有来源记录（存量裸文本）：没有任何时刻
///   可凭，不得压住服务器现行名 → 清除、跟随服务
///   器（用户随时可在编辑器里对现行名重设，届时有
///   时刻、进末写胜）。
/// - 服务器时刻未知（桥不可达/旧桥无时间账）：退回
///   来源对账近似——写入时所对的服务器名 ≠ 现行名
///   即证明写入之后服务器写过 → 清；来源里服务器名
///   缺失同清。此路只是时刻缺失时的近似，时刻齐备
///   时不许走。
public enum AgentNameLWW {
    public static func shouldClearOverride(
        override: String?,
        provenance: AgentNameOverrideProvenance?,
        soulName: String,
        soulUpdatedAt: Date?
    ) -> Bool {
        guard let override, !override.isEmpty else { return false }
        if override == soulName { return false }
        if let soulUpdatedAt, let provenance {
            return provenance.writtenAt <= soulUpdatedAt
        }
        guard let provenance,
              let atWrite = provenance.soulNameAtWrite
        else { return true }
        return atWrite != soulName
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
