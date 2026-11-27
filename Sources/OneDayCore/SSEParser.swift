import Foundation

/// SSE 一行产生的事件：正文增量、思考增量、工具调用
/// 分片（0.8.0）或流结束。
public enum SSEEvent: Equatable, Sendable {
    case delta(String)
    case reasoning(String)
    case toolCalls([ChatStreamChunk.ToolCallFragment])
    case done
}

/// OpenAI 兼容流式响应解析器（纯逻辑，单测覆盖；#22 兼容 RFC 8895 EventSource 直入载荷）。
public struct SSEParser: Sendable {
    private let decoder = JSONDecoder()

    public init() {}

    public func consume(line: String) -> SSEEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("data:") else { return nil }
        let payload = trimmed.dropFirst("data:".count)
            .trimmingCharacters(in: .whitespaces)
        return consume(dataPayload: String(payload))
    }

    /// 供 RFC 8895 `EventSource` 事件流直喂 `event.data` 载荷（#22 真切流）。
    public func consume(dataPayload rawPayload: String) -> SSEEvent? {
        let payload = rawPayload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !payload.isEmpty else { return nil }
        if payload == "[DONE]" {
            return .done
        }
        guard let data = payload.data(using: .utf8),
              let chunk = try? decoder.decode(ChatStreamChunk.self, from: data) else {
            return nil
        }
        if let text = chunk.deltaText {
            return .delta(text)
        }
        if let reasoning = chunk.deltaReasoning {
            return .reasoning(reasoning)
        }
        if let fragments = chunk.toolCallFragments {
            return .toolCalls(fragments)
        }
        return nil
    }
}
