import Foundation
import OneDayCore

/// 频道桥错误：没有钥匙/钥匙被拒是「桥未连接」，其
/// 余失败带伴生回的人话原因如实上抛（配对失败不许
/// 在 App 侧被吞成泛化文案，规格 §6.3）
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

/// 凭据保存回执：值永不回显，只回成败与下一步状态
struct ChannelCredentialsReceipt: Decodable, Sendable {
    let platform: String
    let configured: Bool
    let state: String
    let restartRequired: Bool?
    let botUsername: String?
    /// 邮箱频道回执带的账号地址（用户自己刚填的那个，
    /// 非凭据值，可回显）
    let account: String?
    /// 保存后是否已触发即时生效（一期回执未消费此
    /// 字段的残项，特殊批补上：引导页据此区分「正在
    /// 生效」与「等待生效」）
    let applyTriggered: Bool?
    let applyError: String?
    let message: String?
}

/// 扫码配对会话（与伴生 /channels/qr/* 同形）：状态
/// 只转述伴生的回读（配对层事实），平台是否连上仍
/// 以 /channels/status 的运行时记录为准，两层不混
struct ChannelQRSession: Decodable, Sendable, Equatable {
    let platform: String
    let pairingId: String?
    /// installing / starting / waiting / connected /
    /// error / expired / cancelled
    let status: String
    /// 当前二维码载荷（约 20 秒轮换一张，永远只渲染
    /// 最新一张；无码时为 nil）
    let qrPayload: String?
    let mode: String?
    let accountName: String?
    let accountPhone: String?
    /// 扫码成功后伴生是否已完成启用（apply 只调一次）
    let applied: Bool?
    let applyError: String?
    let error: String?
}

/// 频道桥客户端（频道扩展一期）：路径挂当前服务器
/// 根下 /api/channels-bridge，Bearer 只从
/// BridgeCredential 统一读（与全 App 桥客户端同口
/// 径，0.33.1）；钥匙（平台凭据）经本通道只写不读，
/// App 不留存（输入框状态在页面层、提交即清空）
final class ChannelsBridgeClient: @unchecked Sendable {
    private let session: URLSession
    private let decoder = JSONDecoder()

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        configuration.waitsForConnectivity = true
        session = URLSession(configuration: configuration)
    }

    private var bridgeKey: String? {
        BridgeCredential.read()
    }

    func status(config: ServerConfig) async throws -> ChannelsStatusResponse {
        let data = try await send(
            config: config, path: "/channels/status", method: "GET",
            body: nil, endpoint: L10n.string("频道状态")
        )
        do {
            return try decoder.decode(
                ChannelsStatusResponse.self, from: data
            )
        } catch {
            throw ChannelsBridgeError.failed(
                L10n.string("频道状态返回格式无法识别"))
        }
    }

    func submitCredentials(
        config: ServerConfig, platform: String,
        fields: [String: String], allowedUserIds: [String]?,
        preset: String? = nil
    ) async throws -> ChannelCredentialsReceipt {
        var payload: [String: Any] = [
            "platform": platform, "fields": fields,
        ]
        if let allowedUserIds {
            payload["allowedUserIds"] = allowedUserIds
        }
        if let preset {
            payload["preset"] = preset
        }
        let data = try await send(
            config: config, path: "/channels/credentials",
            method: "POST", body: payload,
            endpoint: L10n.string("频道配对")
        )
        do {
            return try decoder.decode(
                ChannelCredentialsReceipt.self, from: data
            )
        } catch {
            throw ChannelsBridgeError.failed(
                L10n.string("配对结果返回格式无法识别"))
        }
    }

    /// 起一个扫码配对会话（WhatsApp）：伴生代理
    /// Hermes 自带的 onboarding，返回当前码载荷
    func qrStart(
        config: ServerConfig
    ) async throws -> ChannelQRSession {
        let data = try await send(
            config: config, path: "/channels/qr/start",
            method: "POST", body: ["platform": "whatsapp"],
            endpoint: L10n.string("扫码配对")
        )
        return try decodeQRSession(data)
    }

    /// 轮询配对会话：拿最新码载荷/扫码结果；扫码成
    /// 功后伴生自动完成启用（applied 回报）
    func qrStatus(
        config: ServerConfig
    ) async throws -> ChannelQRSession {
        let data = try await send(
            config: config, path: "/channels/qr/status",
            method: "GET", body: nil,
            endpoint: L10n.string("扫码配对")
        )
        return try decodeQRSession(data)
    }

    /// 取消当前配对会话（离开页面/重新开始前调用）
    func qrCancel(
        config: ServerConfig
    ) async throws {
        _ = try await send(
            config: config, path: "/channels/qr/cancel",
            method: "POST", body: ["platform": "whatsapp"],
            endpoint: L10n.string("扫码配对")
        )
    }

    private func decodeQRSession(
        _ data: Data
    ) throws -> ChannelQRSession {
        do {
            return try decoder.decode(
                ChannelQRSession.self, from: data
            )
        } catch {
            throw ChannelsBridgeError.failed(
                L10n.string("配对状态返回格式无法识别"))
        }
    }

    /// 统一发信：非 200 时优先解伴生的 {error} 人话
    /// 原因原样上抛（配对失败态要显示真原因，规格
    /// §6.3），解不出才回落状态码文案
    private func send(
        config: ServerConfig, path: String, method: String,
        body: [String: Any]?, endpoint: String
    ) async throws -> Data {
        guard let key = bridgeKey, !key.isEmpty else {
            throw ChannelsBridgeError.noKey
        }
        var request = URLRequest(
            url: config.endpoint("/api/channels-bridge" + path)
        )
        request.httpMethod = method
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue(
                "application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(
                withJSONObject: body)
        }
        let (data, http) = try await rawSend(request, endpoint: endpoint)
        if http.statusCode == 401 {
            throw ChannelsBridgeError.unauthorized
        }
        guard http.statusCode == 200 else {
            if let view = try? decoder.decode(
                [String: String].self, from: data
            ), let message = view["error"], !message.isEmpty {
                throw ChannelsBridgeError.failed(message)
            }
            throw ChannelsBridgeError.failed(
                L10n.format("%@返回 %@", endpoint, String(http.statusCode))
            )
        }
        return data
    }

    private func rawSend(
        _ request: URLRequest, endpoint: String
    ) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw ChannelsBridgeError.failed(
                    L10n.format("%@无响应", endpoint))
            }
            return (data, http)
        } catch let error as ChannelsBridgeError {
            throw error
        } catch {
            throw ChannelsBridgeError.failed(
                L10n.format("%@网络不可达", endpoint))
        }
    }
}
