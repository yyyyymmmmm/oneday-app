import Foundation

/// 聊天主题（0.26.0；§503 整包化）：一款主题＝一整套
/// 聊天呈现——用户气泡底/字、AI 底衬卡面、聊天背景、
/// 强调色、弱面（tint）全由本表一处辖，呈现层（Palette）
/// 只读解析结果。§503 前本表只辖用户泡/强调/tint，文件
/// 头曾明文「界面底色/AI 泡色不在主题辖区、恒走静态令
/// 牌」——该纪律自 §503 起由整包辖区取代（用户三层框
/// 架＋18:36 终裁：架构学 TG 整包＋参数收敛、配色只取
/// 现成色值、Muse 有对应物以 Muse 为准）。
///
/// 用户可调参数收敛为 6 维（TG 同构）：基主题（本表）、
/// 强调色（预设色点覆盖，见 ChatAccentPresets）、用户泡
/// 色（随基主题）、AI 卡色（随基主题）、背景（背景选择
/// 键，含「跟随主题」档读本表背景行）、圆角（气泡样式
/// 键）；其余细节色锁入骨架令牌、不散成开关。
///
/// 值的出处纪律：有取样出处的逐值标明（§503 取样表＝
/// theme-color-samples-20261124.md）；无取样处沿用在册
/// 令牌并标明，不自调新色。对比闸由 ChatThemeTests 全
/// 款钉住（泡字/卡字/强调多面 ≥4.5 等）。
public struct ChatTheme: Equatable, Identifiable, Sendable {
    public let id: String
    public let displayName: String
    /// 用户气泡底（浅/暗）
    public let bubbleLight: UInt32
    public let bubbleDark: UInt32
    /// 用户气泡字（浅/暗）
    public let bubbleTextLight: UInt32
    public let bubbleTextDark: UInt32
    /// 强调色（浅/暗）：链接、引用竖线、选中态、胶囊
    /// 状态点等全 App 强调面的单源（0.36.1 起）
    public let accentLight: UInt32
    public let accentDark: UInt32
    /// 弱面（浅/暗）：强调的低强度版本——图标盒底、胶
    /// 囊信息底、选中行底一类「强调弱面」的单源；其上
    /// 文字走 ink/bodyInk、不走强调本体
    public let tintLight: UInt32
    public let tintDark: UInt32
    /// AI 底衬卡面（浅/暗，§503 新增辖区）：助手消息全
    /// 宽卡的底色。默认款＝Muse 实测 #E9EAEC（浅，
    /// 本 App 逐像素复验）／#2C2C2E（暗，在册助手面值）
    public let aiCardLight: UInt32
    public let aiCardDark: UInt32
    /// 聊天背景（浅/暗，§503 新增辖区）：背景选择取
    /// 「跟随主题」时消费；独立背景档（雾灰/石板等）
    /// 不读本行
    public let backgroundLight: UInt32
    public let backgroundDark: UInt32

    public init(
        id: String, displayName: String,
        bubbleLight: UInt32, bubbleDark: UInt32,
        bubbleTextLight: UInt32, bubbleTextDark: UInt32,
        accentLight: UInt32, accentDark: UInt32,
        tintLight: UInt32, tintDark: UInt32,
        aiCardLight: UInt32, aiCardDark: UInt32,
        backgroundLight: UInt32, backgroundDark: UInt32
    ) {
        self.id = id
        self.displayName = displayName
        self.bubbleLight = bubbleLight
        self.bubbleDark = bubbleDark
        self.bubbleTextLight = bubbleTextLight
        self.bubbleTextDark = bubbleTextDark
        self.accentLight = accentLight
        self.accentDark = accentDark
        self.tintLight = tintLight
        self.tintDark = tintDark
        self.aiCardLight = aiCardLight
        self.aiCardDark = aiCardDark
        self.backgroundLight = backgroundLight
        self.backgroundDark = backgroundDark
    }
}

/// 主题注册表：默认「三狗」居首（defaultTheme 取首元，
/// 顺序即外观页主题列的呈现顺序）
public enum ChatThemes {
    public static let defaultID = "sangou"

    public static let all: [ChatTheme] = [
        ChatTheme(
            id: "sangou", displayName: "三狗",
            bubbleLight: 0xC8E7FF, bubbleDark: 0x1473C8,
            bubbleTextLight: 0x11191C, bubbleTextDark: 0xFFFFFF,
            // accentLight 沿革：0.26.0 初值 0x1473C8 →
            // 0.41.0（§66.1 浅档专项）同色相加深一档至
            // 0x136FC1 → 2026-11-15（第 85 条）再深一
            // 档至 0x1268B8（压助手泡面差线）
            // accentDark 沿革：0.26.0～0.50.x 长期 0x5EB1EF
            // （H206 S61% V94%）→ dp-214 降饱和收带至
            // 0x359FF0（S78%，H/V 不变，落回降饱和
            // 10–15% 门槛带内）
            accentLight: 0x1268B8, accentDark: 0x359FF0,
            tintLight: 0xEDF7FD, tintDark: 0x16242E,
            // §503：AI 卡＝Muse 实测浅 #E9EAEC／暗在
            // 册 #2C2C2E；背景＝页底在册值（浅 #FFFFFF
            // ／暗 #000000，与 chatSurface 定版同值）
            // dp-214：浅档 #FCFCFC→#FFFFFF 收敛
            aiCardLight: 0xE9EAEC, aiCardDark: 0x2C2C2E,
            backgroundLight: 0xFFFFFF, backgroundDark: 0x000000
        ),
        ChatTheme(
            // §503 新增「微信」款：配色逐值取自取样表
            // （theme-color-samples-20261124.md，腾讯
            // WeUI 官方变量＋多源实测）——发泡 #95EC69、
            // 收泡（＝本 App 的 AI 卡面）#FFFFFF、聊天
            // 背景 #EDEDED（--weui-BG-0 官方变量）。
            // 无取样半边按在册口径落值：泡字浅档＝在册
            // 主墨 #11191C（取样表注微信字色近黑、无确
            // 切 hex）；暗档整组无微信深色取样——泡暗
            // #3E7D2C＝发泡同色相加深的定死常量（离线
            // 实算：白字 5.03、对自家暗背景 3.75，全闸
            // 过线，§66.1 加深先例同式）；卡暗＝在册
            // #2C2C2E；背景暗＝在册雾灰暗值 #111113；
            // 强调＝微信绿同色相加深/提亮至过闸（浅
            // #0B6E35：对页 6.21/对卡 6.37；暗 #3FBF6F：
            // 对暗卡 5.90）；tint＝同色相弱面（浅
            // #EAF9E2／暗 #16280F，强调字形其上 ≥3.0、
            // 浅档强调其上 5.81，逐值实算见 §503）
            id: "wechat", displayName: "微信",
            bubbleLight: 0x95EC69, bubbleDark: 0x3E7D2C,
            bubbleTextLight: 0x11191C, bubbleTextDark: 0xFFFFFF,
            accentLight: 0x0B6E35, accentDark: 0x3FBF6F,
            tintLight: 0xEAF9E2, tintDark: 0x16280F,
            aiCardLight: 0xFFFFFF, aiCardDark: 0x2C2C2E,
            backgroundLight: 0xEDEDED, backgroundDark: 0x111113
        ),
        ChatTheme(
            id: "iceBlue", displayName: "冰蓝",
            bubbleLight: 0xCBE5FE, bubbleDark: 0x2C6FBF,
            bubbleTextLight: 0x10222E, bubbleTextDark: 0xFFFFFF,
            // accentLight：2026-11-15（第 85 条）同色相
            // 深一档 0x2B7CD3→0x1B6AB9（压助手泡面差线）
            accentLight: 0x1B6AB9, accentDark: 0x7CC0FF,
            tintLight: 0xEAF3FE, tintDark: 0x101E30,
            aiCardLight: 0xE9EAEC, aiCardDark: 0x2C2C2E,
            backgroundLight: 0xFCFCFC, backgroundDark: 0x000000
        ),
        ChatTheme(
            id: "obsidian", displayName: "曜黑",
            // bubbleDark 沿革：0.26.0 初值 0x2C3138（对暗
            // 页底仅 1.60）→ 2026-11-21（台账 197／§335
            // 清账）同色相提亮至 0x585E65 定死（泡/页
            // 3.12、字/泡 6.72）
            bubbleLight: 0x000000, bubbleDark: 0x585E65,
            bubbleTextLight: 0xFFFFFF, bubbleTextDark: 0xFFFFFF,
            accentLight: 0x1F1F22, accentDark: 0xC9CDD2,
            tintLight: 0xECEDEF, tintDark: 0x232528,
            aiCardLight: 0xE9EAEC, aiCardDark: 0x2C2C2E,
            backgroundLight: 0xFCFCFC, backgroundDark: 0x000000
        ),
        ChatTheme(
            id: "greige", displayName: "灰米",
            bubbleLight: 0xE4DAD1, bubbleDark: 0x6E5B49,
            bubbleTextLight: 0x2C211A, bubbleTextDark: 0xFFFFFF,
            accentLight: 0x7A5C3E, accentDark: 0xD9B98F,
            tintLight: 0xF5EFE7, tintDark: 0x241C14,
            aiCardLight: 0xE9EAEC, aiCardDark: 0x2C2C2E,
            backgroundLight: 0xFCFCFC, backgroundDark: 0x000000
        ),
        ChatTheme(
            id: "skyBlue", displayName: "天蓝",
            bubbleLight: 0xB8DAFD, bubbleDark: 0x1F6FD6,
            bubbleTextLight: 0x0E2233, bubbleTextDark: 0xFFFFFF,
            // accentLight：0.41.0（§66.1）同色相加深一
            // 档 0x1575D1→0x1463B8（对 tintLight 过闸）
            accentLight: 0x1463B8, accentDark: 0x6FB3FF,
            tintLight: 0xE7F1FE, tintDark: 0x0F2036,
            aiCardLight: 0xE9EAEC, aiCardDark: 0x2C2C2E,
            backgroundLight: 0xFCFCFC, backgroundDark: 0x000000
        ),
        ChatTheme(
            id: "lavender", displayName: "薰衣草",
            bubbleLight: 0xDBC6F1, bubbleDark: 0x6A45A8,
            bubbleTextLight: 0x241338, bubbleTextDark: 0xFFFFFF,
            accentLight: 0x6440C8, accentDark: 0xB79CFF,
            tintLight: 0xF0EAFB, tintDark: 0x1D1430,
            aiCardLight: 0xE9EAEC, aiCardDark: 0x2C2C2E,
            backgroundLight: 0xFCFCFC, backgroundDark: 0x000000
        ),
        ChatTheme(
            id: "pink", displayName: "粉",
            bubbleLight: 0xFDB9DE, bubbleDark: 0xA03A78,
            bubbleTextLight: 0x40162B, bubbleTextDark: 0xFFFFFF,
            // accentLight §503：原 0xBC3A78 对旧助手面
            // #EEEEF0 仅 4.51 压线、对新 AI 卡面
            // #E9EAEC 实算 4.35 跌破闸⑥——按 §66.1 先
            // 例同色相加深一档至 0xB03670（对卡面
            // 4.84、对 tint 5.15，逐面裕量恢复）
            accentLight: 0xB03670, accentDark: 0xFF9ED2,
            tintLight: 0xFDEDF4, tintDark: 0x2C1A22,
            aiCardLight: 0xE9EAEC, aiCardDark: 0x2C2C2E,
            backgroundLight: 0xFCFCFC, backgroundDark: 0x000000
        ),
        ChatTheme(
            id: "peach", displayName: "蜜桃",
            bubbleLight: 0xFFD7B5, bubbleDark: 0x9E5A1C,
            bubbleTextLight: 0x65350F, bubbleTextDark: 0xFFFFFF,
            // accentLight 沿革：0.41.0（§66.1）加深至
            // 0xA55611；§503 对新 AI 卡面 #E9EAEC 实算
            // 约 4.0 跌破闸⑥，同色相再深一档至
            // 0xA14F11（对卡面 4.79、对 tint 5.12）
            accentLight: 0xA14F11, accentDark: 0xF5A95C,
            tintLight: 0xFDF0DF, tintDark: 0x2B2113,
            aiCardLight: 0xE9EAEC, aiCardDark: 0x2C2C2E,
            backgroundLight: 0xFCFCFC, backgroundDark: 0x000000
        ),
    ]

    public static var defaultTheme: ChatTheme {
        // all 首元即默认款（注册表纪律：默认恒居首）
        all[0]
    }

    /// 按 id 查主题：nil/未注册 id 一律回默认（持久化
    /// 读口——脏值不许让界面失去颜色）
    public static func theme(forID id: String?) -> ChatTheme {
        guard let id, let found = all.first(where: { $0.id == id })
        else { return defaultTheme }
        return found
    }
}

/// 用户泡定版（台账 197／DESIGN §335，2026-11-
/// 21 用户亲点 Muse 客户端截图为样板、按推荐三
/// 项拍板）：气泡色效第五度改判——**浅档改「浅
/// 填＋深字」**：浅档恢复消费各款 bubbleLight/
/// bubbleTextLight（0.26.0 在册值、188 起被本层
/// 改判埋没）；暗档维持 188（bubbleDark 深饱实
/// 填＋现泡字）一字不动。188 的两条纪律保留：
/// ①不设浓淡开关——184 的浓淡两式仍退役、每款
/// 仍只有一个定死处理（处理内容换了、开关不许
/// 有）；②解析只在本层（令牌层）发生：视图层只
/// 读解析结果、不许硬编码颜色、不许自算混色。
/// 188 的「饱和实填＋白字」浅档半边自本版退役。
/// 逐款定值与实算对比由 ChatThemeTests 对比闸⑦
/// （197 改判口径）钉住：泡字/泡全款 ≥4.5（浅
/// 6.68–13.84／暗 4.87–6.72）、浅填款泡/页
/// ∈[1.10,1.60]（1.27–1.55）、深泡款曜黑浅档
/// 豁免带只守字闸、暗档泡/页 ≥2.9 维持（3.12–
/// 4.32），2026-11-21 逐值实算。
extension ChatTheme {
    /// 用户泡底解析（明暗的唯一出口）：浅档＝同
    /// 款 bubbleLight（浅填）；暗档＝同款
    /// bubbleDark（188 深饱实填维持）
    public func bubbleFill(dark: Bool) -> UInt32 {
        dark ? bubbleDark : bubbleLight
    }

    /// 用户泡字解析（与 bubbleFill 同出口成对）：
    /// 浅档＝同款 bubbleTextLight（深字，压浅填
    /// 实算全款 ≥7.64）；暗档＝现泡字（全款对
    /// 暗泡 ≥4.87，闸①同线钉住）
    public func bubbleText(dark: Bool) -> UInt32 {
        dark ? bubbleTextDark : bubbleTextLight
    }

    /// AI 卡面解析（§503，整包辖区新增出口）：浅
    /// 档＝同款 aiCardLight；暗档＝同款 aiCardDark
    public func aiCardFill(dark: Bool) -> UInt32 {
        dark ? aiCardDark : aiCardLight
    }

    /// 主题背景解析（§503）：背景选择取「跟随主
    /// 题」档时由 Palette 消费本出口
    public func chatBackground(dark: Bool) -> UInt32 {
        dark ? backgroundDark : backgroundLight
    }
}

/// 强调色预设盘（§503，TG 同构）：Telegram 主题参
/// 数 accent 的出厂预设 11 色（apps 源码 Accent-
/// Colors 逐值，见取样表）——外观页以色点列呈现，
/// 选中即覆盖当前主题强调（存 hex 覆盖键）；另设
/// 「跟随主题」复位（清覆盖、回基主题强调）。覆盖
/// 是用户显式自选值、不进主题对比闸（闸只辖主题
/// 在册值）；深色模式下 TG 对蓝有 #3E88F7 特例，
/// 本盘按单值呈现、特例不落（差异登记 §503）。
public enum ChatAccentPresets {
    /// 预设色（hex）：蓝/青/绿/粉/橙/紫/红/黄/灰/
    /// 黑/白——TG 出厂盘逐值
    public static let values: [UInt32] = [
        0x0088FF, 0x00C2ED, 0x29B327, 0xEB6CA4, 0xF08200,
        0x9472EE, 0xD33213, 0xEDB400, 0x6D839E, 0x000000,
        0xFFFFFF,
    ]
}

/// 虚拟形象大小三档（0.26.0）：作用面＝聊天页顶部身
/// 份胶囊头像＋聊天空态形象（枢纽大头像 110 与连接页
/// 吉祥物不在辖区——那是品牌呈现面、非聊天形象）。
/// 中档 28＝现行胶囊头像边长锚（0.22.0 定版），小
/// 24/大 34 按胶囊 ViewThatFits 布局不破落值：名字
/// 恒 fixedSize＋最高优先级、胶囊宽随内容自适应，
/// 头像 ±6 不挤断名字（构造论证见 §53）。
public enum AvatarSizeTier: String, CaseIterable, Identifiable, Sendable {
    case small
    case medium
    case large

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .small: return "小"
        case .medium: return "中"
        case .large: return "大"
        }
    }

    /// 身份胶囊头像边长（聊天胶囊与 IdentityAnchor
    /// 三面同源共用此档，见 §53 的同源顺带登记）
    public var capsulePointSize: CGFloat {
        switch self {
        case .small: return 24
        case .medium: return 28
        case .large: return 34
        }
    }

    /// 聊天空态形象边长：胶囊档的等比放大呈现
    /// （×2，同源同比例）
    public var emptyStatePointSize: CGFloat {
        capsulePointSize * 2
    }
}

/// 外观持久化键登记（0.26.0 起）：appearanceMode
/// （0.4.0 既有键、不改名不迁移，老用户已选值原样保
/// 留）、chatTheme、avatarSize；台账 179 两键（气泡
/// 样式/聊天背景）；§503 两键（文字大小/强调覆盖）。
/// 本枚举是键名的单一出处——AppStorage 与 UserDefa-
/// ults 读口都引此，不许再散写字面量。
public enum AppearanceStorageKeys {
    public static let appearanceMode = "appearanceMode"
    public static let chatTheme = "chatTheme"
    public static let avatarSize = "avatarSize"
    // 台账 179（OB-I1，DESIGN §391）：聊天个性化两键
    // ——气泡样式与聊天背景；未设/脏值一律回定版
    // （standard），无此键的老用户呈现零变化
    public static let chatBubbleStyle = "chatBubbleStyle"
    public static let chatBackground = "chatBackground"
    // 台账 188 定版（2026-11-20）：184 的气泡浓淡
    // 键 chatBubbleFillStyle 随两式机制整套退役、
    // 键名常量一并删除——设备上可能残留的存量值
    // 已无任何消费方（惰性残留，不读不写不清）
    // §503：聊天文字大小档（未设/脏值回「跟随系统」，
    // 存量用户呈现零变化）
    public static let chatTextSize = "chatTextSize"
    // §503：强调色覆盖（存 hex 整数；未设＝跟随主
    // 题。TG accent 参数同构——基主题之上的一层覆
    // 盖，选「跟随主题」即删键复位）
    public static let chatAccentOverride = "chatAccentOverride"
}

/// 外观偏好读口（0.26.0）：UserDefaults 之上的类型化
/// 薄封装——未设/脏值一律回定版默认（三狗主题/中
/// 档），写入即原始值落盘。App 侧交互写走 AppStorage
/// （同键），本封装供 Palette 等非视图层与单测使用。
public enum AppearancePreferences {
    public static func chatTheme(
        in defaults: UserDefaults = .standard
    ) -> ChatTheme {
        ChatThemes.theme(
            forID: defaults.string(forKey: AppearanceStorageKeys.chatTheme)
        )
    }

    public static func setChatTheme(
        id: String, in defaults: UserDefaults = .standard
    ) {
        defaults.set(id, forKey: AppearanceStorageKeys.chatTheme)
    }

    public static func avatarTier(
        in defaults: UserDefaults = .standard
    ) -> AvatarSizeTier {
        let raw = defaults.string(forKey: AppearanceStorageKeys.avatarSize)
        return AvatarSizeTier(rawValue: raw ?? "") ?? .medium
    }

    public static func setAvatarTier(
        _ tier: AvatarSizeTier, in defaults: UserDefaults = .standard
    ) {
        defaults.set(
            tier.rawValue, forKey: AppearanceStorageKeys.avatarSize
        )
    }

    /// 气泡样式（台账 179）：未设/脏值回定版 standard
    public static func bubbleStyle(
        in defaults: UserDefaults = .standard
    ) -> ChatBubbleStyle {
        let raw = defaults.string(
            forKey: AppearanceStorageKeys.chatBubbleStyle
        )
        return ChatBubbleStyle(rawValue: raw ?? "") ?? .standard
    }

    public static func setBubbleStyle(
        _ style: ChatBubbleStyle,
        in defaults: UserDefaults = .standard
    ) {
        defaults.set(
            style.rawValue,
            forKey: AppearanceStorageKeys.chatBubbleStyle
        )
    }

    /// 聊天背景（台账 179）：未设/脏值回定版 standard
    public static func backgroundStyle(
        in defaults: UserDefaults = .standard
    ) -> ChatBackgroundStyle {
        let raw = defaults.string(
            forKey: AppearanceStorageKeys.chatBackground
        )
        return ChatBackgroundStyle(rawValue: raw ?? "") ?? .standard
    }

    public static func setBackgroundStyle(
        _ style: ChatBackgroundStyle,
        in defaults: UserDefaults = .standard
    ) {
        defaults.set(
            style.rawValue,
            forKey: AppearanceStorageKeys.chatBackground
        )
    }

    /// 聊天文字大小（§503）：未设/脏值回「跟随系统」
    public static func textSizeTier(
        in defaults: UserDefaults = .standard
    ) -> ChatTextSizeTier {
        let raw = defaults.string(
            forKey: AppearanceStorageKeys.chatTextSize
        )
        return ChatTextSizeTier(rawValue: raw ?? "") ?? .system
    }

    public static func setTextSizeTier(
        _ tier: ChatTextSizeTier,
        in defaults: UserDefaults = .standard
    ) {
        defaults.set(
            tier.rawValue, forKey: AppearanceStorageKeys.chatTextSize
        )
    }

    /// 强调色覆盖（§503）：未设＝nil（跟随主题）；
    /// 存量值按 hex 整数读回（范围外脏值回 nil）
    public static func accentOverride(
        in defaults: UserDefaults = .standard
    ) -> UInt32? {
        guard defaults.object(
            forKey: AppearanceStorageKeys.chatAccentOverride
        ) != nil else { return nil }
        let value = defaults.integer(
            forKey: AppearanceStorageKeys.chatAccentOverride
        )
        guard value >= 0, value <= 0xFFFFFF else { return nil }
        return UInt32(value)
    }

    /// 写强调覆盖；传 nil＝删键复位（跟随主题）
    public static func setAccentOverride(
        _ hex: UInt32?, in defaults: UserDefaults = .standard
    ) {
        if let hex {
            defaults.set(
                Int(hex), forKey: AppearanceStorageKeys.chatAccentOverride
            )
        } else {
            defaults.removeObject(
                forKey: AppearanceStorageKeys.chatAccentOverride
            )
        }
    }
}
