import OneDayDesign
import SwiftUI

/// 底部四格（IA v3 定版，docs/IA-V3.md §5.1）：聊天／总览／
/// 智能体／设置。分界线来自智能体竞品集的成文纪律：配置类
/// （模型/密钥/连接）进设置，运维类（记忆/技能/定时/服务端
/// 会话）进「智能体」格——不是把 0.1.3 的整包「管理」格搬回来。
/// 聊天仍是第一格与默认落点（OneDay 是对话优先的个人客户端，
/// 取舍在 IA-V3 §5.1 明记）。
struct ContentView: View {
    enum MainTab: Hashable {
        case chat
        case overview
        case agent
        case settings
    }

    @Environment(AppState.self) private var appState
    @State private var selection: MainTab = .chat

    var body: some View {
        TabView(selection: $selection) {
            Tab("聊天", systemImage: "bubble.left.and.bubble.right", value: MainTab.chat) {
                ChatView(onOpenSettings: { selection = .settings })
            }
            Tab("总览", systemImage: "gauge.with.dots.needle.33percent", value: MainTab.overview) {
                OverviewView(
                    onOpenAgent: { route in
                        appState.pendingAgentRoute = route
                        selection = .agent
                    },
                    onOpenSettings: { route in
                        appState.pendingSettingsRoute = route
                        selection = .settings
                    },
                    onOpenChat: { selection = .chat }
                )
            }
            Tab("智能体", systemImage: "sparkles", value: MainTab.agent) {
                AgentView()
            }
            Tab("设置", systemImage: "gearshape", value: MainTab.settings) {
                SettingsView()
            }
        }
        .tint(Palette.ink)
    }
}
