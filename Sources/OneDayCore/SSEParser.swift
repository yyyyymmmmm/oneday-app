import Foundation

/// SSE 一行产生的事件：文本增量或流结束。
public enum SSEEvent: Equatable, Sendable {
    case delta(String)
    case done
}

/// OpenAI 兼容流式响应的逐行解析器（纯逻辑，单测覆盖）。
///
/// 只认 data: 行：`data: [DONE]` → .done；`data: {json}` 解
/// ChatStreamChunk 取 delta 文本；空行、event:/id:/注释行与
/// 解不出文本的分片一律忽略（返回 nil），流不中断。
/// 非流式错误（如接后端前的提示文本）走完整 JSON 响应，
/// 不经本解析器，由客户端在非 200 / 非流式分支处理。
public struct SSEParser: Sendable {
    private let decoder = JSONDecoder()

    public init() {}

    public func consume(line: String) -> SSEEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("data:") else { return nil }
        let payload = trimmed.dropFirst("data:".count)
            .trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" {
            return .done
        }
        guard let data = String(payload).data(using: .utf8),
              let chunk = try? decoder.decode(ChatStreamChunk.self, from: data),
              let text = chunk.deltaText else {
            return nil
        }
        return .delta(text)
    }
}
