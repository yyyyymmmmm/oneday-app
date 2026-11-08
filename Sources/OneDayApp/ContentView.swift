import OneDayDesign
import SwiftUI

/// 底部四格（聊天／总览／文件／设置；IA 不动）。
/// 0.2.4：底栏回归 SwiftUI 原生 TabView——iOS 26 由系统亲自
/// 渲染 Liquid Glass：材质折光、边缘高光、滚动收起、键盘
/// 联动全走系统。0.2.2 的自绘贴底栏、0.2.3 的自绘玻璃悬浮
/// 栏，连同键盘通知监听、frame 级下沿预留、opacity 页切换
/// 一并删除，不在自绘件上打补丁。
/// 只要图标不要文字：tabItem 只放线条图标（系统 image-only
/// 条目形态），名称只进无障碍标签；选中着色走系统 tint
/// 通道（.tint = 主题 primary，系统允许的主题色入口）。
/// 0.2.3 的自绘浅灰胶囊＋4pt 微点没有系统挂钩，按「冲突时
/// 系统优先」撤销，取舍在案（DESIGN-V4 §8）。
/// 层级与避让全部服从系统默认：聊天抽屉（页内覆盖层）打开
/// 时底栏按系统层级浮于其上；键盘弹起时由系统处理；各页
/// 滚动内容经系统安全区延伸到底栏之下，从玻璃背后流过。
/// 深链口径不变：AgentRoute / SettingsRoute 落点仍是设置格；
/// 聊天第一格默认落点。
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
        TabView(selection: $selection) {
            ChatView(
                onOpenSettings: { selection = .settings },
                onOpenServerSession: { id in
                    appState.pendingAgentRoute = .serverSessionDetail(id)
                    selection = .settings
                }
            )
            .tabItem {
                Image(systemName: "bubble.left.and.bubble.right")
                    .accessibilityLabel("聊天")
                    .accessibilityIdentifier("tab.chat")
            }
            .tag(MainTab.chat)

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
            .tabItem {
                Image(systemName: "gauge.with.dots.needle.33percent")
                    .accessibilityLabel("总览")
                    .accessibilityIdentifier("tab.overview")
            }
            .tag(MainTab.overview)

            FilesView()
                .tabItem {
                    Image(systemName: "folder")
                        .accessibilityLabel("文件")
                        .accessibilityIdentifier("tab.files")
                }
                .tag(MainTab.files)

            SettingsView()
                .tabItem {
                    Image(systemName: "gearshape")
                        .accessibilityLabel("设置")
                        .accessibilityIdentifier("tab.settings")
                }
                .tag(MainTab.settings)
        }
        .tint(Palette.primary)
    }
}
