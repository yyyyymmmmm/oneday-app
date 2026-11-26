import SwiftUI
import OneDayCore

/// OneDay macOS 客户端入口（原生 SwiftUI，非
/// Catalyst）：主窗口按连接态在登录页与三栏主窗之间
/// 切换；设置走 macOS 标准 Settings 场景（⌘,）；
/// 菜单栏状态项常驻（M1）；外观模式与界面语言由根
/// 层统一消费 AppStorage 单源即时生效（棒 5）。
@main
struct OneDayMacApp: App {
    @State private var session = SessionStore()
    @State private var statusStore = MacStatusStore()
    /// 批准与凭据两店提到 App 级（棒 2）：主窗、批
    /// 准面独立窗、菜单栏三处共用同一份状态
    @State private var approvalStore = MacApprovalStore()
    @State private var vaultStore = MacVaultStore()
    /// 速记窗控制器（棒 3，M2；棒 5 支持设置页改键）
    @State private var quickEntry = MacQuickEntryController()

    @AppStorage(AppearanceStorageKeys.appearanceMode)
    private var appearanceModeRaw = "system"
    @AppStorage(LanguageStorageKeys.appLanguage)
    private var appLanguageRaw = AppLanguagePreference.system.rawValue

    private var preferredScheme: ColorScheme? {
        switch appearanceModeRaw {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    private var preferredLocale: Locale {
        let pref = AppLanguagePreference(rawValue: appLanguageRaw) ?? .system
        if let id = pref.localeIdentifier {
            return Locale(identifier: id)
        }
        return .autoupdatingCurrent
    }

    init() {
        // 通知分类/动作/代理先装配（授权等首次待批
        // 出现时才请求，M3 保底段口径）
        MacNotifier.shared.setup()
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView()
                .environment(session)
                .environment(statusStore)
                .environment(approvalStore)
                .environment(vaultStore)
                .preferredColorScheme(preferredScheme)
                .environment(\.locale, preferredLocale)
                .task {
                    await session.restore()
                    statusStore.start(session: session)
                    quickEntry.bind(session: session)
                    quickEntry.registerHotKey()
                }
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandMenu("导航") {
                Button("全局搜索") {
                    NotificationCenter.default.post(
                        name: .macOpenGlobalSearch, object: nil
                    )
                }
                .keyboardShortcut("k", modifiers: .command)
                Button("速记窗") {
                    quickEntry.toggle()
                }
                .keyboardShortcut(.space, modifiers: .option)
            }
            CommandMenu("服务器") {
                Button("断开连接") {
                    session.disconnect()
                }
                .disabled(!session.isConnected)
            }
        }

        WindowGroup(id: "approvals") {
            MacApprovalsWindowView(store: approvalStore)
                .environment(session)
                .environment(approvalStore)
                .preferredColorScheme(preferredScheme)
                .environment(\.locale, preferredLocale)
        }
        .windowResizability(.contentMinSize)

        MenuBarExtra {
            MacMenuBarView()
                .environment(session)
                .environment(statusStore)
                .preferredColorScheme(preferredScheme)
                .environment(\.locale, preferredLocale)
        } label: {
            MenuBarLabel()
                .environment(statusStore)
        }
        .menuBarExtraStyle(.window)

        Settings {
            MacSettingsView(quickEntry: quickEntry)
                .environment(session)
                .preferredColorScheme(preferredScheme)
                .environment(\.locale, preferredLocale)
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
