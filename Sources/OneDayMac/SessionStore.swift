import Foundation
import Observation
import OneDayCore

/// 连接阶段（壳层）：未登录／连接中（带步骤文案）／已连接
enum MacConnectionPhase: Equatable {
    case signedOut
    case connecting(step: String)
    case connected
}

/// Mac 端会话状态（地基棒）：只管连接一件事——面板密
/// 码一步登录链与启动恢复，链路顺序与 iOS 端 AppState
/// .connectWithPassword 逐字同序（健康检查 → web-login
/// 验面板密码 → reveal 换 API_SERVER_KEY → /v1/models
/// 验钥 → 读 capabilities 与服务状态）。功能面的状态
/// 后续棒各自立 Store，不往本类堆。
@MainActor
@Observable
final class SessionStore {
    private(set) var phase: MacConnectionPhase = .signedOut
    private(set) var config: ServerConfig?
    private(set) var modelID: String?
    private(set) var modelCount = 0
    /// 可用模型全清单（棒 1 模型选择器 #17 消费）
    private(set) var availableModels: [String] = []
    private(set) var hermesVersion: String?
    private(set) var capabilities: CapabilitiesResponse?
    /// 当前档案名与智能体名（棒 1 设置通用节 #65 身份
    /// 消费；连上后经档案面读取，读不到留 nil 不冒充）
    private(set) var activeProfileName: String?
    private(set) var agentDisplayName: String?
    var lastError: String?

    private let client = HermesMacClient()

    var isConnected: Bool { phase == .connected }

    var isConnecting: Bool {
        if case .connecting = phase { return true }
        return false
    }

    /// 聊天主链共用通道（棒 1）：功能面 Store 经此取
    /// 客户端与登录密钥，不另持第二套凭据
    var chatClient: HermesMacClient { client }

    var apiKey: String? {
        MacKeychain.read(account: MacCredentialKey.apiKey)
    }

    /// 短时票据能力位（设置服务器节 #75 呈现：服务端
    /// 广告 features.short_lived_tokens 的直读结果）
    var shortLivedTokensSupported: Bool? {
        capabilities?.shortLivedTokensSupported
    }

    /// 能力位摘要（壳层状态面用）：服务端广告的
    /// features 旗标数与端点数，只报数不下结论
    var capabilitySummary: String? {
        guard let capabilities else { return nil }
        return "features \(capabilities.features.count) 项 · endpoints \(capabilities.endpoints.count) 条"
    }

    /// 启动恢复：Keychain 有地址＋存量钥 → 直验
    /// /v1/models（与 iOS restore 同口径），验过进主
    /// 窗；验不过留登录页（凭据保留，待用户处置）
    func restore() async {
        guard let base = MacKeychain.read(account: MacCredentialKey.baseURL),
              let key = MacKeychain.read(account: MacCredentialKey.apiKey),
              let config = ServerConfig(rawInput: base)
        else { return }
        do {
            let ids = try await client.models(config: config, apiKey: key)
            let caps = try? await client.capabilities(
                config: config, apiKey: key
            )
            let status = try? await client.status(config: config)
            self.config = config
            self.modelID = ids.first
            self.modelCount = ids.count
            self.availableModels = ids
            self.capabilities = caps
            self.hermesVersion = status?.version
            phase = .connected
            await loadIdentity()
        } catch {
            phase = .signedOut
        }
    }

    /// 面板密码一步登录（用户 2026-11-11 定版，与 iOS
    /// 同口径）：地址＋账号＋密码一步连上，全过才落 Keychain
    func connectWithPassword(address: String, username: String, password: String) async {
        guard let config = ServerConfig(rawInput: address) else {
            lastError = HermesError.invalidServerAddress.userMessage
            return
        }
        lastError = nil
        phase = .connecting(step: "正在检查服务器…")
        do {
            let health = try await client.health(config: config)
            guard ServiceHealth.from(health: health) == .up else {
                throw HermesError.healthCheckFailed(status: 200)
            }
            phase = .connecting(step: "正在验证面板密码…")
            try await client.login(config: config, username: username, password: password)
            phase = .connecting(step: "正在换取登录密钥…")
            let key = try await client.revealEnvVar(
                config: config, key: "API_SERVER_KEY"
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else {
                throw HermesError.decodingFailed(endpoint: "密钥查看")
            }
            let ids = try await client.models(config: config, apiKey: key)
            let caps = try? await client.capabilities(
                config: config, apiKey: key
            )
            let status = try? await client.status(config: config)
            MacKeychain.save(
                config.baseString, account: MacCredentialKey.baseURL
            )
            MacKeychain.save(password, account: MacCredentialKey.password)
            MacKeychain.save(key, account: MacCredentialKey.apiKey)
            self.config = config
            self.modelID = ids.first
            self.modelCount = ids.count
            self.availableModels = ids
            self.capabilities = caps
            self.hermesVersion = status?.version ?? health.version
            phase = .connected
            await loadIdentity()
        } catch let error as HermesError {
            lastError = error.userMessage
            phase = .signedOut
        } catch {
            lastError = error.localizedDescription
            phase = .signedOut
        }
    }

    /// 身份读取（#65）：当前档案 → 人设正文 → 智能体
    /// 名（Core AgentName.resolve 同口径）；任一段读
    /// 不到如实留空，设置面回落缺省名，不编造
    private func loadIdentity() async {
        guard let config, let key = apiKey else { return }
        let profile = try? await client.activeProfile(
            config: config, apiKey: key
        )
        activeProfileName = profile?.name
        if let name = profile?.name {
            let soul = try? await client.profileSoul(
                config: config, apiKey: key, name: name
            )
            agentDisplayName = AgentName.resolve(
                soulContent: soul?.content
            )
        }
    }

    /// 断开连接：清 Keychain 三件套，回登录页
    func disconnect() {
        MacKeychain.deleteAllCredentials()
        config = nil
        modelID = nil
        modelCount = 0
        availableModels = []
        hermesVersion = nil
        capabilities = nil
        activeProfileName = nil
        agentDisplayName = nil
        lastError = nil
        phase = .signedOut
    }
}
