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

    /// 结构性系统源（R5）：任务板与定时/调度本体。
    /// "local" 是 kanban 行的 session_key 平台段值
    /// （2026-11-11 对账 A6）：source 本体缺失时有
    /// 效来源回落得它，必须在此兜住——否则机器行
    /// 会穿透 R9 落 Hermes 频道错显。存量 9 条
    /// kanban 行 source 俱在、未触发，属防患收紧
    public static let structuralSystem: Set<String> = [
        "kanban", "cron", "cron_job", "scheduler", "local",
    ]

    /// Hermes 人工表面（R7）：网页控制台与命令行
    public static let hermesSurfaces: Set<String> = [
        "dashboard", "cli",
    ]

    /// 外部平台源（R6）：Hermes 网关的平台名全集。
    /// 2026-11-13 频道扩展一期对账（规格 §2.3）：本
    /// 表以网关 Platform 枚举实值为唯一真源——旧表
    /// 的 wechat/qq 与网关实值 weixin/qqbot 错位（微
    /// 信/QQ 会话会穿透落 Hermes 频道），且缺 11 个
    /// 平台。命中即归对应外部频道。
    public static let platforms: Set<String> = [
        "telegram", "discord", "whatsapp", "whatsapp_cloud",
        "slack", "signal", "mattermost", "matrix", "email",
        "sms", "dingtalk", "feishu", "wecom", "wecom_callback",
        "weixin", "bluebubbles", "qqbot", "yuanbao",
        "line", "teams", "google_chat", "photon", "simplex",
    ]

    /// 历史别名（旧表口径与个别插件的旧名）：归一到
    /// 网关实值再判定，别名本身不作频道 id 出现
    public static let platformAliases: [String: String] = [
        "wechat": "weixin",
        "qq": "qqbot",
    ]

    /// 平台名归一：别名映射到网关实值，其余原样
    public static func canonicalPlatform(_ source: String) -> String {
        platformAliases[source] ?? source
    }

    /// 平台源的人话名（频道注册表给平台频道命名用；
    /// 未列者回落原值）
    public static func platformDisplayName(_ source: String) -> String {
        switch source {
        case "whatsapp": return "WhatsApp"
        case "whatsapp_cloud": return "WhatsApp"
        case "telegram": return "Telegram"
        case "feishu": return "飞书"
        case "weixin", "wechat": return "微信"
        case "dingtalk": return "钉钉"
        case "wecom", "wecom_callback": return "企业微信"
        case "qqbot", "qq": return "QQ"
        case "discord": return "Discord"
        case "slack": return "Slack"
        case "signal": return "Signal"
        case "matrix": return "Matrix"
        case "mattermost": return "Mattermost"
        case "email": return "邮箱"
        case "sms": return "短信"
        case "bluebubbles": return "iMessage"
        case "yuanbao": return "腾讯元宝"
        case "line": return "LINE"
        case "teams": return "Teams"
        case "google_chat": return "Google Chat"
        case "photon": return "Photon"
        case "simplex": return "SimpleX"
        default: return source
        }
    }

    /// 平台官方品牌图标资产名（宪法 §4：官方原图入
    /// 资产才登记；没有合格原图的平台回 nil，呈现层
    /// 不许拿仿绘/字母块顶替）。一期登记 Telegram；
    /// 二期续登飞书与令牌四家（钉钉/QQ/Discord/
    /// Slack），均为官方 App 图标原图（来源见
    /// channels-phase1／channels-feishu／
    /// channels-token-batch 三报告）。微信图标随
    /// 二期微信行下架一并退役（2026-11-13 用户拍
    /// 板），故此处不再登记 weixin
    public static func platformIconAssetName(
        _ source: String
    ) -> String? {
        switch source {
        case "telegram": return "ChannelTelegram"
        case "feishu": return "ChannelFeishu"
        case "dingtalk": return "ChannelDingtalk"
        case "qqbot", "qq": return "ChannelQQ"
        case "discord": return "ChannelDiscord"
        case "slack": return "ChannelSlack"
        default: return nil
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

/// 频道配对形态（呈现层据此决定行尾与点开的目的
/// 地，规格 §4/§6）。冻结形态（frozen）随二期微
/// 信行下架退役（2026-11-13 用户拍板删行），枚举
/// 一并摘除、留痕见 channels-feishu-report
public enum ChannelPairingKind: Equatable, Sendable {
    /// 不是外部平台（Hermes 频道本体，无配对概念）
    case none
    /// 填钥匙配对（Telegram、飞书等）
    case token
    /// 扫码配对（WhatsApp，后续批次开放）
    case qr
}

/// 频道注册表（规格 §3.3/§7）：2026-11-13 频道扩
/// 展一期——抽屉清单恒显 Hermes＋Telegram＋微信
/// （冻结行）；二期（同日用户改口径）——微信行下
/// 架、飞书上行，清单＝Hermes＋Telegram＋飞书；
/// 其余平台随各自接入批次往 drawerList 里加
/// （descriptor(for:) 已能为任意平台源派生描述，
/// 频道段/频道页不挑批次）。
public enum ChannelRegistry {
    public static let hermesChannelID = "hermes"

    /// Hermes 频道：非 App 出生、来自这台 Hermes 其
    /// 他表面（网页/接口）的会话收纳处。图标复用
    /// 0.36.3 已登记的本机服务 Hermes 定制图面资产
    /// （LocalServices 同款 LocalHermes，台账 D 节）
    /// 用户面展示名（§234，2026-11-14 大厂九项⑨拍
    /// 板）：「服务器会话」——频道 id 与代码符号仍为
    /// hermes 不动，用户面不再直呼服务端产品名
    public static let hermes = ChannelDescriptor(
        id: hermesChannelID,
        name: "服务器会话",
        pageSubtitle: "在这台 Hermes 的其他地方（网页、接口）发生的对话",
        iconAssetName: "LocalHermes"
    )

    /// Telegram 频道（一期打样）：配对走填钥匙，图
    /// 标为官方品牌原图资产 ChannelTelegram
    public static let telegram = ChannelDescriptor(
        id: "telegram",
        name: "Telegram",
        pageSubtitle: "在 Telegram 里和你的智能体聊的对话",
        iconAssetName: SessionSources.platformIconAssetName("telegram")
    )

    /// 飞书频道（二期）：配对走填应用凭证（App ID
    /// ＋App Secret，飞书开放平台企业自建应用），图
    /// 标为官方品牌原图资产 ChannelFeishu。微信行已
    /// 于二期下架（2026-11-13 用户拍板）：与 ClawBot
    /// 同底座的冻结行连同其说明页、图标资产一并退
    /// 役；来源分类层对 weixin 的归一与识别保留（历
    /// 史来源事实，不属配对面）
    public static let feishu = ChannelDescriptor(
        id: "feishu",
        name: "飞书",
        pageSubtitle: "在飞书里和你的智能体聊的对话",
        iconAssetName: SessionSources.platformIconAssetName("feishu")
    )

    /// 钉钉（二期令牌批）：企业内部应用机器人，
    /// Stream 长连接接入，填 Client ID／Client
    /// Secret 配对；图标为官方 App 原图
    public static let dingtalk = ChannelDescriptor(
        id: "dingtalk",
        name: "钉钉",
        pageSubtitle: "在钉钉里和你的智能体聊的对话",
        iconAssetName: SessionSources.platformIconAssetName("dingtalk")
    )

    /// QQ 机器人（二期令牌批）：QQ 机器人开放平
    /// 台官方机器人，填 AppID／Client Secret 配对
    public static let qqbot = ChannelDescriptor(
        id: "qqbot",
        name: "QQ",
        pageSubtitle: "在 QQ 里和你的智能体聊的对话",
        iconAssetName: SessionSources.platformIconAssetName("qqbot")
    )

    /// Discord（二期令牌批）：开发者门户机器人，
    /// 填 Bot 令牌配对
    public static let discord = ChannelDescriptor(
        id: "discord",
        name: "Discord",
        pageSubtitle: "在 Discord 里和你的智能体聊的对话",
        iconAssetName: SessionSources.platformIconAssetName("discord")
    )

    /// Slack（二期令牌批）：Socket Mode 双钥匙
    /// （Bot Token＋App Token）配对
    public static let slack = ChannelDescriptor(
        id: "slack",
        name: "Slack",
        pageSubtitle: "在 Slack 里和你的智能体聊的对话",
        iconAssetName: SessionSources.platformIconAssetName("slack")
    )

    /// 一期注册表（显行判定与频道段行源）
    public static let phaseOne: [ChannelDescriptor] = [hermes]

    /// 抽屉频道区恒显清单（2026-11-13 新口径覆盖
    /// 0.36.29「通一个显一个」：支持的都列、配好的
    /// 能用、没配的给路）。排序：Hermes（恒在首位、
    /// 本机频道）→ Telegram → 飞书（二期换下微信
    /// 行）→ 二期令牌四家（钉钉/QQ/Discord/Slack）
    public static let drawerList: [ChannelDescriptor] = [
        hermes, telegram, feishu, dingtalk, qqbot, discord, slack,

    ]

    /// 平台的配对形态（呈现层据此决定行尾与目的地：
    /// 已配对/token 未配对进引导页/qr 待后续批次）。
    /// Hermes 与未知平台为 none
    public static func pairingKind(
        for channelID: String
    ) -> ChannelPairingKind {
        switch channelID {
        case "telegram", "feishu", "dingtalk", "qqbot",
             "discord", "slack":
            return .token
        case "whatsapp": return .qr
        default: return .none
        }
    }

    /// 按频道 id 取描述：注册表恒有条目优先；其余平
    /// 台按平台名派生（图标走平台资产登记，无登记
    /// 为 nil）；非平台 id 为 nil
    public static func descriptor(for channelID: String) -> ChannelDescriptor? {
        switch channelID {
        case hermesChannelID: return hermes
        case telegram.id: return telegram
        case feishu.id: return feishu
        case dingtalk.id: return dingtalk
        case qqbot.id: return qqbot
        case discord.id: return discord
        case slack.id: return slack
        default: break
        }
        if SessionSources.platforms.contains(channelID) {
            return ChannelDescriptor(
                id: channelID,
                name: SessionSources.platformDisplayName(channelID),
                pageSubtitle: "",
                iconAssetName: SessionSources.platformIconAssetName(
                    channelID
                )
            )
        }
        return nil
    }
}

/// 凭据保存后的生效相位（频道文案小包，2026-11-13）：
/// 伴生 1.0.46 起保存回执带 applyTriggered/
/// applyError——已触发网关重启时，网关记录翻
/// connected 之前有一个「正在生效」的空窗，只看
/// status 会显成笼统的等待态。呈现层据回执先行给
/// 相位、status 翻终态（connected/error）后相位退
/// 场、呈现完全归 status。判定收成纯逻辑，回执字
/// 段缺失（旧版伴生）时回落 .none、与旧行为同形。

public enum ChannelApplyPhase: Equatable, Sendable {
    /// 无保存流程态：呈现完全按 status 走
    case none
    /// 已触发即时生效、等网关记录翻 connected
    case applying
    /// 即时生效触发失败：如实显等待生效＋桥回的原因
    case applyFailed(reason: String)
    /// 已保存但未触发即时生效（桥没有即时通道）：
    /// 等网关下次重启，呈现落回 status 的等待态
    case awaitingRestart

    public static func resolve(
        applyTriggered: Bool?,
        applyError: String?,
        statusState: String?
    ) -> ChannelApplyPhase {
        if statusState == "connected" || statusState == "error" {
            return .none
        }
        guard let applyTriggered else { return .none }
        if let applyError, !applyError.isEmpty {
            return .applyFailed(reason: applyError)
        }
        return applyTriggered ? .applying : .awaitingRestart
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

    /// 伴生 AI 开旁聊前缀（P2 会话包，2026-11-13）：
    /// 伴生 oneday 桥开旁聊门面（/ai-sessions 与
    /// /mcp-sessions 的 sessions_create）凭服务钥经
    /// 网关客户端指定 id 建会话时铸的 oneday-ai-<hex>；
    /// 桥侧 AI_SESSION_PREFIX 是同一常量的另一出处，
    /// 两边同值、改一处必须同步另一处
    public static let aiCastSessionPrefix = "oneday-ai-"

    /// 网关 runs 铸造前缀（对账 A1：点子/晨报等桥
    /// 生成轮次的真实落形 run_<hex>，存量 5/5 全
    /// 机器、零反例）
    public static let runCastPrefix = "run_"

    /// 探针铸造前缀（对账 A2：api_<unix>_<hex> 静
    /// 默流探针形，存量 2/2）——与 R8 的 api- 标准
    /// 形（连字符）是两个前缀：连字符归频道、下划
    /// 线归系统，钉测钉住不串
    public static let probeCastPrefix = "api_"

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
        // R3b 伴生铸 AI 旁聊前缀（P2 会话包，2026-11-13）：
        // 出生证明收养——AI 经伴生门面自开的旁聊，父
        // 会话＝主线、发起动作 id 记于伴生出生记录，
        // id 前缀即 sessions 侧可查的标记面（不污染正
        // 文/标题）。判据只认此前缀一个形态：探针与
        // runs 同为 api_server 来源但无此标记，仍按
        // R4/R4b 旧规，不许借本条连带放宽任何其他闸
        if id.hasPrefix(aiCastSessionPrefix) {
            return .mine
        }
        // R4 部署侧铸 id：oneday- 前缀但非 main-/side-/ai-
        // （如桥铸 oneday-ideas-gen——oneday- 前缀不
        // 等于 App 资产，主/旁/AI 铸已在 R0/R3/R3b 先行命中）
        if id.hasPrefix(SideChatLink.ownSessionPrefix) {
            return .system
        }
        // R4b 机器铸造前缀（2026-11-11 对账收紧
        // A1/A2）：run_ 是网关 runs 落形、api_ 下划
        // 线形是探针铸造——「前缀即出生证明」，与
        // oneday-/api- 同理据形态定系统。置于 R4
        // 之后、R5 之前；§9-2 前置闸只约束其余自由
        // 形态（人类可读名/uuid 仍默认频道），这两
        // 形形态证据已充分、不在闸内
        if id.hasPrefix(runCastPrefix)
            || id.hasPrefix(probeCastPrefix) {
            return .system
        }
        // R5 结构性系统源（parent_session_id 分支未
        // 启用：该字段不在列表解码模型内，待 §9 实测）
        if let effective,
           SessionSources.structuralSystem.contains(effective) {
            return .system
        }
        // R6 平台源 → 对应外部频道：先按别名归一到
        // 网关实值（wechat→weixin、qq→qqbot）再判，
        // 频道 id 恒为网关实值（2026-11-13 对账 §2.3）
        if let effective {
            let canonical = SessionSources.canonicalPlatform(effective)
            if SessionSources.platforms.contains(canonical) {
                return .channel(canonical)
            }
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
