import Foundation
import OneDayCore

/// 频道桥错误：没有钥匙/钥匙被拒是「桥未连接」，其
/// 余失败带伴生回的人话原因上抛（配对失败不许在
/// App 侧被吞成泛化文案，规格 §6.3）；§233 起原因
/// 须先过 ServerErrorText 安全门才许上屏，不过门
/// 落通用人话、原文只进诊断留痕
enum ChannelsBridgeError: Error, Sendable, Equatable {
    case noKey
    case unauthorized
    case failed(String)
}

/// 单个平台的配对状态（与伴生 channels_bridge 的
/// GET /channels/status 同形）：configured/connected
/// 只认网关自家记录，App 不二次推断
struct ChannelPlatformStatus: Decodable, Sendable, Equatable {
    let platform: String
    let kind: String
    let open: Bool
    let configured: Bool
    let connected: Bool
    let needsIdentity: Bool
    /// not_configured / pending_restart / connected /
    /// error
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
/// applyTriggered/applyError 是伴生 1.0.46 的加法扩
/// 展（保存后有没有触发网关重启即时生效）：旧版伴
/// 生没有这两字段，解码为 nil、呈现回落 status；
/// botName 是飞书验钥后探到的机器人名（二期）
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

/// 频道桥客户端（频道扩展一期）：路径挂当前服务器
/// 根下 /api/channels-bridge，Bearer 只从
/// BridgeCredential 统一读（与全 App 桥客户端同口
/// 径，0.33.1）；钥匙（平台凭据）经本通道只写不读，
/// App 不留存（输入框状态在页面层、提交即清空）
final class ChannelsBridgeClient: @unchecked Sendable {
    /// C-10 收敛：连接/单钥/管线/文案走统一基座，本类
    /// 只留路径、DTO 与状态口径
    private let base = BridgeClientBase<ChannelsBridgeError>(
        pathPrefix: "/api/channels-bridge", timeout: 20,
        waitsForConnectivity: true,
        noKey: .noKey, failed: ChannelsBridgeError.failed
    )

    func status(config: ServerConfig) async throws -> ChannelsStatusResponse {
        let data = try await send(
            config: config, path: "/channels/status", method: "GET",
            body: nil, endpoint: L10n.string("频道状态")
        )
        return try base.decode(
            data,
            orThrow: ChannelsBridgeError.failed(
                L10n.string("频道状态返回格式无法识别"))
        )
    }

    func submitCredentials(
        config: ServerConfig, platform: String,
        fields: [String: String], allowedUserIds: [String]?
    ) async throws -> ChannelCredentialsReceipt {
        var payload: [String: Any] = [
            "platform": platform, "fields": fields,
        ]
        if let allowedUserIds {
            payload["allowedUserIds"] = allowedUserIds
        }
        let data = try await send(
            config: config, path: "/channels/credentials",
            method: "POST", body: payload,
            endpoint: L10n.string("频道配对")
        )
        return try base.decode(
            data,
            orThrow: ChannelsBridgeError.failed(
                L10n.string("配对结果返回格式无法识别"))
        )
    }

    /// 统一发信：非 200 时优先解伴生的 {error} 原因
    /// 上抛（配对失败态要显示真原因，规格 §6.3）——
    /// §233 起原因先过 ServerErrorText 安全门：过门
    /// 原样、不过门落通用人话＋原文进诊断留痕；解
    /// 不出错误体才回落状态码文案
    private func send(
        config: ServerConfig, path: String, method: String,
        body: [String: Any]?, endpoint: String
    ) async throws -> Data {
        let bodyData = try body.map {
            try JSONSerialization.data(withJSONObject: $0)
        }
        let (data, http) = try await base.perform(
            config: config, path: path, method: method,
            bodyData: bodyData, endpoint: endpoint
        )
        if http.statusCode == 401 {
            throw ChannelsBridgeError.unauthorized
        }
        guard http.statusCode == 200 else {
            if let view = try? base.decoder.decode(
                [String: String].self, from: data
            ), let message = view["error"], !message.isEmpty {
                if let safe = ServerErrorText.userSafe(message) {
                    throw ChannelsBridgeError.failed(safe)
                }
                ChatDiagTrace.record(
                    "频道桥错误原文未过安全门 [\(endpoint) \(http.statusCode)] \(message)"
                )
                throw ChannelsBridgeError.failed(
                    L10n.format(
                        "%@返回了无法识别的错误，请稍后再试。",
                        endpoint
                    )
                )
            }
            throw ChannelsBridgeError.failed(
                L10n.format("%@返回 %@", endpoint, String(http.statusCode))
            )
        }
        return data
    }
}
