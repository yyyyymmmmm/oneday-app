import Foundation
import OneDayCore

/// 提供商直连探针（0.37.0）：添加提供商时的连通性
/// 检查——拿用户刚填的密钥直连对方 GET /models（设
/// 计 §6.4：验证就是调 /models，拉不到列表就降级手
/// 填）。密钥只在本次请求头里出现，不落任何本地存
/// 储；本客户端无状态、无缓存。
final class ProviderProbeClient: @unchecked Sendable {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        session = URLSession(configuration: configuration)
    }

    enum ProbeFailure: Error, Equatable {
        case badURL
        case rejected(Int)   // 401/403 等：多半是密钥不对
        case unreachable
        case emptyList       // 通了但没返回任何模型

        var message: String {
            switch self {
            case .badURL:
                return L10n.string("接口地址不对，拼不出模型列表的地址。")
            case .rejected(let status):
                return L10n.format("对方拒绝了（%@），多半是密钥不对或没权限。", String(status))
            case .unreachable:
                return L10n.string("连不上这家提供商，检查地址或稍后再试。")
            case .emptyList:
                return L10n.string("连上了，但对方没返回任何模型；可以手动填模型名。")
            }
        }
    }

    /// GET {base}/models → 模型 id 列表（Core 解析）。
    /// base 尾部的 / 自动收口；已带 /models 的地址不重复拼。
    func fetchModels(
        baseURL: String, apiKey: String
    ) async throws -> [String] {
        var base = baseURL.trimmingCharacters(in: .whitespaces)
        while base.hasSuffix("/") { base.removeLast() }
        let urlString = base.hasSuffix("/models") ? base : base + "/models"
        guard let url = URL(string: urlString) else {
            throw ProbeFailure.badURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(
            "Bearer \(apiKey)", forHTTPHeaderField: "Authorization"
        )
        request.timeoutInterval = 15
        let data: Data
        let http: HTTPURLResponse
        do {
            let (rawData, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ProbeFailure.unreachable
            }
            data = rawData
            http = httpResponse
        } catch let error as ProbeFailure {
            throw error
        } catch {
            throw ProbeFailure.unreachable
        }
        switch http.statusCode {
        case 200...299:
            break
        case 401, 403:
            throw ProbeFailure.rejected(http.statusCode)
        default:
            throw ProbeFailure.rejected(http.statusCode)
        }
        guard let root = try? JSONDecoder().decode(
            JSONValue.self, from: data
        ) else {
            throw ProbeFailure.emptyList
        }
        let models = ProviderRegistry.parseModelList(from: root)
        if models.isEmpty { throw ProbeFailure.emptyList }
        return models
    }
}
