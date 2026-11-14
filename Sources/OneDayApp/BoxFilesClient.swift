import Foundation
import OneDayCore

/// 盒文件错误：与各桥同分法——「没有钥匙」「钥匙被拒
/// （401）」是桥未连接；列表端点 404 是「电脑文件尚未
/// 开通」（桥还没部署文件面）；其余失败给人话、不混报。
enum BoxFilesError: Error, Sendable, Equatable {
    case noKey
    case unauthorized
    case notAvailable
    case failed(String)
}

/// 盒文件客户端（P8，契约 box-files-contract-20261109.md）：
/// 读 Simular Box 的 /workspace 产出，端点挂在盒桥下
/// （/api/box-bridge/files、/files/read），鉴权与盒桥
/// 同一把 Keychain 桥钥匙。桥侧文件面尚未部署（归 P9
/// 电脑面或独立小包），现网请求会 404——客户端据此如
/// 实报「尚未开通」，不拿空列表冒充没有文件。响应形状
/// 与 Hermes /api/files 列表同构（契约钉死），路径为相对
/// Box 工作区根的相对路径（"" 为根）。
final class BoxFilesClient: @unchecked Sendable {
    /// C-10 收敛：连接/单钥/管线/文案走统一基座，本类
    /// 只留路径、查询拼装与状态口径
    private let base = BridgeClientBase<BoxFilesError>(
        pathPrefix: "/api/box-bridge", timeout: 30,
        noKey: .noKey, failed: BoxFilesError.failed
    )

    private var decoder: JSONDecoder { base.decoder }

    /// GET /files?path= → 与 FilesListing 同构的列表
    func list(
        config: ServerConfig, path: String?
    ) async throws -> FilesListing {
        var query: [URLQueryItem] = []
        if let path, !path.isEmpty {
            query.append(URLQueryItem(name: "path", value: path))
        }
        let request = try makeRequest(
            config: config, path: "/files", query: query
        )
        let (data, http) = try await send(request, endpoint: L10n.string("电脑文件列表"))
        if http.statusCode == 404 {
            throw BoxFilesError.notAvailable
        }
        try check(http, endpoint: L10n.string("电脑文件列表"))
        do {
            return try decoder.decode(FilesListing.self, from: data)
        } catch {
            throw BoxFilesError.failed(L10n.string("电脑文件列表返回格式无法识别"))
        }
    }

    /// GET /files/read?path= → 原始字节（预览/下载共用）
    func fileData(
        config: ServerConfig, path: String
    ) async throws -> Data {
        let request = try makeRequest(
            config: config, path: "/files/read",
            query: [URLQueryItem(name: "path", value: path)],
            timeout: 60
        )
        let (data, http) = try await send(request, endpoint: L10n.string("电脑文件读取"))
        if http.statusCode == 404 {
            throw BoxFilesError.failed(L10n.string("这个文件已不存在。"))
        }
        try check(http, endpoint: L10n.string("电脑文件读取"))
        return data
    }

    private func makeRequest(
        config: ServerConfig, path: String,
        query: [URLQueryItem], timeout: TimeInterval? = nil
    ) throws -> URLRequest {
        var request = try base.makeRequest(
            config: config, path: path, method: "GET"
        )
        if !query.isEmpty, let url = request.url {
            var components = URLComponents(
                url: url, resolvingAgainstBaseURL: false
            )
            components?.queryItems = query
            if let composed = components?.url {
                request.url = composed
            }
        }
        if let timeout {
            request.timeoutInterval = timeout
        }
        return request
    }

    private func check(
        _ http: HTTPURLResponse, endpoint: String
    ) throws {
        if http.statusCode == 401 {
            throw BoxFilesError.unauthorized
        }
        guard (200...299).contains(http.statusCode) else {
            throw BoxFilesError.failed(L10n.format("%@返回 %@", endpoint, String(http.statusCode)))
        }
    }

    private func send(
        _ request: URLRequest, endpoint: String
    ) async throws -> (Data, HTTPURLResponse) {
        try await base.data(for: request, endpoint: endpoint)
    }
}
