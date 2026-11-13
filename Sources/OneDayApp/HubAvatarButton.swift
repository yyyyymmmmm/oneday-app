import OneDayDesign
import SwiftUI

/// 枢纽头像钮（§202，路线 B「一个胶囊一个动作」
/// 的另一半）：身份头像自此是顶簇里一个**独立**
/// 圆形按钮——自带头像＋在线状态点，点它开枢纽
/// （fullScreenCover 呈现在 ChatView 根，本件只
/// 管触发）。与模型胶囊（ModelCapsuleView）是两
/// 个分开的元素：顶簇内横排间距 ≥8pt（ChatView
/// 侧 spacingS），各自命中域独立、不相邻融接。
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
                avatar
                    .resizable()
                    .scaledToFill()
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
            .frame(
                width: OneDayMetrics.minTapTarget,
                height: OneDayMetrics.minTapTarget
            )
            .contentShape(Circle())
        }
        .buttonStyle(.odPressable)
        .accessibilityLabel("\(displayName)，\(statusWord)，打开枢纽")
        .accessibilityIdentifier("topbar.hubAvatarButton")
    }
}
