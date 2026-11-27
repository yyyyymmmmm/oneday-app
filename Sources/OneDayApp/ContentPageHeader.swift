import OneDayCore
import OneDayDesign
import SwiftUI

/// 内容页共同页头簇（大厂 52pt 标准单行顶栏）：
/// 动态/点子/目标/资源库共用，搭配原生 .safeAreaBar(edge: .top)
/// 自动触发与聊天页一致的 iOS 26 顶部 Liquid Glass 朦胧效果。
struct ContentPageHeader<Trailing: View>: View {
    @Environment(AppState.self) private var appState

    var onOpenHub: () -> Void
    @ViewBuilder var trailing: Trailing

    var body: some View {
        ZStack(alignment: .center) {
            HubIdentityCapsule(
                displayName: appState.agentDisplayName,
                avatar: appState.agentAvatarImage,
                liveActivityPhrase: appState.liveActivityPhrase,
                onOpenHub: onOpenHub
            )
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
        }
        .padding(.horizontal, OneDayMetrics.pageGutter)
        .padding(.vertical, OneDayMetrics.spacingXS)
    }

    private var statusColor: Color {
        appState.config == nil ? Palette.inkMuted : Palette.success
    }
}

/// 页头圆盘视觉（单源）：系统玻璃盘 40＋字形 20＋命中域外扩 44
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

/// 页头圆钮
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
