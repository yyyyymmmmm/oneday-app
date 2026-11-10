import Foundation

/// 会话三层分类（0.36.29，规格＝channels-conversations-
/// design-20261110.md §2，用户 2026-11-10 20:02 拍板
/// 方案 A）：服务端会话按「出生证明」分入我的对话／
/// Hermes 频道／系统运行三层（主线与合并桶为名单外
/// 特例）。分类是每次拉取时现算的纯函数、不落库、不
/// 回写服务端——天然支持「收养」：频道会话被点开续
/// 聊即建本地线程关联，下一轮 R2 命中升入我的对话。
///
/// 验收问句（规格 §0）：指着任意一条要能答出「这是
/// 谁、从哪来、为什么在这」。判不准的默认归 Hermes
/// 频道（R9）——三层里只有频道是「来源可解释、点开
/// 可续聊收养」的诚实筐；放系统运行会把用户会话错
/// 藏进机器账，放我的对话则冒充用户亲手开的对话。
///
/// 判定只依赖列表回执已证字段（id/source/session_
/// key＋本地线程关联集）。§9 实测未回前不得依赖的
/// 字段一律不进判定主链：parent_session_id 不在
/// ServerSession 解码模型内，R5 的 parent 分支因此
/// 未启用（实测可得后才许加）；origin_json/user_id
/// 同理不入。

// MARK: - 来源常量表（单一真源）

/// 会话来源集合的唯一常量表：分类规则（R2 例外/
/// R5/R6）与抽屉行显过滤（DrawerSideChatFilter）共
/// 用同一份，防两面口径漂移（规格 §2 施工约束）。
/// DrawerSideChatFilter.userChannelSources 自本版起
/// 改为引用本表的 userChannels，本体值不变。
public enum SessionSources {
    /// 用户通道来源：App API 与控制台——经这些面来
    /// 的会话是「人开的」，关联线程可据此升层（R2）
    public static let userChannels: Set<String> = [
        "api_server", "api", "dashboard", "web",
    ]

    /// 结构性系统源（R5）：任务板与定时/调度本体
    public static let structuralSystem: Set<String> = [
        "kanban", "cron", "cron_job", "scheduler",
    ]

    /// Hermes 人工表面（R7）：网页控制台与命令行
    public static let hermesSurfaces: Set<String> = [
        "dashboard", "cli",
    ]

    /// 外部平台源（R6）：Hermes 网关的平台名全集
    /// （规格点名 whatsapp/telegram/feishu/wechat
    /// ＋网关其余平台）。命中即归对应外部频道——
    /// 一期无行无页、规则先行（规格 §7）
    public static let platforms: Set<String> = [
        "whatsapp", "telegram", "feishu", "wechat",
        "dingtalk", "wecom", "qq", "discord", "slack",
        "signal", "matrix", "sms",
    ]

    /// 平台源的人话名（频道注册表给平台频道命名用；
    /// 未列者回落原值——一期无平台行上屏，此表只作
    /// 注册表完备性）
    public static func platformDisplayName(_ source: String) -> String {
        switch source {
        case "whatsapp": return "WhatsApp"
        case "telegram": return "Telegram"
        case "feishu": return "飞书"
        case "wechat": return "微信"
        case "dingtalk": return "钉钉"
        case "wecom": return "企业微信"
        case "qq": return "QQ"
        case "discord": return "Discord"
        case "slack": return "Slack"
        case "signal": return "Signal"
        case "matrix": return "Matrix"
        case "sms": return "短信"
        default: return source
        }
    }

    /// 来源归一：去空白、转小写，空串归 nil（服务端
    /// source 原值大小写/空白不作数，判定前一律过此）
    public static func normalized(_ source: String?) -> String? {
        guard let raw = source else { return nil }
        let value = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return value.isEmpty ? nil : value
    }

    /// session_key 的平台段（形如 agent:main:<平台>:
    /// dm:<id>，第三段即平台名，state.db 留底实证）；
    /// 段数不足或为空返回 nil
    public static func sessionKeyPlatformSegment(
        _ sessionKey: String?
    ) -> String? {
        guard let key = sessionKey, !key.isEmpty else { return nil }
        let parts = key.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count >= 3 else { return nil }
        return normalized(String(parts[2]))
    }

    /// 有效来源：source 本体优先，缺失时以 session_
    /// key 平台段回落（R7/R8 的互证口径，规格 §2）；
    /// 两处皆无为 nil
    public static func effectiveSource(
        source: String?, sessionKey: String?
    ) -> String? {
        normalized(source) ?? sessionKeyPlatformSegment(sessionKey)
    }

    /// 是否用户通道来源（归一后的有效来源判定）
    public static func isUserChannel(_ effective: String?) -> Bool {
        guard let effective else { return false }
        return userChannels.contains(effective)
    }

    /// 是否非用户通道来源（R2 例外谓词）：来源非空
    /// 且不在用户通道集合——kanban/平台/cron 等机
    /// 器与外部来源皆在此列；来源未知（nil）不算，
    /// 不因服务端字段缺失压掉本地关联的升层
    public static func isNonUserChannel(_ effective: String?) -> Bool {
        guard let effective else { return false }
        return !userChannels.contains(effective)
    }
}

// MARK: - 频道注册表

/// 频道描述（值类型）：抽屉频道区、全部对话页频道
/// 段与频道页共用同一份注册表派生行，不许各面自拼
/// 频道名/图标（规格 §3.3）。
public struct ChannelDescriptor: Identifiable, Equatable, Sendable {
    public let id: String
    /// 频道名（行标题与频道页标题）
    public let name: String
    /// 频道页副题（一句话人话，说清这个频道装什么）
    public let pageSubtitle: String
    /// 图标资产名（Assets 内官方/定制图面，宪法 §4；
    /// 平台频道将来落地时各家官方原图入此字段）
    public let iconAssetName: String?

    public init(
        id: String, name: String, pageSubtitle: String,
        iconAssetName: String?
    ) {
        self.id = id
        self.name = name
        self.pageSubtitle = pageSubtitle
        self.iconAssetName = iconAssetName
    }
}

/// 频道注册表（规格 §3.3/§7）：一期仅 Hermes 一条；
/// 外部频道接入时按注册表加行（descriptor(for:)
/// 已能为平台源派生描述，行显与页面属二期）。
public enum ChannelRegistry {
    public static let hermesChannelID = "hermes"

    /// Hermes 频道：非 App 出生、来自这台 Hermes 其
    /// 他表面（网页/接口）的会话收纳处。图标复用
    /// 0.36.3 已登记的本机服务 Hermes 定制图面资产
    /// （LocalServices 同款 LocalHermes，台账 D 节）
    public static let hermes = ChannelDescriptor(
        id: hermesChannelID,
        name: "Hermes",
        pageSubtitle: "在这台 Hermes 的其他地方（网页、接口）发生的对话",
        iconAssetName: "LocalHermes"
    )

    /// 一期注册表（显行判定与频道段行源）
    public static let phaseOne: [ChannelDescriptor] = [hermes]

    /// 按频道 id 取描述：Hermes 恒有；平台频道按平
    /// 台名派生（一期只备不用）；其余 nil
    public static func descriptor(for channelID: String) -> ChannelDescriptor? {
        if channelID == hermesChannelID { return hermes }
        if SessionSources.platforms.contains(channelID) {
            return ChannelDescriptor(
                id: channelID,
                name: SessionSources.platformDisplayName(channelID),
                pageSubtitle: "",
                iconAssetName: nil
            )
        }
        return nil
    }
}

// MARK: - 分类判定（R0–R9）

/// 会话归属层（规格 §2）：main 与 mergeBucket 是
/// 名单呈现的特例位（主线单列钦定行、合并桶在频道
/// 内只读呈现），mine/system/channel 为三层本体
public enum SessionLayer: Equatable, Sendable {
    /// R0 主线：不进任何名单重复出现
    case main
    /// R1 合并桶：Hermes 频道内只读特例行（规格 §4.3）
    case mergeBucket
    /// R2/R3 我的对话：出生（App 铸）或收养（本地关联）
    case mine
    /// R4/R5 系统运行：撤出对话名单、归工作台账
    case system
    /// R6/R7/R8/R9 频道：id 为频道 id（hermes 或平台名）
    case channel(String)

    /// 是否 Hermes 频道成员（合并桶同属频道名单）：
    /// 抽屉频道行显隐与频道页名单的成员谓词
    public var isHermesChannelMember: Bool {
        switch self {
        case .mergeBucket: return true
        case .channel(let id): return id == ChannelRegistry.hermesChannelID
        case .main, .mine, .system: return false
        }
    }
}

/// 三层分类纯函数（规格 §2 规则链 R0→R9，命中即
/// 定、不再往下）。入参口径：
/// - linkedThreadSessionIDs＝存在本地线程关联（非
///   主线线程）的服务端会话 id 集，由 App 层从
///   ChatThread 全集派生（R2 出生/收养证明）；
/// - mainServerSessionID＝SideChatStore 钦定主线
///   服务端 id（R0 走 SideChatClassifier.isMain 双
///   信号，与各名单面同一函数）。
public enum SessionClassifier {
    /// App 铸旁聊前缀（SideChatLink.newSessionID 的
    /// 生成式 oneday-side-<uuid>）
    public static let appSideSessionPrefix = "oneday-side-"

    public static func classify(
        id: String,
        source: String?,
        sessionKey: String?,
        mainServerSessionID: String?,
        linkedThreadSessionIDs: Set<String>
    ) -> SessionLayer {
        // R0 主线（钦定 id 精确命中或 oneday-main- 前缀）
        if SideChatClassifier.isMain(
            serverSessionID: id, mainServerSessionID: mainServerSessionID
        ) {
            return .main
        }
        // R1 合并桶钦定两条（只读特例，先于一切来源判定）
        if SideChatLink.isMergeBucket(id) {
            return .mergeBucket
        }
        let effective = SessionSources.effectiveSource(
            source: source, sessionKey: sessionKey
        )
        // R2 本地关联（出生/收养证明）；例外：关联会
        // 话来源是非用户通道（kanban/平台等）时不升
        // 级——线程本体保留、分类跟随会话继续往下判
        // （沿 DrawerSideChatFilter 现行口径）
        if linkedThreadSessionIDs.contains(id),
           !SessionSources.isNonUserChannel(effective) {
            return .mine
        }
        // R3 App 铸旁聊前缀（R2 未命中：本地线程已删
        // 等留痕情形，仍按出生证明归我的对话）
        if id.hasPrefix(appSideSessionPrefix) {
            return .mine
        }
        // R4 部署侧铸 id：oneday- 前缀但非 main-/side-
        // （如桥铸 oneday-ideas-gen——oneday- 前缀不
        // 等于 App 资产，主/旁已在 R0/R3 先行命中）
        if id.hasPrefix(SideChatLink.ownSessionPrefix) {
            return .system
        }
        // R5 结构性系统源（parent_session_id 分支未
        // 启用：该字段不在列表解码模型内，待 §9 实测）
        if let effective,
           SessionSources.structuralSystem.contains(effective) {
            return .system
        }
        // R6 平台源 → 对应外部频道（一期无行无页）
        if let effective,
           SessionSources.platforms.contains(effective) {
            return .channel(effective)
        }
        // R7 Hermes 人工表面（网页/命令行）
        if let effective,
           SessionSources.hermesSurfaces.contains(effective) {
            return .channel(ChannelRegistry.hermesChannelID)
        }
        // R8 API 来源与 R9 判不准：同归 Hermes 频道。
        // R8 自由形态 id 的归属受施工前置闸约束（规
        // 格 §8-3/§9-2：Dashboard 自建会话 id 形态未
        // 实测前，自由形态默认频道、不许写死为系统）
        return .channel(ChannelRegistry.hermesChannelID)
    }

    /// ServerSession 直判（名单面批量分类的入口）
    public static func classify(
        session: ServerSession,
        mainServerSessionID: String?,
        linkedThreadSessionIDs: Set<String>
    ) -> SessionLayer {
        classify(
            id: session.id,
            source: session.source,
            sessionKey: session.sessionKey,
            mainServerSessionID: mainServerSessionID,
            linkedThreadSessionIDs: linkedThreadSessionIDs
        )
    }

    /// 批量分类：保入序、按层分筐（频道再按频道 id
    /// 分筐）——全部对话页分段、频道页名单与抽屉频
    /// 道行显隐共用同一份分筐结果，不许各面重算
    public static func partition(
        sessions: [ServerSession],
        mainServerSessionID: String?,
        linkedThreadSessionIDs: Set<String>
    ) -> SessionPartition {
        var result = SessionPartition()
        for session in sessions {
            let layer = classify(
                session: session,
                mainServerSessionID: mainServerSessionID,
                linkedThreadSessionIDs: linkedThreadSessionIDs
            )
            result.append(session, layer: layer)
        }
        return result
    }
}

/// 分类分筐结果（保入序）：名单面按筐取行。
/// 不声明 Equatable——ServerSession 本体只有
/// Decodable 口径，分筐结果只作呈现派生、不作值比较
public struct SessionPartition: Sendable {
    public private(set) var main: [ServerSession] = []
    public private(set) var mergeBuckets: [ServerSession] = []
    public private(set) var mine: [ServerSession] = []
    public private(set) var system: [ServerSession] = []
    public private(set) var channels: [String: [ServerSession]] = [:]

    public init() {}

    public mutating func append(_ session: ServerSession, layer: SessionLayer) {
        switch layer {
        case .main: main.append(session)
        case .mergeBucket: mergeBuckets.append(session)
        case .mine: mine.append(session)
        case .system: system.append(session)
        case .channel(let id): channels[id, default: []].append(session)
        }
    }

    /// Hermes 频道全名单（普通行＋合并桶行合并、保
    /// 分筐前的相对序不可得——两筐各自保序，频道页
    /// 按 startedAt 倒序重排后呈现，见频道页注）
    public var hermesChannelSessions: [ServerSession] {
        (channels[ChannelRegistry.hermesChannelID] ?? []) + mergeBuckets
    }

    /// Hermes 频道计数（频道段行小字与抽屉显隐判定：
    /// 普通频道行＋合并桶行）
    public var hermesChannelCount: Int {
        hermesChannelSessions.count
    }
}
