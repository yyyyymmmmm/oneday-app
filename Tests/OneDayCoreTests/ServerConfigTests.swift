import OneDayCore
import XCTest

final class ServerConfigTests: XCTestCase {
    func testBareDomainGetsHTTPS() {
        let config = ServerConfig(rawInput: "hermes.didichou.site")
        XCTAssertEqual(config?.baseString, "https://hermes.didichou.site")
    }

    func testTrailingSlashRemoved() {
        let config = ServerConfig(rawInput: "https://hermes.didichou.site/")
        XCTAssertEqual(config?.baseString, "https://hermes.didichou.site")
    }

    func testWhitespaceTrimmedAndHTTPPreserved() {
        let config = ServerConfig(rawInput: "  http://192.168.1.10:9119  ")
        XCTAssertEqual(config?.baseString, "http://192.168.1.10:9119")
    }

    func testQueryAndFragmentDropped() {
        let config = ServerConfig(rawInput: "https://hermes.didichou.site/?a=1#top")
        XCTAssertEqual(config?.baseString, "https://hermes.didichou.site")
    }

    func testEndpointBuilding() {
        let config = ServerConfig(rawInput: "hermes.didichou.site")
        XCTAssertEqual(config?.endpoint("/health").absoluteString, "https://hermes.didichou.site/health")
        XCTAssertEqual(config?.endpoint("/v1/models").absoluteString, "https://hermes.didichou.site/v1/models")
        XCTAssertEqual(config?.host, "hermes.didichou.site")
    }

    func testInvalidInputs() {
        XCTAssertNil(ServerConfig(rawInput: ""))
        XCTAssertNil(ServerConfig(rawInput: "   "))
        XCTAssertNil(ServerConfig(rawInput: "ftp://example.com"))
        XCTAssertNil(ServerConfig(rawInput: "https://"))
    }
}
