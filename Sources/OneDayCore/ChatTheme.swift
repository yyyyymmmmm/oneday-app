import Foundation

/// 聊天主题（0.26.0，外观页专包）：Palette 级主题变体
/// 的**单一真源**——一款主题只定义两个角色族：
/// ①用户气泡底色＋其上文字色；②强调实色＋其弱面
/// （tint）。界面底色、卡面与文字基线（冷中性）不在
/// 主题辖区，恒走 Palette 静态令牌，主题再花哨也不许
/// 把界面染花（用户定版纪律）。色值全表与实算对比
/// 见 DESIGN-V4 §53；气泡字对比由 ChatThemeTests 闸
/// 钉（浅/暗两档均 ≥4.5，WCAGContrast 同式实算）。
public struct ChatTheme: Equatable, Identifiable, Sendable {
    public let id: String
    public let displayName: String
    /// 用户气泡底（浅/暗）
    public let bubbleLight: UInt32
    public let bubbleDark: UInt32
    /// 气泡上文字（浅/暗）——与同档气泡实算 ≥4.5
    public let bubbleTextLight: UInt32
    public let bubbleTextDark: UInt32
    /// 强调实色（浅/暗）：链接/选中字色/角标填充/光标；
    /// 对页底（浅 #FCFCFC／暗 #000000——0.36.1 批一B
    /// 后 Palette.pageBG 暗档改挂 systemBackground）
    /// 实算同 ≥4.5（闸钉，另扩卡面/泡面/tint 组合闸）
    public let accentLight: UInt32
    public let accentDark: UInt32
    /// 强调弱面（浅/暗）：强调色图标盒/胶囊底（面色，
    /// 其上文字走 ink/bodyInk，不设对比闸）
    public let tintLight: UInt32
    public let tintDark: UInt32

    public init(
        id: String, displayName: String,
        bubbleLight: UInt32, bubbleDark: UInt32,
        bubbleTextLight: UInt32, bubbleTextDark: UInt32,
        accentLight: UInt32, accentDark: UInt32,
        tintLight: UInt32, tintDark: UInt32
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
    }
}

/// 主题注册表（0.26.0）：默认「三狗」＝0.25.0 前的现
/// 行 Palette 原值（用户泡 #C8E7FF/#1473C8、强调
/// #1473C8/#5EB1EF、弱面 #EDF7FD/#16242E、泡字浅档
/// ＝主墨 #11191C）——切回默认即回原貌，零漂移；暗档
/// 泡字原为反演墨 #EDF1F3（对暗泡实算 4.28 压线），
/// 本版改纯白 #FFFFFF（4.87），是全表唯一对旧值的
/// 修正、理由见 §53。其余七款按 Muse 外观页参考图
/// 的色板序（浅蓝/曜黑/米灰/天蓝/浅紫/粉/蜜桃）逐款
/// 以气泡可读性校准：浅档皆淡色泡＋深字、暗档皆深
/// 饱泡＋白字。
public enum ChatThemes {
    public static let defaultID = "sangou"

    // §431（2026-11-24，主题对位包）：七款非默认主题的
    // bubbleLight 已按参照应用（Muse）外观页真机截图
    // 工具采样逐值对齐（色板圆心采样，见 DESIGN §431
    // 参照色表与差异表）；默认款三狗 C8E7FF 为定版锚
    // 不动。bubbleDark／字色／accent／tint 无参照据、
    // 全部不动（参照应用深色面无采样样本，不许编）。
    public static let all: [ChatTheme] = [
        ChatTheme(
            id: "sangou", displayName: "三狗",
            bubbleLight: 0xC8E7FF, bubbleDark: 0x1473C8,
            bubbleTextLight: 0x11191C, bubbleTextDark: 0xFFFFFF,
            // 0.41.0（收口批·浅档专项，DESIGN §66.1 候
            // 选 (a) 落地）：accentLight 同色相加深一档
            // 0x1473C8→0x136FC1——对弱面 tintLight 实算
            // 4.48＜4.5，加深后 4.74；链接/强调落在弱面
            // 与页底均过闸（对比闸④钉住，见测试）
            // 2026-11-15（第 85 条对比度收口）：再深一
            // 档至 0x1268B8——旧值压助手泡面 #EEEEF0
            // 实算 4.45、差 4.5 线 0.05（泡内链接/强
            // 调字格，全格复核唯一差线格）；新值对泡
            // 面 4.90／页底 5.54／卡面 5.68／弱面
            // 5.23／白字压之 5.68，全格过闸（新增对
            // 比闸⑥钉住，见测试）
            accentLight: 0x1268B8, accentDark: 0x5EB1EF,
            tintLight: 0xEDF7FD, tintDark: 0x16242E
        ),
        ChatTheme(
            id: "iceBlue", displayName: "浅蓝",
            bubbleLight: 0xCBE5FE, bubbleDark: 0x1D5FA8,
            bubbleTextLight: 0x14324E, bubbleTextDark: 0xFFFFFF,
            // 2026-11-15（第 85 条收口复核追加）：旧值
            // 0x1F6FC4 压助手泡面 #EEEEF0 实算 4.39 同
            // 样差线（审计原稿只核默认款、本包全格复
            // 核时发现）——同色相深一档至 0x1B6AB9：
            // 对泡面 4.76／页底 5.37／卡面 5.51／弱面
            // 4.98，全格过闸（对比闸⑥）
            accentLight: 0x1B6AB9, accentDark: 0x7FB8F0,
            tintLight: 0xEAF5FD, tintDark: 0x152736
        ),
        ChatTheme(
            id: "obsidian", displayName: "曜黑",
            bubbleLight: 0x000000,
            // 台账 188 定版（2026-11-20）：旧值
            // 0x2C3138 对暗页底（#000000）实算仅
            // 1.60——台账既有留账「曜黑 bubbleDark
            // 未达下限」本次清账：向 accentDark 同
            // 色相提亮定死 0x585E65（mix 口径 0.28
            // 的落值、定死常量不留运行时混色），
            // 实算泡/页 3.20（落同族暗档实测区间
            // 3.12–4.32、不再全表最低贴线）、白字
            // /泡 6.55，双闸过线（对比闸⑦单档口径
            // 钉住，见 ChatThemeTests）
            bubbleDark: 0x585E65,
            bubbleTextLight: 0xFFFFFF, bubbleTextDark: 0xFFFFFF,
            accentLight: 0x23272B, accentDark: 0xC9D1D9,
            tintLight: 0xECEEF0, tintDark: 0x1E2429
        ),
        ChatTheme(
            id: "greige", displayName: "米灰",
            bubbleLight: 0xE4DAD1, bubbleDark: 0x6B5B45,
            bubbleTextLight: 0x46392A, bubbleTextDark: 0xFFF7EA,
            accentLight: 0x84643F, accentDark: 0xC9A87C,
            tintLight: 0xF4EEE5, tintDark: 0x262019
        ),
        ChatTheme(
            id: "skyBlue", displayName: "天蓝",
            bubbleLight: 0xB8DAFD, bubbleDark: 0x1663AC,
            bubbleTextLight: 0x103A5E, bubbleTextDark: 0xFFFFFF,
            // 0.41.0（浅档专项，§66.1 候选 (a)）：同色
            // 相加深一档 0x0B74BC→0x0A6BAE（对 tint-
            // Light 4.31→4.90），理由同默认款注
            accentLight: 0x0A6BAE, accentDark: 0x6FB3EE,
            tintLight: 0xE3F1FD, tintDark: 0x132636
        ),
        ChatTheme(
            id: "lavender", displayName: "浅紫",
            bubbleLight: 0xDBC6F1, bubbleDark: 0x5E4FA3,
            bubbleTextLight: 0x3B2A63, bubbleTextDark: 0xFFFFFF,
            accentLight: 0x6440C8, accentDark: 0xA78BFA,
            tintLight: 0xF0EEFA, tintDark: 0x221F31
        ),
        ChatTheme(
            id: "pink", displayName: "粉",
            bubbleLight: 0xFDB9DE, bubbleDark: 0x9E3565,
            bubbleTextLight: 0x6E2147, bubbleTextDark: 0xFFFFFF,
            accentLight: 0xBC3A78, accentDark: 0xF28BBD,
            tintLight: 0xFDEDF4, tintDark: 0x2C1A22
        ),
        ChatTheme(
            id: "peach", displayName: "蜜桃",
            bubbleLight: 0xFFD7B5, bubbleDark: 0x9E5A1C,
            bubbleTextLight: 0x65350F, bubbleTextDark: 0xFFFFFF,
            // 0.41.0（浅档专项，§66.1 候选 (a)）：同色
            // 相加深一档 0xAC5A12→0xA55611（对 tint-
            // Light 4.43→4.73），理由同默认款注
            accentLight: 0xA55611, accentDark: 0xF5A95C,
            tintLight: 0xFDF0DF, tintDark: 0x2B2113
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

/// 外观三组持久化键（0.26.0 登记）：appearanceMode
/// （0.4.0 既有键、不改名不迁移，老用户已选值原样保
/// 留）、chatTheme、avatarSize。本枚举是键名的单一
/// 出处——AppStorage 与 UserDefaults 读口都引此，
/// 不许再散写字面量。
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
}
