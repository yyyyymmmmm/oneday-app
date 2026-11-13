import OneDayDesign
import SwiftUI

/// 身份胶囊（0.6.0 立，0.6.1 布局根修；§179 起独立
/// 成件供宿主命中域回归测试直接覆盖，照 DrawerCol-
/// lapsibleContent 先例）：顶栏正中一颗装头像＋智能
/// 体名＋状态＋模型，拆两个点按域——身份域（头像/
/// 名/状态）点按开枢纽、模型域（分隔线＋短名＋chev-
/// ron）点开分组选择面（本会话作用域，§153）。点按
/// 分工与一颗装口径沿 0.6.0 不变；本件只收值与两个
/// 动作闭包，数据派生（状态词/色、模型短名）留在
/// ChatView 侧单源。
///
/// 布局（0.6.1 根修）：ViewThatFits 两档——全量档
/// （头像＋名＋状态＋模型）宽度不够时整档换紧凑档
/// （只去名字），每档内全部文字 fixedSize 不许截
/// 断，任何宽度下不出现裸「…」（0.6.0 真机缺陷根
/// 源：胶囊内只有状态 Text 一个可压缩元素，长句必
/// 被压成省略号——名字/模型短名都 fixedSize、独它
/// 扛全部收缩；状态词自此先改短词，见 Overview-
/// StatusLine）。
///
/// 例外（§182 移植抽屉题 4）：模型名是行内唯一可
/// 压缩元素——去 fixedSize、lineLimit(1)＋尾部截
/// 断，长模型名截断保两侧钮位（用户口径）；名字/
/// 状态仍 fixedSize 不截断。空间不足时先由 View-
/// ThatFits 落无名档、再不够才截断模型名；短名时
/// 胶囊照常 hug 内容宽。
///
/// 玻璃承载（§179 立、外壳批二阶段二改判，改此件
/// 前先读 TAP-DISPATCH-DATA 与 HIT-SCAN-DATA）：
/// 官方定式——GlassEffectContainer 包裹、两钮各
/// 自 .glassEffect(.regular.interactive())、
/// .glassEffectUnion 同一 id 拼成一片、不用
/// .odPressable（按压由系统玻璃接管）。证据分工
/// 两门：①结构门（hitTest 扫描）：本形态在胶囊中
/// 带有一片 union 玻璃交互面（实测 230×28）同时
/// 盖住两钮中心，「面跨两域」在结构量上成立；但
/// 上/下缘带无玻璃覆盖，与缺陷形态的分界在此。
/// ②动作门（XCUITest 系统级真实点按）：预注册
/// 15 点全量实测——域内/缘带 8 点精确分发、缝点
/// 以分隔线为界就近分发、零派错；union 面按位置
/// 把触摸转发给正确的钮。**放行依据是动作门**，
/// 结构门的跨域面本身不构成派错（本件即其实证）。
/// **禁形态**：.glassEffect 直接加在装有两钮的整
/// 行本体上（0.17.0–0.50.21 旧形态）——生成的单
/// 一玻璃面盖满整行 42 高、连上/下缘带一并吞下
/// 按位置乱派，是 §179 缺陷本体（点状态栏带求回
/// 顶却开模型面）。§179 过渡形态（玻璃降行背景背
/// 板）随本定式落地退役。回归双守：IdentityCap-
/// suleHitDomainTests 守结构不变量（状态栏带与
/// 胶囊缘带 hitTest 永不返回玻璃、玻璃面不得覆
/// 盖缘带），CapsuleTapDispatchUITests 守动作派
/// 发（域内必对、缘带不错侧）。
struct IdentityCapsuleView: View {
    var avatar: Image
    var displayName: String
    var statusWord: String
    var statusColor: Color
    var avatarPointSize: CGFloat
    var modelTriggerLabel: String
    var modelAccessibilityLabel: String
    var onOpenHub: () -> Void
    var onOpenModelPicker: () -> Void

    @Namespace private var glassUnion

    var body: some View {
        GlassEffectContainer {
            ViewThatFits(in: .horizontal) {
                capsuleRow(showName: true)
                capsuleRow(showName: false)
            }
        }
    }

    private func capsuleRow(showName: Bool) -> some View {
        HStack(spacing: OneDayMetrics.spacingS) {
            Button {
                onOpenHub()
            } label: {
                HStack(spacing: OneDayMetrics.spacingS) {
                    // 0.36.22：头像读本地档案（AppState
                    // 单一出口），改名换头像此处同步
                    avatar
                        .resizable()
                        .scaledToFill()
                        // 0.26.0：边长走形象档（小 24/
                        // 中 28/大 34；中档＝旧值）——
                        // 名字/状态段 fixedSize、胶囊 hug
                        // 宽随内容，±6 不挤断。§182：
                        // 模型段除外（长名截断保钮位）
                        .frame(
                            width: avatarPointSize,
                            height: avatarPointSize
                        )
                        .clipShape(Circle())
                        .accessibilityHidden(true)
                    if showName {
                        // 0.36.22：显示名收敛档案出口
                        // （档案覆盖→soul 名→Hermes）
                        Text(displayName)
                            .font(.headline)
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    HStack(spacing: OneDayMetrics.iconTextGap) {
                        StatusDot(color: statusColor)
                        Text(statusWord)
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .contentShape(Rectangle())
            }
            .glassEffect(.regular.interactive(), in: Capsule())
            .glassEffectUnion(id: "identity-capsule", namespace: glassUnion)
            .accessibilityLabel("\(displayName)，\(statusWord)，打开枢纽")

            Rectangle()
                .fill(Palette.hairline)
                .frame(width: 0.5, height: 18)

            // 模型域（§153 B1/B2）：触发器形态不变
            // （短名＋chevron），点开改分组选择面
            // （sheet，呈现宿主在 ChatView 根、§175
            // 迁移，本件只管触发）；勾的纪律与选择
            // 落账在选择面与 ChatView 侧，本件不涉。
            // §182（移植抽屉题 4）：模型名 Text 不
            // fixedSize、允许尾部截断（长名截断保
            // 钮位）；chevron 与其余元素不压缩
            Button {
                onOpenModelPicker()
            } label: {
                HStack(spacing: OneDayMetrics.stackGap) {
                    Text(modelTriggerLabel)
                        .font(.callout)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        // §182：去掉 fixedSize(horizontal:)，
                        // 使模型名成为胶囊内唯一可压缩元素、
                        // 长名时尾部截断不撑宽胶囊
                    Image(systemName: "chevron.down")
                        // 0.23.0（审计 G6）：9pt 字形升
                        // caption2 角色（默认 11 视觉当
                        // 量、随 Dynamic Type 缩放），与
                        // 胶囊内同件同口径
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Palette.inkSecondary)
                }
                .contentShape(Rectangle())
            }
            .glassEffect(.regular.interactive(), in: Capsule())
            .glassEffectUnion(id: "identity-capsule", namespace: glassUnion)
            .accessibilityLabel(modelAccessibilityLabel)
        }
        .padding(.horizontal, OneDayMetrics.spacingSM)
        .padding(.vertical, 7)
    }
}
