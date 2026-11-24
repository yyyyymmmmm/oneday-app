import XCTest
@testable import OneDayCore

/// 配对一期（台账 153/160）：连接二维码载荷的组装
/// 与解析钉测——扫码侧只认真形态，任何偏离（版本/
/// 字段/码形/指纹形/地址）一律拒，呈现层据 nil 给
/// 「不是 OneDay 连接二维码」人话
final class EnrollmentPayloadTests: XCTestCase {

    private var config: ServerConfig {
        ServerConfig(rawInput: "hermes.example.com")!
    }
    private let code = "ABCDEFGHJKMNPQRSTUVW"  // 20 字符
    private let fingerprint = "0123456789abcdef"

    func testRoundTrip() {
        let payload = EnrollmentPayload(
            config: config, code: code, fingerprint: fingerprint
        )
        let parsed = EnrollmentPayload.parse(payload.qrString())
        XCTAssertEqual(parsed, payload)
        XCTAssertEqual(parsed?.config.baseString, "https://hermes.example.com")
    }

    func testRejectsNonJSON() {
        XCTAssertNil(EnrollmentPayload.parse("https://hermes.example.com"))
        XCTAssertNil(EnrollmentPayload.parse(""))
        XCTAssertNil(EnrollmentPayload.parse("ABCDEFGHJKMNPQRSTUVW"))
    }

    func testRejectsWrongVersion() {
        let raw = #"{"v":2,"url":"https://hermes.example.com","code":"ABCDEFGHJKMNPQRSTUVW","fp":"0123456789abcdef"}"#
        XCTAssertNil(EnrollmentPayload.parse(raw))
    }

    func testRejectsMissingFields() {
        XCTAssertNil(EnrollmentPayload.parse(
            #"{"v":1,"url":"https://hermes.example.com","code":"ABCDEFGHJKMNPQRSTUVW"}"#
        ))
        XCTAssertNil(EnrollmentPayload.parse(
            #"{"v":1,"code":"ABCDEFGHJKMNPQRSTUVW","fp":"0123456789abcdef"}"#
        ))
    }

    func testRejectsBadCodeShape() {
        // 太短
        XCTAssertNil(EnrollmentPayload.parse(
            #"{"v":1,"url":"https://hermes.example.com","code":"ABC123","fp":"0123456789abcdef"}"#
        ))
        // 含非字母数字字符
        XCTAssertNil(EnrollmentPayload.parse(
            #"{"v":1,"url":"https://hermes.example.com","code":"ABCDEFGHJKMNPQRSTUV!","fp":"0123456789abcdef"}"#
        ))
    }

    func testRejectsBadFingerprintShape() {
        XCTAssertNil(EnrollmentPayload.parse(
            #"{"v":1,"url":"https://hermes.example.com","code":"ABCDEFGHJKMNPQRSTUVW","fp":"0123"}"#
        ))
        XCTAssertNil(EnrollmentPayload.parse(
            #"{"v":1,"url":"https://hermes.example.com","code":"ABCDEFGHJKMNPQRSTUVW","fp":"0123456789abcdeg"}"#
        ))
    }

    func testRejectsBadURL() {
        XCTAssertNil(EnrollmentPayload.parse(
            #"{"v":1,"url":"","code":"ABCDEFGHJKMNPQRSTUVW","fp":"0123456789abcdef"}"#
        ))
    }

    /// 服务端回执 DTO 解码（公网实测回执形态同字面）
    func testIssueAndClaimDecode() throws {
        let issueData = Data(
            #"{"code":"ABCDEFGHJKMNPQRSTUVW","expires_at":1763616000.0,"ttl_seconds":300,"fingerprint":"0123456789abcdef"}"#.utf8
        )
        let issue = try JSONDecoder().decode(EnrollmentIssue.self, from: issueData)
        XCTAssertEqual(issue.code, code)
        XCTAssertEqual(issue.ttlSeconds, 300)
        XCTAssertEqual(issue.fingerprint, fingerprint)

        let claimData = Data(
            #"{"api_key":"test-key","fingerprint":"0123456789abcdef"}"#.utf8
        )
        let claim = try JSONDecoder().decode(EnrollmentClaim.self, from: claimData)
        XCTAssertEqual(claim.apiKey, "test-key")
        XCTAssertEqual(claim.fingerprint, fingerprint)
    }

    /// 认领四态人话互不串味：无效/过期/锁定/出码超
    /// 限各说各的，不许把过期说成不对
    func testEnrollmentErrorCopy() {
        XCTAssertTrue(HermesError.enrollmentCodeInvalid.userMessage.contains("不对"))
        XCTAssertTrue(HermesError.enrollmentCodeExpired.userMessage.contains("过期"))
        XCTAssertTrue(HermesError.enrollmentLocked.userMessage.contains("锁"))
        XCTAssertTrue(HermesError.enrollmentTooManyPending.userMessage.contains("满"))
    }
}
