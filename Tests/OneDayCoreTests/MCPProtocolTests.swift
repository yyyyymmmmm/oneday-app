import XCTest
@testable import OneDayCore

/// F11：MCP 协议测试（请求信封编码、响应解码、SSE 解析、内容解析）
final class MCPProtocolTests: XCTestCase {

    // MARK: - F2 请求信封形状测试

    func testToolsCallRequestEnvelope() throws {
        // F2：tools/call params 顶层包含 name 和 arguments
        let request = MCPRequest(
            id: "test-123",
            method: "tools/call",
            params: [
                "name": .string("box_status"),
                "arguments": .object(["wait": .bool(true)])
            ]
        )

        let data = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["jsonrpc"] as? String, "2.0")
        XCTAssertEqual(json["id"] as? String, "test-123")
        XCTAssertEqual(json["method"] as? String, "tools/call")

        let params = json["params"] as! [String: Any]
        XCTAssertEqual(params["name"] as? String, "box_status")

        let arguments = params["arguments"] as! [String: Any]
        XCTAssertEqual(arguments["wait"] as? Bool, true)

        // 不应该有 "tool" 包装
        XCTAssertNil(params["tool"])
    }

    // MARK: - JSON 响应解码

    func testMCPResponseDecoding() throws {
        let jsonText = """
        {
            "jsonrpc": "2.0",
            "id": "req-1",
            "result": {
                "content": [
                    {"type": "text", "text": "Hello"}
                ],
                "isError": false
            }
        }
        """

        let data = jsonText.data(using: .utf8)!
        let response = try JSONDecoder().decode(MCPResponse.self, from: data)

        XCTAssertEqual(response.id, "req-1")
        XCTAssertFalse(response.isError)
        XCTAssertNotNil(response.result)
        XCTAssertEqual(response.result?.isError, false)
    }

    func testMCPErrorDecoding() throws {
        let jsonText = """
        {
            "jsonrpc": "2.0",
            "id": "req-2",
            "error": {
                "code": -32600,
                "message": "Invalid request",
                "data": {"detail": "missing field"}
            }
        }
        """

        let data = jsonText.data(using: .utf8)!
        let response = try JSONDecoder().decode(MCPResponse.self, from: data)

        XCTAssertTrue(response.isError)
        XCTAssertEqual(response.error?.code, -32600)
        XCTAssertEqual(response.error?.message, "Invalid request")
    }

    // MARK: - F4 SSE 响应解析

    func testSSEResponseParsing() throws {
        let sseText = """
        event: message
        data: {"jsonrpc":"2.0","id":"req-1","result":{"content":[{"type":"text","text":"OK"}]}}

        data: {"jsonrpc":"2.0","id":"req-2","result":{"content":[]}}

        """

        let data = sseText.data(using: .utf8)!

        // 提取 req-1 的响应
        let extracted1 = parseSSEResponse(data: data, requestId: "req-1")
        XCTAssertNotNil(extracted1)

        let response1 = try JSONDecoder().decode(MCPResponse.self, from: extracted1!)
        XCTAssertEqual(response1.id, "req-1")

        // 提取 req-2 的响应
        let extracted2 = parseSSEResponse(data: data, requestId: "req-2")
        XCTAssertNotNil(extracted2)

        let response2 = try JSONDecoder().decode(MCPResponse.self, from: extracted2!)
        XCTAssertEqual(response2.id, "req-2")

        // 不存在的 ID
        let extracted3 = parseSSEResponse(data: data, requestId: "req-999")
        XCTAssertNil(extracted3)
    }

    // MARK: - MCPContent 解码

    func testMCPContentTextDecoding() throws {
        let jsonText = """
        {"type": "text", "text": "Hello World"}
        """

        let data = jsonText.data(using: .utf8)!
        let content = try JSONDecoder().decode(MCPContent.self, from: data)

        if case .text(let text) = content {
            XCTAssertEqual(text, "Hello World")
        } else {
            XCTFail("Expected text content")
        }
    }

    func testMCPContentImageDecoding() throws {
        let jsonText = """
        {"type": "image", "data": "iVBORw0KGgo=", "mimeType": "image/png"}
        """

        let data = jsonText.data(using: .utf8)!
        let content = try JSONDecoder().decode(MCPContent.self, from: data)

        if case .image(let imageData, let mimeType) = content {
            XCTAssertEqual(imageData, "iVBORw0KGgo=")
            XCTAssertEqual(mimeType, "image/png")
        } else {
            XCTFail("Expected image content")
        }
    }

    func testMCPContentImageDecodingWithSnakeCase() throws {
        // 兼容 mime_type 键名
        let jsonText = """
        {"type": "image", "data": "abc123", "mime_type": "image/jpeg"}
        """

        let data = jsonText.data(using: .utf8)!
        let content = try JSONDecoder().decode(MCPContent.self, from: data)

        if case .image(let imageData, let mimeType) = content {
            XCTAssertEqual(imageData, "abc123")
            XCTAssertEqual(mimeType, "image/jpeg")
        } else {
            XCTFail("Expected image content")
        }
    }

    // MARK: - mcpTexts / mcpStructured / mcpErrorText

    func testMcpTexts() throws {
        let jsonText = """
        {
            "content": [
                {"type": "text", "text": "Line 1"},
                {"type": "image", "data": "xyz", "mimeType": "image/png"},
                {"type": "text", "text": "Line 2"}
            ]
        }
        """

        let data = jsonText.data(using: .utf8)!
        let result = try JSONDecoder().decode(MCPResult.self, from: data)

        let texts = mcpTexts(result)
        XCTAssertEqual(texts.count, 2)
        XCTAssertEqual(texts[0], "Line 1")
        XCTAssertEqual(texts[1], "Line 2")
    }

    func testMcpStructured() throws {
        let jsonText = """
        {
            "structuredContent": {
                "state": "running",
                "credits_left": 100.5
            }
        }
        """

        let data = jsonText.data(using: .utf8)!
        let result = try JSONDecoder().decode(MCPResult.self, from: data)

        let structured = mcpStructured(result)
        XCTAssertNotNil(structured)
        XCTAssertEqual(structured?["state"] as? String, "running")
        XCTAssertEqual(structured?["credits_left"] as? Double, 100.5)
    }

    func testMcpStructuredFallbackToTextJSON() throws {
        let jsonText = """
        {
            "content": [
                {"type": "text", "text": "{\\"key\\": \\"value\\"}"}
            ]
        }
        """

        let data = jsonText.data(using: .utf8)!
        let result = try JSONDecoder().decode(MCPResult.self, from: data)

        let structured = mcpStructured(result)
        XCTAssertNotNil(structured)
        XCTAssertEqual(structured?["key"] as? String, "value")
    }

    func testMcpErrorText() throws {
        let jsonText = """
        {
            "content": [
                {"type": "text", "text": "Error: something went wrong with details"}
            ]
        }
        """

        let data = jsonText.data(using: .utf8)!
        let result = try JSONDecoder().decode(MCPResult.self, from: data)

        let errorText = mcpErrorText(result)
        XCTAssertTrue(errorText.hasPrefix("Error:"))
        XCTAssertLessThanOrEqual(errorText.count, 400)
    }

    func testMcpErrorTextEmpty() throws {
        let jsonText = """
        {
            "content": []
        }
        """

        let data = jsonText.data(using: .utf8)!
        let result = try JSONDecoder().decode(MCPResult.self, from: data)

        let errorText = mcpErrorText(result)
        XCTAssertEqual(errorText, "tool error")
    }
}
