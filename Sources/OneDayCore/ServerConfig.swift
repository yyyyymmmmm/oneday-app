import Foundation

/// 用户在连接页填入的服务器地址归一化与端点拼装。
///
/// 归一化规则（连接页「测试并连接」前先行，单测覆盖）：
/// - 去首尾空白；未写协议时补 https://；
/// - 只保留 scheme / host / port / path，去掉 query 与 fragment；
/// - 去掉 path 尾斜杠，根地址形如 https://hermes.didichou.site；
/// - host 为空、协议非 http/https、无法解析 → 返回 nil（连接页报
///   「服务器地址看起来不对」）。
public struct ServerConfig: Equatable, Sendable {
    /// 归一化后的根地址字符串（无尾斜杠）
    public let baseString: String

    public init?(rawInput: String) {
        var text = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") {
            text = "https://" + text
        }
        guard var components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty else {
            return nil
        }
        components.query = nil
        components.fragment = nil
        var path = components.path
        while path.hasSuffix("/") {
            path.removeLast()
        }
        components.path = path
        guard let normalized = components.string else { return nil }
        baseString = normalized
    }

    public var baseURL: URL {
        // baseString 由 URLComponents 拼成，恒可解析
        URL(string: baseString)! // swiftlint:disable:this force_unwrapping
    }

    /// 显示用 host（如 hermes.didichou.site）
    public var host: String {
        URLComponents(string: baseString)?.host ?? baseString
    }

    /// 由根地址拼端点：path 以 / 开头，如 /health、/v1/models
    public func endpoint(_ path: String) -> URL {
        URL(string: baseString + path)! // swiftlint:disable:this force_unwrapping
    }
}
