import Foundation
import OneDayCore
import UIKit

/// 推送上送缝（可测口）：生产实现直调 HermesClient 的
/// 登记端点；钉测注入假实现验状态机，不许为测试改生产
/// 路径分叉
typealias PushUploadFunction = @Sendable (
    _ client: HermesClientProtocol,
    _ config: ServerConfig,
    _ apiKey: String,
    _ body: PushTokenRegistrationBody
) async throws -> PushTokenRegisteredResponse

/// 系统回调转接盒（回调隔离铁律的落点）：UIApplication-
/// Delegate 的推送回调与通知中心点按回调都是 nonisolated
/// 系统域入口——只许把 Sendable 值（令牌 Data／错误描述
/// 串／已解析路由）交进本盒，不碰任何 actor 隔离状态；
/// 盒内处理器由 PushRegistrationStore 在 init 时认领，
/// 处理器内部再经 Task 跳回主隔离。点按路由若赶在认领
/// 前到达（冷启点按），先存盒内、认领时补交，不许丢。
final class PushRegistrationCenter: @unchecked Sendable {
    static let shared = PushRegistrationCenter()

    private let lock = NSLock()
    private var tokenHandler: (@Sendable (Data) -> Void)?
    private var failureHandler: (@Sendable (String) -> Void)?
    private var routeHandler: (@Sendable (PushNotificationRoute) -> Void)?
    private var bufferedRoute: PushNotificationRoute?

    static func attach(
        onToken: @escaping @Sendable (Data) -> Void,
        onFailure: @escaping @Sendable (String) -> Void,
        onRoute: @escaping @Sendable (PushNotificationRoute) -> Void
    ) {
        shared.attach(
            onToken: onToken, onFailure: onFailure, onRoute: onRoute
        )
    }

    private func attach(
        onToken: @escaping @Sendable (Data) -> Void,
        onFailure: @escaping @Sendable (String) -> Void,
        onRoute: @escaping @Sendable (PushNotificationRoute) -> Void
    ) {
        lock.lock()
        tokenHandler = onToken
        failureHandler = onFailure
        routeHandler = onRoute
        let buffered = bufferedRoute
        bufferedRoute = nil
        lock.unlock()
        if let buffered {
            onRoute(buffered)
        }
    }

    static func deliver(token: Data) {
        shared.lock.lock()
        let handler = shared.tokenHandler
        shared.lock.unlock()
        handler?(token)
    }

    static func deliver(failureDescription: String) {
        shared.lock.lock()
        let handler = shared.failureHandler
        shared.lock.unlock()
        handler?(failureDescription)
    }

    static func deliver(route: PushNotificationRoute) {
        shared.lock.lock()
        if let handler = shared.routeHandler {
            shared.lock.unlock()
            handler(route)
        } else {
            shared.bufferedRoute = route
            shared.lock.unlock()
        }
    }
}

/// 弱盒：转接盒处理器捕获存储本体时经此转手（@Sendable
/// 闭包不直接捕获 @MainActor 类，与本仓弱盒先例同式）
private final class PushStoreWeakBox: @unchecked Sendable {
    weak var value: PushRegistrationStore?
}

/// APNs 回调承接（总表 138，DESIGN §397）：SwiftUI App
/// 无原生令牌回调口，经 UIApplicationDelegateAdaptor
/// 挂本委托——两回调均为 nonisolated，只把 Sendable 值
/// 交进转接盒，不在此碰任何状态（回调隔离铁律）
final class PushAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken
            deviceToken: Data
    ) {
        PushRegistrationCenter.deliver(token: deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError
            error: Error
    ) {
        PushRegistrationCenter.deliver(
            failureDescription: error.localizedDescription
        )
    }
}

/// 推送登记存储（总表 138／G-21 准备面，DESIGN §397）：
/// 持有登记状态机（Core PushRegistrationPhase）、令牌
/// 快照落盘与服务端上送。边界：服务端登记端点属部署
/// 包批 4b（未装机）——上送真回 404 时如实记 serverNot-
/// Ready，不许冒充已登记；签名权益卡付费账号——系统回
/// 调失败如实记 noEntitlement。
///
/// 授权铁律在本类的落法：只在通知授权**现读为 granted**
/// 时发起系统登记（registerForRemoteNotifications 不是
/// 授权请求，但时机仍以已授权为门）；未决定／已拒绝绝
/// 不在此触发任何授权请求——请求归连接引导段，本类连
/// requestAuthorization 都不许出现（结构钉测把守）。
@MainActor
@Observable
/// §416 新鲜度普查豁免：推送注册生命周期事件驱动，无读触发拉取（判定表见 DESIGN §416）
final class PushRegistrationStore {
    private(set) var phase: PushRegistrationPhase = .idle
    private(set) var permission: DevicePermissionState = .notDetermined
    private(set) var snapshot: PushRegistrationSnapshot?
    /// 没能落点的点按路由（如 run 完成推送的会话落点，
    /// 缺口登记见 §397.6）：如实记账待接，不假装已达
    private(set) var pendingRoute: PushNotificationRoute?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let registerAction: @MainActor () -> Void
    @ObservationIgnored private let environmentProvider:
        @Sendable () -> PushEnvironment?
    @ObservationIgnored private let upload: PushUploadFunction
    @ObservationIgnored private weak var appState: AppState?
    @ObservationIgnored private var connection: (
        client: HermesClientProtocol, config: ServerConfig, apiKey: String
    )?
    @ObservationIgnored private var uploadInFlight = false

    private static let snapshotKey = "push.registration.snapshot.v1"

    init(
        defaults: UserDefaults = .standard,
        registerAction: @escaping @MainActor () -> Void = {
            UIApplication.shared.registerForRemoteNotifications()
        },
        environmentProvider: @escaping @Sendable () -> PushEnvironment?
            = {
                guard let url = Bundle.main.url(
                    forResource: "embedded",
                    withExtension: "mobileprovision"
                ), let data = try? Data(contentsOf: url)
                else { return nil }
                return PushProvisionReader.apsEnvironment(
                    fromProvisionData: data
                )
            },
        upload: @escaping PushUploadFunction = { client, config, apiKey, body in
            try await client.registerPushToken(
                config: config, apiKey: apiKey, body: body
            )
        }
    ) {
        self.defaults = defaults
        self.registerAction = registerAction
        self.environmentProvider = environmentProvider
        self.upload = upload
        if let data = defaults.data(forKey: Self.snapshotKey),
           let decoded = try? JSONDecoder().decode(
            PushRegistrationSnapshot.self, from: data
           ) {
            snapshot = decoded
        }
        // 回调认领：转接盒处理器经弱盒跳回主隔离
        let box = PushStoreWeakBox()
        box.value = self
        PushRegistrationCenter.attach(
            onToken: { data in
                Task { @MainActor in box.value?.recordToken(data) }
            },
            onFailure: { description in
                Task { @MainActor in
                    box.value?.recordFailure(description: description)
                }
            },
            onRoute: { route in
                Task { @MainActor in box.value?.handleRoute(route) }
            }
        )
    }

    /// 就绪报告（呈现单源在 Core，本类只喂现行状态）
    var readinessReport: PushReadinessReport {
        PushReadiness.report(
            permission: permission, phase: phase, snapshot: snapshot
        )
    }

    // MARK: 同步（RootView 三处与伴生探测同拍调用）

    /// 冷启／回前台／连接成立时调用：收连接三件套→现读
    /// 授权→granted 才发起登记（每次启动重登记是令牌轮
    /// 换的拾取口，批 4b §4.4）→已有令牌补上送（upsert
    /// 幂等，每次启动真回读，不拿旧账冒充现行）
    func synchronize(appState: AppState) async {
        self.appState = appState
        guard !appState.isDemo else { return }
        if appState.phase == .connected,
           let config = appState.config,
           let apiKey = appState.apiKey {
            adoptConnection(
                client: appState.client, config: config,
                apiKey: apiKey
            )
        }
        await proceed(
            permission: await NotificationEngine.readSystemState()
        )
    }

    /// 授权现读后的推进（synchronize 的可测缝）：钉测
    /// 直喂权限态验状态机，生产路径只从 synchronize 进
    func proceed(permission state: DevicePermissionState) async {
        permission = state
        guard state == .granted else {
            if phase == .registering { phase = .idle }
            return
        }
        if shouldAttemptRegistration {
            phase = .registering
            registerAction()
        }
        if snapshot != nil {
            await uploadIfPossible()
        }
    }

    /// 连接三件套收编（synchronize 的可测缝）：生产由
    /// synchronize(appState:) 喂真值，钉测直喂假值
    func adoptConnection(
        client: HermesClientProtocol, config: ServerConfig,
        apiKey: String
    ) {
        connection = (client, config, apiKey)
    }

    /// 终局失败（无权益／环境不明）不许每次回前台重撞系
    /// 统回调——同错重报只是噪声；其余态照常重试
    private var shouldAttemptRegistration: Bool {
        switch phase {
        case .idle, .registering, .uploadPending:
            return true
        case .registered:
            return false
        case .failed(let failure):
            switch failure {
            case .noEntitlement, .environmentUnknown:
                return false
            case .serverNotReady, .serverRejected,
                 .unauthorizedByServer, .network, .system:
                return true
            }
        }
    }

    // MARK: 系统回调入口（经转接盒跳回主隔离后到达）

    /// 令牌到手：编码→读环境→落快照→上送。环境读不出
    /// ＝不许上送（拿猜的环境登记是给服务端埋错令牌）
    func recordToken(_ data: Data) {
        let hex = PushTokenHex.encode(data)
        guard !hex.isEmpty else { return }
        guard let environment = environmentProvider() else {
            phase = .failed(.environmentUnknown)
            return
        }
        let snap = PushRegistrationSnapshot(
            tokenHex: hex,
            environment: environment,
            appVersion: Self.appVersion,
            updatedAt: Date()
        )
        let changed = snap.tokenHex != snapshot?.tokenHex
            || snap.environment != snapshot?.environment
        snapshot = snap
        persistSnapshot()
        if phase == .registered, !changed {
            return
        }
        phase = .uploadPending
        Task { await uploadIfPossible() }
    }

    /// 系统登记失败：原文只进诊断，呈现走 Core 分型 label
    func recordFailure(description: String) {
        ChatDiagTrace.record("推送登记系统回调失败：\(description)")
        phase = .failed(
            PushFailureClassifier.classify(
                systemErrorDescription: description
            )
        )
    }

    // MARK: 点按落点

    /// 待批→枢纽审批段（既有 requestHubDestination 通
    /// 道）；run 会话落点缺本层取数口（账本 records 需
    /// ChatStore 现场重演），如实记 pendingRoute 待接
    /// （§397.6 登记），不假装已达
    func handleRoute(_ route: PushNotificationRoute) {
        switch route {
        case .approval:
            appState?.router.requestHubDestination(.approvalHome)
        case .session:
            pendingRoute = route
        case .none:
            break
        }
    }

    // MARK: 上送

    private func uploadIfPossible() async {
        guard !uploadInFlight, phase != .registered,
              let snap = snapshot else { return }
        guard let connection else {
            if phase != .registered { phase = .uploadPending }
            return
        }
        uploadInFlight = true
        defer { uploadInFlight = false }
        do {
            let response = try await upload(
                connection.client, connection.config,
                connection.apiKey,
                PushTokenRegistrationBody(
                    deviceToken: snap.tokenHex,
                    environment: snap.environment,
                    bundleID: Self.bundleID,
                    appVersion: snap.appVersion
                )
            )
            phase = response.registered
                ? .registered : .failed(.serverRejected)
        } catch let error as HermesError {
            switch error {
            case .pushEndpointNotReady:
                phase = .failed(.serverNotReady)
            case .apiKeyRejected:
                phase = .failed(.unauthorizedByServer)
            default:
                phase = .failed(.network(error.userMessage))
            }
        } catch {
            phase = .failed(.network(error.localizedDescription))
        }
    }

    private func persistSnapshot() {
        guard let snapshot,
              let data = try? JSONEncoder().encode(snapshot)
        else { return }
        defaults.set(data, forKey: Self.snapshotKey)
    }

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"]
            as? String ?? "0"
    }

    private static var bundleID: String {
        Bundle.main.bundleIdentifier ?? "site.didichou.oneday"
    }
}
