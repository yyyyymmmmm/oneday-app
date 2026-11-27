import Foundation

/// SSE 一行产生的事件：正文增量、思考增量、工具调用
/// 分片（0.8.0）或流结束。
public enum SSEEvent: Equatable, Sendable {
    case delta(String)
    case reasoning(String)
    case toolCalls([ChatStreamChunk.ToolCallFragment])
    case done
}

/// OpenAI 兼容流式响应的逐行解析器（纯逻辑，单测覆盖）。
///
/// 只认 data: 行：`data: [DONE]` → .done；`data: {json}` 解
/// ChatStreamChunk 取增量；空行、event:/id:/注释行与解不出
/// 增量的分片一律忽略（返回 nil），流不中断。
/// 非流式错误（如接后端前的提示文本）走完整 JSON 响应，
/// 不经本解析器，由客户端在非 200 / 非流式分支处理。
///
/// 思考通道（0.5.1，§32）：delta.reasoning_content →
/// .reasoning。正文与思考同帧并存时正文优先、思考让位
/// ——网关与 DeepSeek 均为分帧下发（思考期 content 为
/// 空、正文期 reasoning_content 缺席），并存不发生；
/// 让位保证正文永不丢字。
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
