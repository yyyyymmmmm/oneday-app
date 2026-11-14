import Foundation
import OneDayCore

/// 频道错误：登录失效与服务端原因分开报；原因须先
/// 过 ServerErrorText 安全门才许上屏（§233），不过
/// 门落通用人话、原文只进诊断留痕
enum ChannelsBridgeError: Error, Sendable, Equatable {
    case noKey
    case unauthorized
    case failed(String)
}

/// 单个平台的配对状态：configured/connected 只认
/// 网关自家记录（Dashboard /api/messaging/platforms
/// 载荷经 OneDayCore 映射），App 不二次推断
struct ChannelPlatformStatus: Decodable, Sendable, Equatable {
    let platform: String
    let kind: String
    let open: Bool
    let configured: Bool
    let connected: Bool
    let needsIdentity: Bool
    /// not_configured / pending_restart / connected /
    /// error / frozen
    let state: String
    let sessionCount: Int
    let message: String?
}

/// 频道状态全量回执
struct ChannelsStatusResponse: Decodable, Sendable {
    let gatewayRunning: Bool
    let platforms: [ChannelPlatformStatus]
}

/// 凭据保存回执：值永不回显，只回成败与下一步状态。
/// 直连后由 App 按落盘＋重启触发结果合成（形状与
/// 桥时代回执一致，呈现层零改）：applyTriggered＝
/// 保存后网关重启是否触发成功，失败带 applyError
/// 人话原因；botUsername/botName 是桥时代验钥产物，
/// 直连面无来源恒 nil（呈现本就是可选）
struct ChannelCredentialsReceipt: Decodable, Sendable {
    let platform: String
    let configured: Bool
    let state: String
    let restartRequired: Bool?
    let applyTriggered: Bool?
    let applyError: String?
    let botUsername: String?
    let botName: String?
    let message: String?
}

/// 频道直连客户端（API 直连 B 包，2026-11-14）：
/// 状态读与凭据编排从 channels 桥迁到 Hermes
/// Dashboard 原生面——
///   读  GET /api/messaging/platforms（performAdmin）
///   写  PUT /api/messaging/platforms/{id}（env 编排
///       在 OneDayCore MessagingCredentialsComposer）
///       + POST /api/gateway/restart 触发即时生效
/// 凭据只做编排、经登录会话通道上行，App 不留存
/// （输入框状态在页面层、提交即清空，口径不变）
final class ChannelsDirectClient: @unchecked Sendable {

    func status(appState: AppState) async throws -> ChannelsStatusResponse {
        let response: MessagingPlatformsResponse
        do {
            response = try await appState.performAdmin { client, config in
                try await client.messagingPlatforms(config: config)
            }
        } catch let error as HermesError {
            throw Self.bridgeError(
                for: error, endpoint: L10n.string("频道状态"))
        }
        let mapped = MessagingStatusMapping.map(response)
        return ChannelsStatusResponse(
            gatewayRunning: mapped.gatewayRunning,
            platforms: mapped.statuses.map {
                ChannelPlatformStatus(
                    platform: $0.platform, kind: $0.kind, open: $0.open,
                    configured: $0.configured, connected: $0.connected,
                    needsIdentity: $0.needsIdentity, state: $0.state,
                    sessionCount: $0.sessionCount, message: $0.message
                )
            }
        )
    }

    func submitCredentials(
        appState: AppState, platform: String,
        fields: [String: String], allowedUserIds: [String]?
    ) async throws -> ChannelCredentialsReceipt {
        let composed: MessagingCredentialsComposer.Composed
        do {
            composed = try MessagingCredentialsComposer.compose(
                platform: platform, fields: fields,
                allowedUserIds: allowedUserIds
            )
        } catch let error as MessagingComposeError {
            throw ChannelsBridgeError.failed(error.message)
        }
        do {
            try await appState.performAdmin { client, config in
                try await client.updateMessagingPlatform(
                    config: config, platform: platform, enabled: true,
                    env: composed.env, clearEnv: composed.clearEnv
                )
            }
        } catch let error as HermesError {
            throw Self.bridgeError(
                for: error, endpoint: L10n.string("频道配对"))
        }
        // 保存后触发网关重启即时生效（桥时代同一时
        // 序）：触发失败不算提交失败——钥匙已落盘，
        // 回执如实带 applyError、等下次重启生效
        var applyError: String?
        do {
            try await appState.performAdmin { client, config in
                try await client.gatewayRestart(config: config)
            }
        } catch {
            applyError = L10n.string(
                "即时生效没触发成功，将在网关下次重启时生效")
        }
        return ChannelCredentialsReceipt(
            platform: platform, configured: true,
            state: "pending_restart", restartRequired: true,
            applyTriggered: applyError == nil, applyError: applyError,
            botUsername: nil, botName: nil,
            message: applyError == nil
                ? L10n.string("钥匙已保存，正在生效")
                : L10n.string("钥匙已保存，正在等待生效")
        )
    }

    /// HermesError -> 频道错误口径：服务端原因先过
    /// §233 安全门（过门原样、不过门落通用人话＋原
    /// 文进诊断留痕），与桥时代 {error} 上抛同规矩
    static func bridgeError(
        for error: HermesError, endpoint: String
    ) -> ChannelsBridgeError {
        switch error {
        case .sessionExpired:
            return .failed(L10n.string("登录已失效，请重新连接服务器后再试"))
        case .serverMessage(let raw):
            return gated(raw, endpoint: endpoint)
        case .server(let code, let raw):
            if let raw, !raw.isEmpty {
                return gated(raw, endpoint: endpoint)
            }
            return .failed(
                L10n.format("%@返回 %@", endpoint, String(code)))
        case .unexpectedStatus(let name, let code):
            return .failed(
                L10n.format("%@返回 %@", name, String(code)))
        case .decodingFailed:
            return .failed(L10n.string("频道状态返回格式无法识别"))
        default:
            return .failed(L10n.string("频道服务连接失败，请稍后再试"))
        }
    }

    private static func gated(
        _ raw: String, endpoint: String
    ) -> ChannelsBridgeError {
        if let safe = ServerErrorText.userSafe(raw) {
            return .failed(safe)
        }
        ChatDiagTrace.record(
            "频道直连错误原文未过安全门 [\(endpoint)] \(raw)"
        )
        return .failed(L10n.format(
            "%@返回了无法识别的错误，请稍后再试。", endpoint
        ))
    }
}
