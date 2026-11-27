import Foundation
import LinkPresentation

/// 链接预览元数据提供者（按 iMessage 通行做法）：
/// 检出文本中第一个 URL、异步获取元数据、会话级缓存。
/// 失败兜底显示简化卡片（仅域名）
@MainActor
public final class LinkPreviewProvider: ObservableObject {
    @Published public private(set) var metadata: LPLinkMetadata?
    @Published public private(set) var isLoading = false
    @Published public private(set) var currentURL: URL?

    private var metadataCache: [URL: LPLinkMetadata] = [:]
    private var fetchTask: Task<Void, Never>?
    private let timeoutSeconds: TimeInterval = 15

    public init() {}

    /// 从文本中检出第一个 URL 并获取元数据（debounce 外部控制）
    public func detectAndFetch(from text: String) {
        fetchTask?.cancel()

        guard let url = detectFirstURL(in: text) else {
            clear()
            return
        }

        // URL 未变不重复获取
        if currentURL == url, metadata != nil {
            return
        }

        currentURL = url

        // 命中缓存立即返回
        if let cached = metadataCache[url] {
            metadata = cached
            isLoading = false
            return
        }

        isLoading = true
        metadata = nil

        fetchTask = Task {
            await fetchMetadata(for: url)
        }
    }

    /// 清除当前预览状态
    public func clear() {
        fetchTask?.cancel()
        currentURL = nil
        metadata = nil
        isLoading = false
    }

    /// 用 NSDataDetector 检出第一个 URL（通行做法）
    private func detectFirstURL(in text: String) -> URL? {
        guard !text.isEmpty else { return nil }

        let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.link.rawValue
        )
        let range = NSRange(text.startIndex..., in: text)

        guard let match = detector?.firstMatch(
            in: text, options: [], range: range
        ),
              let url = match.url,
              url.scheme?.lowercased() == "http" || url.scheme?.lowercased() == "https"
        else {
            return nil
        }

        return url
    }

    /// 异步获取元数据，15 秒超时，失败兜底
    private func fetchMetadata(for url: URL) async {
        let provider = LPMetadataProvider()
        provider.timeout = timeoutSeconds

        do {
            let fetched = try await provider.startFetchingMetadata(for: url)

            guard !Task.isCancelled else { return }

            metadataCache[url] = fetched
            metadata = fetched
            isLoading = false
        } catch {
            guard !Task.isCancelled else { return }

            // 失败兜底：构造仅含 URL 的简化元数据
            let fallback = LPLinkMetadata()
            fallback.originalURL = url
            fallback.url = url
            fallback.title = url.host ?? url.absoluteString

            metadataCache[url] = fallback
            metadata = fallback
            isLoading = false
        }
    }
}
