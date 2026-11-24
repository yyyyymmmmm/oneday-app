import Foundation
import OneDayCore

/// 「允许智能体调用」开关与设备标识（UserDefaults）：
/// 开关默认关——装上新版不会在用户没点头前就把数据
/// 递给智能体（双层开关的 App 内层，设计档 §3.3）。
/// 设备标识是本机生成的随机 UUID，只用于桥侧会话
/// 区分，不含任何个人信息。
enum DevicePreferences {
    private static let deviceIDKey = "device.session.deviceId"

    static func agentCallEnabled(_ source: DeviceSourceID) -> Bool {
        UserDefaults.standard.bool(
            forKey: "device.agentCall.\(source.rawValue)"
        )
    }

    static func setAgentCallEnabled(_ source: DeviceSourceID, _ on: Bool) {
        UserDefaults.standard.set(
            on, forKey: "device.agentCall.\(source.rawValue)"
        )
    }

    static var deviceID: String {
        if let existing = UserDefaults.standard.string(forKey: deviceIDKey) {
            return existing
        }
        let created = UUID().uuidString
        UserDefaults.standard.set(created, forKey: deviceIDKey)
        return created
    }
}

/// 最近调用元数据（逐件一份，UserDefaults）：只记
/// 工具名/时刻/成败/错误码，与桥审计同纪律——参数
/// 与结果内容永不落盘。
enum DeviceCallLogStore {
    private static let key = "device.callLog.v1"

    static func entries() -> [DeviceSourceID: DeviceCallLogEntry] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let raw = try? JSONDecoder().decode(
                [String: DeviceCallLogEntry].self, from: data
              ) else { return [:] }
        var mapped: [DeviceSourceID: DeviceCallLogEntry] = [:]
        for (name, entry) in raw {
            if let source = DeviceSourceID(rawValue: name) {
                mapped[source] = entry
            }
        }
        return mapped
    }

    static func record(_ entry: DeviceCallLogEntry) {
        var current = entries()
        current[entry.source] = entry
        let raw = Dictionary(
            uniqueKeysWithValues: current.map {
                ($0.key.rawValue, $0.value)
            }
        )
        if let data = try? JSONEncoder().encode(raw) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

/// 设备会话控制器（0.34.0 批一）：App 前台且已连接
/// 时向 device-bridge 注册会话、长轮询领调用、交给
/// 分发器现读现写、回执；退后台即断开（桥 45 秒无
/// 心跳自动判离线兜底）。生命周期由 RootView 按
/// scenePhase/连接态驱动（activate/deactivate）。
///
/// 诚实边界：会话在线只说明「手机这边通道活着」——
/// Hermes 侧的 MCP 门面注册不在本版（留收官窗口），
/// 呈现层不许据此宣称智能体已可调用（设计档定版）。
@MainActor
@Observable
final class DeviceSessionController {
    /// 逐件系统权限（进页/回前台重读，不缓存冒充）
    private(set) var permissions: [DeviceSourceID: DevicePermissionState] =
        DevicePermissions.currentStates()
    /// 逐件「允许智能体调用」开关（默认关）
    private(set) var agentCallEnabled: [DeviceSourceID: Bool] = [
        .calendar: DevicePreferences.agentCallEnabled(.calendar),
        .reminders: DevicePreferences.agentCallEnabled(.reminders),
        .contacts: DevicePreferences.agentCallEnabled(.contacts),
        .photos: DevicePreferences.agentCallEnabled(.photos),
        .motion: DevicePreferences.agentCallEnabled(.motion),
        // 剪贴板/文件无系统权限：开关不与权限对齐
        // （没有权限可对齐），保持用户亲手拨的独立
        // 开关、默认关
        .clipboard: DevicePreferences.agentCallEnabled(.clipboard),
        .files: DevicePreferences.agentCallEnabled(.files),
        // 批二三件：闹钟/通知有真系统权限（开关与权
        // 限分开，与日历等现调件同）；打开目标无系
        // 统权限、开关即唯一的门（与剪贴板同）
        .alarm: DevicePreferences.agentCallEnabled(.alarm),
        .notifications: DevicePreferences
            .agentCallEnabled(.notifications),
        .opener: DevicePreferences.agentCallEnabled(.opener),
        // 批三五件：相机有真系统权限（开关与权限分
        // 开，与闹钟同）；识别/翻译/端上智能/本人确
        // 认无系统权限、开关即唯一的门（与剪贴板同）
        .camera: DevicePreferences.agentCallEnabled(.camera),
        .vision: DevicePreferences.agentCallEnabled(.vision),
        .translate: DevicePreferences.agentCallEnabled(.translate),
        .ondevice: DevicePreferences.agentCallEnabled(.ondevice),
        .biometric: DevicePreferences.agentCallEnabled(.biometric),
        // 批四五件：定位/媒体库有真系统权限（开关与
        // 权限分开，与相机同）；拨号与撰写/快捷指
        // 令/设备信息无系统权限、开关即唯一的门
        // （与剪贴板同）
        .location: DevicePreferences.agentCallEnabled(.location),
        .media: DevicePreferences.agentCallEnabled(.media),
        .compose: DevicePreferences.agentCallEnabled(.compose),
        .shortcuts: DevicePreferences.agentCallEnabled(.shortcuts),
        .deviceinfo: DevicePreferences
            .agentCallEnabled(.deviceinfo),
        .health: false,
        .home: false,
    ]
    /// 设备会话是否在线（通道态，非「智能体可调
    /// 用」）：由状态机相位派生、单一事实源。历史
    /// 上注册回调里无条件置真——状态机没给出 .poll
    /// 时 App 也自报在线（2026-11-13 实案的假阳
    /// 性），故不再单独存这个旗标
    var sessionOnline: Bool { machine.isOnline }
    /// 会话层最近一次错误人话（注册失败等；调用级错
    /// 误走调用日志，不混进这里）
    private(set) var sessionError: String?
    /// 逐件最近调用元数据（详情页呈现源）
    private(set) var lastCallEntries: [DeviceSourceID: DeviceCallLogEntry] =
        DeviceCallLogStore.entries()

    private var machine = DeviceSessionMachine()
    private var config: ServerConfig?
    private var pollTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var registering = false
    private let client = DeviceBridgeClient()
    let dispatcher = DeviceToolDispatcher()
    /// 对话内授权流协调器（§244）：授权卡的持有者，
    /// ask/notice 两路伪调用与回前台续办都经它
    let permissionFlow = DevicePermissionCoordinator()

    private var appVersion: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "0"
    }

    // MARK: - 生命周期（RootView 驱动）

    /// 进前台/连接成立时调：有配置才动，演示模式不发网络
    func activate(config: ServerConfig?, isDemo: Bool) {
        guard !isDemo, let config else { return }
        self.config = config
        refreshPermissions()
        // 通知状态只有异步读法：进前台补刷一次真状
        // 态回填缓存，变了 refreshPermissions 会带着
        // 重注册（§113 登记的出入落点之一）
        Task {
            await NotificationEngine.readSystemState()
            refreshPermissions()
        }
        if machine.phase == .offline {
            _ = machine.handle(.startRequested)
            beginRegister()
        }
        // §244 P-3：回前台扫一遍留着的授权卡——去设
        // 置改完权限/开关回来，卡点已清的自动续办
        Task { [weak self] in
            guard let self else { return }
            await self.permissionFlow.checkResumes(host: self)
        }
    }

    /// 当前连接配置（协调器续办/同步取用；未连接为 nil）
    var activeConfig: ServerConfig? { config }

    /// 凭 token 续办挂起调用（§244 P-4 客户端口）
    func resumeParkedCall(
        token: String
    ) async throws -> PermissionResumeOutcome {
        guard let config else {
            throw DeviceBridgeError.failed(
                L10n.string("还没连上服务器，续办不了")
            )
        }
        return try await client.resumeCall(
            config: config, resumeToken: token
        )
    }

    /// 桥侧 park 状态读面（§261 ①）：卡对账取用。
    /// 读面不可达/回执不可信一律回 nil（协调器据此
    /// 跳过该卡对账、本地缓存兜底），不把不确定当
    /// 「桥说没了」
    func parkState(token: String) async -> PermissionParkState? {
        guard let config else { return nil }
        return try? await client.parkState(
            config: config, resumeToken: token
        ) ?? nil
    }

    /// 退后台/断开连接时调：停轮询＋尽力断开会话
    func deactivate() {
        pollTask?.cancel()
        pollTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        let wasOnline = machine.sessionID
        _ = machine.handle(.disconnectRequested)
        if let config, let wasOnline {
            Task { await client.disconnect(config: config, sessionId: wasOnline) }
        }
        config = nil
    }

    // MARK: - 权限与开关（详情页/总览页驱动）

    /// 重读系统权限；变了且会话在线就重注册（桥侧权
    /// 限快照跟着更新，下一次注册即生效——设计档口径）。
    /// 0.36.18 收敛：记录型五件的「允许调用」不再有
    /// 独立开关——每次重读时一律对齐真实权限（授权
    /// 即可调用、权限关即不可调用），0.36.16 的同步
    /// 开关镜像与启动对齐都收进这一处；健康/家庭不
    /// 在此列（批二未接线、恒关）
    func refreshPermissions() {
        let fresh = DevicePermissions.currentStates()
        var changed = fresh != permissions
        permissions = fresh
        for dataset in DeviceSyncDataset.allCases {
            let want = DeviceSyncControl.agentCanQuery(
                permission: fresh[dataset.sourceID] ?? .notDetermined
            )
            if agentCallEnabled[dataset.sourceID] != want {
                agentCallEnabled[dataset.sourceID] = want
                DevicePreferences.setAgentCallEnabled(
                    dataset.sourceID, want
                )
                changed = true
            }
        }
        if changed, machine.isOnline { beginRegister() }
    }

    /// 申请某件的系统权限（用到才问：详情页开关拨
    /// 开时触发，绝不在启动时一揽子索权）。授权铁
    /// 律在本口落死：先同步读现态，只有真未决定才
    /// 发那一次请求——已决定（已授权/已拒绝/受限）
    /// 一律只重读状态，绝不重走异步请求回调
    func requestAccess(for source: DeviceSourceID) async {
        if DeviceSyncDataset.fromSource(source) != nil,
           DevicePermissions.currentStates()[source]
            != .notDetermined
        {
            refreshPermissions()
            return
        }
        await performAccessRequest(for: source)
        refreshPermissions()
    }

    /// 只发那一次系统请求、不带刷新尾巴（§244）：授
    /// 权卡流要先回桥决定、后才刷新权限重注册（刷新
    /// 会取消轮询环，先后倒置桥就永远等不到答复）。
    /// 铁律不变：只许在现态未决定时调用——已决定态
    /// 的把关在调用方（requestAccess/协调器），本函
    /// 数自身不判状态
    func performAccessRequest(for source: DeviceSourceID) async {
        switch source {
        case .calendar:
            _ = await dispatcher.events.requestCalendarAccess()
        case .reminders:
            _ = await dispatcher.events.requestRemindersAccess()
        case .contacts:
            _ = await dispatcher.contacts.requestAccess()
        case .photos:
            _ = await DevicePermissions.requestPhotosAccess()
        case .motion:
            _ = await DevicePermissions.requestMotionAccess()
        case .alarm:
            _ = await dispatcher.alarms.requestAccess()
        case .notifications:
            _ = await dispatcher.notifications.requestAccess()
        case .camera:
            _ = await dispatcher.camera.requestAccess()
        case .location:
            _ = await dispatcher.location.requestAccess()
        case .media:
            _ = await dispatcher.media.requestAccess()
        case .clipboard, .files, .opener, .vision, .translate,
             .ondevice, .biometric, .compose, .shortcuts,
             .deviceinfo:
            break // 无系统权限可申请：开关即唯一的门
        case .health, .home:
            break // 未接线，不申请
        }
    }

    func setAgentCallEnabled(_ source: DeviceSourceID, _ on: Bool) {
        agentCallEnabled[source] = on
        DevicePreferences.setAgentCallEnabled(source, on)
        // 工具清单随开关变：在线时重注册即时生效
        if machine.isOnline { beginRegister() }
    }

    // MARK: - 注册与轮询

    private func beginRegister() {
        guard let config, !registering else { return }
        registering = true
        pollTask?.cancel()
        heartbeatTask?.cancel()
        Task { [weak self] in
            guard let self else { return }
            defer { self.registering = false }
            let payload = DeviceRegistration.payload(
                permissions: self.permissions,
                agentCallEnabled: self.agentCallEnabled
            )
            // 端上智能的可用性门（批三，§114）：机型
            // 不支持/未开启/模型未就绪时把
            // ondevice_model_run 从注册清单摘掉——
            // 可用性是机型事实、不进 Core 静态名册；
            // 状态变化后下一次注册自动跟上，引擎执
            // 行时另有复查兜底
            var tools = payload.tools
            if !OnDeviceModelEngine.isAvailable {
                tools.removeAll { $0 == "ondevice_model_run" }
            }
            do {
                let grant = try await self.client.registerSession(
                    config: config,
                    deviceId: DevicePreferences.deviceID,
                    appVersion: self.appVersion,
                    permissions: payload.permissions,
                    tools: tools,
                    agentCall: DeviceRegistrationExtras.agentCallMap(
                        agentCallEnabled: self.agentCallEnabled
                    ),
                    capabilities: DeviceRegistrationExtras.capabilities
                )
                let action = self.machine.handle(
                    .registered(sessionID: grant.sessionId)
                )
                self.sessionError = nil
                if action == .poll {
                    self.beginPoll(sessionId: grant.sessionId)
                    self.beginHeartbeat(sessionId: grant.sessionId)
                }
            } catch let error as DeviceBridgeError {
                _ = self.machine.handle(.registrationFailed)
                self.sessionError = Self.errorLine(error)
            } catch {
                _ = self.machine.handle(.registrationFailed)
                self.sessionError = L10n.string("设备会话注册失败")
            }
        }
    }

    /// 轮询到一条调用的分发（§244）：权限流伪调用
    /// （permission_ask/permission_notice）走协调器、
    /// 不进工具分发器；普通工具照旧分发。三元组＝
    /// 结果/错误/错误结构化字段
    private func routePolledCall(
        _ call: DeviceIncomingCall
    ) async -> (JSONValue?, DeviceToolError?, [String: JSONValue]) {
        if call.kind == "permission_ask" || call.tool == "permission_ask" {
            let (result, error) = await permissionFlow.handleAsk(
                call: call, host: self
            )
            return (result, error, [:])
        }
        if call.kind == "permission_notice"
            || call.tool == "permission_notice" {
            permissionFlow.ingestNotice(call: call)
            return (.object([:]), nil, [:])
        }
        let (result, error) = await dispatcher.execute(
            call: call,
            permissions: permissions,
            agentCallEnabled: agentCallEnabled
        )
        var fields: [String: JSONValue] = [:]
        if let error, case .permissionDenied = error,
           let source = DeviceToolRegistry.spec(call.tool)?.source {
            // P-1：手机侧权限兜底错误带上现读状态（桥
            // 词表 bridgeValue），桥据此补结构化字段
            let state = DevicePermissions.currentStates()[source]
                ?? .notDetermined
            fields["state"] = .string(state.bridgeValue)
        }
        return (result, error, fields)
    }

    private func beginPoll(sessionId: String) {
        guard let config else { return }
        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    let call = try await self.client.poll(
                        config: config, sessionId: sessionId, wait: 25
                    )
                    guard let call else {
                        _ = self.machine.handle(.pollReturnedEmpty)
                        continue
                    }
                    _ = self.machine.handle(
                        .pollReturnedCall(callID: call.callId)
                    )
                    let (result, error, errorFields) =
                        await self.routePolledCall(call)
                    if let source = DeviceToolRegistry.spec(call.tool)?.source {
                        let entry = DeviceCallLogEntry(
                            tool: call.tool, source: source,
                            at: Date().timeIntervalSince1970,
                            succeeded: error == nil,
                            errorCode: error?.code
                        )
                        DeviceCallLogStore.record(entry)
                        self.lastCallEntries[source] = entry
                    }
                    do {
                        try await self.client.respond(
                            config: config, sessionId: sessionId,
                            callId: call.callId, result: result,
                            error: error, errorFields: errorFields
                        )
                    } catch is CancellationError {
                        // 轮询环被重注册/断开取消：不是回
                        // 执失败，不留痕
                    } catch {
                        // 回执没送达＝桥侧永远等不到结果：
                        // 不许 try? 静默吞——落调用日志让
                        // 失败显形（如执行期重注册后拿旧会
                        // 话回执、被桥回 404 的放大项）
                        if let source = DeviceToolRegistry
                            .spec(call.tool)?.source {
                            let entry = DeviceCallLogEntry(
                                tool: call.tool, source: source,
                                at: Date().timeIntervalSince1970,
                                succeeded: false,
                                errorCode: Self.respondErrorCode(
                                    error
                                )
                            )
                            DeviceCallLogStore.record(entry)
                            self.lastCallEntries[source] = entry
                        }
                    }
                    _ = self.machine.handle(.respondFinished)
                } catch is CancellationError {
                    return
                } catch DeviceBridgeError.unknownSession {
                    // 会话被顶替/过期：状态机回注册
                    _ = self.machine.handle(.pollUnknownSession)
                    self.beginRegister()
                    return
                } catch let error as DeviceBridgeError {
                    switch error {
                    case .noKey, .unauthorized:
                        // 钥匙问题不是抖动：停轮询、如实露。
                        // 相位推回 offline 让派生的在线旗标
                        // 跟着落下（桥侧会话不可用、同钥回
                        // 执也会被拒，不另发 disconnect）
                        self.sessionError = Self.errorLine(error)
                        _ = self.machine.handle(.disconnectRequested)
                        return
                    default:
                        try? await Task.sleep(for: .seconds(3))
                    }
                } catch {
                    try? await Task.sleep(for: .seconds(3))
                }
            }
        }
    }

    /// 心跳保活：轮询本身会刷新桥侧 lastSeen，本环只
    /// 兜「正在执行长调用」等轮询停顿期；心跳 404＝
    /// 会话已不在，重注册
    private func beginHeartbeat(sessionId: String) {
        guard let config else { return }
        heartbeatTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                if Task.isCancelled { return }
                guard self.machine.sessionID == sessionId else { return }
                let alive = (try? await self.client.heartbeat(
                    config: config, sessionId: sessionId
                )) ?? true
                if !alive {
                    _ = self.machine.handle(.pollUnknownSession)
                    self.beginRegister()
                    return
                }
            }
        }
    }

    /// 回执失败落调用日志的错误码（与 DeviceToolError
    /// .code 同为 snake_case 纪律，respond_ 前缀点明坏
    /// 在回执段而非执行段）
    private static func respondErrorCode(_ error: Error) -> String {
        guard let bridgeError = error as? DeviceBridgeError else {
            return "respond_failed"
        }
        switch bridgeError {
        case .noKey: return "respond_no_key"
        case .unauthorized: return "respond_unauthorized"
        case .unknownSession: return "respond_unknown_session"
        case .failed: return "respond_failed"
        }
    }

    private static func errorLine(_ error: DeviceBridgeError) -> String {
        switch error {
        case .noKey: return L10n.string("还没有登录密钥，设备会话未注册。")
        case .unauthorized: return L10n.string("登录密钥被拒（401），设备会话未注册。")
        case .unknownSession: return L10n.string("设备会话已过期。")
        case .failed(let message): return message
        }
    }
}
