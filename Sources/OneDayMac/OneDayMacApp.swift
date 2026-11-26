import SwiftUI

/// OneDay macOS 客户端入口（原生 SwiftUI，非
/// Catalyst）：主窗口按连接态在登录页与三栏主窗之间
/// 切换；设置走 macOS 标准 Settings 场景（⌘,）；
/// 菜单栏状态项常驻（M1 基础形态，棒 1）。
@main
struct OneDayMacApp: App {
    @State private var session = SessionStore()
    @State private var statusStore = MacStatusStore()

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView()
                .environment(session)
                .environment(statusStore)
                .task {
                    await session.restore()
                    statusStore.start(session: session)
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

        MenuBarExtra {
            MacMenuBarView()
                .environment(session)
                .environment(statusStore)
        } label: {
            MenuBarLabel()
                .environment(statusStore)
        }
        .menuBarExtraStyle(.window)

        Settings {
            MacSettingsView()
                .environment(session)
        }
    }
}

/// 菜单栏标签：状态点＋待批数（有待批才显数）
private struct MenuBarLabel: View {
    @Environment(MacStatusStore.self) private var statusStore

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
            if let pending = statusStore.pendingApprovals,
               pending > 0 {
                Text("\(pending)")
            }
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
