import Foundation
import OneDayCore

/// 三步探活的步骤口径：连接页与设置页「重新测试连接」共用。
enum ProbeStep: Int, CaseIterable {
    case health
    case login
    case apiKey

    var label: String {
        switch self {
        case .health: return "健康检查"
        case .login: return "登录面板"
        case .apiKey: return "验证 API 密钥"
        }
    }
}

/// 连接状态单点：持有当前服务器配置与客户端，负责
/// 启动恢复、三步探活、凭据存取、会话过期自动重登、断开连接。
/// 凭据只经 Keychain 进出，本类不落任何明文副本到磁盘。
@MainActor
@Observable
final class AppState {
    enum Phase {
        case needsConnection
        case connected
    }

    private(set) var phase: Phase = .needsConnection
    private(set) var config: ServerConfig?
    private(set) var username: String?
    /// 对话模型 id：探活第三步从 /v1/models 取第一个，缺失时回退实测值
    private(set) var modelID: String = "hermes-agent"
    /// 聊天模型（0.3.0 接线，DESIGN-V4 §15）：写死三项
    /// （ChatModels）、本地选择、逐请求生效（请求带
    /// provider=custom 切上游）；与服务端默认模型
    /// （defaultModel，设置页管理面口径）互不干扰。
    /// 持久化于 UserDefaults，初始口径见 ChatModels
    private(set) var chatModel: String = ChatModels.initialSelection(
        stored: UserDefaults.standard.string(forKey: "chatModelID"),
        serverDefault: nil
    )

    /// 选择聊天模型（本地生效，不发网络请求、不改服务端）
    func selectChatModel(_ id: String) {
        guard ChatModels.contains(id) else { return }
        chatModel = id
        UserDefaults.standard.set(id, forKey: "chatModelID")
    }
    /// 服务端默认模型（0.2.2 获取制）：自 /api/config 的 model 键
    /// 拉取，聊天页顶栏与抽屉身份块展示它；切换走 setDefaultModel
    private(set) var defaultModel: String?
    /// 可切换模型目录（0.2.4 根治）：候选只许来自上游——
    /// /api/model/options 正规端点优先，为空回落「用量 ∪
    /// 当前值」，且硬排除网关别名（见 ModelCatalog）。0.2.2
    /// 把网关 /v1/models 的别名并进候选是 bug，已撤销
    private(set) var availableModels: [String] = []
    /// 网关别名集（/v1/models 返回的 id，如 hermes-agent）：
    /// 是客户端调网关时填的模型名、不是上游模型；只许在
    /// 连接信息里只读出现，永不进默认模型候选
    private(set) var gatewayAliases: Set<String> = []

    let client: HermesClientProtocol
    /// 演示模式（截图验收环）：为真时不读不写 Keychain、
    /// 不发网络请求（客户端已被替换为 DemoHermesClient）。
    let isDemo: Bool

    /// 跨页深链（总览 → 智能体格/设置格二级页）：目标页消费后置 nil
    var pendingAgentRoute: AgentRoute?
    var pendingSettingsRoute: SettingsRoute?
    /// 待打开的应用格内页面（0.6.0）：抽屉齿轮等置位，
    /// ContentView 据此切应用格、AppsView 消费后置 nil
    var pendingAppsPage: AppsPage?
    /// 待续聊的服务端会话 id（0.4.0，审计 §3.4）：四处
    /// 入口（抽屉／服务端会话页／状态页／定时运行记录）
    /// 置位，ContentView 据此切聊天格、ChatView 消费后
    /// 导入历史并置 nil。不再走设置格的只读详情页
    var pendingChatSessionID: String?
    /// 总览快捷动作「新建定时任务」：定时页消费后自动拉起新建表单
    var cronCreateRequested = false
    /// 聊天抽屉开合的语义状态（0.2.2 立；0.4.5 改口径，
    /// §30）：壳层 ContentView 是执行者（推式动画与跟手
    /// 状态在壳层），任何视图想开/关抽屉只写这里、壳层
    /// onChange 执行；DrawerView 据此在打开时拉服务端
    /// 会话组。（0.2.2–0.4.4 的旧注「ContentView 据此
    /// 隐藏自绘底栏」随自绘底栏与覆盖式抽屉一并作废）
    var drawerPresented = false
    /// 抽屉与 ChatView 之间的三条通道（0.4.5，抽屉提到
    /// 壳层后立；模式与 pendingChatSessionID 一致：置位
    /// 方写、消费方读后清零）
    /// 当前显示的线程 id（ChatView 随 currentThread 回
    /// 写；抽屉据此高亮当前位、判定删除对象是否当前线程）
    var activeThreadID: UUID?
    /// 抽屉点选/新建的线程 id（DrawerView 写，ChatView
    /// 消费后切 currentThreadID 并清零）
    var drawerThreadSelection: UUID?
    /// 抽屉刚删掉的线程 id（DrawerView 写，ChatView 若
    /// 正显示该线程则置空 currentThreadID 并清零）
    var drawerDeletedThreadID: UUID?

    init(client: HermesClientProtocol = HermesClient(), demoMode: DemoMode = .off) {
        self.client = client
        isDemo = demoMode.isDemo
        switch demoMode {
        case .connected:
            // 演示会话：地址与账号只是展示数据，密钥由假客户端消化
            config = ServerConfig(rawInput: "https://hermes.didichou.site")
            username = "admin"
            // 演示口径：模型名与总览「当前配置」同为 deepseek-chat，
            // 三处展示（顶栏副题/抽屉服务器行/设置）一致；假客户端
            // 不校验模型名，生产路径的 modelID 仍以 /v1/models 为准
            modelID = "deepseek-chat"
            defaultModel = "deepseek-chat"
            availableModels = ["deepseek-chat", "deepseek-flash", "deepseek-v4-pro"]
            gatewayAliases = ["hermes-agent"]
            phase = .connected
        case .connectPage:
            // 停在连接页：保持未连接，字段预填在 ConnectView 侧
            break
        case .off:
            restore()
        }
    }

    // MARK: - 启动恢复

    /// 已连接的判定（0.6.0 直登口径）：地址＋API 密钥
    /// （Bearer）齐全即成立；面板账号/密码是 0.5.x 四件
    /// 套存量凭据，有则一并恢复（管理面自动重登要用），
    /// 缺失不挡直登成立——直登连接的管理面 401 时没有
    /// 静默重登兜底、按会话过期报错（performAdmin 口径）。
    private func restore() {
        guard let base = KeychainStore.read(account: CredentialKey.baseURL),
              let config = ServerConfig(rawInput: base),
              KeychainStore.read(account: CredentialKey.apiKey) != nil else {
            phase = .needsConnection
            return
        }
        self.config = config
        username = KeychainStore.read(account: CredentialKey.username)
        phase = .connected
    }

    var apiKey: String? {
        // 演示假值：只会被递给 DemoHermesClient，不出设备
        if isDemo { return "demo-api-key" }
        return KeychainStore.read(account: CredentialKey.apiKey)
    }

    private var password: String? {
        if isDemo { return "demo-password" }
        return KeychainStore.read(account: CredentialKey.password)
    }

    // MARK: - 三步探活并连接

    /// 依次执行三步探活，onStep 在每步开始时回调（连接页画进度）。
    /// 全部通过才落 Keychain 并置 connected；任一步失败抛
    /// HermesError，凭据不落盘（不存坏凭据）。
    func connect(
        config: ServerConfig,
        username: String,
        password: String,
        apiKey: String,
        onStep: @escaping (ProbeStep) -> Void = { _ in }
    ) async throws {
        onStep(.health)
        let health = try await client.health(config: config)
        guard health.isOK else {
            throw HermesError.healthCheckFailed(status: 200)
        }
        onStep(.login)
        try await client.login(config: config, username: username, password: password)
        onStep(.apiKey)
        let ids = try await client.models(config: config, apiKey: apiKey)
        if let first = ids.first {
            modelID = first
        }
        // 演示模式不落 Keychain：假凭据写进去会污染真实连接
        if !isDemo {
            KeychainStore.save(config.baseString, account: CredentialKey.baseURL)
            KeychainStore.save(username, account: CredentialKey.username)
            KeychainStore.save(password, account: CredentialKey.password)
            KeychainStore.save(apiKey, account: CredentialKey.apiKey)
        }
        self.config = config
        self.username = username
        phase = .connected
    }

    /// 直登（0.6.0，用户拍板学 OpenMuse 欢迎页）：欢迎页
    /// 只输服务器地址＋密钥（Hermes Bearer），两步校验
    /// （健康检查→验证密钥）全过才落 Keychain 并置
    /// connected。面板账号/密码不参与直登：落盘时清掉
    /// 旧四件套里的账号/密码，防换址后拿旧服务器的面板
    /// 凭据去新服务器静默重登。设置页改址/换钥走同一
    /// 方法（ServerDetailView）。
    func connectDirect(
        config: ServerConfig,
        apiKey: String,
        onStep: @escaping (ProbeStep) -> Void = { _ in }
    ) async throws {
        onStep(.health)
        let health = try await client.health(config: config)
        guard health.isOK else {
            throw HermesError.healthCheckFailed(status: 200)
        }
        onStep(.apiKey)
        let ids = try await client.models(config: config, apiKey: apiKey)
        if let first = ids.first {
            modelID = first
        }
        if !isDemo {
            KeychainStore.save(config.baseString, account: CredentialKey.baseURL)
            KeychainStore.save(apiKey, account: CredentialKey.apiKey)
            KeychainStore.delete(account: CredentialKey.username)
            KeychainStore.delete(account: CredentialKey.password)
        }
        self.config = config
        username = nil
        phase = .connected
    }

    /// 设置页「重新测试连接」：存量四件套走三步探活；
    /// 直登连接（无面板密码）走两步（健康＋密钥），不改状态。
    func retestConnection(onStep: @escaping (ProbeStep) -> Void = { _ in }) async throws {
        guard let config, let apiKey else {
            throw HermesError.sessionExpired
        }
        if let username, let password {
            try await connect(
                config: config, username: username, password: password,
                apiKey: apiKey, onStep: onStep
            )
        } else {
            onStep(.health)
            let health = try await client.health(config: config)
            guard health.isOK else {
                throw HermesError.healthCheckFailed(status: 200)
            }
            onStep(.apiKey)
            _ = try await client.models(config: config, apiKey: apiKey)
        }
    }

    // MARK: - 会话接口（自动重登）

    /// 管理面统一通道：拿当前配置执行操作，遇 401 先用已存
    /// 密码静默重登再重试一次；重登失败或再 401 →
    /// sessionExpired（页面提示重新登录）。全部 /api/* 调用走它。
    func performAdmin<T>(
        _ operation: (HermesClientProtocol, ServerConfig) async throws -> T
    ) async throws -> T {
        guard let config else {
            throw HermesError.sessionExpired
        }
        do {
            return try await operation(client, config)
        } catch HermesError.unexpectedStatus(_, let status) where status == 401 {
            guard let username, let password else {
                throw HermesError.sessionExpired
            }
            try await client.login(config: config, username: username, password: password)
            do {
                return try await operation(client, config)
            } catch HermesError.unexpectedStatus(_, let retryStatus) where retryStatus == 401 {
                throw HermesError.sessionExpired
            }
        }
    }

    // MARK: - 模型目录（0.2.2 获取制）

    /// 刷新默认模型与可切换目录（0.2.4）：当前值来自
    /// /api/config；候选只来自上游（ModelCatalog 口径）：
    /// /api/model/options 优先，为空回落近 30 天用量 ∪
    /// 当前值；网关 /v1/models 的返回只作别名集用于排除，
    /// 本身永不进候选（0.2.2 的并集口径是 bug 源头）
    func refreshModelCatalog() async {
        guard phase == .connected else { return }
        if let raw = try? await performAdmin({ client, config in
            try await client.rawConfig(config: config)
        }), let current = raw["model"]?.stringValue {
            defaultModel = current
            // 聊天模型初始播种（0.3.0）：用户没选过时，若
            // 服务端默认在写死清单内则以它为初始选择
            if UserDefaults.standard.string(forKey: "chatModelID") == nil {
                chatModel = ChatModels.initialSelection(
                    stored: nil, serverDefault: current
                )
            }
        }
        var aliases = Set<String>()
        if let apiKey,
           let ids = try? await performAdmin({ client, config in
               try await client.models(config: config, apiKey: apiKey)
           }) {
            aliases = Set(ids)
        }
        gatewayAliases = aliases
        var options: [String] = []
        if let ids = try? await performAdmin({ client, config in
            try await client.modelOptions(config: config)
        }) {
            options = ids
        }
        var usage: [String] = []
        if let analytics = try? await performAdmin({ client, config in
            try await client.modelAnalytics(config: config, days: 30)
        }) {
            usage = analytics.models.map(\.model)
        }
        let merged = ModelCatalog.candidates(
            options: options, usage: usage,
            current: defaultModel, gatewayAliases: aliases
        )
        if !merged.isEmpty {
            availableModels = merged
        }
    }

    /// 切换服务端默认模型：读全量 config → 只改 model 键 →
    /// 整包写回（PUT /api/config 既有写接口，演示/单测验证，
    /// 不对生产执行）
    func setDefaultModel(_ model: String) async throws {
        // 写入校验（0.2.4）：不在上游候选集内的值一律拦截，
        // 不许把网关别名等非法值写进生产配置
        guard ModelCatalog.isWritable(model, candidates: availableModels) else {
            throw HermesError.modelNotUpstream(model)
        }
        var raw = try await performAdmin { client, config in
            try await client.rawConfig(config: config)
        }
        raw["model"] = .string(model)
        try await performAdmin { client, config in
            try await client.updateConfig(config: config, newConfig: raw)
        }
        defaultModel = model
        if !availableModels.contains(model) {
            availableModels.insert(model, at: 0)
        }
    }

    /// 设置页在本页内写回 config 后同步内存态（避免两处口径漂移）。
    /// 网关别名不回填候选（它不是可选的上游模型）。
    func noteDefaultModel(_ model: String) {
        defaultModel = model
        if !availableModels.contains(model), !gatewayAliases.contains(model) {
            availableModels.insert(model, at: 0)
        }
    }

    /// 拉配置摘要（总览旧路径，走统一通道）
    func configSummary() async throws -> ServerConfigSummary {
        try await performAdmin { client, config in
            try await client.configSummary(config: config)
        }
    }

    // MARK: - 断开

    /// 断开连接：清 Keychain 与该服务器 cookie，回连接页。
    /// 本地聊天记录保留（是用户数据，删除口子在聊天页历史里）。
    func disconnect() {
        if isDemo {
            // 演示模式只复位状态：不动 Keychain、不清 cookie
            config = nil
            username = nil
            phase = .needsConnection
            return
        }
        if let config {
            client.clearCookies(config: config)
        }
        KeychainStore.clearAll()
        config = nil
        username = nil
        phase = .needsConnection
    }
}
