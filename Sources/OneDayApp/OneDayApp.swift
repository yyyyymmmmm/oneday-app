import OneDayCore
import OneDayDesign
import SwiftData
import SwiftUI

@main
struct OneDayApp: App {
    @State private var appState: AppState
    private let container: ModelContainer

    init() {
        // 0.33.1：退役桥钥残项清理——0.32.1 写进 Keychain
        // 的五条 bridge.key.* 分项钥在启动时删净（清单与
        // 删除面见 RetiredBridgeKeyCleanup，只删这组键、
        // 登录凭据不动）；每次启动跑一遍、幂等无害
        RetiredBridgeKeyCleanup.purge()
        // 演示模式（截图验收环）：启动参数触发，换假客户端＋
        // 内存库，正常启动路径与持久化口径零变化。
        let demo = DemoMode.current
        _appState = State(initialValue: AppState(
            client: demo.isDemo ? DemoHermesClient() : HermesClient(),
            demoMode: demo
        ))
        let schema = Schema([ChatThread.self, ChatEntry.self])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: demo.isDemo
        )
        // 与 .modelContainer(for:) 修饰符同口径：建库失败即致命错误
        // swiftlint:disable:next force_try
        container = try! ModelContainer(for: schema, configurations: [configuration])
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                // 全 App 固定中文区域（沿礼记口径：系统控件跟随中文）
                .environment(\.locale, Locale(identifier: "zh_CN"))
        }
        .modelContainer(container)
    }
}

/// 根切换：未连接只给连接页，连上才进五格。
/// 会话 cookie 可能已过期，总览页拉配置时由 AppState 自动重登兜底。
struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    /// 设备会话生命周期驱动（0.34.0）：前台＋已连接
    /// 才注册设备会话，退后台即断开（见 deviceHooks）
    @Environment(\.scenePhase) private var scenePhase
    /// 外观三档（0.4.0，§1.1 AccentTheme 废止后的最小
    /// 改型）：AppearanceView 的 Picker 写同一 AppStorage
    /// 键，根层在此施加 .preferredColorScheme（跟随系统
    /// ＝nil）
    @AppStorage("appearanceMode") private var appearanceModeRaw =
        AppearanceMode.system.rawValue
    /// 外观·聊天主题/形象大小（0.26.0）：根层只观察
    /// （body 里读一次挂上依赖）——任一键变更即重渲
    /// 整棵树，Palette 主题角色与各页档位在重渲中重
    /// 新求值，是主题/形象切换即时全 App 生效的机制
    /// 本体（值本身由 Palette/各组件各自消费）
    @AppStorage(AppearanceStorageKeys.chatTheme)
    private var chatThemeRaw = ChatThemes.defaultID
    @AppStorage(AppearanceStorageKeys.avatarSize)
    private var avatarSizeRaw = AvatarSizeTier.medium.rawValue

    var body: some View {
        _ = chatThemeRaw
        _ = avatarSizeRaw
        return Group {
            switch appState.phase {
            case .needsConnection:
                ConnectView()
            case .connected:
                ContentView()
            }
        }
        // 0.4.0（审计 §1.1／§8 一期）：根层 pageCrossfade
        // 注入已删——自研动效不许在根层给系统切换强加动
        // 画，连接态切换呈现回系统默认
        .preferredColorScheme(
            AppearanceMode(rawValue: appearanceModeRaw)?.colorScheme
        )
        .background(Palette.pageBG)
        // 设备会话（0.34.0）：连接成立且在前台→激活；
        // 退后台/断开→停会话。桥侧另有 45 秒无心跳自
        // 动判离线兜底，杀进程也不会留假在线
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                appState.deviceSession.activate(
                    config: appState.config, isDemo: appState.isDemo
                )
                if !appState.isDemo {
                    appState.deviceSync.foregroundCheck(
                        config: appState.config
                    )
                }
            } else if newPhase == .background {
                appState.deviceSession.deactivate()
            }
        }
        .onChange(of: appState.phase == .connected) { _, connected in
            if connected {
                appState.deviceSession.activate(
                    config: appState.config, isDemo: appState.isDemo
                )
                if !appState.isDemo {
                    appState.deviceSync.foregroundCheck(
                        config: appState.config
                    )
                }
            } else {
                appState.deviceSession.deactivate()
            }
        }
        .task {
            // 冷启恢复的连接不触发 onChange，设备会话
            // 在此补一次激活（activate 内部幂等）
            appState.deviceSession.activate(
                config: appState.config, isDemo: appState.isDemo
            )
            if !appState.isDemo {
                appState.deviceSync.foregroundCheck(
                    config: appState.config
                )
            }
            // 演示样本播种：内存库为空时种一轮拟真对话（仅演示模式）
            if DemoMode.current.isDemo {
                DemoSeeder.seedIfNeeded(context: modelContext)
            }
        }
    }
}
