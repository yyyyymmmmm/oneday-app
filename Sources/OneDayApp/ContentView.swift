import OneDayCore
import OneDayDesign
import SwiftUI

/// 底部四格（聊天／总览／文件／设置；IA 不动）。
/// 底栏沿革：0.2.4 回归原生 TabView → 0.3.1 换 Tab(value:)
/// ＋Label 直渲 → 0.3.8 按当时裁决隐藏原生栏、叠自绘
/// FloatingTabBar → **0.4.0 拆自绘、回原生（审计 §3.2）**：
/// 自绘前提「原生选中垫宽约 98pt 改不了」已被 Muse 本体
/// 截图证伪（它用的就是 iOS 26 原生玻璃坞）；本版删四处
/// .toolbarVisibility(.hidden)、删覆盖层与 FloatingTabBar
/// 本体、删 TabBarLayout，呈现全交系统——Liquid Glass 坞、
/// 选中态、滚动最小化、键盘联动都是系统行为（WWDC25-323）。
/// 符号源仍是 OneDayCore.TabBarSymbols（原生 Tab 的 Label
/// 直接取用，§1.2 #28 数据保留）；Label 标题随栏进系统
/// 排布（0.3.1 礼记同款口径）。
/// 抽屉与底栏的关系（§3.2 影响面 1，推荐案）：不为抽屉
/// 态隐藏底栏——抽屉打开时原生玻璃坞按系统层级浮于抽屉
/// 之上，抽屉底条经面板安全区让位（ChatView drawer 侧
/// bottomInset 含底栏安全区高、系统给多少让多少）。
/// 深链口径：AgentRoute / SettingsRoute 落点仍是设置格；
/// 服务端会话续聊（§3.4）经 pendingChatSessionID 切聊天格。
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
            Tab(value: MainTab.chat) {
                ChatView(
                    onOpenServerSession: { id in
                        // 0.4.0（§3.4）：服务端会话改道
                        // 聊天页续聊，不再送设置格只读详情
                        appState.pendingChatSessionID = id
                    },
                    onSelectTab: { selection = $0 }
                )
            } label: {
                Label(
                    TabBarSymbols.chat.title,
                    systemImage: TabBarSymbols.chat.normal
                )
            }

            Tab(value: MainTab.overview) {
                OverviewView(
                    onOpenAgent: { route in
                        appState.pendingAgentRoute = route
                        selection = .settings
                    },
                    onOpenChatSession: { id in
                        appState.pendingChatSessionID = id
                    },
                    onOpenSettings: { route in
                        appState.pendingSettingsRoute = route
                        selection = .settings
                    },
                    onOpenChat: { selection = .chat }
                )
            } label: {
                Label(
                    TabBarSymbols.overview.title,
                    systemImage: TabBarSymbols.overview.normal
                )
            }

            Tab(value: MainTab.files) {
                FilesView()
            } label: {
                Label(
                    TabBarSymbols.files.title,
                    systemImage: TabBarSymbols.files.normal
                )
            }

            Tab(value: MainTab.settings) {
                SettingsView()
            } label: {
                Label(
                    TabBarSymbols.settings.title,
                    systemImage: TabBarSymbols.settings.normal
                )
            }
        }
        // 0.4.0（审计 §1.1）：根 .tint(Palette.ink) 与暗色
        // 字重降档 hack 一并删除——tint 回系统默认（强调
        // 色由系统/用户系统设置决定），字重不再做环境级
        // 覆写（正文字重回归语义样式自带，批次 4 收口）
        // 0.4.0（§3.4）：任一入口置位待续聊会话 → 切聊天格
        // （ChatView 侧消费导入；已在聊天格时 onChange 同样
        // 触发、由 ChatView 直接消费）
        .onChange(of: appState.pendingChatSessionID) { _, id in
            if id != nil { selection = .chat }
        }
    }
}
