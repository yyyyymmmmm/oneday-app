import OneDayDesign
import SwiftUI

/// 枢纽头像钮（§202 立、§434 升 hero 档、§449
/// 沿用）：身份头像是顶带里居中的**独立**圆形
/// 按钮——自带头像＋状态角点（§449 去重后在线
/// 状态全簇唯一呈现点），点它开枢纽（呈现＝
/// ChatView 导航 push＋zoom，本件只管触发）。
/// §202 时与它同排的模型胶囊（ModelCapsule-
/// View）已随 §449 第 2 条整件退役（模型入口
/// 唯一收中枢），顶带内不再有相邻融接之虞。
///
/// 沿革：0.6.0–0.50.26 头像/名/状态与模型同装一
/// 颗双动作胶囊（IdentityCapsuleView），融域命中
/// 在真机反复派错（§179/症二、0.50.26 终验判
/// 红），用户 2026-11-13 拍板路线 B 拆开：胶囊
/// 只管模型、枢纽回归独立入口。无障碍标签文案
/// 自旧胶囊身份域逐字承接（「名，状态，打开枢
/// 纽」），不随旧件删除丢失。
///
/// 命中域口径：视觉盘＝头像本体（边长走形象档，
/// 与旧胶囊同源 avatarPointSize）；命中域外扩
/// 至 minTapTarget 44 圆盘（与同排汉堡/铃铛圆钮
/// 的「视觉盘居中、命中域 44」同式），content-
/// Shape 与命中盘同形（Circle）。状态点压头像
/// 右下、衬一圈页面色环保证压在头像上也可辨。
struct HubAvatarButton: View {
    var avatar: Image
    /// 活头像控制器（§479）：在位时盘内改播状态
    /// 片段（静态图作兜底）；不在位维持纯静态呈现
    var livingAvatar: LivingAvatarController? = nil
    var displayName: String
    var statusWord: String
    var statusColor: Color
    var avatarPointSize: CGFloat
    var onOpenHub: () -> Void

    var body: some View {
        Button {
            onOpenHub()
        } label: {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let livingAvatar {
                        LivingAvatarView(
                            controller: livingAvatar,
                            fallback: avatar
                        )
                    } else {
                        avatar
                            .resizable()
                            .scaledToFill()
                    }
                }
                .frame(
                    width: avatarPointSize,
                    height: avatarPointSize
                )
                .clipShape(Circle())
                .accessibilityHidden(true)
                StatusDot(color: statusColor)
                    .background {
                        Circle()
                            .fill(Palette.chatSurface)
                            .padding(-1.5)
                    }
            }
            .frame(
                width: avatarPointSize,
                height: avatarPointSize
            )
            // §434：命中帧取大者——形象档（≤34）时恒
            // 为 44 外扩、旧行为不变；聊天页 hero 档
            // （67）时以头像本体为准，不许 44 帧反压
            // 大头像致布局溢出
            .frame(
                width: max(avatarPointSize, OneDayMetrics.minTapTarget),
                height: max(avatarPointSize, OneDayMetrics.minTapTarget)
            )
            .contentShape(Circle())
        }
        .buttonStyle(.odPressable)
        .accessibilityLabel("\(displayName)，\(statusWord)，打开枢纽")
        .accessibilityIdentifier("topbar.hubAvatarButton")
    }
}
