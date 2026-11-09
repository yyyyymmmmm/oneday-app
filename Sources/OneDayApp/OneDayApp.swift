import OneDayDesign
import SwiftData
import SwiftUI

@main
struct OneDayApp: App {
    @State private var appState: AppState
    private let container: ModelContainer

    init() {
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

/// 根切换：未连接只给连接页，连上才进四栏。
/// 会话 cookie 可能已过期，总览页拉配置时由 AppState 自动重登兜底。
struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    /// 外观三档（0.4.0，§1.1 AccentTheme 废止后的最小
    /// 改型）：AppearanceView 的 Picker 写同一 AppStorage
    /// 键，根层在此施加 .preferredColorScheme（跟随系统
    /// ＝nil）
    @AppStorage("appearanceMode") private var appearanceModeRaw =
        AppearanceMode.system.rawValue

    var body: some View {
        Group {
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
        .task {
            // 演示样本播种：内存库为空时种一轮拟真对话（仅演示模式）
            if DemoMode.current.isDemo {
                DemoSeeder.seedIfNeeded(context: modelContext)
            }
        }
    }
}
