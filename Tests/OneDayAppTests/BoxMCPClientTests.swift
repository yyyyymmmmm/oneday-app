import XCTest
@testable import OneDayApp

final class BoxMCPClientTests: XCTestCase {

    /// M2 回归测试：Bool 参数应编码为 JSON true/false，不是数字
    func testAnyToJSONValueBoolEncoding() async throws {
        let client = BoxMCPClient(
            mcpURL: URL(string: "https://example.com")!,
            apiKey: "test-key"
        )

        // 测试 Bool 值编码
        let boolTrue = await client.anyToJSONValue(true)
        let boolFalse = await client.anyToJSONValue(false)

        if case .bool(let value) = boolTrue {
            XCTAssertTrue(value)
        } else {
            XCTFail("Expected .bool(true), got \(boolTrue)")
        }

        if case .bool(let value) = boolFalse {
            XCTAssertFalse(value)
        } else {
            XCTFail("Expected .bool(false), got \(boolFalse)")
        }

        // 测试包含 Bool 的字典
        let dict: [String: Any] = ["wait": true, "front": false, "count": 42]
        let jsonValue = await client.anyToJSONValue(dict)

        if case .object(let obj) = jsonValue {
            if case .bool(let waitValue) = obj["wait"] {
                XCTAssertTrue(waitValue)
            } else {
                XCTFail("Expected wait to be .bool(true)")
            }

            if case .bool(let frontValue) = obj["front"] {
                XCTAssertFalse(frontValue)
            } else {
                XCTFail("Expected front to be .bool(false)")
            }

            if case .number(let countValue) = obj["count"] {
                XCTAssertEqual(countValue, 42.0)
            } else {
                XCTFail("Expected count to be .number(42.0)")
            }
        } else {
            XCTFail("Expected .object")
        }
    }
}
