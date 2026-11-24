import OneDayCore
import XCTest

/// 能力协商单源钉测（总表 157，DESIGN §394）：逐项判
/// 定矩阵——探针分流（405/404/message_not_found）与
/// features 旗标（对象型/子旗标缺失）逐字钉；没证据
/// 一律 unknown、不往好处猜
final class CapabilityNegotiationTests: XCTestCase {

    // MARK: - 样本（与现网 /v1/capabilities 实测形态同构）

    private func capabilities(
        idempotencyBody: String
    ) throws -> CapabilitiesResponse {
        let json = """
        {
          "object": "hermes.api_server.capabilities",
          "platform": "hermes-agent",
          "auth": {"type": "bearer", "required": true},
          "runtime": {"mode": "server_agent"},
          "features": {
            "chat_completions": true,
            "runs_idempotency": \(idempotencyBody)
          },
          "endpoints": {
            "health": {"method": "GET", "path": "/health"},
            "models": {"method": "GET", "path": "/v1/models"},
            "chat_completions": {"method": "POST", "path": "/v1/chat/completions"},
            "runs": {"method": "POST", "path": "/v1/runs"},
            "sessions": {"method": "GET", "path": "/api/sessions"}
          }
        }
        """
        return try JSONDecoder().decode(
            CapabilitiesResponse.self, from: Data(json.utf8)
        )
    }

    private let legacyBody = """
    {"supported": true, "durable": true, "retention_seconds": 86400}
    """
    private let withClientMessageIdBody = """
    {"supported": true, "durable": true, "retention_seconds": 86400,
     "client_message_id": true}
    """
    private let unsupportedBody = """
    {"supported": false, "durable": false, "retention_seconds": 0}
    """

    // MARK: - #1 认领探针

    func testEnrollmentProbeMatrix() {
        XCTAssertEqual(
            CapabilityNegotiation.enrollmentAvailability(
                RouteProbeResult(status: 405, errorCode: nil)
            ), .available
        )
        XCTAssertEqual(
            CapabilityNegotiation.enrollmentAvailability(
                RouteProbeResult(status: 404, errorCode: nil)
            ), .unavailable
        )
        XCTAssertEqual(
            CapabilityNegotiation.enrollmentAvailability(
                RouteProbeResult(status: 200, errorCode: nil)
            ), .unknown
        )
        XCTAssertEqual(
            CapabilityNegotiation.enrollmentAvailability(nil),
            .unknown
        )
    }

    // MARK: - #2 反应探针

    func testReactionsProbeMatrix() {
        XCTAssertEqual(
            CapabilityNegotiation.reactionsAvailability(
                RouteProbeResult(status: 405, errorCode: nil)
            ), .available
        )
        XCTAssertEqual(
            CapabilityNegotiation.reactionsAvailability(
                RouteProbeResult(status: 404, errorCode: "message_not_found")
            ), .available
        )
        XCTAssertEqual(
            CapabilityNegotiation.reactionsAvailability(
                RouteProbeResult(status: 404, errorCode: "not_found")
            ), .unavailable
        )
        XCTAssertEqual(
            CapabilityNegotiation.reactionsAvailability(
                RouteProbeResult(status: 500, errorCode: nil)
            ), .unknown
        )
        XCTAssertEqual(
            CapabilityNegotiation.reactionsAvailability(nil),
            .unknown
        )
    }

    // MARK: - #4 任务幂等旗标

    func testRunIdempotencyFlag() throws {
        XCTAssertEqual(
            CapabilityNegotiation.runIdempotencyAvailability(
                try capabilities(idempotencyBody: legacyBody)
            ), .available
        )
        XCTAssertEqual(
            CapabilityNegotiation.runIdempotencyAvailability(
                try capabilities(idempotencyBody: unsupportedBody)
            ), .unavailable
        )
        XCTAssertEqual(
            CapabilityNegotiation.runIdempotencyAvailability(nil),
            .unknown
        )
    }

    // MARK: - #14 消息级幂等子旗标

    func testClientMessageIdFlag() throws {
        // 现网形态（部署包 1.5.0 待应用）：对象在、子旗
        // 标未发布 → unavailable（不是 unknown）
        let legacy = try capabilities(idempotencyBody: legacyBody)
        XCTAssertNil(legacy.clientMessageIdSupported)
        XCTAssertEqual(
            CapabilityNegotiation.clientMessageIdAvailability(legacy),
            .unavailable
        )
        // 子旗标发布后 → available
        let upgraded = try capabilities(
            idempotencyBody: withClientMessageIdBody
        )
        XCTAssertEqual(upgraded.clientMessageIdSupported, true)
        XCTAssertEqual(
            CapabilityNegotiation.clientMessageIdAvailability(upgraded),
            .available
        )
        // 能力面根本没取到 → unknown
        XCTAssertEqual(
            CapabilityNegotiation.clientMessageIdAvailability(nil),
            .unknown
        )
    }

    // MARK: - 整表

    func testVerdictsTableShapeAndAbsenceText() throws {
        let verdicts = CapabilityNegotiation.verdicts(
            capabilities: try capabilities(idempotencyBody: legacyBody),
            enrollmentProbe: RouteProbeResult(
                status: 404, errorCode: nil
            ),
            reactionsProbe: RouteProbeResult(
                status: 405, errorCode: nil
            )
        )
        XCTAssertEqual(
            verdicts.map(\.id),
            ["enrollment", "reactionsWrite", "runIdempotency",
             "optionsCard", "clientMessageId"]
        )
        let enrollment = CapabilityNegotiation.verdict(
            id: "enrollment", in: verdicts
        )
        XCTAssertEqual(enrollment?.availability, .unavailable)
        XCTAssertEqual(
            enrollment?.absenceText, "扫码配对不可用，退回手填连接信息"
        )
        let reactions = CapabilityNegotiation.verdict(
            id: "reactionsWrite", in: verdicts
        )
        XCTAssertEqual(reactions?.availability, .available)
        XCTAssertNil(reactions?.absenceText)
        // §441：选择框行——样本 features 无 options_
        // card 旗标＝未发布（unavailable＋缺席文案）
        let optionsCard = CapabilityNegotiation.verdict(
            id: "optionsCard", in: verdicts
        )
        XCTAssertEqual(optionsCard?.availability, .unavailable)
        XCTAssertEqual(
            optionsCard?.absenceText,
            "提问轮不带可点选选项，只能打字作答"
        )
        let clientMessageId = CapabilityNegotiation.verdict(
            id: "clientMessageId", in: verdicts
        )
        XCTAssertEqual(clientMessageId?.availability, .unavailable)
        XCTAssertNotNil(clientMessageId?.absenceText)
    }

    func testVerdictsAllUnknownWithoutEvidence() {
        let verdicts = CapabilityNegotiation.verdicts(
            capabilities: nil, enrollmentProbe: nil,
            reactionsProbe: nil
        )
        XCTAssertTrue(
            verdicts.allSatisfy { $0.availability == .unknown }
        )
        XCTAssertTrue(verdicts.allSatisfy { $0.absenceText == nil })
    }
}
