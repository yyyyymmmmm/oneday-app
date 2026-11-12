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
/// 玻璃承载（§179 硬纪律，改此行前先读该节）：玻
/// 璃只许作行**背景层**（下方 background 里的
/// Capsule 玻璃背板），不许再把 .glassEffect 直接
/// 加回行本体——0.17.0–0.50.21 的行本体玻璃会在
/// iOS 26 生成单一 UIPlatformGlassInteraction-
/// View 盖满整颗胶囊（宿主实测 256×42、与行帧逐
/// 点同域），两钮失去独立命中域：胶囊上缘玻璃带
/// （在任何标签之外、紧贴状态栏带下沿 9pt）落点
/// 被整面吞下按位置派给模型钮，用户点状态栏求回
/// 顶却开模型面（2026-11-12 真机点名）。背景层玻
/// 璃不生成交互视图（宿主实测：胶囊玻璃交互视图
/// 消失、只剩左右圆钮各自独立的玻璃盘），两钮命
/// 中域回到各自 label 的 contentShape。视觉复合
/// 不变：玻璃恒在内容之后采样同一画布。
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

    var body: some View {
        ViewThatFits(in: .horizontal) {
            capsuleRow(showName: true)
            capsuleRow(showName: false)
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
            .buttonStyle(.odPressable)
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
            .buttonStyle(.odPressable)
            .accessibilityLabel(modelAccessibilityLabel)
        }
        .padding(.horizontal, OneDayMetrics.spacingSM)
        .padding(.vertical, 7)
        // §179：玻璃只作背景背板（见文件头硬纪律）；
        // 0.17.0 本体换玻璃的定案（浮件自带 backdrop
        // 模糊＋明度调整、.regular 为系统浮件默认档、
        // 聊天页禁用 .clear）由背板同档承接
        .background {
            Capsule()
                .fill(.clear)
                .glassEffect(.regular, in: Capsule())
        }
    }
}
