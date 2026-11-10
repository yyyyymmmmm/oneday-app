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
        .health: false,
        .home: false,
    ]
    /// 设备会话是否在线（通道态，非「智能体可调用」）
    private(set) var sessionOnline = false
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
        if machine.phase == .offline {
            _ = machine.handle(.startRequested)
            beginRegister()
        }
    }

    /// 退后台/断开连接时调：停轮询＋尽力断开会话
    func deactivate() {
        pollTask?.cancel()
        pollTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        let wasOnline = machine.sessionID
        _ = machine.handle(.disconnectRequested)
        sessionOnline = false
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
        case .health, .home:
            break // 批二未接线，不申请
        }
        refreshPermissions()
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
            do {
                let grant = try await self.client.registerSession(
                    config: config,
                    deviceId: DevicePreferences.deviceID,
                    appVersion: self.appVersion,
                    permissions: payload.permissions,
                    tools: payload.tools
                )
                let action = self.machine.handle(
                    .registered(sessionID: grant.sessionId)
                )
                self.sessionOnline = true
                self.sessionError = nil
                if action == .poll {
                    self.beginPoll(sessionId: grant.sessionId)
                    self.beginHeartbeat(sessionId: grant.sessionId)
                }
            } catch let error as DeviceBridgeError {
                _ = self.machine.handle(.registrationFailed)
                self.sessionOnline = false
                self.sessionError = Self.errorLine(error)
            } catch {
                _ = self.machine.handle(.registrationFailed)
                self.sessionOnline = false
                self.sessionError = "设备会话注册失败"
            }
        }
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
                    let (result, error) = await self.dispatcher.execute(
                        call: call,
                        permissions: self.permissions,
                        agentCallEnabled: self.agentCallEnabled
                    )
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
                    try? await self.client.respond(
                        config: config, sessionId: sessionId,
                        callId: call.callId, result: result, error: error
                    )
                    _ = self.machine.handle(.respondFinished)
                } catch is CancellationError {
                    return
                } catch DeviceBridgeError.unknownSession {
                    // 会话被顶替/过期：状态机回注册
                    _ = self.machine.handle(.pollUnknownSession)
                    self.sessionOnline = false
                    self.beginRegister()
                    return
                } catch let error as DeviceBridgeError {
                    switch error {
                    case .noKey, .unauthorized:
                        // 钥匙问题不是抖动：停轮询、如实露
                        self.sessionError = Self.errorLine(error)
                        self.sessionOnline = false
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
                    self.sessionOnline = false
                    self.beginRegister()
                    return
                }
            }
        }
    }

    private static func errorLine(_ error: DeviceBridgeError) -> String {
        switch error {
        case .noKey: return "还没有登录密钥，设备会话未注册。"
        case .unauthorized: return "登录密钥被拒（401），设备会话未注册。"
        case .unknownSession: return "设备会话已过期。"
        case .failed(let message): return message
        }
    }
}
