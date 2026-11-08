import OneDayDesign
import SwiftUI

/// 底部四格（0.2.1 改版，0.2.2 形态纠偏）：聊天／总览／文件／设置。
/// IA v3 的「智能体」格取消——运维四模块并入设置页「智能体」
/// 组；第三格为「文件」（交付物库）。
/// 0.2.2（DESIGN-V3-NOTES §6）：底栏改自绘贴底栏——iOS 26 系统
/// TabView 的浮动玻璃胶囊会跨层漂浮在抽屉 scrim 之上且选中态
/// 是大面积主题色块，违近单色纪律。自绘栏回归布局流（表面色
/// ＋顶部发丝线），图标全线条体，选中态＝墨色＋字重区分＋一颗
/// 4pt 主题色微点；聊天抽屉打开时整栏隐藏，scrim 完整覆盖。
/// 四页常驻挂载（opacity 切换）保各自状态，与 TabView 行为一致。
/// 深链口径：AgentRoute 落点统一是设置格（其内 NavigationStack
/// 消费 pendingAgentRoute），SettingsRoute 不变；聊天第一格默认。
struct ContentView: View {
    enum MainTab: Hashable {
        case chat
        case overview
        case files
        case settings
    }

    @Environment(AppState.self) private var appState
    @State private var selection: MainTab = .chat

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                ChatView(
                    onOpenSettings: { selection = .settings },
                    onOpenServerSession: { id in
                        appState.pendingAgentRoute = .serverSessionDetail(id)
                        selection = .settings
                    }
                )
                .odTabPage(selection == .chat)

                OverviewView(
                    onOpenAgent: { route in
                        appState.pendingAgentRoute = route
                        selection = .settings
                    },
                    onOpenSettings: { route in
                        appState.pendingSettingsRoute = route
                        selection = .settings
                    },
                    onOpenChat: { selection = .chat }
                )
                .odTabPage(selection == .overview)

                FilesView()
                    .odTabPage(selection == .files)

                SettingsView()
                    .odTabPage(selection == .settings)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !appState.drawerPresented {
                tabBar
            }
        }
        .tint(Palette.primary)
    }

    // MARK: - 自绘贴底栏

    private var tabBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Palette.hairline)
                .frame(height: 1)
            HStack(spacing: 0) {
                tabButton(
                    .chat, id: "tab.chat", title: "聊天",
                    icon: "bubble.left.and.bubble.right"
                )
                tabButton(
                    .overview, id: "tab.overview", title: "总览",
                    icon: "gauge.with.dots.needle.33percent"
                )
                tabButton(
                    .files, id: "tab.files", title: "文件",
                    icon: "folder"
                )
                tabButton(
                    .settings, id: "tab.settings", title: "设置",
                    icon: "gearshape"
                )
            }
            .padding(.top, 6)
            .padding(.bottom, 2)
        }
        .background(Palette.surface.ignoresSafeArea(edges: .bottom))
    }

    private func tabButton(
        _ tab: MainTab, id: String, title: String, icon: String
    ) -> some View {
        let selected = selection == tab
        return Button {
            selection = tab
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 21, weight: selected ? .medium : .regular))
                Text(title)
                    .font(.system(size: 11, weight: selected ? .semibold : .regular))
                Circle()
                    .fill(selected ? Palette.primary : Color.clear)
                    .frame(width: 4, height: 4)
            }
            .foregroundStyle(selected ? Palette.ink : Palette.inkMuted)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
        .accessibilityLabel(title)
    }
}

private extension View {
    /// 常驻挂载的页切换：不可见页不响应点按、不进无障碍树
    func odTabPage(_ active: Bool) -> some View {
        self
            .opacity(active ? 1 : 0)
            .allowsHitTesting(active)
            .accessibilityHidden(!active)
    }
}
