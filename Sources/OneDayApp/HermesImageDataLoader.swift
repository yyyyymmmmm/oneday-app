import Foundation
import Nuke

/// §418（#23 图片管线换底）：全仓唯一自定义 DataLoader
/// ——按 RemoteImageRequestFactory 的构造标记分发，不
/// 在本类里猜鉴权：
/// - localdata:// → LocalImageDataRegistry 注入表回查；
/// - img.oneday.invalid/rendition → 登记的变体通道，
///   无登记通道时走桥 rendition（登记 config），失败
///   回落登记的原图通道（旧管线 fetch 的变体优先／原
///   图回落口径逐字迁移）；
/// - img.oneday.invalid/original → 登记的原图通道
///   （宿主 performAdmin 鉴权下载，401 自动重登在通
///   道闭包内，loader 无感）；
/// - img.oneday.invalid/poster → 登记的变体通道
///   kind=poster，无回落（旧口径）；
/// - 其余 http(s) 公开 URL → Nuke 默认 URLSession
///   loader 直通。
final class HermesImageDataLoader {
    static let shared = HermesImageDataLoader()

    private let fallback = DataLoader()
    private let bridgeClient = OneDayBridgeClient()

    private init() {}
}

extension HermesImageDataLoader: @unchecked Sendable {}

extension HermesImageDataLoader: DataLoading {
    func loadData(
        with request: URLRequest,
        didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void,
        completion: @escaping @Sendable (Error?) -> Void
    ) -> any Cancellable {
        guard let url = request.url else {
            completion(URLError(.badURL))
            return CompletedCancellable()
        }
        if url.scheme == "localdata" {
            guard let key = RemoteImageRequestFactory.localKey(
                      for: url),
                  let data = LocalImageDataRegistry.shared
                      .data(for: key)
            else {
                completion(URLError(.fileDoesNotExist))
                return CompletedCancellable()
            }
            didReceiveData(data, Self.response(for: url))
            completion(nil)
            return CompletedCancellable()
        }
        if url.host == RemoteImageRequestFactory.routeHost {
            let task = Task { [self] in
                do {
                    let data = try await fetchRouted(url)
                    guard !Task.isCancelled else { return }
                    didReceiveData(
                        data, Self.response(for: url))
                    completion(nil)
                } catch {
                    guard !Task.isCancelled else { return }
                    completion(error)
                }
            }
            return TaskCancellable(task: task)
        }
        return fallback.loadData(
            with: request,
            didReceiveData: didReceiveData,
            completion: completion)
    }

    // MARK: - 路由取数

    private func fetchRouted(_ url: URL) async throws -> Data {
        guard let route = RemoteImageRequestFactory.route(
            for: url) else {
            throw URLError(.badURL)
        }
        let entry = RemoteImageRequestFactory.routeKey(
            for: url).flatMap {
            HermesImageRouting.shared.entry(forKey: $0)
        }
        switch route {
        case .rendition(let path, let width):
            if let renditionLoader = entry?.renditionLoader,
               let data = await renditionLoader("image") {
                return data
            }
            if let config = entry?.config,
               let data = try? await bridgeClient.rendition(
                   config: config, path: path, width: width) {
                return data
            }
            if let originalLoader = entry?.originalLoader,
               let data = await originalLoader() {
                return data
            }
            throw URLError(.resourceUnavailable)
        case .original:
            if let originalLoader = entry?.originalLoader,
               let data = await originalLoader() {
                return data
            }
            throw URLError(.resourceUnavailable)
        case .poster:
            if let renditionLoader = entry?.renditionLoader,
               let data = await renditionLoader("poster") {
                return data
            }
            throw URLError(.resourceUnavailable)
        }
    }

    private static func response(for url: URL) -> URLResponse {
        HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: nil,
            headerFields: nil) ?? URLResponse(
            url: url, mimeType: nil, expectedContentLength: 0,
            textEncodingName: nil)
    }
}

/// 已同步完成、无可取消的占位句柄
private struct CompletedCancellable: Cancellable {
    func cancel() {}
}

/// Task 句柄装箱：取消即取消底层取数任务
private final class TaskCancellable: Cancellable, @unchecked Sendable {
    private let task: Task<Void, Never>

    init(task: Task<Void, Never>) {
        self.task = task
    }

    func cancel() {
        task.cancel()
    }
}
