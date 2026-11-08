import Combine
import OneDayDesign
import SwiftUI
import UIKit

/// 底部四格（聊天／总览／文件／设置；IA 不动）。
/// 0.2.3（docs/DESIGN-V4.md §2，Liquid Glass 定版）：底栏改
/// iOS 26 玻璃悬浮胶囊——仅图标无线条文字（无障碍标签保留），
/// 选中态＝浅灰高亮胶囊＋墨色图标＋4pt 主题微点；栏以 overlay
/// 悬浮于内容上（玻璃半透明才有意义），抽屉打开或键盘弹起时
/// 隐藏，页面内容以 safeAreaInset 预留下沿空间。
/// 四页常驻挂载（opacity 切换）保各自状态，与 TabView 行为一致。
/// 深链口径不变：AgentRoute 落点统一是设置格，SettingsRoute
/// 不变；聊天第一格默认。
struct ContentView: View {
    enum MainTab: Hashable {
        case chat
        case overview
        case files
        case settings
    }

    @Environment(AppState.self) private var appState
    @State private var selection: MainTab = .chat
    /// 键盘可见性（底栏避让口径，DESIGN-V4 §2）：弹起即藏栏
    @State private var keyboardVisible = false

    private var barHidden: Bool {
        appState.drawerPresented || keyboardVisible
    }

    var body: some View {
        ZStack(alignment: .bottom) {
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
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: 76)
            }
            .animation(.easeInOut(duration: 0.18), value: selection)

            if !barHidden {
                glassTabBar
                    .padding(.bottom, 10)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: barHidden)
        .tint(Palette.primary)
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIResponder.keyboardWillShowNotification
            )
        ) { _ in
            keyboardVisible = true
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIResponder.keyboardWillHideNotification
            )
        ) { _ in
            keyboardVisible = false
        }
    }

    // MARK: - 玻璃悬浮栏（仅图标）

    private var glassTabBar: some View {
        HStack(spacing: 4) {
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
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        // 玻璃在布局之后施加（LG 审查清单：modifier order）
        .glassEffect(.regular, in: Capsule())
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
                Circle()
                    .fill(selected ? Palette.primary : Color.clear)
                    .frame(width: 4, height: 4)
            }
            .foregroundStyle(selected ? Palette.ink : Palette.inkMuted)
            .frame(width: 62, height: 44)
            .background(
                selected ? Palette.fieldFill : Color.clear,
                in: Capsule()
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.odPressable)
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
