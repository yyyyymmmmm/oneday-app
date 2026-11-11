import OneDayCore
import SwiftUI
import UIKit

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
}

public enum Palette {
    /// 页面底（OpenMuse canvas #FCFCFC，ui.tsx:19；
    /// 暗档 0.36.1 改挂 systemBackground＝纯黑 #000——
    /// 审计 D1：旧派生 #101619 是带蓝灰的「灰雾」基底、
    /// 与 settingsBG 双基底并存（互比 1.03），自本版
    /// 基底身份归一为语义 base 锚）
    public static let pageBG = appleColor(
        light: 0xFCFCFC, dark: .systemBackground
    )
    /// 卡面（OpenMuse card #FFFFFF，ui.tsx:20；暗档
    /// secondarySystemBackground #1C1C1E——层级步对齐
    /// 苹果梯：#000→#1C1C1E 步幅 1.23:1，旧派生
    /// #1B2226 步幅被压缩且全程带蓝，审计 D2）
    public static let surface = appleColor(
        light: 0xFFFFFF, dark: .secondarySystemBackground
    )
    /// 助手泡（OpenMuse 助手泡 #EEEEF0，chat.tsx:593；
    /// 暗档 tertiarySystemBackground #2C2C2E——背景三
    /// 级梯的第三级，旧派生 #272E33 让位）
    public static let bubbleFill = appleColor(
        light: 0xEEEEF0, dark: .tertiarySystemBackground
    )
    /// 字段面（OpenMuse input 底 #FFF，ui.tsx:62；暗档
    /// 同取三级面 #2C2C2E——字段恒落在页底/卡面上、
    /// 取高一级使输入区在两面都可辨）
    public static let fieldFill = appleColor(
        light: 0xFFFFFF, dark: .tertiarySystemBackground
    )
    /// 聊天表面（OpenMuse canvas #FCFCFC；暗档随页面
    /// 底同锚 systemBackground #000）
    public static let chatSurface = appleColor(
        light: 0xFCFCFC, dark: .systemBackground
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
    /// （0x1473C8→0x136FC1，见 ChatTheme 注），与上
    /// 述旧值脱钩是本意；暗档仍逐字相同。
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
    /// 彩虹板。取值按代码面（浅 #FFFFFF 字段面／暗
    /// #2C2C2E 三级面）实算对比：关键词紫浅 #A626A4
    /// （对白 6.1:1）／暗 #C792EA（5.8:1）；字符串绿
    /// 浅 #116329（7.4:1）／暗 #98C379（6.9:1）；数字
    /// 蓝浅 #0550AE（7.6:1）／暗 #79B8FF（6.7:1），
    /// 全过 4.5 小字线（WCAGContrast 同式心算，落法
    /// 与 D3 派生档同机制：浅档字面、暗档 UIColor
    /// 字面经 appleColor 解析）
    public static let codeKeyword = appleColor(
        light: 0xA626A4,
        dark: UIColor(
            red: 0xC7 / 255.0, green: 0x92 / 255.0,
            blue: 0xEA / 255.0, alpha: 1
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
    /// 0.43.0（A11Y-S5）：浅档高对比变体 #8C332C
    /// ——对卡面 8.00:1、对 errorSurface 7.11:1，
    /// 双面过 7:1；默认解析不变
    public static let danger = appleColor(
        light: 0xAA4A45, dark: .systemRed,
        lightHighContrast: 0x8C332C
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
    /// 设置页组间距（0.20.0 图中组间约 28；0.41.0 收
    /// 口批 C4 处置：28 不在间距梯队内、收编为梯队值
    /// spacingL 24——组间 24 对组内行距（8/12）仍达
    /// 2–3 倍分段比，宪法 §3.2 的分段可读性不减；全
    /// App 设置型页面的组距随之统一小收 4pt，真机若
    /// 觉挤可单独回 28 并入宪法修订，本批先入梯队）
    public static let settingsSectionSpacing: CGFloat = 24
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
