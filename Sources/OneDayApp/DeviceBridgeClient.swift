import Foundation
import OneDayCore

/// device-bridge 错误口径：401 钥匙被拒如实露；409
/// 是会话已被顶替/过期（客户端状态机据此重注册）；
/// 其余失败给人话、不混报。
enum DeviceBridgeError: Error, Sendable, Equatable {
    case noKey
    case unauthorized
    case unknownSession
    case failed(String)
}

/// 注册回执（桥契约）：轮询/调用/会话的时限以桥下
/// 发为准、客户端不写死第二套数
struct DeviceSessionGrant: Decodable, Sendable {
    let sessionId: String
    let pollWaitSec: Double
    let callTimeoutSec: Double
    let sessionTtlSec: Double
}

/// 桥下发的一次待执行调用（poll 回执）：arguments
/// 是动态 JSON，先以 JSONValue 接住、由 Core 逐工
/// 具解析校验
struct DeviceIncomingCall: Decodable, Sendable {
    let callId: String
    let tool: String
    let arguments: [String: JSONValue]
    let createdAt: Double
}

/// device-bridge 设备会话通道客户端（0.34.0 批一）：
/// 注册/心跳/长轮询/回执/断开五口，路径挂在当前服
/// 务器根下 /api/device-bridge（nginx 单钥入口：App
/// 以 Hermes 登录密钥作 Bearer，入口验过后在服务器
/// 内部换桥自己的服务钥——BridgeCredential 统一读，
/// 与其余桥客户端同口径）。桥只转发调用、手机现读
/// 现回，服务器不存设备数据（设计档工具调用制）。
final class DeviceBridgeClient: @unchecked Sendable {
    private let session: URLSession
    private let pollSession: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        session = URLSession(configuration: configuration)
        // 长轮询单次挂起 ≤25 秒（桥上限），请求超时给
        // 到 45 秒留足网络余量；不用默认 60 秒免得退
        // 后台后迟迟不断
        let pollConfiguration = URLSessionConfiguration.default
        pollConfiguration.timeoutIntervalForRequest = 45
        pollSession = URLSession(configuration: pollConfiguration)
    }

    private var bridgeKey: String? {
        BridgeCredential.read()
    }

    /// POST /device/session：注册会话（新注册顶替旧
    /// 会话），201 回 sessionId 与三项时限
    func registerSession(
        config: ServerConfig, deviceId: String, appVersion: String,
        permissions: [String: String], tools: [String]
    ) async throws -> DeviceSessionGrant {
        var request = try makeRequest(
            config: config, path: "/device/session", method: "POST"
        )
        // permissions 是动态键字典，整体走 JSONSerialization 组装
        var body: [String: Any] = [
            "deviceId": deviceId,
            "appVersion": appVersion,
            "tools": tools,
        ]
        body["permissions"] = permissions
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue(
            "application/json", forHTTPHeaderField: "Content-Type"
        )
        let (data, http) = try await send(request, endpoint: "注册设备会话")
        try checkStatus(http, data: data, endpoint: "注册设备会话")
        do {
            return try decoder.decode(DeviceSessionGrant.self, from: data)
        } catch {
            throw DeviceBridgeError.failed("注册回执格式无法识别")
        }
    }

    /// POST /device/heartbeat：会话还在回 true，已被
    /// 顶替/过期（404）回 false——不抛错，调用方据此
    /// 走状态机重注册
    func heartbeat(
        config: ServerConfig, sessionId: String
    ) async throws -> Bool {
        var request = try makeRequest(
            config: config, path: "/device/heartbeat", method: "POST"
        )
        request.httpBody = try encoder.encode(
            ["sessionId": sessionId]
        )
        request.setValue(
            "application/json", forHTTPHeaderField: "Content-Type"
        )
        let (_, http) = try await send(request, endpoint: "设备心跳")
        if http.statusCode == 404 { return false }
        try checkStatus(http, data: Data(), endpoint: "设备心跳")
        return true
    }

    /// GET /device/poll：长轮询领一次调用（无调用回
    /// nil）；409＝会话不在了，抛 unknownSession 供
    /// 状态机重注册。任务被取消时 URLSession 抛
    /// URLError.cancelled、原样上抛（停轮询的信号）
    func poll(
        config: ServerConfig, sessionId: String, wait: Double
    ) async throws -> DeviceIncomingCall? {
        var components = URLComponents(
            url: config.endpoint("/api/device-bridge/device/poll"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "sessionId", value: sessionId),
            URLQueryItem(name: "wait", value: String(wait)),
        ]
        guard let key = bridgeKey, !key.isEmpty else {
            throw DeviceBridgeError.noKey
        }
        guard let url = components?.url else {
            throw DeviceBridgeError.failed("轮询地址组装失败")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(
            "Bearer \(key)", forHTTPHeaderField: "Authorization"
        )
        let (data, http) = try await send(
            request, endpoint: "领取设备调用", using: pollSession
        )
        if http.statusCode == 409 {
            throw DeviceBridgeError.unknownSession
        }
        try checkStatus(http, data: data, endpoint: "领取设备调用")
        struct PollBody: Decodable {
            let call: DeviceIncomingCall?
        }
        do {
            return try decoder.decode(PollBody.self, from: data).call
        } catch {
            throw DeviceBridgeError.failed("轮询回执格式无法识别")
        }
    }

    /// POST /device/respond：回一次调用的结果或结构
    /// 化错误。result 是动态 JSON（JSONValue 对象形）
    func respond(
        config: ServerConfig, sessionId: String, callId: String,
        result: JSONValue?, error: DeviceToolError?
    ) async throws {
        var request = try makeRequest(
            config: config, path: "/device/respond", method: "POST"
        )
        var body: [String: Any] = [
            "sessionId": sessionId,
            "callId": callId,
            "status": error == nil ? "ok" : "error",
        ]
        if let result {
            body["result"] = try JSONSerialization.jsonObject(
                with: encoder.encode(result)
            )
        }
        if let error {
            body["error"] = ["code": error.code, "message": error.message]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue(
            "application/json", forHTTPHeaderField: "Content-Type"
        )
        let (data, http) = try await send(request, endpoint: "回执设备调用")
        try checkStatus(http, data: data, endpoint: "回执设备调用")
    }

    /// POST /device/disconnect：尽力断开（退后台时调，
    /// 失败无妨——桥有 45 秒无心跳自动判离线兜底）
    func disconnect(config: ServerConfig, sessionId: String) async {
        guard var request = try? makeRequest(
            config: config, path: "/device/disconnect", method: "POST"
        ) else { return }
        request.httpBody = try? encoder.encode(["sessionId": sessionId])
        request.setValue(
            "application/json", forHTTPHeaderField: "Content-Type"
        )
        _ = try? await send(request, endpoint: "断开设备会话")
    }

    // MARK: - 请求底座

    private func makeRequest(
        config: ServerConfig, path: String, method: String
    ) throws -> URLRequest {
        guard let key = bridgeKey, !key.isEmpty else {
            throw DeviceBridgeError.noKey
        }
        var request = URLRequest(
            url: config.endpoint("/api/device-bridge" + path)
        )
        request.httpMethod = method
        request.setValue(
            "Bearer \(key)", forHTTPHeaderField: "Authorization"
        )
        return request
    }

    private struct BridgeErrorBody: Decodable {
        let error: String
    }

    private func checkStatus(
        _ http: HTTPURLResponse, data: Data, endpoint: String
    ) throws {
        switch http.statusCode {
        case 200...299:
            return
        case 401:
            throw DeviceBridgeError.unauthorized
        default:
            if let body = try? decoder.decode(
                BridgeErrorBody.self, from: data
            ), !body.error.isEmpty {
                throw DeviceBridgeError.failed(body.error)
            }
            throw DeviceBridgeError.failed(
                "\(endpoint)返回 \(http.statusCode)"
            )
        }
    }

    private func send(
        _ request: URLRequest, endpoint: String,
        using session: URLSession? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await (session ?? self.session)
                .data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw DeviceBridgeError.failed("\(endpoint)无响应")
            }
            return (data, http)
        } catch let error as DeviceBridgeError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw DeviceBridgeError.failed("\(endpoint)网络不可达")
        }
    }
}
