import OneDayDesign
import SwiftUI

/// 底部四格（0.2.1 用户改版）：聊天／总览／文件／设置。
/// IA v3 的「智能体」格取消——运维四模块并入设置页「智能体」
/// 组；第三格改为「文件」（服务端工作区，仿 Muse 资源库）。
/// 深链口径随之调整：AgentRoute 的落点统一是设置格（其内
/// NavigationStack 消费 pendingAgentRoute），SettingsRoute
/// 不变。聊天仍是第一格与默认落点。
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
            Tab("聊天", systemImage: "bubble.left.and.bubble.right", value: MainTab.chat) {
                ChatView(
                    onOpenSettings: { selection = .settings },
                    onOpenServerSession: { id in
                        appState.pendingAgentRoute = .serverSessionDetail(id)
                        selection = .settings
                    }
                )
            }
            Tab("总览", systemImage: "gauge.with.dots.needle.33percent", value: MainTab.overview) {
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
            }
            Tab("文件", systemImage: "folder", value: MainTab.files) {
                FilesView()
            }
            Tab("设置", systemImage: "gearshape", value: MainTab.settings) {
                SettingsView()
            }
        }
        .tint(Palette.primary)
    }
}
