import Foundation

/// 身份缓存（§245 身份包，复杂化审计 C-2 收敛）：名字
/// 与头像的真值自此只有一份——服务端（名字＝SOUL、
/// 头像＝伴生头像仓）。App 不再存「本机覆盖」语义，
/// 只存带时间戳的缓存副本：呈现读副本、刷新整份替
/// 换副本；用户在 App 里改名/换头像＝写穿到服务端
/// 后以服务端回读刷新副本。末写胜（2026-11-13 用
/// 户拍板）由服务端天然承接：谁的写入后到服务端
/// 谁生效，不再需要 App 侧双账裁决。
public struct IdentityNameCache: Codable, Equatable, Sendable {
    /// 缓存的名字（服务端现行身份名在本机的副本）
    public var name: String
    /// 服务端侧该值的写入时刻：取自 Dashboard soul
    /// 回执的 updatedAt（文件 mtime 近似，A2 直连的
    /// 既定代价，见 api-direct-inventory）；回执没给
    /// 时为 nil——只影响新鲜度注记、不参与任何裁决
    public var serverUpdatedAt: Date?
    /// 本机落缓存的时刻（新鲜度注记）
    public var cachedAt: Date

    public init(name: String, serverUpdatedAt: Date?, cachedAt: Date) {
        self.name = name
        self.serverUpdatedAt = serverUpdatedAt
        self.cachedAt = cachedAt
    }
}

/// 头像缓存里的当前选择：预置引用或仓内图片条目
public enum IdentityAvatarSelection: Codable, Equatable, Sendable {
    case preset(id: String)
    case image(itemID: String)
}

/// 头像缓存（§245）：头像仓当前指针在本机的副本。
/// itemID 为 nil 只出现在一种情形——升级迁移时用
/// 户旧选择胜出但还没写穿到仓里（待推），推完即以
/// 服务端回读整份替换、itemID 落真值。
public struct IdentityAvatarCache: Codable, Equatable, Sendable {
    public var selection: IdentityAvatarSelection
    /// 仓内条目 id；本地待推时为 nil
    public var itemID: String?
    /// 仓指针最后一次被设定的时刻（服务器收到写入
    /// 的时刻）；本地待推时为 nil
    public var serverUpdatedAt: Date?
    /// 本机落缓存的时刻
    public var cachedAt: Date

    public init(
        selection: IdentityAvatarSelection, itemID: String?,
        serverUpdatedAt: Date?, cachedAt: Date
    ) {
        self.selection = selection
        self.itemID = itemID
        self.serverUpdatedAt = serverUpdatedAt
        self.cachedAt = cachedAt
    }
}

/// 改名入参校验（§245）：与服务端改名窄口的校验同
/// 口径（桥 _validate_new_name 镜像）——净化（折叠空
/// 白/去首尾）后须非空、≤20 字、无句读标点、非结构
/// 词、不含 `#` 与控制字符。不合回 nil，调用方给人
/// 话提示；最终裁决仍在服务端（校验只是先行同口径
/// 拦截，不许两边口径漂移后 App 放行、服务端拒收又
/// 无话可说——服务端 400 文案经安全门兜底上屏）。
public enum AgentNameEdit {
    /// 结构词黑名单（与 AgentName.resolve 同表：这些
    /// 词是文档标题、不是身份名）
    private static let structuralNames: Set<String> = [
        "soul", "soul.md", "灵魂", "人设", "身份",
        "identity", "persona", "about", "profile",
    ]

    private static let sentencePunctuation = "。．.：:、，,；;！!？?"

    public static func sanitizedRename(_ raw: String) -> String? {
        let collapsed = raw
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !collapsed.isEmpty, collapsed.count <= 20 else {
            return nil
        }
        guard !collapsed.contains(where: {
            sentencePunctuation.contains($0)
        }),
              !structuralNames.contains(collapsed.lowercased()),
              !collapsed.contains("#"),
              !collapsed.unicodeScalars.contains(where: {
                  CharacterSet.controlCharacters.contains($0)
              })
        else { return nil }
        return collapsed
    }
}

/// 旧覆盖的来源记录形状（退役前 AgentNameOverride-
/// Provenance 的落盘 JSON 镜像）：迁移要读存量数据，
/// 字段名/类型必须与旧版写下的逐字一致，故在本文件
/// 内自带一份，只服务迁移、不再产生新记录。
public struct LegacyNameOverrideProvenance: Codable, Equatable, Sendable {
    public var writtenAt: Date
    public var soulNameAtWrite: String?

    public init(writtenAt: Date, soulNameAtWrite: String?) {
        self.writtenAt = writtenAt
        self.soulNameAtWrite = soulNameAtWrite
    }
}

/// 升级迁移裁决（§245，一次性）：旧账（本机改名覆盖
/// ＋来源记录、头像用户槽/AI 槽双槽）在退役前最后一
/// 判——按退役前仍有效的末写胜规则算出「升级瞬间用
/// 户实际看到的名字/头像」，以此播种新缓存，保证升
/// 级不改观感。胜出的若是本机侧值（覆盖/用户槽），
/// 它还不是服务端真值：needsPush 置真，App 在首次
/// 连通刷新时把它写穿到服务端，此后全仓只剩服务端
/// 一份真值。本裁决只在迁移时跑一次，不构成常驻裁
/// 决机制（那正是 C-2 要退役的东西）；旧裁决的语义
/// 在此自包含实现，不再依赖已退役的 AgentNameLWW/
/// AgentAvatarChoice。
public enum IdentityLegacyMigration {
    /// 名字迁移结果
    public struct NameOutcome: Equatable, Sendable {
        /// 播种缓存的名字（无任何可用名时为 nil）
        public var name: String?
        /// 胜出的是本机覆盖且与服务端现行名不同：
        /// 须写穿服务端
        public var needsPush: Bool

        public init(name: String?, needsPush: Bool) {
            self.name = name
            self.needsPush = needsPush
        }
    }

    /// 旧名字裁决（末写胜，退役前口径原样）：覆盖与
    /// 服务器名各带写入时刻，后写者胜、同刻取服务
    /// 器；裸覆盖（无来源记录）不得压住服务器现行
    /// 名；服务器时刻未知时退回来源对账近似（写入时
    /// 所对的服务器名 ≠ 现行名即清）。
    static func legacyOverrideCleared(
        override: String?,
        provenance: LegacyNameOverrideProvenance?,
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

    public static func effectiveName(
        override: String?,
        provenance: LegacyNameOverrideProvenance?,
        soulName: String?,
        soulUpdatedAt: Date?
    ) -> NameOutcome {
        guard let soulName, !soulName.isEmpty else {
            // 从未解析到服务端名：覆盖是唯一可用值，
            // 先作缓存、待推写穿
            if let override, !override.isEmpty {
                return NameOutcome(name: override, needsPush: true)
            }
            return NameOutcome(name: nil, needsPush: false)
        }
        let cleared = legacyOverrideCleared(
            override: override, provenance: provenance,
            soulName: soulName, soulUpdatedAt: soulUpdatedAt
        )
        if let override, !override.isEmpty, !cleared {
            return NameOutcome(
                name: override, needsPush: override != soulName
            )
        }
        return NameOutcome(name: soulName, needsPush: false)
    }

    /// 头像迁移结果：胜出方的选择值＋是否本机侧胜出
    /// （须写穿头像仓）
    public struct AvatarOutcome: Equatable, Sendable {
        public var selection: AgentAvatarSelection?
        /// 胜出的 AI 档条目 id（服务端胜出时有值）
        public var aiItemID: String?
        /// AI 档写入时刻（服务端胜出时作缓存时刻凭据）
        public var aiUpdatedAt: Date?
        public var userWon: Bool

        public init(
            selection: AgentAvatarSelection?, aiItemID: String?,
            aiUpdatedAt: Date?, userWon: Bool
        ) {
            self.selection = selection
            self.aiItemID = aiItemID
            self.aiUpdatedAt = aiUpdatedAt
            self.userWon = userWon
        }
    }

    /// 旧头像裁决（末写胜，退役前口径原样）：AI 档为
    /// 空→用户胜；用户从未留下带时刻的选择→AI 胜；
    /// 同刻取服务器（AI 档）。AI 档时刻缺失按最早处
    /// 理（旧槽位 init 的 distantPast 口径）。用户从
    /// 未选过且 AI 档为空→无胜出（selection 为 nil，
    /// 呈现回落缺省、不播种缓存、不待推）。
    public static func effectiveAvatar(
        aiPresetID: String?,
        aiItemID: String?,
        aiUpdatedAt: Date?,
        user: AgentAvatarSelection,
        userSelectedAt: Date?,
        userEverSelected: Bool
    ) -> AvatarOutcome {
        let aiWins: Bool
        if aiItemID == nil {
            aiWins = false
        } else if let userSelectedAt {
            aiWins = (aiUpdatedAt ?? .distantPast) >= userSelectedAt
        } else {
            aiWins = true
        }
        if aiWins, let aiItemID {
            if let aiPresetID {
                return AvatarOutcome(
                    selection: .preset(
                        id: AgentAvatarPreset.resolve(id: aiPresetID).id
                    ),
                    aiItemID: aiItemID, aiUpdatedAt: aiUpdatedAt,
                    userWon: false
                )
            }
            return AvatarOutcome(
                selection: .custom,
                aiItemID: aiItemID, aiUpdatedAt: aiUpdatedAt,
                userWon: false
            )
        }
        guard userEverSelected else {
            return AvatarOutcome(
                selection: nil, aiItemID: nil, aiUpdatedAt: nil,
                userWon: false
            )
        }
        return AvatarOutcome(
            selection: user, aiItemID: nil, aiUpdatedAt: nil,
            userWon: true
        )
    }
}
