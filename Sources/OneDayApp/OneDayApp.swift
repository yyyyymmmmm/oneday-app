import OneDayDesign
import SwiftData
import SwiftUI

@main
struct OneDayApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                // 全 App 固定中文区域（沿礼记口径：系统控件跟随中文）
                .environment(\.locale, Locale(identifier: "zh_CN"))
        }
        .modelContainer(for: [ChatThread.self, ChatEntry.self])
    }
}

/// 根切换：未连接只给连接页，连上才进四栏。
/// 会话 cookie 可能已过期，总览页拉配置时由 AppState 自动重登兜底。
struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            switch appState.phase {
            case .needsConnection:
                ConnectView()
            case .connected:
                ContentView()
            }
        }
        .animation(MotionTokens.pageCrossfade, value: appState.phase == .connected)
        .background(Palette.pageBG)
    }
}
