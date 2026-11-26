import OneDayCore
import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

#if os(macOS)
// MARK: - macOS 平台垫片（Mac 地基棒，改动清单在案）
// Palette 的动态色构造在 iOS 走 UIColor traits 解析；
// macOS 无 UIKit，本节以 NSColor 动态供应者等价实现：
// UIColor 别名到 NSColor、语义色名按角色映射到 AppKit
// 语义色。映射是角色等值而非逐值复刻（iOS 暗档的 α 语
// 义在 macOS 以动态 α 近似给值），视觉逐值对齐由后续
// 棒按真机截图验收，不在本棒口径内。
typealias UIColor = NSColor

/// 浅/暗动态 NSColor（按当前外观解析）
private func dynamicNSColor(
    light: NSColor, dark: NSColor
) -> NSColor {
    NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? dark : light
    }
}

/// 把（可能是动态的）NSColor 在暗外观下解析成 sRGB 分量
private func resolvedDarkSRGB(
    _ color: NSColor
) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
    var rgba: (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 1)
    NSAppearance(named: .darkAqua)?.performAsCurrentDrawingAppearance {
        if let resolved = color.usingColorSpace(.sRGB) {
            rgba = (
                resolved.redComponent, resolved.greenComponent,
                resolved.blueComponent, resolved.alphaComponent
            )
        }
    }
    return rgba
}

extension NSColor {
    static var systemBackground: NSColor { .windowBackgroundColor }
    static var secondarySystemBackground: NSColor {
        .controlBackgroundColor
    }
    static var tertiarySystemBackground: NSColor {
        dynamicNSColor(
            light: NSColor(
                red: 0xF2 / 255.0, green: 0xF2 / 255.0,
                blue: 0xF7 / 255.0, alpha: 1
            ),
            dark: NSColor(
                red: 0x2C / 255.0, green: 0x2C / 255.0,
                blue: 0x2E / 255.0, alpha: 1
            )
        )
    }
    static var systemGroupedBackground: NSColor {
        .windowBackgroundColor
    }
    // fill 四级：基色 (120,120,128)＋α 阶梯，与 iOS 语义
    // 档同口径近似（浅 0.20/0.16/0.12/0.08、暗 0.36 起）
    static var systemFill: NSColor {
        dynamicNSColor(
            light: NSColor(white: 120.0 / 255.0, alpha: 0.20),
            dark: NSColor(white: 120.0 / 255.0, alpha: 0.36)
        )
    }
    static var secondarySystemFill: NSColor {
        dynamicNSColor(
            light: NSColor(white: 120.0 / 255.0, alpha: 0.16),
            dark: NSColor(white: 120.0 / 255.0, alpha: 0.32)
        )
    }
    static var tertiarySystemFill: NSColor {
        dynamicNSColor(
            light: NSColor(white: 120.0 / 255.0, alpha: 0.12),
            dark: NSColor(white: 120.0 / 255.0, alpha: 0.28)
        )
    }
    static var quaternarySystemFill: NSColor {
        dynamicNSColor(
            light: NSColor(white: 120.0 / 255.0, alpha: 0.08),
            dark: NSColor(white: 120.0 / 255.0, alpha: 0.24)
        )
    }
    static var separator: NSColor { .separatorColor }
    static var opaqueSeparator: NSColor { .separatorColor }
    static var label: NSColor { .labelColor }
    static var secondaryLabel: NSColor { .secondaryLabelColor }
    static var tertiaryLabel: NSColor { .tertiaryLabelColor }
    static var quaternaryLabel: NSColor { .quaternaryLabelColor }
}
#endif

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
// 0.36.1 口径变更（批一B／审计 D1–D6）：上段「字面直
// 给」自本版起只辖浅档——暗档整表改挂苹果语义体系
// （见 appleColor 注），派生色板退役；防漂移改由解析
// 值钉＋合成对比闸把守。浅档 OpenMuse 原值一字未动。
/// OpenMuse 令牌动态色构造：浅色取它源码原值，暗色取
/// 同色相派生值（注释逐项注明）。
private func omColor(
    light: (CGFloat, CGFloat, CGFloat),
    dark: (CGFloat, CGFloat, CGFloat)
) -> Color {
    #if os(iOS)
    Color(
        UIColor { traits in
            let v = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: v.0, green: v.1, blue: v.2, alpha: 1)
        }
    )
    #else
    Color(
        NSColor(name: nil) { appearance in
            let v = appearance.bestMatch(from: [.darkAqua, .aqua])
                == .darkAqua ? dark : light
            return NSColor(red: v.0, green: v.1, blue: v.2, alpha: 1)
        }
    )
    #endif
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

/// 苹果语义档构造（0.36.1，批一B／审计 D1–D6）：浅档
/// 仍取 OpenMuse 原值字面（浅色已定版、本批不动），
/// 暗档改挂 UIKit 语义色——构造时以暗 traits 解析为
/// 具体值（含 α）直给。α 定义的档（标签/fill）渲染时
/// 压在任何面上按比例自适应，这正是语义体系的本义、
/// 字面 hex 无法表达：0.6.1「色值全部字面直给」旧口
/// 径自本版起只辖浅档，暗档整表归苹果语义体系（用户
/// 2026-11-10 17:20 总原则＋S19 宪法为单一真源）。
/// 防漂移不再靠钉字面值：改由 RenderMeasureTests 的
/// 解析值钉＋VisualDirectionGateTests 的合成对比闸
/// 把守（双模式）。回滚基线＝本文件单文件回退。
private func appleColor(
    light: UInt32, dark: UIColor, lightHighContrast: UInt32? = nil
) -> Color {
    #if os(macOS)
    // macOS 等价实现：暗档语义色先在暗外观下解析成具体
    // sRGB 值（与 iOS 的 resolvedColor 同义），再按外观
    // 动态取档；浅档高对比变体按高对比外观取档
    let darkResolved = resolvedDarkSRGB(dark)
    let (lr, lg, lb) = omHex(light)
    let hc = lightHighContrast.map(omHex)
    return Color(
        NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua])
                == .darkAqua {
                return NSColor(
                    red: darkResolved.0, green: darkResolved.1,
                    blue: darkResolved.2, alpha: darkResolved.3
                )
            }
            if let hc,
               appearance.bestMatch(
                   from: [.accessibilityHighContrastAqua, .aqua]
               ) == .accessibilityHighContrastAqua {
                return NSColor(
                    red: hc.0, green: hc.1, blue: hc.2, alpha: 1
                )
            }
            return NSColor(red: lr, green: lg, blue: lb, alpha: 1)
        }
    )
    #else
    let darkResolved = dark.resolvedColor(
        with: UITraitCollection(userInterfaceStyle: .dark)
    )
    let (lr, lg, lb) = omHex(light)
    // 高对比变体（0.43.0，无障碍专项 A11Y-S5）：仅
    // 系统「增加对比度」开启且浅档时生效——动态色
    // 的 traits 本就带 accessibilityContrast，变体
    // 在解析层一步到位、消费点零改动；默认设置下
    // 解析值与旧值逐字相同（视觉零变化，闸在
    // AccessibilityPackageTests）。暗档的语义色
    // （label 族/system 色）由系统自带高对比调整、
    // 不在此重复设变体
    let hc = lightHighContrast.map(omHex)
    return Color(
        UIColor { traits in
            if traits.userInterfaceStyle == .dark {
                return darkResolved
            }
            if traits.accessibilityContrast == .high, let hc {
                return UIColor(
                    red: hc.0, green: hc.1, blue: hc.2, alpha: 1
                )
            }
            return UIColor(red: lr, green: lg, blue: lb, alpha: 1)
        }
    )
    #endif
}

public enum Palette {
    /// 页面底（OpenMuse canvas #FCFCFC，ui.tsx:19；
    /// 暗档 0.36.1 改挂 systemBackground＝纯黑 #000——
    /// 审计 D1：旧派生 #101619 是带蓝灰的「灰雾」基底、
    /// 与 settingsBG 双基底并存（互比 1.03），自本版
    /// 基底身份归一为语义 base 锚）
    /// dp-214：浅档 #FCFCFC→#FFFFFF（systemBackground
    /// 逐值对齐，Δ2 口径收敛）
    public static let pageBG = appleColor(
        light: 0xFFFFFF, dark: .systemBackground
    )
    /// 卡面（OpenMuse card #FFFFFF，ui.tsx:20；暗档
    /// secondarySystemBackground #1C1C1E——层级步对齐
    /// 苹果梯：#000→#1C1C1E 步幅 1.23:1，旧派生
    /// #1B2226 步幅被压缩且全程带蓝，审计 D2）
    public static let surface = appleColor(
        light: 0xFFFFFF, dark: .secondarySystemBackground
    )
    /// AI 底衬卡面（§503 改判：原「助手泡」#EEEEF0——
    /// OpenMuse chat.tsx:593 旧值自本版让位给用户
    /// 18:36 终裁的 Muse 式全宽卡：浅 #E9EAEC＝Muse
    /// 本 App 逐像素实测、暗 #2C2C2E＝原语义三级面定
    /// 值）。§503 起本令牌归当前主题整包辖（读主题
    /// aiCard 行：默认款即上述两值、微信款浅档为收泡
    /// 取样 #FFFFFF）；消费面＝助手卡本体及一切助手
    /// 承载面（附件面板/交付卡/图片行衬底同源跟随）
    public static var bubbleFill: Color {
        let theme = currentChatTheme
        return themedColor(
            light: theme.aiCardLight, dark: theme.aiCardDark
        )
    }
    /// 字段面（OpenMuse input 底 #FFF，ui.tsx:62；暗档
    /// 同取三级面 #2C2C2E——字段恒落在页底/卡面上、
    /// 取高一级使输入区在两面都可辨）
    public static let fieldFill = appleColor(
        light: 0xFFFFFF, dark: .tertiarySystemBackground
    )
    /// 聊天表面（OpenMuse canvas #FCFCFC；暗档随页面
    /// 底同锚 systemBackground #000）
    /// dp-214：浅档 #FCFCFC→#FFFFFF（与 pageBG 同步收敛）
    public static let chatSurface = appleColor(
        light: 0xFFFFFF, dark: .systemBackground
    )
    /// 聊天页背景（台账 179，OB-I1，DESIGN §391）：只供
    /// 聊天页背景层现读——默认档与 chatSurface 逐值相
    /// 同；雾灰/石板为冷中性灰阶（浅/暗成对）。抽屉、
    /// 接缝等共用 chatSurface 的面不读本口、恒守定版
    public static var chatBackground: Color {
        switch AppearancePreferences.backgroundStyle() {
        case .theme:
            // §503「跟随主题」：当前主题整包的背景行
            let theme = currentChatTheme
            return themedColor(
                light: theme.backgroundLight,
                dark: theme.backgroundDark
            )
        case .standard:
            return chatSurface
        case .mist:
            return themedColor(light: 0xF0F0F2, dark: 0x111113)
        case .slate:
            return themedColor(light: 0xE6E6EA, dark: 0x1A1A1E)
        case .wechatGray:
            // §503 取样值：浅 #EDEDED（WeUI --weui-
            // BG-0）；暗档无取样、沿用雾灰暗值
            return themedColor(light: 0xEDEDED, dark: 0x111113)
        case .gptGray:
            // §503 取样值：浅 #F4F4F4（ChatGPT 浅面）；
            // 暗档无取样、沿用石板暗值
            return themedColor(light: 0xF4F4F4, dark: 0x1A1A1E)
        case .dots, .grid, .diagonal:
            // 图案档的底色＝定版面；纹理由 ChatBack-
            // groundSurface 在本色之上叠绘（单源）
            return chatSurface
        }
    }
    /// 抽屉接缝中间层底（§351）：深色开态卡面横向
    /// 内缩露出的中间带读本色——深 #191919 出处＝
    /// 2026-11-22 用户 Muse 真机视频定格量测
    /// （接缝三段台阶：抽屉面 #000000 → 中间带
    /// lum≈24 ≈ #191919、宽约 14–16pt → 卡面
    /// #2C2C2E，见 DrawerCardGeometry.darkCard-
    /// LeadingInset）；浅档与 pageBG 同值 #FCFCFC
    /// ——浅色该带即旧容器底色、视觉零变化（浅色
    /// 接缝层次走 §345 柔影、不走本层）
    public static let drawerBackdrop = appleColor(
        light: 0xFCFCFC, dark: UIColor(white: 25.0 / 255.0, alpha: 1)
    )
    /// 选中填充（OpenMuse 底栏激活项 #F0F1F2，App.tsx:
    /// 464；暗档 0.36.1 改挂 systemFill (120,120,128，
    /// α 为系统常量、暗档实测 0.36)——压卡面合成实算
    /// ≈1.6:1，旧派生 #232B30 仅 1.12:1 暗档几乎不可
    /// 辨，审计 D5；本色即 fill 四级阶梯的一级，见下
    /// 方 fillPrimary）
    public static let selectionFill = appleColor(
        light: 0xF0F1F2, dark: .systemFill
    )
    /// 抽屉专用选中填充（§225，Muse 对齐三项包）：
    /// 本令牌只供抽屉三行（导航/频道/旁聊当前行）
    /// 选中垫。浅档沿革：§225 取 #E4E5E7（当时面板
    /// 为 thinMaterial 合成面、需加深才立得住）；
    /// 2026-11-21 抽屉样板对齐包改 #EEEFF1——§318
    /// 后面板已是 chatSurface 实色 #FCFCFC，用户亲
    /// 递 Muse 现行版截图三点采样选中胶囊正是
    /// #EEEFF1 压 #FCFCFC（逐通道 Δ14/13/11），直
    /// 接落样板原值、不再加深。暗档挂 tertiary-
    /// SystemBackground #2C2C2E 不变——压纯黑面板
    /// Δ44、与浅档「面上一档灰」语义等值（样板无
    /// 深色图、按角色等值口径，见交卷报告）。selec-
    /// tionFill 本体与其余消费面不动
    public static let drawerSelectionFill = appleColor(
        light: 0xEEEFF1, dark: .tertiarySystemBackground
    )
    /// 抽屉分区头墨（2026-11-21 样板对齐包）：只供
    /// 抽屉分区头与折叠态「显示」字样。浅档 #9D9DA2
    /// ——样板分组头核心色三点采样 #9FA0A2/#9D9DA2、
    /// 「显示」#9B9C9E，同值落点。明示代价：本色压
    /// 面板 #FCFCFC 对比约 2.6:1、不达 4.5 文字线
    /// ——0.22.0 审计 G1/D2 正是因此把分区头自弱墨
    /// 换到 inkSecondary（5.27:1）；本包按用户
    /// 2026-11-21「颜色也要学」亲令只在**抽屉分区
    /// 头**这一处回退到样板原值（装饰性导航标签、
    /// 非正文），其余一切要读的字仍守 inkSecondary
    /// 纪律、本令牌不许外溢。暗档挂 secondaryLabel
    /// （压纯黑合成约 #8E8E96、对比约 6.9:1 自达
    /// 标）——样板无深色图、按角色等值口径
    public static let drawerSectionInk = appleColor(
        light: 0x9D9DA2, dark: .secondaryLabel
    )
    /// 抽屉组间发丝线色（2026-11-21 样板对齐包）：
    /// 只供抽屉 drawerDivider。浅档 #E3E3E3——样板
    /// 分隔线核心色采样 #E2E2E2/#E3E3E3，压实色面
    /// 板 #FCFCFC 逐通道 Δ25/25/25、淡但可辨
    /// （样板本体即此观感）。沿革：抽屉线旧挂
    /// Palette.separator（α 语义、压本面合成约
    /// #C4C4C8、Δ约 56）——那是 0.36.x 材质面板时
    /// 代「发丝线不可见」（用户 05:34 点题）后的加
    /// 强档；§318 面板改实色后前提已变、本包按样
    /// 板原值回落本令牌，全 App 其余分隔仍走
    /// separator 单源不动。暗档挂 opaqueSeparator
    /// #38383A（与 hairline 暗档同值、压纯黑 Δ56
    /// 同级可辨）
    public static let drawerHairline = appleColor(
        light: 0xE3E3E3, dark: .opaqueSeparator
    )
    /// 设置页底（0.20.0，用户给的 Muse 设置页真机图
    /// 口径：浅灰底托白色分组卡，图中约 #F2F2F4 级）：
    /// 取 iOS 系统分组底同族 #F2F2F7 落点；暗档 0.36.1
    /// 改挂 systemGroupedBackground＝#000（grouped 体
    /// 系 base 与 systemBackground 同锚，双基底消除，
    /// 审计 D1）；其上分组卡走 surface #1C1C1E——与
    /// grouped 二级面 secondarySystemGroupedBackground
    /// 暗值同为 #1C1C1E，层级关系由此定）
    public static let settingsBG = appleColor(
        light: 0xF2F2F7, dark: .systemGroupedBackground
    )
    /// 浮层面（OpenMuse 浮件＝白卡，ui.tsx card #FFFFFF；
    /// 暗档 0.36.1 取三级面 #2C2C2E——旧派生与卡面同
    /// 值 #1B2226、浮层零提级层级塌陷，审计 D2）
    public static let floatFill = appleColor(
        light: 0xFFFFFF, dark: .tertiarySystemBackground
    )

    /// fill 四级阶梯（0.36.1，审计 D5）：苹果 systemFill
    /// 四级 α 阶梯双档直挂语义色——选中态/胶囊/输入
    /// 底/弱填充按强度取级（基色同为 (120,120,128)；
    /// α 为系统常量，暗档实测 systemFill 0.36、
    /// secondarySystemFill 0.32），强度由 α 定义、随
    /// 所压面自适应；新消费点一律取此梯，不许再手派
    /// 生填充值。selectionFill 是其一档的历史角色
    /// （浅档保留 OpenMuse 原值、暗档同源 systemFill）
    public static let fillPrimary = Color(UIColor.systemFill)
    public static let fillSecondary = Color(
        UIColor.secondarySystemFill
    )
    public static let fillTertiary = Color(
        UIColor.tertiarySystemFill
    )
    public static let fillQuaternary = Color(
        UIColor.quaternarySystemFill
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
        // 强调色联动（用户 2026-11-25 裁定，TG 口径）：
        // 外观页选了预设强调色时，用户泡＝该强调色（明暗
        // 同值），与链接/勾选/选中同源同色；未设/复位＝
        // 当前主题气泡行（台账 197 定版，处理经 Core 解
        // 析出口，本层不硬编码色值）
        if let override = AppearancePreferences.accentOverride() {
            return themedColor(light: override, dark: override)
        }
        let theme = currentChatTheme
        return themedColor(
            light: theme.bubbleFill(dark: false),
            dark: theme.bubbleFill(dark: true)
        )
    }

    /// 用户泡上的文字（0.26.0 新增）：默认「三狗」浅
    /// 档＝主墨 #11191C（与此前 bodyInk 呈现一致）；暗
    /// 档＝纯白——此前泡上字走 bodyInk 暗档反演墨
    /// #EDF1F3、对暗泡实算对比仅 4.28 压线，本版随主
    /// 题表修正为 4.87（§53 登记）
    public static var userBubbleText: Color {
        // 强调色联动（用户 2026-11-25 裁定）：覆盖态下
        // 泡字按该强调色明度自动取黑/白，保证可读；未
        // 设/复位＝当前主题泡字行（台账 197 定版成对取
        // 值，浅深字/暗现泡字）
        if let override = AppearancePreferences.accentOverride() {
            return contrastText(forHex: override)
        }
        let theme = currentChatTheme
        return themedColor(
            light: theme.bubbleText(dark: false),
            dark: theme.bubbleText(dark: true)
        )
    }

    /// 强调色上的可读文字色（ITU-R BT.601 luma，与
    /// AppearanceView.accentDot 同口径）：亮度 >0.6 取
    /// 黑、否则取白，保证浅/深强调色上字都够对比
    private static func contrastText(forHex hex: UInt32) -> Color {
        let r = Double((hex >> 16) & 0xFF)
        let g = Double((hex >> 8) & 0xFF)
        let b = Double(hex & 0xFF)
        let luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
        return luminance > 0.6 ? Color.black : Color.white
    }

    // 抽屉纱（0.4.1 第 10 修量测对齐，例外 E5 自有形态）：
    // OpenMuse 无对应物（它的 modalShade 是模态遮罩、非
    // 抽屉纱），本值保留不动——0.4.0 的白 0.55 在采样里
    // 近乎无纱，改均匀浅灰白纱 #F4F4F6 @ 0.66，模糊由视
    // 图侧 ultraThinMaterial 承担；暗色维持黑纱 0.50
    public static var scrim: Color {
        #if os(iOS)
        return Color(
            UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor.black.withAlphaComponent(0.50)
                    : UIColor(
                        red: 0xF4 / 255.0, green: 0xF4 / 255.0,
                        blue: 0xF6 / 255.0, alpha: 0.66
                    )
            }
        )
        #else
        return Color(
            NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua])
                    == .darkAqua
                    ? NSColor.black.withAlphaComponent(0.50)
                    : NSColor(
                        red: 0xF4 / 255.0, green: 0xF4 / 255.0,
                        blue: 0xF6 / 255.0, alpha: 0.66
                    )
            }
        )
        #endif
    }

    /// 主墨（OpenMuse text #11191C，ui.tsx:21；暗档
    /// 0.36.1 改挂 label＝纯白 #FFFFFF，审计 D3）
    public static let ink = appleColor(
        light: 0x11191C, dark: .label
    )
    /// 消息正文墨（OpenMuse 正文与框架同色 text #11191C、
    /// 16pt/24 行高，chat.tsx:597——0.4.4 的笔芯量测口径
    /// #262626 自本版让位：它正文不另设弱墨；暗档随
    /// 主墨同挂 label）
    public static let bodyInk = appleColor(
        light: 0x11191C, dark: .label
    )
    /// 次墨（OpenMuse muted #697176，ui.tsx:22）
    /// 0.36.0（无障碍 A11Y-C1）：浅档同色相加深一档至
    /// #646B71——原值落设置页底 #F2F2F7 实算 4.46:1
    /// 压线下，新值三面实算：设置底 4.85／页面底
    /// 5.27／卡面 5.41，全过 4.5（闸在
    /// VisualDirectionGateTests）
    /// 0.36.1：暗档改挂 secondaryLabel (235,235,245,
    /// α0.60)——合成实算：页底 6.36／卡面 5.94／泡
    /// 面 5.29，随面自适应（旧实色 #9AA3A8 换面漂移
    /// 7.11→5.36 靠补丁档逐面救，审计 D3）
    /// 0.43.0（A11Y-S5）：浅档高对比变体 #43494E
    /// （同色相加深）——增加对比度开启时三面实算：
    /// 设置底 8.18／页面底 8.89／卡面 9.12，全过
    /// 7:1（WCAG 增强级）；默认解析不变（见
    /// appleColor 注）
    public static let inkSecondary = appleColor(
        light: 0x646B71, dark: .secondaryLabel,
        lightHighContrast: 0x43494E
    )
    /// 弱墨（OpenMuse 三档弱色无独立令牌，取其输入占位
    /// 色 #949B9F 为实证弱档，chat.tsx:948）
    /// 0.23.0（审计 G1）：实算对比 2.75:1 不达文字线，
    /// 本色自本版起**只许非文字用途**（占位符/禁用态/
    /// 装饰字形/状态点/纯填充），一切要读的字走 ink 或
    /// inkSecondary；文字位清零由 §50 的 grep 清单把守
    /// 0.36.1：暗档改挂 tertiaryLabel (235,235,245,
    /// α0.30)——旧派生 #6E777D 比浅档更暗（对页底仅
    /// 4.00:1）、与 α 体系方向相反（审计 D3）；新档
    /// 合成值随所压面走、身份由 α 定义。角色纪律不
    /// 变（仍只许非文字用途）
    public static let inkMuted = appleColor(
        light: 0x949B9F, dark: .tertiaryLabel
    )
    /// 四级墨（0.36.1 新设，审计 D3 标签四级补齐）：
    /// quaternaryLabel 双档直挂语义色（暗档 α 系统
    /// 实测 40/255）——时间戳级、占位级的最弱档，此
    /// 前无处安放只能借 inkMuted 硬凑；本色是新令
    /// 牌、双档皆语义（无旧浅档可守）
    public static let inkQuaternary = Color(
        UIColor.quaternaryLabel
    )
    /// 填充面次墨（0.23.0，审计 C4）：inkSecondary 落在
    /// 助手泡 #EEEEF0 上实算 4.29:1 压线下——泡内/填
    /// 充面上的次级文字专用加深档 #5F666B（在 #EEEEF0
    /// 上实算 5.04:1，WCAG 公式自证复算 5.035）；暗档
    /// 0.36.1 随 inkSecondary 同挂 secondaryLabel——泡
    /// 面语义化后 α 自适应合成实算 5.29:1 达标，补丁
    /// 档在暗档退化为同源（浅档专用加深值不变）
    public static let inkSecondaryOnFill = appleColor(
        light: 0x5F666B, dark: .secondaryLabel
    )
    /// 发丝线（OpenMuse line #EEEEF0，ui.tsx:23——与助
    /// 手泡同 hex 是它源码本貌；暗档 0.36.1 改挂
    /// opaqueSeparator #38383A——旧派生 #262E33 对卡
    /// 面仅 1.17:1 近乎消失，新档实算 1.45:1，审计
    /// D4 的 odGroup 描边侧收口；GroupDivider 本体走
    /// Palette.separator 语义 α，两路同属语义体系）
    public static let hairline = appleColor(
        light: 0xEEEEF0, dark: .opaqueSeparator
    )

    /// 分隔线色（0.36.0，宪法 §3／审计 C2）：改挂系
    /// 统 separator 语义色——浅 (60,60,67,α0.29)／
    /// 暗 (84,84,88,α0.60)，α 定义使其压在任何层
    /// 级的面上都保持可辨（旧 hairline 实色平移在暗
    /// 档对卡面仅 1.17:1 近乎消失，审计 D4）。本色
    /// 是 0.6.1「字面直给」旧口径的宪法级例外：α 体
    /// 系即其定义本身、字面 hex 无法表达跨面自适
    /// 应，故按 §3 口径改挂语义色（S19：宪法为单一
    /// 真源）。GroupDivider 专用；odGroup 描边走
    /// hairline（其暗档已于 0.36.1 随批一B 改挂
    /// opaqueSeparator 收口，D4）
    public static let separator = Color(UIColor.separator)

    /// 强调（OpenMuse blueDark #1473C8，ui.tsx:25——链
    /// 接/图标/角标/光标的实色；暗色派生亮化 #5EB1EF）
    /// 0.26.0 起主题化：值自当前主题强调行——默认
    /// 「三狗」行浅档 0.41.0 起按浅档专项加深一档
    /// （0x1473C8→0x136FC1，2026-11-15 第 85 条再深
    /// 一档至 0x1268B8——压助手泡面 #EEEEF0 4.45 差
    /// 线 0.05，见 ChatTheme 注），与上述旧值脱钩是
    /// 本意；暗档仍逐字相同。
    public static var primary: Color {
        // §503 强调覆盖（TG accent 参数同构）：用户在
        // 外观页选了预设色点时覆盖优先（明暗同值——
        // TG 单值口径，特例见 ChatAccentPresets 注）；
        // 未设/复位＝当前主题强调行
        if let override = AppearancePreferences.accentOverride() {
            return themedColor(light: override, dark: override)
        }
        let theme = currentChatTheme
        return themedColor(
            light: theme.accentLight, dark: theme.accentDark
        )
    }
    /// 强调实填：与 primary 同源同值（0.26.0 前即同
    /// 值双名，本版直接别名化，语义不变）
    public static var primaryFill: Color { primary }
    /// 主钮饱和强调色：跟随当前主题与用户自定义强调色
    /// （审批「批准」、点子「开始吧」、目标主钮等全局主按钮统一跟随主题色）
    public static var primarySaturated: Color {
        primary
    }
    /// 主填充蓝（与 userBubbleFill 同源）
    public static var primaryPale: Color {
        userBubbleFill
    }
    /// 强调弱面：有自定义强调色覆盖时取其 14% 浅底，否则读主题弱面行
    public static var primaryTint: Color {
        if let override = AppearancePreferences.accentOverride() {
            return themedColor(light: override, dark: override).opacity(0.14)
        }
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
        // 台账 184/188/197：消费面恒骑 primaryPale
        // ——字色随之别名 userBubbleText（与泡字恒
        // 同值，主按钮字/面配对不脱钩；197 定版后
        // 配对恒为定死填充＋其上字色：浅填＋深字/
        // 暗深饱＋现泡字）
        userBubbleText
    }

    // pastel 点缀家族（OpenMuse 图标盒/chip/状态卡的轮
    // 换底色，ui.tsx:26-29）
    // 0.36.1：暗档改「同色相系统色 α0.20」统一构造——
    // 旧逐个手派生（#16242E/#17251C/#221F31/#2B2113）
    // 强度互不一致、无体系可依（审计 D5）；新构造四
    // 色同 α、随所压面同比例呈现，家族强度由构造一致
    /// 天蓝点缀面（sky #EDF7FD）
    public static let tintSky = appleColor(
        light: 0xEDF7FD,
        dark: UIColor.systemBlue.withAlphaComponent(0.20)
    )
    /// 绿点缀面（green #E3F3E8）
    public static let tintGreen = appleColor(
        light: 0xE3F3E8,
        dark: UIColor.systemGreen.withAlphaComponent(0.20)
    )
    /// 紫点缀面（lavender #F0EEFA）
    public static let tintLavender = appleColor(
        light: 0xF0EEFA,
        dark: UIColor.systemPurple.withAlphaComponent(0.20)
    )
    /// 橙点缀面（orange #FDF0DF）
    public static let tintOrange = appleColor(
        light: 0xFDF0DF,
        dark: UIColor.systemOrange.withAlphaComponent(0.20)
    )
    /// 查找命中词底（§503）：对话内查找激活时正文
    /// 命中词的着色面——成熟会话内查找的通行黄标
    /// （WhatsApp/TG 同族）；浅档实色 #FBE38A、暗
    /// 档随 pastel 家族同构造走系统黄 α0.40（压暗
    /// 泡面仍可辨）
    public static let findMatchFill = appleColor(
        light: 0xFBE38A,
        dark: UIColor.systemYellow.withAlphaComponent(0.40)
    )
    /// 代码面（OpenMuse 行内/块代码底 #E2E4E7，
    /// assistant-response.tsx:17-18；暗档 0.36.1 改走
    /// fill 阶梯二级 secondarySystemFill——压泡面/卡
    /// 面合成步幅约 1.4:1，旧派生 #2B3237 让位）
    public static let codeFill = appleColor(
        light: 0xE2E4E7, dark: .secondarySystemFill
    )

    /// 代码高亮三色（0.36.25，对话渲染补全包）：只分
    /// 关键词／字符串／数字三类着色＋注释走 inkSec-
    /// ondaryOnFill、正文走 bodyInk——克制口径，不设
    /// 彩虹板。实算口径（2026-11-15 第 85 条收口回填，
    /// WCAGContrast 同式）：浅档基面＝codeFill 实色
    /// #E2E4E7——关键词 #A626A4 4.80／字符串 #116329
    /// 5.80／数字 #0550AE 5.96；暗档基面＝codeFill
    /// （secondarySystemFill α0.32）压所托面的合成色
    /// ——压黑 (38,38,41)：7.47／7.49／7.27；压
    /// #1C1C1E (57,57,61)：5.69／5.70／5.54；压
    /// #2C2C2E (68,68,72)：4.80／4.81／4.67，全过
    /// 4.5 小字线。旧注「对白 6.1／暗按 #2C2C2E 实色
    /// 5.8」口径有误（浅档基面错位、暗档漏算 α 叠
    /// 层——关键词旧值 #C792EA 在三级面合成上实算
    /// 仅 4.03），本版一并纠正、关键词暗档同色相提
    /// 亮至 #D0A6F0（落法与 D3 派生档同机制：浅档
    /// 字面、暗档 UIColor 字面经 appleColor 解析）
    public static let codeKeyword = appleColor(
        light: 0xA626A4,
        dark: UIColor(
            red: 0xD0 / 255.0, green: 0xA6 / 255.0,
            blue: 0xF0 / 255.0, alpha: 1
        )
    )
    /// 代码高亮·字符串绿
    public static let codeString = appleColor(
        light: 0x116329,
        dark: UIColor(
            red: 0x98 / 255.0, green: 0xC3 / 255.0,
            blue: 0x79 / 255.0, alpha: 1
        )
    )
    /// 代码高亮·数字蓝
    public static let codeNumber = appleColor(
        light: 0x0550AE,
        dark: UIColor(
            red: 0x79 / 255.0, green: 0xB8 / 255.0,
            blue: 0xFF / 255.0, alpha: 1
        )
    )
    /// 错误面（OpenMuse error 底 #FBEFED，ui.tsx:99；
    /// 暗档 0.36.1 改 systemRed α0.16——随语义红走、
    /// 压任何面上同比例，旧派生 #33201E 让位）
    public static let errorSurface = appleColor(
        light: 0xFBEFED,
        dark: UIColor.systemRed.withAlphaComponent(0.16)
    )

    /// 状态实色（0.36.1，审计 D6 归队系统语义）：
    /// success/warning 改挂 systemGreen/systemOrange
    /// 语义色——旧 Color.green/orange 是 SwiftUI 固定
    /// 色、暗档调整不由苹果体系保证；新档暗值分别为
    /// #30D158/#FF9F0A（提亮保饱和）。danger 浅档保
    /// OpenMuse 原值 #AA4A45（ui.tsx:30），暗档改挂
    /// systemRed #FF453A——旧派生 #D08B87 是「提亮＋
    /// 褪色」的洗旧砖粉、色相身份变弱，新档走苹果
    /// 「提亮且保饱和」路线（对卡面实算 4.99:1）
    public static let success = Color(UIColor.systemGreen)
    public static let warning = Color(UIColor.systemOrange)
    /// 状态文字绿（2026-11-15，第 85 条对比度收口）：
    /// success 本职是状态点/图标色，浅档 systemGreen
    /// 作可读文字仅 2.22:1——一切要读的状态字（「通
    /// 过」「使用中」「已安装」等）走本令牌：浅档同
    /// 色相深值 #1A7431（实算：对白 5.86／页底 5.71
    /// ／设置底 5.25／tintGreen 面 5.09／success
    /// α0.12 胶囊合成面 5.30，全过 4.5）；暗档随
    /// success 同挂 systemGreen（对黑 10.39、本已
    /// 达标）。状态点/纯图标位继续走 success、不动
    public static let successText = appleColor(
        light: 0x1A7431, dark: .systemGreen
    )
    /// 状态文字橙（同上收口）：浅档同色相深值
    /// #9C5700（实算：对白 5.56／页底 5.42／设置
    /// 底 4.98）；暗档随 warning 同挂 systemOrange
    /// （对黑 10.22）。点/图标位继续走 warning
    public static let warningText = appleColor(
        light: 0x9C5700, dark: .systemOrange
    )
    /// 0.43.0（A11Y-S5）：浅档高对比变体 #8C332C
    /// ——对卡面 8.00:1、对 errorSurface 7.11:1，
    /// 双面过 7:1；默认解析不变
    public static let danger = appleColor(
        light: 0xAA4A45, dark: .systemRed,
        lightHighContrast: 0x8C332C
    )
    /// 角标填充红（2026-11-15，第 85 条收口）：danger
    /// 本职文字/图标色——暗档 systemRed 提亮保饱和，
    /// 白字压之作角标填充仅 3.41:1；角标填充专用本
    /// 令牌：浅档与 danger 同值 #AA4A45（白字实算
    /// 5.56），暗档深红 #D92B1F（白字实算 4.87）。
    /// danger 本体不动（作文字对 #1C1C1E 4.99 达标）
    public static let dangerFill = appleColor(
        light: 0xAA4A45,
        dark: UIColor(
            red: 0xD9 / 255.0, green: 0x2B / 255.0,
            blue: 0x1F / 255.0, alpha: 1
        )
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

    /// 状态文字色（2026-11-15，第 85 条收口）：state-
    /// Color 的文字位姊妹——状态点继续走 stateColor，
    /// 状态词上屏走本函数：success/warning 换文字档
    /// （successText/warningText，浅档 2.22/2.20 的
    /// 不达标组合就此退出文字位），danger 作文字双
    /// 档本已达标（5.56/4.99）直用，未知态回落
    /// inkSecondary（stateColor 的 inkMuted 回落只
    /// 许点位、不许文字位）
    public static func stateTextColor(_ state: String?) -> Color {
        switch state?.lowercased() {
        case "connected", "running", "ok", "ready":
            return successText
        case "error", "failed", "disconnected", "stopped":
            return danger
        case "degraded", "warning", "restarting":
            return warningText
        default:
            return inkSecondary
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
    /// 抽屉旁聊会话行高。沿革：0.20.0 按当时 Muse 图
    /// 推算取 58；2026-11-21 抽屉样板对齐包改 44——
    /// 用户亲递现行版截图五连行＋空间五行逐行实测
    /// 行距恒 44.0pt（选中胶囊高＝行高 44），全抽屉
    /// 行档自此统一 44（导航簇同值，见下）；仍是
    /// minHeight 语义，大字体时随内容增长
    public static let drawerRowHeight: CGFloat = 44
    /// 抽屉选中垫圆角（OpenBot 样式采纳包，2026-11-20
    /// 用户亲批）：选中态改整行垫底填充——圆角取
    /// OpenBot 抽屉行 rounded-2xl 的 16，取代旧挂
    /// fieldCorner（19，输入字段圆角、与行垫无涉）；
    /// 填充色仍走 Palette.drawerSelectionFill（浅
    /// #E4E5E7 与 OpenBot 选中填充 #E9E9ED 同族冷中
    /// 性浅灰，按「优先映射现有令牌」不新立色值；
    /// 暗档 tertiarySystemBackground 与其深档
    /// #212121 同为深面级）
    public static let drawerSelectionCorner: CGFloat = 16
    /// 顶栏圆钮直径（OpenBot 样式采纳包）：会话列表
    /// 页顶栏按钮改 48 圆钮（OpenBot 首页栏钮 48 口
    /// 径），画法走现行圆钮式（glassEffect 圆＋
    /// odPressable，字形走 FrameworkIcon
    /// .barButtonGlyphSize）
    public static let barRoundButtonDiameter: CGFloat = 48
    /// 会话列表页（全部对话）两行行最小高（OpenBot
    /// 样式采纳包）：本页去分隔线、改靠留白分行，需
    /// 比现行内容实高（题 22＋stackGap 3＋副题 20
    /// ≈45）多一档呼吸——取 68（内容＋约 23 纵向留
    /// 白）；不照搬 OpenBot 的 80（那是 54 头像＋三
    /// 行字之设，本页两行制、密度优先，68 档一屏约
    /// 多一行）。与 ListRowSpec.sessionRowMinHeight
    /// （57）分工：57 仍管其余消费面（ContentRow/
    /// UnifiedRow），本值只管本页行（rowLabel 与频
    /// 道行），两档并存是本包明示切割、不互相冒充
    public static let sessionListRowMinHeight: CGFloat = 68
    /// 抽屉导航簇行高（§157，用户 2026-11-11 21:01 补
    /// 充方案②）：导航行/频道行/管理行的最小行高。
    /// 沿革：§157 取 54（设计起点值、非实测）；2026-
    /// 11-21 样板对齐包改 44——样板导航行与会话行
    /// 同距 44.0pt 实测，两档自此同值（量测全表见
    /// 交卷报告）；仍是 minHeight 语义
    public static let drawerNavRowHeight: CGFloat = 44
    /// 设置页行最小高（0.20.0，Muse 设置图推算行距
    /// 约 63 含卡内呼吸，行本体取 60）
    public static let settingsRowHeight: CGFloat = 60
    /// 设置页组间距（0.20.0 图中组间约 28；0.41.0 收
    /// 口批 C4 处置：28 不在间距梯队内、收编为梯队值
    /// spacingL 24——组间 24 对组内行距（8/12）仍达
    /// 2–3 倍分段比，宪法 §3.2 的分段可读性不减；全
    /// App 设置型页面的组距随之统一小收 4pt，真机若
    /// 觉挤可单独回 28 并入宪法修订，本批先入梯队）
    public static let settingsSectionSpacing: CGFloat = 24
    /// 设置页统一行盒（台账 198 收敛 B7）：纵向 0
    /// （行高只由行内容 minHeight 决定）、横向 20 与
    /// 页 gutter 对齐线一致。此前设置首页/外观页/支
    /// 持组三页各复刻一份同值 EdgeInsets（审计 B7），
    /// 自此单源住令牌层，各页不许再自备
    public static var settingsRowInsets: EdgeInsets {
        EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20)
    }
    /// 分区外距（组节奏定版，DESIGN-V2 §3.2「分区标题
    /// 上 28 下 8」）：手搓页 SectionLabel 之上的留白
    /// 与页末最后一组之下的收尾留白同值同族——下 8
    /// 即 spacingS、本值管 28 一侧。此前 38 处以字
    /// 面量散写于 14 个管理面文件（PM/UI 复盘点名的
    /// 「组顶距 28 复发」即此），本批（UI 台账余项＋
    /// 深色批，2026-11-14）收编入令牌：数值不变、版
    /// 式零变化，变的只是出处归一。28 不在间距梯队
    /// 内的处置同 pageGutter/cardPadding 的 20——
    /// 有定版出处（组节奏）的具名值，记账保留
    public static let sectionOuterSpacing: CGFloat = 28
    /// 名单行图标字形（0.23.0 单源化：改引用 Core
    /// FrameworkIcon，本处只留别名、不再自带数值）
    public static let navGlyph: CGFloat = FrameworkIcon.navGlyphSize
    /// 底栏字形（0.23.0 单源化：同上，值 22 不变）
    public static let tabGlyph: CGFloat = FrameworkIcon.tabGlyphSize
    /// 抽屉底部浮动条圆钮边长（搜索胶囊同高）。沿
    /// 革：0.3.6 取 52；2026-11-21 样板对齐包改
    /// 45——样板圆钮 Ø45pt、搜索胶囊高 45 实测（±1）；
    /// 控件居中于 52 行盒（Core DrawerGeometry.
    /// bottomBarRowHeight），落位中心距屏底 64.0 与
    /// 样板 64.2 同归一线
    public static let drawerBarButton: CGFloat = 45
    /// 输入字段（0.6.1 改挂 OpenMuse input 圆角 19，
    /// ui.tsx:58）
    public static let fieldCorner: CGFloat = 19
    /// 按钮（0.6.1 改挂 OpenMuse button 圆角 24 近胶囊，
    /// ui.tsx:74）
    public static let buttonCorner: CGFloat = 24
    /// 消息气泡（0.6.1：与 OpenMuse 气泡圆角 22 同值，
    /// chat.tsx:590，出处自本版换为它的令牌）
    /// 台账 179（OB-I1，DESIGN §391）：改现读个性化档
    /// ——未设（定版 standard）时逐值回 22、与旧常量恒
    /// 等；用户在外观页改选后新求值即新值（读口与
    /// currentChatTheme 同制：现读 UserDefaults）
    public static var bubbleCorner: CGFloat {
        AppearancePreferences.bubbleStyle().bubbleCorner
    }
    /// 助手消息气泡（0.6.1：改同 22——OpenMuse 双泡同
    /// 圆角，旧「助手略收 18」口径让位）；§391 同上现读
    public static var assistantBubbleCorner: CGFloat {
        AppearancePreferences.bubbleStyle()
            .assistantBubbleCorner
    }
    /// 气泡尾角（0.6.1 新增：OpenMuse 靠己侧底角收 7，
    /// chat.tsx:591-592）；§391 同上现读
    public static var bubbleTailCorner: CGFloat {
        AppearancePreferences.bubbleStyle().bubbleTailCorner
    }
    /// 输入区胶囊（多行态圆角矩形的圆角，单行态走 Capsule）
    public static let composerCorner: CGFloat = 24
    /// 代码块（正文区内的内容面）
    public static let codeCorner: CGFloat = 10

    // —— 圆角角色令牌（0.41.0 收口批 C15：散值 6/9/12/
    // 14/16 按角色收编；旧「梯队 {7,10,28}」与卡面实
    // 际形态脱节，本表即新梯队——同心推导面（气泡/容
    // 器/字段等上方专名令牌）不在此列、不受影响）——
    /// 小符号瓷砖（34–36pt 方砖：类型砖/工具类砖）
    public static let radiusTile: CGFloat = 9
    /// 缩略图（54pt 级图面）
    public static let radiusThumb: CGFloat = 10
    /// 一般卡面（来源卡/正文卡/状态卡/链接卡）
    public static let radiusCard: CGFloat = 12
    /// 大卡/预览面（文档预览卡/横幅行/终端卡；图片查
    /// 看器卡圆角 16 与此同值、走 ImageViewerSpec）
    public static let radiusPreview: CGFloat = 16
    /// 勾选框（24pt 方框的形状圆角，与 AppSymbolTile
    /// 的 size×0.26 比例画法同源量级）
    public static let radiusCheckbox: CGFloat = 6
    /// 小徽标描边圆角（台账「补记」徽标等 caption2 级
    /// 微形标签；HIG 全过第一波具名收编，值 4 不变）
    public static let radiusBadge: CGFloat = 4

    /// 页面左右边距（内容页）
    public static let pageGutter: CGFloat = 20
    /// 中枢页局部边距（§477，2026-11-24 全抄参照量
    /// 测 ≈16–17）：只许中枢页头/分段条/三子页消费，
    /// pageGutter 全局口径不动、不许外溢其他页面
    public static let hubGutter: CGFloat = 16
    /// 中枢段头与行标题字号（§477 立、§500 订正：
    /// §477 注记的参照量测 ≈20 系误记——用户参照截
    /// 图逐像素实测 ≈17 semibold（Headline 档），见
    /// hub-type-measurement-20261124.md；段头三页单
    /// 源、行标题同档）
    public static let hubTitleSize: CGFloat = 17
    /// 中枢页头大名字号（§477 立、§500 订正：§477
    /// 注记的参照 ≈32 系误记，实测 ≈25 bold；仅页
    /// 头 hero 消费）
    public static let hubHeroNameSize: CGFloat = 25
    /// 列表行图标槽宽：全页同一条对齐线（0.24.0 与
    /// 设置/抽屉统一取 30，ListRowSpec.iconSlotWidth
    /// 同值，见 §51）
    public static let iconSlot: CGFloat = 30
    /// 智能体头像尺寸三档（§224，头像呈现 harmonize）：
    /// 全 App 渲染智能体头像的位点只许取这三档，不许
    /// 再散写字面量——页头档＝枢纽页头与身份详情页
    /// hero（110/88 两处旧值收敛至 90，对齐 Muse 档
    /// 案页页头盘实测）；段头档＝枢纽身份段段头（52
    /// 沿用 §218 定版）；列表行档＝抽屉身份行/设置身
    /// 份卡/编辑器行（36/44 两值收敛至 44）。用户自选
    /// 的形象档（Core AvatarSizeTier，顶簇/空态/锚点
    /// 三面）是用户偏好、不在此列。
    public static let avatarPageHead: CGFloat = 90
    public static let avatarSectionHead: CGFloat = 45
    public static let avatarListRow: CGFloat = 44
    /// 页头改版档（§434，参照截图工具采样定值）：
    /// 聊天页居中身份区头像 67／中枢页 hero 头像
    /// 85——照抄参照量测，不与页头盘 90 档混用
    /// §477（2026-11-24 全抄复量）：中枢 hero 头像
    /// 85→95（参照档案页大头实测 ≈95），仅本档改值
    public static let avatarChatHero: CGFloat = 67
    public static let avatarHubHero: CGFloat = 95
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
    /// 枢纽分段条高（§222，2026-11-14 对 Muse 智能
    /// 体页真机图量测：整条胶囊 ≈48；系统 segmented
    /// 轨道 32 不可调、自绘条按此值落）
    public static let hubSegBarHeight: CGFloat = 48
    /// 枢纽分段选中胶囊高（§222，同上量测 ≈36；条内
    /// 上下各留 6）
    public static let hubSegCapsuleHeight: CGFloat = 36
    /// 枢纽分段图标字形（§222，同上量测 ≈22）
    public static let hubSegGlyphSize: CGFloat = 22

    // —— 气泡内边距（0.6.1 改挂 OpenMuse 气泡内边距
    // 16/13，chat.tsx:588-589；0.3.2 收编的 14/10 让位）——
    /// 气泡横向内边距（用户泡与助手泡共用）
    public static let bubblePaddingH: CGFloat = 16
    /// 气泡纵向内边距
    public static let bubblePaddingV: CGFloat = 13
    /// 气泡靠边让位：对侧 Spacer 的最小让宽（用户泡左让/
    /// 助手泡右让同值，0.2.5 对齐口径）
    public static let bubbleSideInset: CGFloat = 44
    /// 助手正文段间额外距（§263：对齐 Muse 同机实测
    /// 16pt；消费单源＝MarkdownText.proseParagraphs 的
    /// 段后距，不再借间距梯队的 spacingSM）
    public static let paragraphSpacing: CGFloat = 16
    /// 助手正文左缘占屏比（§263 沿革值）：§503 起助
    /// 手面改全宽卡（卡缘＝pageGutter），本比不再有
    /// 布局消费方——保留仅作 §263 量测沿革档案，新
    /// 代码禁读（文宽走 assistantTextWidth 单源）
    public static let assistantTextLeadingFraction: CGFloat = 0.082
    /// 助手正文文宽（§503 单源）：全宽卡内正文宽＝
    /// 屏宽 − 2×pageGutter（卡缘）− 2×bubblePaddingH
    /// （卡内距）；@402 ＝ 330（§263 旧口径 309 系窄
    /// 列时代值、随 §503 改判）。气泡布局与量测喂入
    /// （LayoutProductService/ChatNativeRowHeight/
    /// ChatView）同源消费本函数、不许再各自拼算
    public static func assistantTextWidth(
        screenWidth: CGFloat
    ) -> CGFloat {
        screenWidth - pageGutter * 2 - bubblePaddingH * 2
    }

    // —— 梯外具名值（审查 T-4 收编：光学/手势/设备驱动）——
    /// 流式词元流布局的词间/行间距（光学值，TokenFlow 用）
    public static let tokenFlowSpacing: CGFloat = 5
    /// 抽屉左缘唤出热区宽（手势值：够拇指起滑、不挡正文滚动）
    public static let drawerEdgeZone: CGFloat = 24
    /// 抽屉宽占屏比（0.3.6 立宪 peek 口径约 79%；
    /// 0.4.1 第 10 修按用户逐像素采样改约 75%；
    /// 2026-11-21 样板对齐包改回 0.79——现行版截图
    /// 实测 317.0pt/402pt＝0.7886，与 Core Drawer-
    /// CardGeometry.travelWidthFraction 单源同值；
    /// 本令牌现无消费面（容器走 Core 派生）、留作
    /// 口径档案，两处不许再分叉）
    public static let drawerWidthFraction: CGFloat = 0.79
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

    // —— 组件内微距（0.41.0 收口批 C5 收编：题/副题紧
    // 排、字形与文字的贴身间隙等组件内部量，不作页
    // 面布局间距使用；数值与收编前字面量逐一相同、
    // 版式零变化，变的只是出处归一到本表）——
    /// 贴身微距（同组两行字/字形与计数等的最紧间隙）
    public static let spacingMicro: CGFloat = 2
    /// 题副紧排（行内标题与副题的纵向贴合）
    public static let stackGap: CGFloat = 3
    /// 图文贴身（小图标/状态点与相邻文字）
    public static let iconTextGap: CGFloat = 5
    /// 行内小组（行内两三个元素成组时的组内距）
    public static let rowInnerGap: CGFloat = 6
    /// 卡内一组（横幅行/卡内图标与文字列的间距）
    public static let cardInnerGap: CGFloat = 10
}

/// 聊天背景呈现面（§503）：聊天页背景层与外观页预
/// 览的**同一消费面**——底色走 Palette.chatBack-
/// ground 现读；图案档（点阵/网格/斜纹）再以主墨低
/// 对比叠绘骨架纹理（浅 4%/暗 6% 不透明度——纹理对
/// 底色对比 ≤1.15、正文可读性不受影响，口径钉在
/// ThemePackage503Tests）。间距定死：点阵 22pt 错
/// 格圆点 r1.2、网格 26pt 线宽 0.75、斜纹 14pt 线
/// 宽 0.75（45°）。非图案档只出底色、与旧背景层逐
/// 像素同
public struct ChatBackgroundSurface: View {
    public init() {}

    @AppStorage(AppearanceStorageKeys.chatBackground)
    private var chatBackgroundRaw = ChatBackgroundStyle.standard.rawValue

    private var backgroundStyle: ChatBackgroundStyle {
        ChatBackgroundStyle(rawValue: chatBackgroundRaw) ?? .standard
    }

    public var body: some View {
        ZStack {
            Palette.chatBackground
            if let kind = backgroundStyle.patternKind {
                Canvas { context, size in
                    draw(kind, in: &context, size: size)
                }
                .opacity(Self.patternOpacity)
            }
        }
    }

    /// 纹理不透明度（浅/暗在解析时同值取舍：取对底
    /// 色对比的保守侧——以浅档 4% 为准、暗档同值；
    /// 暗底上主墨（白）4% 的对比 ≈1.10、同在 ≤1.15
    /// 线内，两档一值不分叉）
    private static let patternOpacity: Double = 0.07

    private func draw(
        _ kind: ChatBackgroundPattern,
        in context: inout GraphicsContext, size: CGSize
    ) {
        let ink = GraphicsContext.Shading.color(.primary)
        switch kind {
        case .dots:
            let step: CGFloat = 22, r: CGFloat = 1.2
            var row = 0
            var y: CGFloat = step / 2
            while y < size.height + step {
                var x: CGFloat = row % 2 == 0 ? step / 2 : step
                while x < size.width + step {
                    let rect = CGRect(
                        x: x - r, y: y - r,
                        width: r * 2, height: r * 2
                    )
                    context.fill(Path(ellipseIn: rect), with: ink)
                    x += step
                }
                y += step
                row += 1
            }
        case .grid:
            let step: CGFloat = 26
            var path = Path()
            var x: CGFloat = 0
            while x <= size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += step
            }
            var y: CGFloat = 0
            while y <= size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += step
            }
            context.stroke(path, with: ink, lineWidth: 0.75)
        case .diagonal:
            let step: CGFloat = 14
            var path = Path()
            var offset: CGFloat = -size.height
            while offset < size.width {
                path.move(to: CGPoint(x: offset, y: 0))
                path.addLine(
                    to: CGPoint(x: offset + size.height, y: size.height)
                )
                offset += step
            }
            context.stroke(path, with: ink, lineWidth: 0.75)
        }
    }
}
