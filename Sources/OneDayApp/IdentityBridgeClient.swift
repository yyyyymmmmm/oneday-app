import Foundation
import OneDayCore

/// 身份桥错误：与总览桥同分法——没有钥匙/钥匙被拒是
/// 「桥未连接」，其余失败如实报、不归因于钥匙。
enum IdentityBridgeError: Error, Sendable, Equatable {
    case noKey
    case unauthorized
    case failed(String)
}

/// 头像仓状态（与伴生 identity_bridge 的 GET
/// /identity/avatar 同形）：当前指针＋全量条目历史；
/// 图片条目的字节本体走单独端点取，不塞进状态回执。
struct IdentityAvatarState: Decodable, Sendable {
    struct Item: Decodable, Sendable {
        let id: String
        let kind: String
        let presetId: String?
        let contentType: String?
        let bytes: Int?
        let sha256: String?
        let current: Bool
        /// 条目写入时刻（epoch 秒，桥侧账；末写胜用）
        let createdAt: Double?
        /// 写入来源（ai/app…）：只留痕、不参与裁决
        let source: String?

        var createdAtDate: Date? {
            createdAt.map { Date(timeIntervalSince1970: $0) }
        }
    }

    let currentId: String?
    let items: [Item]
    /// 当前指针最后一次被设定的时刻（epoch 秒）：设
    /// 当前的那次写入（新增设当前/重选）落账；旧桥
    /// 无此字段时为 nil，调用方以当前条目 createdAt
    /// 兜底
    let currentUpdatedAt: Double?
    /// 设定当前指针的来源：只留痕、不参与裁决
    let currentSource: String?

    /// 当前条目：优先信条目自带的 current 标记，缺失
    /// 时按 currentId 兜底查
    var currentItem: Item? {
        items.first(where: { $0.current })
            ?? items.first(where: { $0.id == currentId })
    }

    /// AI 档的写入时刻（末写胜凭据）：指针时刻优先，
    /// 缺失时回落当前条目的写入时刻，再缺失为 nil
    var currentUpdatedAtDate: Date? {
        if let currentUpdatedAt {
            return Date(timeIntervalSince1970: currentUpdatedAt)
        }
        return currentItem?.createdAtDate
    }
}


/// 身份桥客户端（P1 身份包）：头像仓读面＋§245 起
/// 的写穿面——App 改名/换头像与智能体改名改头像走
/// 同一组服务端窄口（服务端单真值：校验、备份、回
/// 读验名、留痕全在桥侧收口，App 不开第二条写路、
/// 不在本地裁决）。路径挂当前服务器根下
/// /api/identity-bridge，Bearer 只从 BridgeCredential
/// 统一读（与全 App 桥客户端同口径，0.33.1）。
/// C-10 收敛：连接/单钥/管线/文案走统一基座，本类只
/// 留路径、DTO 与状态口径。
final class IdentityBridgeClient: @unchecked Sendable {
    private let base = BridgeClientBase<IdentityBridgeError>(
        pathPrefix: "/api/identity-bridge", timeout: 15,
        waitsForConnectivity: true,
        noKey: .noKey, failed: IdentityBridgeError.failed
    )

    func avatarState(config: ServerConfig) async throws -> IdentityAvatarState {
        let data = try await get(
            config: config, path: "/identity/avatar",
            endpoint: L10n.string("头像仓")
        )
        return try base.decode(
            data,
            orThrow: IdentityBridgeError.failed(L10n.string("头像仓返回格式无法识别"))
        )
    }

    func avatarImage(config: ServerConfig, id: String) async throws -> Data {
        try await get(
            config: config, path: "/identity/avatar/image?id=\(id)",
            endpoint: L10n.string("头像图")
        )
    }

    // MARK: - 写穿（§245：App 改名/换头像直达服务端真值）
    //
    // 判读口径（§232 安全门）：2xx 过；401 未授权；
    // 其余取服务端 error 文案先过 ServerErrorText.
    // userSafe 才许带出，不过门/解不出落本类通用人
    // 话（只报是哪件失败、带状态码定位），绝不露服
    // 务端原文。

    /// 改名写穿：POST /identity/name（dryRun=false、
    /// actor=user；服务端复校、写 SOUL 人设标题行、
    /// 落 name-state 账并留痕）。成功后调用方以
    /// Dashboard 回读刷新名字缓存
    func setName(config: ServerConfig, name: String) async throws {
        try await post(
            config: config, path: "/identity/name",
            body: ["name": name, "dryRun": false, "actor": "user"],
            endpoint: L10n.string("身份名")
        )
    }

    /// 预置头像写穿：POST /identity/avatar kind=preset
    /// （append-only 新条目并设为当前；服务端回 201）
    func addAvatarPreset(
        config: ServerConfig, presetID: String
    ) async throws {
        try await post(
            config: config, path: "/identity/avatar",
            body: [
                "kind": "preset",
                "presetId": presetID,
                "source": "app-user",
                "makeCurrent": true,
            ],
            endpoint: L10n.string("头像仓")
        )
    }

    /// 图片头像写穿：POST /identity/avatar imageBase64
    /// （制备 JPEG 字节；服务端硬顶 2MB、魔数校验）
    func addAvatarImage(
        config: ServerConfig, imageData: Data
    ) async throws {
        try await post(
            config: config, path: "/identity/avatar",
            body: [
                "imageBase64": imageData.base64EncodedString(),
                "source": "app-user",
                "makeCurrent": true,
            ],
            endpoint: L10n.string("头像仓")
        )
    }

    private func post(
        config: ServerConfig, path: String,
        body: [String: Any], endpoint: String
    ) async throws {
        guard let bodyData = try? JSONSerialization.data(
            withJSONObject: body
        ) else {
            throw IdentityBridgeError.failed(
                L10n.format("%@保存失败。", endpoint)
            )
        }
        let (data, http) = try await base.perform(
            config: config, path: path, method: "POST",
            bodyData: bodyData, endpoint: endpoint
        )
        if (200..<300).contains(http.statusCode) { return }
        if http.statusCode == 401 {
            throw IdentityBridgeError.unauthorized
        }
        if let raw = base.serverMessage(data),
           let safe = ServerErrorText.userSafe(raw) {
            throw IdentityBridgeError.failed(safe)
        }
        throw IdentityBridgeError.failed(
            L10n.format(
                "%@保存失败（错误 %@）。", endpoint,
                String(http.statusCode)
            )
        )
    }

    private func get(
        config: ServerConfig, path: String, endpoint: String
    ) async throws -> Data {
        let request = try base.makeRequest(
            config: config, path: path, method: "GET",
            cachePolicy: .reloadIgnoringLocalCacheData
        )
        let (data, http) = try await base.data(
            for: request, endpoint: endpoint
        )
        if http.statusCode == 401 {
            throw IdentityBridgeError.unauthorized
        }
        guard http.statusCode == 200 else {
            throw IdentityBridgeError.failed(
                L10n.format("%@返回 %@", endpoint, String(http.statusCode))
            )
        }
        return data
    }
}
