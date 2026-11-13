import OneDayDesign
import OneDayCore
import SwiftUI
import UIKit

/// 版本字面单源（设置页重塑 §164）：设置页脚与关于
/// 页 hero 共用——发版五处同改时本文件一处即两面
/// （版本源第五处自此收敛为本常量，grep 校验照旧
/// 命中版本号字面）
enum OneDayVersionLabel {
    static let full = "OneDay v0.50.29 (157)"
    static let hero = "v0.50.29 (157)"
}

/// App 图标位图（§188）：经 Info.plist 的 CFBundleIcons
/// 取图标集文件名再 UIImage(named:)——与桌面图标同
/// 源（Assets 的 AppIcon 图标集）、换图标自动跟随，
/// 不复制位图、不占位。取不到返回 nil，消费方整件
/// 降级（只少图标、不留空框）
enum AppIconBitmap {
    static let image: UIImage? = {
        guard let icons = Bundle.main.infoDictionary?[
            "CFBundleIcons"
        ] as? [String: Any],
        let primary = icons["CFBundlePrimaryIcon"]
            as? [String: Any],
        let files = primary["CFBundleIconFiles"]
            as? [String],
        let name = files.last else { return nil }
        return UIImage(named: name)
    }()
}

/// App 图标视图（§188）：真实位图＋连续圆角裁切。
/// 消费点＝设置页脚签名行（19pt/角 5）与关于页 hero
/// （68pt/角 17），尺寸由消费点按原型口径给。图标本
/// 身自带底色，深浅色同图、不另加框；无障碍恒隐藏
/// （相邻名称文字已达意）
struct AppIconView: View {
    let size: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        if let image = AppIconBitmap.image {
            Image(uiImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: cornerRadius,
                        style: .continuous
                    )
                )
                .accessibilityHidden(true)
        }
    }
}

/// 支持组共用行盒（与设置首页/外观页同口径复刻）
private var supportRowInsets: EdgeInsets {
    EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20)
}

private func supportHeader(_ title: String) -> some View {
    Text(L10n.string(title))
        .font(.sectionLabel)
        .foregroundStyle(Palette.inkSecondary)
        .textCase(nil)
}

// MARK: - 帮助与反馈

/// 帮助与反馈（设置页重塑 §164；蓝本＝用户亲递原型
/// help 页）：连接帮助两条如实口径（地址形态、双方式
/// 登录凭据）＋反馈外链两条（OneDay 议题、Hermes 项
/// 目）。全部是静态真内容，不接任何假表单
struct HelpView: View {
    var body: some View {
        List {
            Section {
                helpRow(
                    icon: "server.rack", title: "服务器地址",
                    text: "形如 https://hermes.example.com，不要带结尾斜杠。手机需要能直接访问这个地址，不能用 localhost。"
                )
                helpRow(
                    icon: "key", title: "登录凭据",
                    text: "可以用伴生服务的面板密码登录，也可以用 Hermes 的 API 密钥登录；密钥在 Hermes 服务端的配置中生成。连接不上先在「当前服务器」里重新测试连接。"
                )
            } header: {
                supportHeader("连接帮助")
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(supportRowInsets)

            Section {
                linkRow(
                    icon: "text.bubble", title: "在 GitHub 提交问题",
                    subtitle: "附上复现步骤与系统版本",
                    url: "https://github.com/yyyyymmmmm/oneday-app/issues"
                )
                linkRow(
                    icon: "doc.text", title: "Hermes 部署文档",
                    subtitle: nil,
                    url: "https://github.com/NousResearch/hermes-agent"
                )
            } header: {
                supportHeader("反馈")
            } footer: {
                Text("请勿在公开议题中粘贴密钥、服务器地址或个人数据。")
                    .font(.rowSubtitle)
                    .foregroundStyle(Palette.inkSecondary)
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(supportRowInsets)
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        .navigationTitle("帮助与反馈")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func helpRow(
        icon: String, title: String, text: String
    ) -> some View {
        HStack(alignment: .top, spacing: OneDayMetrics.spacingSM) {
            Image(systemName: icon)
                .font(.system(
                    size: FrameworkIcon.settingsGlyphSize,
                    weight: .regular
                ))
                .foregroundStyle(Palette.ink)
                .frame(width: OneDayMetrics.iconSlot, alignment: .center)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                Text(L10n.string(title))
                    .font(.rowTitleL)
                    .foregroundStyle(Palette.ink)
                Text(L10n.string(text))
                    .font(.rowSubtitle)
                    .foregroundStyle(Palette.inkSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, OneDayMetrics.spacingS)
        .contentShape(Rectangle())
    }

    private func linkRow(
        icon: String, title: String, subtitle: String?, url: String
    ) -> some View {
        Link(destination: URL(string: url)!) {
            HStack(spacing: OneDayMetrics.spacingSM) {
                Image(systemName: icon)
                    .font(.system(
                        size: FrameworkIcon.settingsGlyphSize,
                        weight: .regular
                    ))
                    .foregroundStyle(Palette.ink)
                    .frame(width: OneDayMetrics.iconSlot, alignment: .center)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                    Text(L10n.string(title))
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.ink)
                    if let subtitle {
                        Text(L10n.string(subtitle))
                            .font(.rowSubtitle)
                            .foregroundStyle(Palette.inkSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: OneDayMetrics.spacingS)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Palette.inkMuted)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: OneDayMetrics.settingsRowHeight)
            .contentShape(Rectangle())
        }
    }
}

// MARK: - 关于

/// 关于 OneDay（设置页重塑 §164；蓝本＝用户亲递原型
/// about 页）：版本 hero＋服务两行（Hermes/伴生——原
/// 设置首页版本组整组迁入，数值由 SettingsView 已加
/// 载的 status 与伴生探测派生注入，本页不另发请求）
/// ＋法律与隐私（隐私政策/用户协议正式全文两页）＋开源与署名（原
/// 关于组两条外链迁入＋OneDay 仓库一条）。组脚注＝
/// 三层命名分工句（2026-11-11 21:06 定案）与原隐私
/// 说明合并
struct AboutView: View {
    /// Hermes 版本位（读不到如实显「未知」，口径同原
    /// 版本组，不许拿已知生产版本冒充现读）
    let hermesVersionText: String
    /// 伴生副行（Core CompanionStatus 派生整行）
    let companionLine: String
    /// 伴生组脚注（缺失/需升级时的一句可行动人话）
    let companionNote: String?

    var body: some View {
        List {
            heroSection
            serviceSection
            legalSection
            openSourceSection
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        .navigationTitle("关于 OneDay")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var heroSection: some View {
        Section {
            VStack(spacing: OneDayMetrics.spacingXS) {
                // §188：原型 hero 顶部 68×68 圆角图标
                // 居中（角 17），图标与名行距 16＝
                // SM(12)＋XS(4) 梯队合成
                AppIconView(size: 68, cornerRadius: 17)
                    .padding(.bottom, OneDayMetrics.spacingSM)
                Text("OneDay")
                    .font(.screenName)
                    .foregroundStyle(Palette.ink)
                Text(OneDayVersionLabel.hero)
                    .font(.rowSubtitle)
                    .foregroundStyle(Palette.inkSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, OneDayMetrics.spacingSM)
            .accessibilityElement(children: .combine)
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(supportRowInsets)
    }

    private var serviceSection: some View {
        Section {
            LabeledContent("Hermes") {
                Text(hermesVersionText)
                    .font(.system(.callout, design: .monospaced))
            }
            HStack(spacing: OneDayMetrics.spacingSM) {
                VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                    Text("伴生服务")
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.ink)
                    Text(companionLine)
                        .font(.rowSubtitle)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: OneDayMetrics.spacingS)
            }
            .frame(minHeight: OneDayMetrics.settingsRowHeight)
            .contentShape(Rectangle())
        } header: {
            supportHeader("服务")
        } footer: {
            if let companionNote {
                Text(companionNote)
                    .font(.rowSubtitle)
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(supportRowInsets)
    }

    private var legalSection: some View {
        Section {
            legalRow(icon: "lock.shield", title: "隐私政策", route: .privacy)
            legalRow(icon: "doc.text", title: "用户协议", route: .terms)
        } header: {
            supportHeader("法律与隐私")
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(supportRowInsets)
    }

    private func legalRow(
        icon: String, title: String, route: SettingsRoute
    ) -> some View {
        NavigationLink(value: route) {
            HStack(spacing: OneDayMetrics.spacingSM) {
                Image(systemName: icon)
                    .font(.system(
                        size: FrameworkIcon.settingsGlyphSize,
                        weight: .regular
                    ))
                    .foregroundStyle(Palette.ink)
                    .frame(width: OneDayMetrics.iconSlot, alignment: .center)
                    .accessibilityHidden(true)
                Text(L10n.string(title))
                    .font(.rowTitleL)
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: OneDayMetrics.spacingS)
            }
            .frame(minHeight: OneDayMetrics.settingsRowHeight)
            .contentShape(Rectangle())
        }
    }

    private var openSourceSection: some View {
        Section {
            linkRow(
                title: "OneDay 开源项目",
                url: "https://github.com/yyyyymmmmm/oneday-app"
            )
            linkRow(
                title: "Hermes 开源项目",
                url: "https://github.com/NousResearch/hermes-agent"
            )
            linkRow(
                title: "Icons by Lordicon",
                url: "https://lordicon.com"
            )
        } header: {
            supportHeader("开源与署名")
        } footer: {
            Text("OneDay 是客户端，服务端是 Hermes 开源项目；智能体的名字以你服务器上的人设为准。OneDay 只与你自己的服务器通信；凭据存本机钥匙串，聊天记录存本机，服务端数据归你所有。")
                .font(.rowSubtitle)
                .foregroundStyle(Palette.inkSecondary)
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(supportRowInsets)
    }

    private func linkRow(title: String, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            HStack(spacing: OneDayMetrics.spacingSM) {
                Color.clear
                    .frame(width: OneDayMetrics.iconSlot)
                    .accessibilityHidden(true)
                Text(L10n.string(title))
                    .font(.rowTitleL)
                    .foregroundStyle(Palette.ink)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Palette.inkMuted)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: OneDayMetrics.settingsRowHeight)
            .contentShape(Rectangle())
        }
    }
}

// MARK: - 法律文档页

/// 隐私政策／用户协议正式全文（设置页重塑 §164；
/// 用户 2026-11-11 亲口授权「隐私和协议你自己给咱
/// 们写好」——由开发方自拟全文，替代原型亲递的草
/// 稿结构稿，草稿标记随之撤销）：正文与仓内
/// docs/PRIVACY-POLICY.md／docs/USER-AGREEMENT.md
/// 同文，简体中文为正文，繁体与英文经本地化词条同
/// 文跟随。条款只述已成立的真实数据流（无账号体系、
/// 无中转服务器、凭据只存本机钥匙串、设备数据副本
/// 只在用户自己的服务器），生效日期 2026-11-11
struct LegalDocumentView: View {
    enum Kind {
        case privacy, terms

        var title: String {
            switch self {
            case .privacy: return "隐私政策"
            case .terms: return "用户协议"
            }
        }

        /// 章节（标题＋正文，正文段落以空行分隔）：
        /// 标题与正文都是中文源串，经本地化词条取词
        var sections: [(heading: String, body: String)] {
            switch self {
            case .privacy: return Self.privacySections
            case .terms: return Self.termsSections
            }
        }

        private static let privacySections: [(heading: String, body: String)] = [
            (
                "运营方与联系方式",
                "OneDay 由知和数智（下称「我们」）开发并维护。本政策说明 OneDay 在你使用过程中如何处理信息。如有疑问，或要行使下文所述的权利，可通过 GitHub 仓库 Issues（github.com/yyyyymmmmm/oneday-app/issues）或邮箱 inkroot001@gmail.com 联系我们。"
            ),
            (
                "没有账号，也不收集使用数据",
                "OneDay 没有账号体系，不要求注册，我们也没有承接用户数据的服务器。App 不向我们回传你的对话、文件、设备数据或使用行为；App 内不集成广告 SDK，也不集成统计、崩溃上报等第三方数据收集 SDK。"
            ),
            (
                "服务器地址与凭据只存本机",
                "你填写的服务器地址与登录凭据（面板密码或 API 密钥）只保存在这台设备的系统钥匙串中，用于连接你自己的 Hermes 服务器。凭据不上传给我们，也不同步到任何第三方云服务。清除方法见下文「你的权利」。"
            ),
            (
                "对话与文件只在你与你的服务器之间流转",
                "你的对话内容，以及你上传、智能体生成的文件，只在这台设备与你自己的 Hermes 服务器之间直接传输，不经过我们或任何第三方的中转。对话与文件的保留时长由你决定，可随时在设备与服务器上删除。"
            ),
            (
                "设备数据：逐项授权、副本在你自己的服务器",
                "日历、提醒事项、通讯录、照片元数据与步数这五类数据，只有在你逐项授予 iOS 系统权限后才会被读取。授权后自动同步：同步副本只写入你自己的服务器（伴生服务），供智能体在你的服务器上查询，不会发给我们。其中照片只同步元数据索引，不含照片原图与拍摄地点；步数只同步每日汇总。\n\n同步了哪些数据、副本有多少条，可在「设置 → 设备与权限」中逐项查看；该页提供一键删除全部同步副本，删除只删服务器上的副本，不动手机上的原始数据与系统权限。你也可以在该页逐项关闭，或到 iOS 系统设置中撤回权限；撤回后智能体立即停供该类数据，不再读取已有副本。"
            ),
            (
                "你配置的第三方服务",
                "你在 App 中自行添加的模型服务商、连接器等第三方服务（例如你自己的模型网关），由你提供地址与密钥；经这些服务处理的数据，适用你与该服务商之间的约定及其自身的隐私政策，不适用本政策。我们无法查看，也无法控制这些服务的数据处理方式。"
            ),
            (
                "你的权利",
                "你的数据都在你的设备与你自己的服务器上，查询、删除与撤回授权都可以在 App 内直接完成：\n\n查询：对话在聊天页查看；设备数据的同步状态与副本条数在「设置 → 设备与权限」查看；保存在服务器上的文件在「文件」页查看。\n\n删除：在「设置 → 设备与权限」一键删除全部同步副本；在设置页底部「断开连接」可清除本机保存的服务器凭据与登录会话；卸载 App 将清除本机聊天记录等本地数据；服务器一侧的数据可通过服务器文件管理自行删除。\n\n撤回授权：在「设置 → 设备与权限」逐项关闭，或到 iOS 系统设置中撤回权限，撤回后立即停供。\n\n如需协助，可通过上文联系方式联系我们；但因我们不持有你的数据，具体操作仍需在你自己的设备与服务器上完成。"
            ),
            (
                "未成年人",
                "OneDay 面向能够自行部署与管理服务器的用户。未成年人应在监护人指导下使用；监护人如发现未成年人未经同意使用并产生了数据，可按上文路径在设备与服务器上删除，或联系我们获取操作说明。"
            ),
            (
                "政策变更与生效",
                "本政策自 2026 年 11 月 11 日起生效。如我们变更信息的处理方式，会先更新本页并注明新的生效日期；涉及重大变化时，会在 App 内显著提示。更新后继续使用，即视为接受变更后的政策。"
            ),
        ]

        private static let termsSections: [(heading: String, body: String)] = [
            (
                "服务定位",
                "OneDay 是客户端软件，用于连接你自己部署的 Hermes 服务。Hermes 是由 Nous Research 维护的开源项目。OneDay 本身不提供云服务：没有我们的服务器承接你的对话、文件或设备数据。"
            ),
            (
                "自托管与责任划分",
                "服务器的部署、运行、可用性与安全维护，由你或你的服务器提供方负责；对话、文件与同步副本等数据的保管、备份与删除也在你一侧。我们提供的是客户端软件及其更新，无法保证你的服务器持续可用，也不为服务器故障、第三方服务中断造成的数据损失负责。"
            ),
            (
                "可接受使用",
                "你承诺遵守所在地法律法规，不利用 OneDay 从事违法活动，不侵害他人合法权益，不攻击或干扰你无权访问的系统与服务。因你使用 OneDay 的方式产生的后果由你承担。"
            ),
            (
                "AI 输出与操作确认",
                "智能体的回复由模型生成，可能不准确或不完整，不构成医疗、法律、财务等专业建议，重要决定请自行核实。通过智能体执行的操作（包括发送消息、修改文件、调用设备能力等），应由你在执行前确认；你对已确认执行的操作及其结果负责。涉及审批的写入操作会在聊天中请你批准，请勿批准你不理解的操作。"
            ),
            (
                "知识产权",
                "OneDay 客户端以开源形式发布于 GitHub 仓库（github.com/yyyyymmmmm/oneday-app），其使用与分发遵循仓库内所附的许可证。Hermes 为 Nous Research 的开源项目，权利归其权利人所有。本协议提及的其他名称与标识归各自权利人所有，不表示隶属或背书关系。"
            ),
            (
                "责任限制",
                "在法律允许的最大范围内，OneDay 按「现状」提供，我们不对软件无错误、无中断作出明示或默示保证；对于因使用或无法使用 OneDay 引起的间接、偶然或后果性损失，我们不承担责任。本条不排除依法不得排除的责任。"
            ),
            (
                "终止",
                "你可以随时停止使用并卸载 OneDay，凭据与本地数据的清除方式见隐私政策。我们如停止维护，会在 GitHub 仓库公告；已安装的客户端与你的服务器之间的数据不受影响。"
            ),
            (
                "适用法律与协议变更",
                "本协议适用中华人民共和国法律，自 2026 年 11 月 11 日起生效。我们更新协议时，会先更新本页并注明新的生效日期；重大变更会在 App 内显著提示，更新后继续使用即视为接受。"
            ),
        ]
    }

    let kind: Kind

    var body: some View {
        List {
            Section {
                Text("生效日期：2026 年 11 月 11 日")
                    .font(.rowSubtitle)
                    .foregroundStyle(Palette.inkSecondary)
                    .padding(.vertical, OneDayMetrics.spacingXS)
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(supportRowInsets)

            ForEach(
                Array(kind.sections.enumerated()), id: \.offset
            ) { _, section in
                bodySection(heading: section.heading, body: section.body)
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func bodySection(heading: String, body: String) -> some View {
        let paragraphs = L10n.string(body)
            .components(separatedBy: "\n\n")
            .filter { !$0.isEmpty }
        return Section {
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingSM) {
                ForEach(
                    Array(paragraphs.enumerated()), id: \.offset
                ) { _, paragraph in
                    Text(paragraph)
                        .font(.rowSubtitle)
                        .foregroundStyle(Palette.ink)
                }
            }
            .padding(.vertical, OneDayMetrics.spacingS)
        } header: {
            supportHeader(L10n.string(heading))
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(supportRowInsets)
    }
}
