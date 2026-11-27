import OneDayCore
import OneDayDesign
import SwiftData
import SwiftUI

/// §237（基础正解批 P10）：本地库启动结果——原库
/// 建不成时不许再 `try!` 把 App 砖死：先降级到临
/// 时内存库把界面打开，并把「原记录未删、本次内
/// 容不落盘」明示给用户；连内存库也建不成时只剩
/// 专门的不可用页，不伪造一个能用的主界面。
struct ChatModelContainerBootstrap {
    let container: ModelContainer?
    let usesFallback: Bool
    let failureMessage: String?
    /// 打开前备份的主文件（§332）：落盘打开时留的
    /// 回滚点；内存形态/首装无库时为 nil
    let backupStoreURL: URL?
}

enum ChatModelContainerBootstrapFactory {
    /// 生产入口。§332（根治版包 3）起打开次序改
    /// 为「先备份、带迁移链打开、失败才降级」：
    /// Schema 只许经 CurrentChatSchema＋ChatMigra-
    /// tionPlan 立，不许再裸 Schema 直开落盘库
    static func make(
        isStoredInMemoryOnly: Bool
    ) -> ChatModelContainerBootstrap {
        let schema = Schema(versionedSchema: CurrentChatSchema.self)
        if isStoredInMemoryOnly {
            // 内存形态（演示模式）：无文件、无迁移、
            // 无备份，走既有主/降级缝
            return make(
                primary: {
                    try ModelContainer(
                        for: schema,
                        migrationPlan: ChatMigrationPlan.self,
                        configurations: [ModelConfiguration(
                            schema: schema,
                            isStoredInMemoryOnly: true
                        )]
                    )
                },
                fallback: {
                    try ModelContainer(
                        for: schema,
                        migrationPlan: ChatMigrationPlan.self,
                        configurations: [ModelConfiguration(
                            schema: schema,
                            isStoredInMemoryOnly: true
                        )]
                    )
                }
            )
        }
        let storeURL = ModelConfiguration(
            schema: schema, isStoredInMemoryOnly: false
        ).url
        return makePersistent(storeURL: storeURL)
    }

    /// 落盘打开（可测缝：显式库文件 URL，次序与生
    /// 产入口同构）：①迁移前备份（ChatStoreBack-
    /// up，失败留痕后继续——备份是兜底不是闸）；
    /// ②带迁移链打开（迁移在容器 init 内沿链逐级
    /// 走）；③打开/迁移失败留痕＋走 P10 降级（内
    /// 存库＋明示＋原文件保留），备份随结果带出、
    /// 提示里点名，恢复有据可依
    static func makePersistent(
        storeURL: URL
    ) -> ChatModelContainerBootstrap {
        let schema = Schema(versionedSchema: CurrentChatSchema.self)
        var backupURL: URL?
        do {
            backupURL = try ChatStoreBackup.backupStoreIfPresent(
                at: storeURL,
                versionTag: CurrentChatSchema.versionTag
            )
        } catch {
            ChatDiagTrace.record(
                "本地库迁移前备份失败："
                    + error.localizedDescription
                    + "——继续尝试打开原库"
            )
        }
        let result = make(
            primary: {
                do {
                    return try ModelContainer(
                        for: schema,
                        migrationPlan: ChatMigrationPlan.self,
                        configurations: [ModelConfiguration(
                            schema: schema, url: storeURL
                        )]
                    )
                } catch {
                    ChatDiagTrace.record(
                        "本地库打开失败（将降级内存库）："
                            + error.localizedDescription
                    )
                    throw error
                }
            },
            fallback: {
                try ModelContainer(
                    for: schema,
                    migrationPlan: ChatMigrationPlan.self,
                    configurations: [ModelConfiguration(
                        schema: schema,
                        isStoredInMemoryOnly: true
                    )]
                )
            }
        )
        guard result.usesFallback else {
            return ChatModelContainerBootstrap(
                container: result.container,
                usesFallback: false,
                failureMessage: nil,
                backupStoreURL: backupURL
            )
        }
        let message = (result.failureMessage ?? "")
            + (backupURL != nil
                ? "打开前的备份已保留，可供恢复。"
                : "")
        return ChatModelContainerBootstrap(
            container: result.container,
            usesFallback: true,
            failureMessage: message,
            backupStoreURL: backupURL
        )
    }

    /// 可测缝：primary 失败才走 fallback；fallback
    /// 也失败则 container 为 nil，由根层显示不可用
    /// 页。任何一路都不删原库文件。
    static func make(
        primary: () throws -> ModelContainer,
        fallback: () throws -> ModelContainer
    ) -> ChatModelContainerBootstrap {
        do {
            return ChatModelContainerBootstrap(
                container: try primary(),
                usesFallback: false,
                failureMessage: nil,
                backupStoreURL: nil
            )
        } catch {
            do {
                return ChatModelContainerBootstrap(
                    container: try fallback(),
                    usesFallback: true,
                    failureMessage: "本地记录暂时不可用：原来的记录没有删除，重启 App 会再试；这次打开期间的新内容不会保存到本机。",
                    backupStoreURL: nil
                )
            } catch {
                return ChatModelContainerBootstrap(
                    container: nil,
                    usesFallback: true,
                    failureMessage: "本地记录暂时打不开：原来的记录没有删除。请先关闭 App 后重新打开；如果一直这样，请联系支持并说明聊天记录打不开。",
                    backupStoreURL: nil
                )
            }
        }
    }
}

@main
struct OneDayApp: App {
    @State private var appState: AppState
    /// 推送登记回调承接（总表 138，DESIGN §397）：
    /// APNs 令牌/失败回调只经此 adaptor 进 PushRegis-
    /// trationCenter（nonisolated 转 Sendable 值），
    /// 不进视图层
    @UIApplicationDelegateAdaptor(PushAppDelegate.self)
    private var pushAppDelegate
    @State private var storeFallbackNoticeDismissed = false
    private let modelBootstrap: ChatModelContainerBootstrap
    /// 语言覆盖档（§145）：设置页外观·语言 Picker
    /// 写同一 AppStorage 键（LanguageStorageKeys.
    /// appLanguage，单一事实源）；根层在此消费——
    /// 改值即触发 body 重估，下方 .environment 与
    /// .id 双管齐下整树按新语言重建、即时生效、
    /// 不重启、不写 appleLanguages
    @AppStorage(LanguageStorageKeys.appLanguage)
    private var appLanguageRaw = AppLanguagePreference.system.rawValue

    init() {
        // 通知中心委托安装（总表 138，DESIGN §397）：
        // 必须赶在任何本地通知到达前——前台呈现与点按
        // 落点都经它；装晚了首个前台通知会被系统静默
        NotificationCenterDelegate.install()
        // 0.33.1：退役桥钥残项清理——0.32.1 写进 Keychain
        // 的五条 bridge.key.* 分项钥在启动时删净（清单与
        // 删除面见 RetiredBridgeKeyCleanup，只删这组键、
        // 登录凭据不动）；每次启动跑一遍、幂等无害
        RetiredBridgeKeyCleanup.purge()
        // §384（G-14）：崩溃/诊断采集订阅（MetricKit
        // 平台通道）——开关缺省开，关口在关于页内部
        // 实验节；记录过隐私门落本机、报告面回读
        CrashDiagnosticsCollector.shared.startIfEnabled()
        MetricKitDiagnostics.shared.start()
        Task { @MainActor in
            Haptics.prepare()
        }
#if ONEDAY_TABBAR_DIAG
        // §382 底栏诊断（诊断分支专用）：只登记激活
        // 通知、进程内自启四点快照，不碰视图树
        TabBarDiagRecorder.shared.arm()
#endif
        // 演示模式（截图验收环）：启动参数触发，换假客户端＋
        // 内存库，正常启动路径与持久化口径零变化。
        let demo = DemoMode.current
        _appState = State(initialValue: AppState(
            client: demo.isDemo ? DemoHermesClient() : HermesClient(),
            demoMode: demo
        ))
        // §237 P10：建库走可降级工厂——原库失败降
        // 级内存库＋明示，原库文件保留不删；不再用
        // try! 让一次库故障把整个 App 砖死。
        modelBootstrap = ChatModelContainerBootstrapFactory.make(
            isStoredInMemoryOnly: demo.isDemo
        )
    }

    var body: some Scene {
        WindowGroup {
            rootSceneContent
        }
    }

    /// 根内容（容器分叉＋存储降级条）。
    @ViewBuilder
    private var rootSceneContent: some View {
        if let container = modelBootstrap.container {
                // （症二实验台 CapsuleTapHarness 已随
                // §202 路线 B 退役：动作级点按验证改打真
                // App 演示模式装配，见 TopBarSingleAction-
                // TapTests；正常启动路径自此无实验分支）
                RootView()
                    .environment(appState)
                    // 0.42.0 国际化包：旧版「全 App 固定中文
                    // 区域」（沿礼记口径钉 zh_CN）退役——环
                    // 境语言改钉 AppLocale.uiLocale（App 随
                    // 系统语言解析出的界面语言），系统控件
                    // 与视图内格式化器随之与界面语言一致
                    // §145：uiLocale 已改覆盖优先（设置页
                    // 语言档），此处仍只读它一口；再以语言
                    // 档值作 .id 强制整树重建——字面量取词、
                    // Core 格式化与各页缓存的语言形态在切
                    // 换瞬间全体换档，不留半吊子混排
                    .environment(\.locale, AppLocale.uiLocale)
                    .id(appLanguageRaw)
                    .modelContainer(container)
                    .overlay(alignment: .top) {
                        if modelBootstrap.usesFallback,
                           !storeFallbackNoticeDismissed,
                           let message = modelBootstrap.failureMessage {
                            LocalStoreFallbackBanner(
                                message: message
                            ) {
                                storeFallbackNoticeDismissed = true
                            }
                            .padding(.horizontal, OneDayMetrics.pageGutter)
                            .padding(.top, OneDayMetrics.spacingS)
                        }
                    }
            } else {
                LocalStoreUnavailableView(
                    message: modelBootstrap.failureMessage
                        ?? "本地记录暂时打不开：原来的记录没有删除。请先关闭 App 后重新打开。"
                )
                .environment(\.locale, AppLocale.uiLocale)
            }
    }
}

/// §237 P10 降级明示条：只说用户能理解和行动的
/// 话——记录没删、重启再试、本次内容不落盘；不
/// 把 SwiftData/迁移错误原文甩给用户。
private struct LocalStoreFallbackBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: OneDayMetrics.spacingS) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Palette.danger)
                .accessibilityHidden(true)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: FrameworkIcon.smallGlyphSize, weight: .regular))
                    .foregroundStyle(Palette.inkSecondary)
                    .frame(
                        width: OneDayMetrics.minTapTarget,
                        height: OneDayMetrics.minTapTarget
                    )
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("关闭提示")
        }
        .padding(OneDayMetrics.spacingM)
        .background(
            Palette.surface,
            in: RoundedRectangle(
                cornerRadius: OneDayMetrics.containerCorner
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: OneDayMetrics.containerCorner
            )
            .strokeBorder(Palette.hairline, lineWidth: 1)
        }
    }
}

/// §237 P10 最末降级页：原库与内存库都建不成时
/// 的唯一诚实出口，不进主界面、不假装记录可用。
private struct LocalStoreUnavailableView: View {
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label(
                "本地记录暂时打不开",
                systemImage: "exclamationmark.triangle"
            )
        } description: {
            Text(message)
        }
        .background(Palette.pageBG)
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
    // 强调色/背景/圆角/文字大小（§503）：根层同样只
    // 观察（body 读一次挂依赖）。此前只观察主题与形象
    // 大小，漏了这四个键——改强调色等只重渲设置页本
    // 身，主页/聊天要等下一次导航才迟到读到新值（用
    // 户 2026-11-25 报「切换主页半天反应不过来」）。
    // 补齐后任一外观键变更即重渲整棵树，即时全 App 生效。
    @AppStorage(AppearanceStorageKeys.chatAccentOverride)
    private var accentOverrideRaw = -1
    @AppStorage(AppearanceStorageKeys.chatBackground)
    private var chatBackgroundRaw = ChatBackgroundStyle.standard.rawValue
    @AppStorage(AppearanceStorageKeys.chatBubbleStyle)
    private var bubbleStyleRaw = ChatBubbleStyle.standard.rawValue
    @AppStorage(AppearanceStorageKeys.chatTextSize)
    private var chatTextSizeRaw = ChatTextSizeTier.system.rawValue

    var body: some View {
        _ = chatThemeRaw
        _ = avatarSizeRaw
        _ = accentOverrideRaw
        _ = chatBackgroundRaw
        _ = bubbleStyleRaw
        _ = chatTextSizeRaw
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
        .tint(Palette.primary)
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
                // 伴生探测（DESIGN §110）：回前台节流
                // 再探（距上次尝试 <60 秒跳过，口径在
                // CompanionProbeStore）
                Task {
                    await appState.companionProbe.probeIfNeeded(
                        appState: appState
                    )
                    // 头像仓同步（P1）：与伴生探测同拍
                    await appState.syncAgentAvatarFromBridge()
                    // 身份名刷新（身份反映修复）：同拍，
                    // 服务器改名回前台即反映＋覆盖对账
                    await appState.refreshIdentityName()
                    await appState.pushRegistration.synchronize(appState: appState)
                    _ = await CrashDiagnosticsCollector.shared.uploadPendingIfNeeded(appState: appState)
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
                // 伴生探测（DESIGN §110）：登录成功即
                // 探一次（不受回前台节流约束）
                Task {
                    await appState.companionProbe.probe(
                        appState: appState
                    )
                    // 头像仓同步（P1）：与伴生探测同拍
                    await appState.syncAgentAvatarFromBridge()
                    // 身份名刷新（身份反映修复）：同拍
                    await appState.refreshIdentityName()
                    await appState.pushRegistration.synchronize(appState: appState)
                    _ = await CrashDiagnosticsCollector.shared.uploadPendingIfNeeded(appState: appState)
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
            // 伴生探测（DESIGN §110）：冷启恢复连接同
            // 样在此补一次（节流口径，刚登录探过的不会
            // 立刻重探）
            await appState.companionProbe.probeIfNeeded(
                appState: appState
            )
            // 头像仓同步（P1）：冷启恢复同拍补一次
            await appState.syncAgentAvatarFromBridge()
            // 身份名刷新（身份反映修复）：冷启同拍
            await appState.refreshIdentityName()
            await appState.pushRegistration.synchronize(appState: appState)
            _ = await CrashDiagnosticsCollector.shared.uploadPendingIfNeeded(appState: appState)
            // 演示样本播种：内存库为空时种一轮拟真对话（仅演示模式）
            if DemoMode.current.isDemo {
                DemoSeeder.seedIfNeeded(context: modelContext)
            }
        }
        // 快捷指令 x-callback 回执入口（设备扩容批
        // 四）：oneday://shortcut-callback/<nonce>/
        // <档> 由 ShortcutCallbackCenter 按 nonce 交
        // 回等回执的一方；形态不对的一律在中心里安
        // 静忽略，不作出错面
        .onOpenURL { url in
            ShortcutCallbackCenter.handle(url: url)
        }
    }
}
