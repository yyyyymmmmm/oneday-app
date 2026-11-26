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
    private(set) var hermesVersion: String?
    private(set) var capabilities: CapabilitiesResponse?
    var lastError: String?

    private let client = HermesMacClient()

    var isConnected: Bool { phase == .connected }

    var isConnecting: Bool {
        if case .connecting = phase { return true }
        return false
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
            self.capabilities = caps
            self.hermesVersion = status?.version
            phase = .connected
        } catch {
            phase = .signedOut
        }
    }

    /// 面板密码一步登录（用户 2026-11-11 定版，与 iOS
    /// 同口径）：地址＋密码一步连上，全过才落 Keychain
    func connectWithPassword(address: String, password: String) async {
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
            try await client.login(config: config, password: password)
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
            self.capabilities = caps
            self.hermesVersion = status?.version ?? health.version
            phase = .connected
        } catch let error as HermesError {
            lastError = error.userMessage
            phase = .signedOut
        } catch {
            lastError = error.localizedDescription
            phase = .signedOut
        }
    }

    /// 断开连接：清 Keychain 三件套，回登录页
    func disconnect() {
        MacKeychain.deleteAllCredentials()
        config = nil
        modelID = nil
        modelCount = 0
        hermesVersion = nil
        capabilities = nil
        lastError = nil
        phase = .signedOut
    }
}
