import OneDayCore
import SwiftUI

// MARK: - 语义色角色层（0.6.1：OpenMuse 令牌接管）
// 沿革：0.4.0 降级为系统语义色命名引用层 → **0.6.1 起整表
// 改挂 OpenMuse 设计令牌**：用户 2026-11-09 15:07 亲令
// 「UI 风格和配色用 OpenMuse 的」——旧封存口径（主题蓝
// #0052D9、助手泡 #E9EAEC／用户泡 #F0F0F2、笔芯量测
// #262626、选中 #EEEFF1 等）自本版正式让位，不再回潮。
// 浅色值逐一取自 OpenMuse 源码（openmuse-build/apps/
// mobile/src/ui.tsx 的 colors 表与各组件内联样式，对照
// 表见 docs 外档 openmuse-token-map-20261109.md）；它
// **没有暗色令牌**（全仓单套浅色），暗色值按其冷蓝灰语
// 言逐项派生、在每条注释里明标「派生」，不冒充原值。
// 系统语义色挂接随本版退役：色值全部字面直给（动态色
// 按 traits 解析），防系统灰阶的蓝紫漂移重演（0.4.1
// 第 6 修的教训改以钉值单测守，见 RenderMeasureTests）。
/// OpenMuse 令牌动态色构造：浅色取它源码原值，暗色取
/// 同色相派生值（注释逐项注明）。
private func omColor(
    light: (CGFloat, CGFloat, CGFloat),
    dark: (CGFloat, CGFloat, CGFloat)
) -> Color {
    Color(
        UIColor { traits in
            let v = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: v.0, green: v.1, blue: v.2, alpha: 1)
        }
    )
}

private func omHex(_ hex: UInt32) -> (CGFloat, CGFloat, CGFloat) {
    (
        CGFloat((hex >> 16) & 0xFF) / 255.0,
        CGFloat((hex >> 8) & 0xFF) / 255.0,
        CGFloat(hex & 0xFF) / 255.0
    )
}

/// 0.26.0 主题双档色：自 Core 主题表的一对十六进制值
/// 拼装——与 omColor 同机制（浅/暗随 traits 取档），
/// 只是值来自当前主题而非编译期常量。
private func themedColor(light: UInt32, dark: UInt32) -> Color {
    omColor(light: omHex(light), dark: omHex(dark))
}

public enum Palette {
    /// 页面底（OpenMuse canvas #FCFCFC，ui.tsx:19；
    /// 暗色派生：以其 text #11191C 再压一档 #101619 作底）
    public static let pageBG = omColor(
        light: omHex(0xFCFCFC), dark: omHex(0x101619)
    )
    /// 卡面（OpenMuse card #FFFFFF，ui.tsx:20；暗色派生
    /// #1B2226＝底上提一级的同色相面）
    public static let surface = omColor(
        light: omHex(0xFFFFFF), dark: omHex(0x1B2226)
    )
    /// 助手泡（OpenMuse 助手泡 #EEEEF0，chat.tsx:593；
    /// 暗色派生 #272E33）
    public static let bubbleFill = omColor(
        light: omHex(0xEEEEF0), dark: omHex(0x272E33)
    )
    /// 字段面（OpenMuse input 底 #FFF，ui.tsx:62；暗色
    /// 派生随卡面 #1B2226）
    public static let fieldFill = omColor(
        light: omHex(0xFFFFFF), dark: omHex(0x1B2226)
    )
    /// 聊天表面（OpenMuse canvas #FCFCFC——与 0.4.1 第 10
    /// 修的量测封存值恰同，出处自本版换为它的令牌；
    /// 暗色派生随页面底 #101619）
    public static let chatSurface = omColor(
        light: omHex(0xFCFCFC), dark: omHex(0x101619)
    )
    /// 选中填充（OpenMuse 底栏激活项 #F0F1F2，App.tsx:
    /// 464——取代 0.4.1 封存的 #EEEFF1；暗色派生 #232B30）
    public static let selectionFill = omColor(
        light: omHex(0xF0F1F2), dark: omHex(0x232B30)
    )
    /// 设置页底（0.20.0，用户给的 Muse 设置页真机图
    /// 口径：浅灰底托白色分组卡，图中约 #F2F2F4 级）：
    /// 取 iOS 系统分组底同族 #F2F2F7 落点（与图中采样
    /// 差在测量噪声内、且与系统 insetGrouped 语言同
    /// 源）；暗色派生 #0D1214（页面底再压一档的冷灰）
    public static let settingsBG = omColor(
        light: omHex(0xF2F2F7), dark: omHex(0x0D1214)
    )
    /// 浮层面（OpenMuse 浮件＝白卡，ui.tsx card #FFFFFF；
    /// 暗色派生随卡面）
    public static let floatFill = omColor(
        light: omHex(0xFFFFFF), dark: omHex(0x1B2226)
    )
    /// 当前聊天主题（0.26.0）：Palette 主题角色的读
    /// 口——每次求值现读 UserDefaults（主题变更后
    /// RootView/聊天页的 AppStorage 观察触发重渲、重
    /// 新求值即新值；单一真源＝Core ChatThemes 表）
    public static var currentChatTheme: ChatTheme {
        AppearancePreferences.chatTheme()
    }

    /// 用户泡（OpenMuse 用户泡＝colors.blue #C8E7FF，
    /// chat.tsx:593——浅蓝填充是它聊天页的标志面，旧封存
    /// #F0F0F2 自本版让位；暗色取其 blueDark #1473C8 原值
    /// 作深档，保其上浅字对比）
    /// 0.26.0 起主题化：值自当前主题表——默认「三狗」
    /// 行与上述旧值逐字相同，切回默认即回原貌。
    public static var userBubbleFill: Color {
        let theme = currentChatTheme
        return themedColor(
            light: theme.bubbleLight, dark: theme.bubbleDark
        )
    }

    /// 用户泡上的文字（0.26.0 新增）：默认「三狗」浅
    /// 档＝主墨 #11191C（与此前 bodyInk 呈现一致）；暗
    /// 档＝纯白——此前泡上字走 bodyInk 暗档反演墨
    /// #EDF1F3、对暗泡实算对比仅 4.28 压线，本版随主
    /// 题表修正为 4.87（§53 登记）
    public static var userBubbleText: Color {
        let theme = currentChatTheme
        return themedColor(
            light: theme.bubbleTextLight,
            dark: theme.bubbleTextDark
        )
    }

    // 抽屉纱（0.4.1 第 10 修量测对齐，例外 E5 自有形态）：
    // OpenMuse 无对应物（它的 modalShade 是模态遮罩、非
    // 抽屉纱），本值保留不动——0.4.0 的白 0.55 在采样里
    // 近乎无纱，改均匀浅灰白纱 #F4F4F6 @ 0.66，模糊由视
    // 图侧 ultraThinMaterial 承担；暗色维持黑纱 0.50
    public static let scrim = Color(
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.black.withAlphaComponent(0.50)
                : UIColor(
                    red: 0xF4 / 255.0, green: 0xF4 / 255.0,
                    blue: 0xF6 / 255.0, alpha: 0.66
                )
        }
    )

    /// 主墨（OpenMuse text #11191C，ui.tsx:21；暗色派生
    /// 反演 #EDF1F3）
    public static let ink = omColor(
        light: omHex(0x11191C), dark: omHex(0xEDF1F3)
    )
    /// 消息正文墨（OpenMuse 正文与框架同色 text #11191C、
    /// 16pt/24 行高，chat.tsx:597——0.4.4 的笔芯量测口径
    /// #262626 自本版让位：它正文不另设弱墨；暗色派生
    /// 随主墨 #EDF1F3）
    public static let bodyInk = omColor(
        light: omHex(0x11191C), dark: omHex(0xEDF1F3)
    )
    /// 次墨（OpenMuse muted #697176，ui.tsx:22；暗色派生
    /// 亮化 #9AA3A8）
    /// 0.36.0（无障碍 A11Y-C1）：浅档同色相加深一档至
    /// #646B71——原值落设置页底 #F2F2F7 实算 4.46:1
    /// 压线下，新值三面实算：设置底 4.85／页面底
    /// 5.27／卡面 5.41，全过 4.5（闸在
    /// VisualDirectionGateTests）
    public static let inkSecondary = omColor(
        light: omHex(0x646B71), dark: omHex(0x9AA3A8)
    )
    /// 弱墨（OpenMuse 三档弱色无独立令牌，取其输入占位
    /// 色 #949B9F 为实证弱档，chat.tsx:948；暗色派生
    /// #6E777D）
    /// 0.23.0（审计 G1）：实算对比 2.75:1 不达文字线，
    /// 本色自本版起**只许非文字用途**（占位符/禁用态/
    /// 装饰字形/状态点/纯填充），一切要读的字走 ink 或
    /// inkSecondary；文字位清零由 §50 的 grep 清单把守
    public static let inkMuted = omColor(
        light: omHex(0x949B9F), dark: omHex(0x6E777D)
    )
    /// 填充面次墨（0.23.0，审计 C4）：inkSecondary 落在
    /// 助手泡 #EEEEF0 上实算 4.29:1 压线下——泡内/填
    /// 充面上的次级文字专用加深档 #5F666B（在 #EEEEF0
    /// 上实算 5.04:1，WCAG 公式自证复算 5.035）；暗色
    /// 派生随暗色 inkSecondary #9AA3A8（在暗色泡
    /// #272E33 上实算 5.36:1）
    public static let inkSecondaryOnFill = omColor(
        light: omHex(0x5F666B), dark: omHex(0x9AA3A8)
    )
    /// 发丝线（OpenMuse line #EEEEF0，ui.tsx:23——与助
    /// 手泡同 hex 是它源码本貌；暗色派生 #262E33）
    public static let hairline = omColor(
        light: omHex(0xEEEEF0), dark: omHex(0x262E33)
    )

    /// 分隔线色（0.36.0，宪法 §3／审计 C2）：改挂系
    /// 统 separator 语义色——浅 (60,60,67,α0.29)／
    /// 暗 (84,84,88,α0.60)，α 定义使其压在任何层
    /// 级的面上都保持可辨（旧 hairline 实色平移在暗
    /// 档对卡面仅 1.17:1 近乎消失，审计 D4）。本色
    /// 是 0.6.1「字面直给」旧口径的宪法级例外：α 体
    /// 系即其定义本身、字面 hex 无法表达跨面自适
    /// 应，故按 §3 口径改挂语义色（S19：宪法为单一
    /// 真源）；暗档取值与批一B 同源、由批一B 真机
    /// 验收收口，本处不另定第二套值。GroupDivider
    /// 专用；odGroup 描边仍走 hairline（C3/D4 归批
    /// 一B/批三处置）
    public static let separator = Color(UIColor.separator)

    /// 强调（OpenMuse blueDark #1473C8，ui.tsx:25——链
    /// 接/图标/角标/光标的实色；暗色派生亮化 #5EB1EF）
    /// 0.26.0 起主题化：值自当前主题强调行——默认
    /// 「三狗」行与上述旧值逐字相同。
    public static var primary: Color {
        let theme = currentChatTheme
        return themedColor(
            light: theme.accentLight, dark: theme.accentDark
        )
    }
    /// 强调实填：与 primary 同源同值（0.26.0 前即同
    /// 值双名，本版直接别名化，语义不变）
    public static var primaryFill: Color { primary }
    /// 主填充蓝（OpenMuse blue #C8E7FF，ui.tsx:24——它
    /// 的主按钮面色：浅蓝填充＋深墨字，与用户泡同源；
    /// 暗色取 blueDark #1473C8 作深档）
    /// 0.26.0 起主题化＝主题气泡行（同源关系的字面
    /// 落实：与 userBubbleFill 恒同值）
    public static var primaryPale: Color {
        let theme = currentChatTheme
        return themedColor(
            light: theme.bubbleLight, dark: theme.bubbleDark
        )
    }
    /// 强调弱面（OpenMuse sky #EDF7FD，ui.tsx:26——图
    /// 标盒/附件牌/聚焦钮面；取代旧 accentColor 12% 透
    /// 明度近似值；暗色派生 #16242E）
    /// 0.26.0 起主题化＝主题弱面行（默认值逐字同旧）
    public static var primaryTint: Color {
        let theme = currentChatTheme
        return themedColor(
            light: theme.tintLight, dark: theme.tintDark
        )
    }
    /// 填充钮上的字色（OpenMuse 主钮文字恒 text
    /// #11191C，浅蓝填充配深字，ui.tsx:77＋s.text；
    /// 消费面恒骑 primaryPale——发送钮/主按钮）
    /// 0.26.0 起主题化＝主题泡字行（浅档与旧值同；
    /// 暗档随泡字修正 #EDF1F3→#FFFFFF，§53）
    public static var onPrimary: Color {
        let theme = currentChatTheme
        return themedColor(
            light: theme.bubbleTextLight,
            dark: theme.bubbleTextDark
        )
    }

    // pastel 点缀家族（OpenMuse 图标盒/chip/状态卡的轮
    // 换底色，ui.tsx:26-29；暗色一律派生压暗同色相面）
    /// 天蓝点缀面（sky #EDF7FD）
    public static let tintSky = omColor(
        light: omHex(0xEDF7FD), dark: omHex(0x16242E)
    )
    /// 绿点缀面（green #E3F3E8）
    public static let tintGreen = omColor(
        light: omHex(0xE3F3E8), dark: omHex(0x17251C)
    )
    /// 紫点缀面（lavender #F0EEFA）
    public static let tintLavender = omColor(
        light: omHex(0xF0EEFA), dark: omHex(0x221F31)
    )
    /// 橙点缀面（orange #FDF0DF）
    public static let tintOrange = omColor(
        light: omHex(0xFDF0DF), dark: omHex(0x2B2113)
    )
    /// 代码面（OpenMuse 行内/块代码底 #E2E4E7，
    /// assistant-response.tsx:17-18；暗色派生 #2B3237）
    public static let codeFill = omColor(
        light: omHex(0xE2E4E7), dark: omHex(0x2B3237)
    )
    /// 错误面（OpenMuse error 底 #FBEFED，ui.tsx:99；
    /// 暗色派生 #33201E）
    public static let errorSurface = omColor(
        light: omHex(0xFBEFED), dark: omHex(0x33201E)
    )

    /// 状态实色：OpenMuse 无 success/warning 语义实色原
    /// 值（它只给 pastel 面），两色保留系统色不编值；
    /// danger 有原值 #AA4A45（ui.tsx:30），落字面（暗色
    /// 派生亮化 #D08B87）
    public static let success = Color.green
    public static let warning = Color.orange
    public static let danger = omColor(
        light: omHex(0xAA4A45), dark: omHex(0xD08B87)
    )

    /// 阴影基色：取 OpenMuse 浮动底栏阴影色 #132631
    /// （App.tsx:443，带蓝黑是它的影语言；阴影色不分
    /// 模式）
    public static let shadowBase = Color(
        red: 0x13 / 255.0, green: 0x26 / 255.0, blue: 0x31 / 255.0
    )

    /// 语义分层别名（0.3.2 与礼记对齐的叫法）：底＝页面
    /// 底色、卡＝分组卡面、浮＝浮层/弹层级表面
    public static var layerPage: Color { pageBG }
    public static var layerCard: Color { surface }
    public static var layerOverlay: Color { bubbleFill }

    public static func stateColor(_ state: String?) -> Color {
        switch state?.lowercased() {
        case "connected", "running", "ok", "ready":
            return success
        case "error", "failed", "disconnected", "stopped":
            return danger
        case "degraded", "warning", "restarting":
            return warning
        default:
            return inkMuted
        }
    }
}

// MARK: - 度量（定版 §3.2/§3.4：4pt 网格、圆角梯队、行高与对齐线）
// 纪律（0.3.2 补，审查 T-4）：每个数有出处——梯队值之外
// 的光学/手势/设备驱动值一律在此具名，不许散落在页面里
// 写字面量（tokenFlowSpacing/drawerEdgeZone 等即此收编）。

public enum OneDayMetrics {
    /// 触摸目标下限 44pt
    public static let minTapTarget: CGFloat = 44

    // 圆角梯队（同心推导的锚点，内层走 CornerRadius.concentric）
    /// 分组容器（0.6.1 改挂 OpenMuse card 圆角 23，
    /// ui.tsx:49）
    public static let containerCorner: CGFloat = 23
    /// 侧边抽屉面板右侧圆角（0.3.6 立宪大圆角，§22）
    public static let drawerCorner: CGFloat = 28
    /// 抽屉内容左右边距（0.3.6：名字/组标签/行标题/
    /// 发丝线同一条 20 线）
    public static let drawerInset: CGFloat = 20
    /// 名单导航行高（0.3.6 实测约 47）
    public static let navRowHeight: CGFloat = 47
    /// 抽屉导航/旁聊行高（0.20.0，用户给的 Muse 抽屉
    /// 真机图推算：选中垫行高约 53、旁聊行距约 58，
    /// 取 58 统一抽屉行档；推算锚点见 DESIGN-V4 §47）
    public static let drawerRowHeight: CGFloat = 58
    /// 设置页行最小高（0.20.0，Muse 设置图推算行距
    /// 约 63 含卡内呼吸，行本体取 60）
    public static let settingsRowHeight: CGFloat = 60
    /// 设置页组间距（0.20.0，图中组间约 28）
    public static let settingsSectionSpacing: CGFloat = 28
    /// 名单行图标字形（0.23.0 单源化：改引用 Core
    /// FrameworkIcon，本处只留别名、不再自带数值）
    public static let navGlyph: CGFloat = FrameworkIcon.navGlyphSize
    /// 底栏字形（0.23.0 单源化：同上，值 22 不变）
    public static let tabGlyph: CGFloat = FrameworkIcon.tabGlyphSize
    /// 抽屉底部浮动条圆钮边长（0.3.6 实测约 52；搜索
    /// 胶囊同高）
    public static let drawerBarButton: CGFloat = 52
    /// 输入字段（0.6.1 改挂 OpenMuse input 圆角 19，
    /// ui.tsx:58）
    public static let fieldCorner: CGFloat = 19
    /// 按钮（0.6.1 改挂 OpenMuse button 圆角 24 近胶囊，
    /// ui.tsx:74）
    public static let buttonCorner: CGFloat = 24
    /// 消息气泡（0.6.1：与 OpenMuse 气泡圆角 22 同值，
    /// chat.tsx:590，出处自本版换为它的令牌）
    public static let bubbleCorner: CGFloat = 22
    /// 助手消息气泡（0.6.1：改同 22——OpenMuse 双泡同
    /// 圆角，旧「助手略收 18」口径让位）
    public static let assistantBubbleCorner: CGFloat = 22
    /// 气泡尾角（0.6.1 新增：OpenMuse 靠己侧底角收 7，
    /// chat.tsx:591-592）
    public static let bubbleTailCorner: CGFloat = 7
    /// 输入区胶囊（多行态圆角矩形的圆角，单行态走 Capsule）
    public static let composerCorner: CGFloat = 24
    /// 代码块（正文区内的内容面）
    public static let codeCorner: CGFloat = 10

    /// 页面左右边距（内容页）
    public static let pageGutter: CGFloat = 20
    /// 列表行图标槽宽：全页同一条对齐线（0.24.0 与
    /// 设置/抽屉统一取 30，ListRowSpec.iconSlotWidth
    /// 同值，见 §51）
    public static let iconSlot: CGFloat = 30
    /// 分隔线起点（0.36.0，宪法 §3／审计 C1 定版）：
    /// 整行贯通——起点＝容器左缘、全 App 一个 x
    /// 值，恒 0。旧值 62（边距 20＋槽 30＋间距 12、
    /// 对齐文字）与定版几何相反，自本版退役；显式
    /// 传 inset 的消费点是详情正文内的段落分隔、不
    /// 在此列（各自上下文里核过）
    public static let dividerInset: CGFloat = 0
    /// 内容行最小高（0.3.3 按礼记行口径放大：礼记
    /// MeView.entryLabel minHeight 44＋List 行内边距的实
    /// 效行高约 56；OneDay 自 52 提到 56，行不再挤）
    public static let rowHeight: CGFloat = 56
    /// 列表行图标字形字号（0.3.3 旧注「取 20 semibold」
    /// 与消费点实现不符——Components 两处消费恒为无字
    /// 重声明的 regular 渲染，0.24.0 注记纠正于此、以
    /// 实现为准；槽宽与 dividerInset 推导见上两条）
    /// 0.23.0 单源化：数值改引用 Core FrameworkIcon
    /// .rowGlyphSize（20 不变），本处只留别名
    public static let rowIconGlyph: CGFloat = FrameworkIcon.rowGlyphSize
    /// 主按钮高（0.6.1 改挂 OpenMuse button minHeight
    /// 42，ui.tsx:72）
    public static let primaryButtonHeight: CGFloat = 42
    /// 卡内边距（0.6.1 新增：OpenMuse card padding 20，
    /// ui.tsx:52）
    public static let cardPadding: CGFloat = 20

    // —— 气泡内边距（0.6.1 改挂 OpenMuse 气泡内边距
    // 16/13，chat.tsx:588-589；0.3.2 收编的 14/10 让位）——
    /// 气泡横向内边距（用户泡与助手泡共用）
    public static let bubblePaddingH: CGFloat = 16
    /// 气泡纵向内边距
    public static let bubblePaddingV: CGFloat = 13
    /// 气泡靠边让位：对侧 Spacer 的最小让宽（用户泡左让/
    /// 助手泡右让同值，0.2.5 对齐口径）
    public static let bubbleSideInset: CGFloat = 44

    // —— 梯外具名值（审查 T-4 收编：光学/手势/设备驱动）——
    /// 流式词元流布局的词间/行间距（光学值，TokenFlow 用）
    public static let tokenFlowSpacing: CGFloat = 5
    /// 抽屉左缘唤出热区宽（手势值：够拇指起滑、不挡正文滚动）
    public static let drawerEdgeZone: CGFloat = 24
    /// 抽屉宽占屏比（0.3.6 立宪 peek 口径约 79%；
    /// 0.4.1 第 10 修按用户逐像素采样改约 75%——
    /// Muse 本体抽屉实测占比，§26.10）
    public static let drawerWidthFraction: CGFloat = 0.75
    /// 抽屉宽上限（设备值，大屏不无限拉宽）
    public static let drawerMaxWidth: CGFloat = 340
    /// （tabBarZone 已于 0.4.0 删除，审计 §3.2：底栏回
    /// 原生后底部避让由系统安全区自理，手算占位带退役）
    /// 两行制会话行最小高（0.3.8 第 19 条，与 Core 的
    /// ListRowSpec.sessionRowMinHeight 同值）
    public static let sessionRowHeight: CGFloat = 57

    /// 间距梯队：4/8/12/16/20/24/32/48，只许取梯队值
    public static let spacingXS: CGFloat = 4
    public static let spacingS: CGFloat = 8
    public static let spacingSM: CGFloat = 12
    public static let spacingM: CGFloat = 16
    public static let spacingL: CGFloat = 24
    public static let spacingXL: CGFloat = 32
    public static let spacingXXL: CGFloat = 48
}
