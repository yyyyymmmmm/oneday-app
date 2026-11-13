import OneDayDesign
import SwiftUI

/// 模型胶囊（§198，路线 B「一个胶囊一个动作」）：
/// 顶簇中央只剩一颗单动作胶囊——整颗只有一个
/// Button、只开模型选择面（ChatGPT 顶部式：当前
/// 模型名＋chevron）。身份/枢纽自此不在本件内，
/// 走顶簇里独立的头像钮（HubAvatarButton），两
/// 元素分开排布、命中域互不相邻融接。
///
/// 退役形态（同轮删除）：IdentityCapsuleView 的
/// 双动作玻璃 union 形态（GlassEffectContainer＋
/// 两钮各自 .glassEffect(.regular.interactive())
/// ＋glassEffectUnion 融成一片）——0.50.26 真机终
/// 验判红（点枢纽侧仍升模型列表、胶囊变窄）。社
/// 区实证（调研 capsule-teardown-research-
/// 20261113）：异语义双动作融进一片交互玻璃无生
/// 产先例、交互玻璃命中域是公认雷区（玻璃面≠命
/// 中面、真机吞触摸、行为按小版本漂移），改造路
/// 线经用户 2026-11-13 拍板 B。
///
/// 玻璃口径（单钮常规形态）：玻璃只作本钮自身
/// 的视觉层，且**只挂背景层**——标签本体不带玻
/// 璃，命中链里没有玻璃面：.glassEffect(.regular,
/// in: Capsule()) 加在与标签同帧的背景形状上。
/// 不用 union、不用 .interactive()、不叠第二层
/// 玻璃。按压反馈走 .odPressable（同排圆钮同款）。
/// contentShape 与可见玻璃同形（Capsule），命中
/// 域即按钮帧本形——社区「画形＝交互形」永久实
/// 践。背景化缘由（动作门实测，run 43369981760）：
/// 玻璃挂标签本体时其命中域比钮帧外扩约 4pt——
/// 与头像钮间隔正中（距胶囊缘 4pt）的点也升了
/// 模型面（10/11 点全对、独间隙点违规；无玻璃的
/// 头像钮侧无外溢，对照成立）。玻璃退到背景层
/// 后命中只剩按钮本体帧，间隙再由顶簇侧的显式
/// 隔断兜底（见 ChatView topBarCenterCluster）。
///
/// 尺寸口径：padding（水平 spacingSM 12／垂直
/// 7）在标签内、玻璃覆盖整段标签含 padding 环
/// ——即 153 的整行背板口径，不许再出现「玻璃面
/// 比行帧小一圈」（992944a 把玻璃改挂钮体、pad-
/// ding 环出局致可见玻璃 −24×−14pt，是变窄定因，
/// 见调研 §2.4）。模型名仍是行内唯一可压缩元素
/// （§182 纪律沿用：不 fixedSize、尾部截断保钮
/// 位），其余元素不压缩。
struct ModelCapsuleView: View {
    var modelTriggerLabel: String
    var modelAccessibilityLabel: String
    var onOpenModelPicker: () -> Void

    var body: some View {
        Button {
            onOpenModelPicker()
        } label: {
            HStack(spacing: OneDayMetrics.stackGap) {
                Text(modelTriggerLabel)
                    .font(.callout)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Palette.inkSecondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, OneDayMetrics.spacingSM)
            .padding(.vertical, 7)
            .contentShape(Capsule())
            .background {
                Color.clear
                    .glassEffect(.regular, in: Capsule())
            }
        }
        .buttonStyle(.odPressable)
        .accessibilityLabel(modelAccessibilityLabel)
        .accessibilityIdentifier("topbar.modelCapsule")
    }
}
