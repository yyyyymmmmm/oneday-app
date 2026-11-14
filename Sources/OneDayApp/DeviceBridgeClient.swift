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
    /// 载荷种类（§244）：permission_ask/permission_
    /// notice 为权限流伪调用；普通工具调用为 nil 或
    /// "tool"（旧桥不带此字段，解码为 nil）
    let kind: String?
}

/// device-bridge 设备会话通道客户端（0.34.0 批一）：
/// 注册/心跳/长轮询/回执/断开五口，路径挂在当前服
/// 务器根下 /api/device-bridge（nginx 单钥入口：App
/// 以 Hermes 登录密钥作 Bearer，入口验过后在服务器
/// 内部换桥自己的服务钥——BridgeCredential 统一读，
/// 与其余桥客户端同口径）。桥只转发调用、手机现读
/// 现回，服务器不存设备数据（设计档工具调用制）。
final class DeviceBridgeClient: @unchecked Sendable {
    /// C-10 收敛：连接/单钥/管线/文案走统一基座，本类
    /// 只留路径、DTO 与设备桥状态口径
    private let base = BridgeClientBase<DeviceBridgeError>(
        pathPrefix: "/api/device-bridge", timeout: 15,
        noKey: .noKey, failed: DeviceBridgeError.failed
    )
    /// 长轮询单次挂起 ≤25 秒（桥上限），请求超时给
    /// 到 45 秒留足网络余量；不用默认 60 秒免得退
    /// 后台后迟迟不断
    private let pollSession = BridgeClientBase<DeviceBridgeError>
        .makeSession(timeout: 45)

    private var decoder: JSONDecoder { base.decoder }
    private var encoder: JSONEncoder { base.encoder }

    /// POST /device/session：注册会话（新注册顶替旧
    /// 会话），201 回 sessionId 与三项时限
    func registerSession(
        config: ServerConfig, deviceId: String, appVersion: String,
        permissions: [String: String], tools: [String],
        agentCall: [String: Bool] = [:],
        capabilities: [String] = []
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
        // §244 P-2：调用开关映射（桥分层判门用）＋
        // 权限流能力声明（旧桥忽略未知字段）
        if !agentCall.isEmpty { body["agentCall"] = agentCall }
        if !capabilities.isEmpty {
            body["capabilities"] = capabilities
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue(
            "application/json", forHTTPHeaderField: "Content-Type"
        )
        let (data, http) = try await send(request, endpoint: L10n.string("注册设备会话"))
        try checkStatus(http, data: data, endpoint: L10n.string("注册设备会话"))
        do {
            return try decoder.decode(DeviceSessionGrant.self, from: data)
        } catch {
            throw DeviceBridgeError.failed(L10n.string("注册回执格式无法识别"))
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
        let (_, http) = try await send(request, endpoint: L10n.string("设备心跳"))
        if http.statusCode == 404 { return false }
        try checkStatus(http, data: Data(), endpoint: L10n.string("设备心跳"))
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
        let key = try base.requireKey()
        guard let url = components?.url else {
            throw DeviceBridgeError.failed(L10n.string("这一步的结果没确认回来，请再试一次；如果反复这样，把这条记录发我看。"))
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(
            "Bearer \(key)", forHTTPHeaderField: "Authorization"
        )
        let (data, http) = try await send(
            request, endpoint: L10n.string("领取设备调用"), using: pollSession
        )
        if http.statusCode == 409 {
            throw DeviceBridgeError.unknownSession
        }
        try checkStatus(http, data: data, endpoint: L10n.string("领取设备调用"))
        struct PollBody: Decodable {
            let call: DeviceIncomingCall?
        }
        do {
            return try decoder.decode(PollBody.self, from: data).call
        } catch {
            throw DeviceBridgeError.failed(L10n.string("这一步的结果没确认回来，请再试一次；如果反复这样，把这条记录发我看。"))
        }
    }

    /// POST /device/respond：回一次调用的结果或结构
    /// 化错误。result 是动态 JSON（JSONValue 对象形）
    func respond(
        config: ServerConfig, sessionId: String, callId: String,
        result: JSONValue?, error: DeviceToolError?,
        errorFields: [String: JSONValue] = [:]
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
            var errorBody: [String: Any] = [
                "code": error.code, "message": error.message,
            ]
            // §244 P-1：结构化字段随错误体透传（权限
            // 类带 state，桥据此补 blockerLayer 等）
            for (key, value) in errorFields {
                errorBody[key] = try JSONSerialization.jsonObject(
                    with: encoder.encode(value)
                )
            }
            body["error"] = errorBody
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue(
            "application/json", forHTTPHeaderField: "Content-Type"
        )
        let (data, http) = try await send(request, endpoint: L10n.string("回执设备调用"))
        try checkStatus(http, data: data, endpoint: L10n.string("回执设备调用"))
    }

    /// POST /device/resume（§244 P-4）：凭 resumeToken
    /// 让桥把挂起的原调用重发执行。404（token 过期/
    /// 未知）与 409（会话不在线）是业务分型不抛错，
    /// 交 PermissionResumeOutcome 分型给协调器；401
    /// 仍按未授权抛
    func resumeCall(
        config: ServerConfig, resumeToken: String
    ) async throws -> PermissionResumeOutcome {
        var request = try makeRequest(
            config: config, path: "/device/resume", method: "POST"
        )
        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["resumeToken": resumeToken]
        )
        request.setValue(
            "application/json", forHTTPHeaderField: "Content-Type"
        )
        let (data, http) = try await send(
            request, endpoint: L10n.string("续办设备调用")
        )
        if http.statusCode == 401 || http.statusCode == 403 {
            throw DeviceBridgeError.unauthorized
        }
        let body = try? decoder.decode(JSONValue.self, from: data)
        return PermissionResumeOutcome.from(
            httpStatus: http.statusCode, body: body
        )
    }

    /// POST /device/park-state（§261 ①）：只读查桥侧
    /// park 还在不在、何时过期、ask 结局——卡对账的
    /// 真相源，不消费 token。旧桥无此端点（404）或
    /// 回执不可信回 nil，调用方走本地兜底；桥明确回
    /// exists=false 是有效答复、照常返回
    func parkState(
        config: ServerConfig, resumeToken: String
    ) async throws -> PermissionParkState? {
        var request = try makeRequest(
            config: config, path: "/device/park-state",
            method: "POST"
        )
        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["resumeToken": resumeToken]
        )
        request.setValue(
            "application/json", forHTTPHeaderField: "Content-Type"
        )
        let (data, http) = try await send(
            request, endpoint: L10n.string("查询挂起状态")
        )
        if http.statusCode == 401 || http.statusCode == 403 {
            throw DeviceBridgeError.unauthorized
        }
        guard http.statusCode == 200 else { return nil }
        let body = try? decoder.decode(JSONValue.self, from: data)
        return PermissionParkState.parse(body: body)
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
        _ = try? await send(request, endpoint: L10n.string("断开设备会话"))
    }

    // MARK: - 同步通道（0.36.14，规格 §3.1）

    /// JSONValue → JSONSerialization 可吃的 Any（借
    /// respond 的既有转法：先 Codable 编码再解回）
    private func anyJSON(_ value: JSONValue) throws -> Any {
        try JSONSerialization.jsonObject(with: encoder.encode(value))
    }

    private func postSync(
        config: ServerConfig, path: String,
        body: [String: Any], endpoint: String
    ) async throws -> [String: Any] {
        var request = try makeRequest(
            config: config, path: path, method: "POST"
        )
        request.httpBody = try JSONSerialization.data(
            withJSONObject: body
        )
        request.setValue(
            "application/json", forHTTPHeaderField: "Content-Type"
        )
        let (data, http) = try await send(request, endpoint: endpoint)
        try checkStatus(http, data: data, endpoint: endpoint)
        guard let object = try? JSONSerialization.jsonObject(
            with: data
        ) as? [String: Any] else {
            throw DeviceBridgeError.failed(L10n.format("%@回执格式无法识别", endpoint))
        }
        return object
    }

    /// GET /device/sync/status：逐数据集状态（只出
    /// 状态、无记录内容），回 Data 交 Core 解码
    func syncStatusData(config: ServerConfig) async throws -> Data {
        let key = try base.requireKey()
        var request = URLRequest(
            url: config.endpoint("/api/device-bridge/device/sync/status")
        )
        request.httpMethod = "GET"
        request.setValue(
            "Bearer \(key)", forHTTPHeaderField: "Authorization"
        )
        let (data, http) = try await send(request, endpoint: L10n.string("读取同步状态"))
        try checkStatus(http, data: data, endpoint: L10n.string("读取同步状态"))
        return data
    }

    /// POST /device/sync/manifest：通讯录标识＋指纹
    /// 清单比对，回有变/已消失两张单（桥回执键是
    /// snake_case，与 complete 的混排不同，逐个取）
    func syncManifest(
        config: ServerConfig, entries: [ContactManifestEntry]
    ) async throws -> (
        changed: [String], removed: [String], currentTotal: Int
    ) {
        let body: [String: Any] = [
            "dataset": "contacts",
            "entries": try entries.map {
                try anyJSON(.object($0.json))
            },
        ]
        let out = try await postSync(
            config: config, path: "/device/sync/manifest",
            body: body, endpoint: L10n.string("通讯录清单比对")
        )
        return (
            changed: out["changed_ids"] as? [String] ?? [],
            removed: out["removed_ids"] as? [String] ?? [],
            currentTotal:
                (out["current_total"] as? NSNumber)?.intValue ?? 0
        )
    }

    /// POST /device/sync/batch：分批暂存（一批 ≤500
    /// 条的口径在 App 侧切，见 SyncBatchPlan）；暂存
    /// 不进正式表，完成确认才整批换入
    func syncBatch(
        config: ServerConfig, dataset: DeviceSyncDataset,
        batchId: String, records: [[String: JSONValue]],
        mode: String
    ) async throws -> Int {
        let body: [String: Any] = [
            "dataset": dataset.bridgeName,
            "batchId": batchId,
            "mode": mode,
            "records": try records.map { try anyJSON(.object($0)) },
        ]
        let out = try await postSync(
            config: config, path: "/device/sync/batch",
            body: body, endpoint: L10n.string("同步分批上传")
        )
        return (out["received"] as? NSNumber)?.intValue ?? 0
    }

    /// POST /device/sync/complete：报应到总数，桥核
    /// 对无误才换入；对不上回 409（checkStatus 把桥
    /// 的 error 码原样带出，控制层据码翻人话）
    func syncComplete(
        config: ServerConfig, dataset: DeviceSyncDataset,
        batchId: String, expectedTotal: Int,
        deviceCompletedAt: Date, mode: String,
        coverage: [String: JSONValue]?,
        aggregates: [String: JSONValue]?,
        removedIds: [String]?,
        authRange: String, rangeNote: String?,
        permissionState: String
    ) async throws -> (
        totalInStore: Int, syncedAt: Date?, authRange: String?
    ) {
        var body: [String: Any] = [
            "dataset": dataset.bridgeName,
            "batchId": batchId,
            "expectedTotal": expectedTotal,
            "deviceCompletedAt":
                DeviceISO8601.format(deviceCompletedAt),
            "mode": mode,
            "authRange": authRange,
            "permissionState": permissionState,
        ]
        if let coverage {
            body["coverage"] = try anyJSON(.object(coverage))
        }
        if let aggregates {
            body["aggregates"] = try anyJSON(.object(aggregates))
        }
        if let removedIds {
            body["removedIds"] = removedIds
        }
        if let rangeNote {
            body["rangeNote"] = rangeNote
        }
        let out = try await postSync(
            config: config, path: "/device/sync/complete",
            body: body, endpoint: L10n.string("同步完成确认")
        )
        return (
            totalInStore:
                (out["total_in_store"] as? NSNumber)?.intValue ?? 0,
            syncedAt: (out["synced_at"] as? String)
                .flatMap(DeviceISO8601.parse),
            authRange: out["auth_range"] as? String
        )
    }

    /// POST /device/sync/state：上报权限/范围变化；
    /// 范围变了桥回 reimport_required（下轮整本重灌）
    func syncReportState(
        config: ServerConfig, dataset: DeviceSyncDataset,
        permissionState: String, authRange: String,
        rangeNote: String?
    ) async throws -> Bool {
        var body: [String: Any] = [
            "dataset": dataset.bridgeName,
            "permissionState": permissionState,
            "authRange": authRange,
        ]
        if let rangeNote { body["rangeNote"] = rangeNote }
        let out = try await postSync(
            config: config, path: "/device/sync/state",
            body: body, endpoint: L10n.string("上报权限状态")
        )
        return out["reimport_required"] as? Bool ?? false
    }

    /// POST /device/sync/delete：删副本（单件传
    /// dataset、全删不传）；删的是服务器副本，手机
    /// 数据/权限/配对都不动
    func syncDelete(
        config: ServerConfig, dataset: DeviceSyncDataset?
    ) async throws -> [String] {
        var body: [String: Any] = [:]
        if let dataset { body["dataset"] = dataset.bridgeName }
        let out = try await postSync(
            config: config, path: "/device/sync/delete",
            body: body, endpoint: L10n.string("删除同步副本")
        )
        return out["deleted"] as? [String] ?? []
    }

    // MARK: - 请求底座

    private func makeRequest(
        config: ServerConfig, path: String, method: String
    ) throws -> URLRequest {
        try base.makeRequest(config: config, path: path, method: method)
    }

    private func checkStatus(
        _ http: HTTPURLResponse, data: Data, endpoint: String
    ) throws {
        try base.checkPassthroughStatus(
            http, data: data, endpoint: endpoint,
            unauthorized: .unauthorized
        )
    }

    private func send(
        _ request: URLRequest, endpoint: String,
        using session: URLSession? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        // 设备通道取消即停轮询信号：取消必须原样上抛
        // （基座 propagateCancellation 口径）
        try await base.data(
            for: request, endpoint: endpoint, using: session,
            propagateCancellation: true
        )
    }
}
