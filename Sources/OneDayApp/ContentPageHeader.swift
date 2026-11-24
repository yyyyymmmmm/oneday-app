import OneDayCore
import OneDayDesign
import SwiftUI

/// 内容页共同页头簇（§486 立、§498 收编为单源）：动态/
/// 点子/目标/资源库四内容页共用同一簇——左抽屉圆钮＋
/// 居中身份区（大头像 hero＋身份胶囊压下沿，与聊天页
/// topBand 同构成同数值）＋右页专属动作位（逐页登记
/// 见 §498：动态＝滑杆、点子＝无、目标＝无、资源库＝
/// 放大镜＋菜单）。
/// §498（用户 2026-11-24 真机点名）：§486.4 的滚动整
/// 簇收起废止——共同簇在全部主页面恒常驻，滚动不消
/// 失、不淡没、不位移（聊天页现行行为）；几何对齐聊
/// 天 topBand 定版：钮行顶距 spacingS（钮心在头像心
/// 上方 ≈8，§449.3）、hero 顶距 spacingXS、带高 107
/// （头像 67＋胶囊 44－重叠 8＋顶距 4）。胶囊状态词
/// 与聊天同源（§474：liveActivityPhrase 直读、无活
/// 动留空，不回落连接词）；头像钮接活头像（§479，
/// 与聊天同路）。
struct ContentPageHeader<Trailing: View>: View {
    @Environment(AppState.self) private var appState

    var onOpenHub: () -> Void
    @ViewBuilder var trailing: Trailing

    var body: some View {
        ZStack(alignment: .top) {
            hero
            HStack(alignment: .center) {
                PageHeaderCircleButton(
                    symbol: "line.3.horizontal",
                    label: "会话列表"
                ) {
                    appState.router.drawerPresented = true
                }
                Spacer()
                trailing
            }
            // 钮行顶距与聊天 topBand 同值（spacingS）：
            // 钮心落在头像心上方 ≈8pt（§449.3 量测
            // 定版）；§486 旧值 spacingSM 钮心低 4pt，
            // §498 对齐废止
            .padding(.top, OneDayMetrics.spacingS)
        }
        .padding(.horizontal, OneDayMetrics.pageGutter)
    }

    /// 居中身份区：与聊天页 headerIdentityHero 逐值同
    /// 构成（HubAvatarButton hero 档＋HubIdentity-
    /// Capsule 压下沿 8）——同件同数，不许在本件另
    /// 定一套。状态点数据源与文件页旧 IdentityAnchor
    /// 同口径（config 在位判定；聊天页走总览桥
    /// statusTone，边缘态分叉登记于 §498）
    private var hero: some View {
        ZStack(alignment: .bottom) {
            HubAvatarButton(
                avatar: appState.agentAvatarImage,
                livingAvatar: appState.livingAvatar,
                displayName: appState.agentDisplayName,
                statusWord: statusWord,
                statusColor: statusColor,
                avatarPointSize: OneDayMetrics.avatarChatHero,
                onOpenHub: onOpenHub
            )
            .padding(.bottom, 36)

            HubIdentityCapsule(
                displayName: appState.agentDisplayName,
                // §474/§498：第二行只读工作短语（与聊
                // 天胶囊同源同口径）；无活动传 nil 留
                // 空——§486 旧回落「在线/未连接」删除
                statusWord: appState.liveActivityPhrase,
                onOpenHub: onOpenHub
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.top, OneDayMetrics.spacingXS)
    }

    /// 连接状态词（头像钮状态点/无障碍口径：config
    /// 缺位＝未连接；胶囊第二行不消费本词）
    private var statusWord: String {
        appState.config == nil ? "未连接" : "在线"
    }

    private var statusColor: Color {
        appState.config == nil ? Palette.inkMuted : Palette.success
    }
}

/// 页头圆盘视觉（单源）：系统玻璃盘 40＋字形 20＋
/// 命中域外扩 44。按钮（PageHeaderCircleButton）与
/// 菜单标签（资源库 ···）共用同一视觉本体，不许各
/// 页另描一遍
struct PageHeaderCircleGlyph: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(
                size: HeaderButtonSpec.glyphPointSize,
                weight: .regular
            ))
            .foregroundStyle(Palette.ink)
            .frame(
                width: HeaderButtonSpec.diameter,
                height: HeaderButtonSpec.diameter
            )
            .glassEffect(.regular, in: Circle())
            .frame(
                width: OneDayMetrics.minTapTarget,
                height: OneDayMetrics.minTapTarget
            )
            .contentShape(Rectangle())
    }
}

/// 页头圆钮（聊天页顶栏圆钮同规格：HeaderButtonSpec
/// 单源，见 PageHeaderCircleGlyph）
struct PageHeaderCircleButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            PageHeaderCircleGlyph(symbol: symbol)
        }
        .buttonStyle(.odPressable)
        .accessibilityLabel(label)
    }
}
