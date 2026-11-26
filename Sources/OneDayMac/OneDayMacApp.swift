import SwiftUI

/// OneDay macOS 客户端入口（原生 SwiftUI，非
/// Catalyst）：主窗口按连接态在登录页与三栏主窗之间
/// 切换；设置走 macOS 标准 Settings 场景（⌘,）。
@main
struct OneDayMacApp: App {
    @State private var session = SessionStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .task {
                    await session.restore()
                }
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandMenu("服务器") {
                Button("断开连接") {
                    session.disconnect()
                }
                .disabled(!session.isConnected)
            }
        }

        Settings {
            MacSettingsView()
                .environment(session)
        }
    }
}

/// 根视图：已连接进三栏主窗，未连接（或连接失败回落）
/// 停在登录页——与 iOS 首启连接页同一落点口径
struct RootView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        if session.isConnected {
            MainShellView()
        } else {
            LoginView()
        }
    }
}
