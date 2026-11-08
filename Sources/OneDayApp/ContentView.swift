import OneDayDesign
import SwiftUI

/// 底部四格（0.1.3 导航定版，见 docs/DESIGN-V2.md §7）：聊天是
/// 第一格与默认落点——OneDay 的主任务是与自托管 Agent 对话，
/// 总览/管理/设置是它的支撑面。ChatGPT 与 Claude 都没有底栏
/// （纯聊天产品），OneDay 保留底栏的取舍记录在定版追记里。
struct ContentView: View {
    enum MainTab: Hashable {
        case chat
        case overview
        case manage
        case settings
    }

    @State private var selection: MainTab = .chat

    var body: some View {
        TabView(selection: $selection) {
            Tab("聊天", systemImage: "bubble.left.and.bubble.right", value: MainTab.chat) {
                ChatView(onOpenSettings: { selection = .settings })
            }
            Tab("总览", systemImage: "gauge.with.dots.needle.33percent", value: MainTab.overview) {
                OverviewView()
            }
            Tab("管理", systemImage: "square.grid.2x2", value: MainTab.manage) {
                ManageView()
            }
            Tab("设置", systemImage: "gearshape", value: MainTab.settings) {
                SettingsView()
            }
        }
        .tint(Palette.ink)
    }
}
