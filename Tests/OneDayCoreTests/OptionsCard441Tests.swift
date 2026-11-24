import OneDayCore
import XCTest

/// 选择框钉测（总表 203，DESIGN §441）：载荷解码
/// 宽容口径、播种尾位规则、状态派生矩阵、覆盖层
/// 语义、能力判定——协议面逐项钉，坏载荷不许打
/// 死整页解码、旧卡不许在新消息后复活
final class OptionsCard441Tests: XCTestCase {

    // MARK: - 载荷解码

    private func decodeMessage(_ json: String) throws -> SessionMessage {
        try JSONDecoder().decode(
            SessionMessage.self, from: Data(json.utf8)
        )
    }

    func testDecodeFullPayload() throws {
        let message = try decodeMessage("""
        {"id": 42, "role": "assistant", "content": "选一条路",
         "options": {"v": 1, "at": 1700000000.0, "options": [
            {"label": "方案 A", "send_text": "按方案 A 走"},
            {"label": "方案 B"}
         ]}}
        """)
        let options = try XCTUnwrap(message.options)
        XCTAssertEqual(options.options.count, 2)
        XCTAssertEqual(options.options[0].label, "方案 A")
        XCTAssertEqual(options.options[0].sendText, "按方案 A 走")
        // send_text 缺省＝label（服务端校验单源同口径）
        XCTAssertEqual(options.options[1].sendText, "方案 B")
        XCTAssertEqual(options.v, 1)
    }

    func testDecodeMissingKeyIsNil() throws {
        let message = try decodeMessage(
            #"{"id": 1, "role": "assistant", "content": "hi"}"#
        )
        XCTAssertNil(message.options)
    }

    func testDecodeBadShapeIsNilNotFatal() throws {
        // options 非对象 / 项全坏：整页解码照常、载荷判 nil
        let notObject = try decodeMessage("""
        {"id": 2, "role": "assistant", "content": "hi",
         "options": [1, 2, 3]}
        """)
        XCTAssertNil(notObject.options)
        let emptyItems = try decodeMessage("""
        {"id": 3, "role": "assistant", "content": "hi",
         "options": {"options": [{"label": "  "}, {"nope": 1}]}}
        """)
        XCTAssertNil(emptyItems.options)
    }

    // MARK: - 播种尾位规则

    private func message(
        _ id: Double, _ role: String, options: Bool = false
    ) -> SessionMessage {
        SessionMessage(
            id: id, role: role, content: "x",
            options: options
                ? MessageOptions(options: [
                    MessageOption(label: "A", sendText: "A"),
                    MessageOption(label: "B", sendText: "B"),
                ])
                : nil
        )
    }

    func testSeedCandidateTailAssistant() {
        let candidate = OptionsCardLogic.seedCandidate(in: [
            message(1, "user"), message(2, "assistant", options: true),
        ])
        XCTAssertEqual(candidate?.serverRowID, 2)
        XCTAssertEqual(candidate?.options.options.count, 2)
    }

    func testSeedCandidateUserAfterBlocks() {
        XCTAssertNil(OptionsCardLogic.seedCandidate(in: [
            message(1, "assistant", options: true), message(2, "user"),
        ]))
    }

    func testSeedCandidateOnlyLastAssistantCounts() {
        // 旧轮带卡、新轮无卡：尾位是新轮，不播种旧卡
        XCTAssertNil(OptionsCardLogic.seedCandidate(in: [
            message(1, "assistant", options: true),
            message(2, "user"), message(3, "assistant"),
        ]))
    }

    // MARK: - 状态派生矩阵

    private func card(
        selected: String? = nil
    ) -> OptionsCardOverlay.Card {
        .init(
            serverRowID: 2,
            options: MessageOptions(options: [
                MessageOption(label: "A", sendText: "A"),
                MessageOption(label: "B", sendText: "B"),
            ]),
            selectedLabel: selected
        )
    }

    func testStateMatrix() {
        let live = OptionsCardLogic.state(
            card: card(), isTailAssistant: true,
            hasUserAfter: false, runInFlight: false, isDemo: false
        )
        XCTAssertEqual(live, .live)
        // 已选优先于过期判定（回执行常驻本会话）
        XCTAssertEqual(
            OptionsCardLogic.state(
                card: card(selected: "A"), isTailAssistant: false,
                hasUserAfter: true, runInFlight: false, isDemo: false
            ),
            .selected("A")
        )
        // 新消息后旧卡过期
        XCTAssertEqual(
            OptionsCardLogic.state(
                card: card(), isTailAssistant: true,
                hasUserAfter: true, runInFlight: false, isDemo: false
            ),
            .expired
        )
        // 在飞轮期间不可点
        XCTAssertEqual(
            OptionsCardLogic.state(
                card: card(), isTailAssistant: true,
                hasUserAfter: false, runInFlight: true, isDemo: false
            ),
            .expired
        )
        // 演示态与无卡恒 hidden
        XCTAssertEqual(
            OptionsCardLogic.state(
                card: card(), isTailAssistant: true,
                hasUserAfter: false, runInFlight: false, isDemo: true
            ),
            .hidden
        )
        XCTAssertEqual(
            OptionsCardLogic.state(
                card: nil, isTailAssistant: true,
                hasUserAfter: false, runInFlight: false, isDemo: false
            ),
            .hidden
        )
    }

    // MARK: - 覆盖层语义

    @MainActor
    func testOverlaySeedAndSelect() {
        let overlay = OptionsCardOverlay()
        let thread = UUID()
        overlay.seed(threadID: thread, card: card())
        XCTAssertEqual(overlay.card(for: thread)?.serverRowID, 2)
        // 旧行迟到不许覆盖新卡
        overlay.seed(
            threadID: thread,
            card: .init(serverRowID: 1, options: card().options)
        )
        XCTAssertEqual(overlay.card(for: thread)?.serverRowID, 2)
        overlay.markSelected(threadID: thread, label: "A")
        XCTAssertEqual(
            overlay.card(for: thread)?.selectedLabel, "A"
        )
    }

    // MARK: - 能力判定

    func testOptionsCardAvailability() throws {
        let withFlag = try JSONDecoder().decode(
            CapabilitiesResponse.self,
            from: Data(#"""
            {"object": "hermes.api_server.capabilities",
             "features": {"options_card": true}, "endpoints": {}}
            """#.utf8)
        )
        XCTAssertEqual(
            CapabilityNegotiation.optionsCardAvailability(withFlag),
            .available
        )
        let withoutFlag = try JSONDecoder().decode(
            CapabilitiesResponse.self,
            from: Data(#"""
            {"object": "hermes.api_server.capabilities",
             "features": {}, "endpoints": {}}
            """#.utf8)
        )
        XCTAssertEqual(
            CapabilityNegotiation.optionsCardAvailability(withoutFlag),
            .unavailable
        )
        XCTAssertEqual(
            CapabilityNegotiation.optionsCardAvailability(nil),
            .unknown
        )
    }

    // MARK: - 行高输入

    func testHeightInputMapping() {
        XCTAssertEqual(
            OptionsCardHeightInput(state: .live, optionCount: 3)?.kind,
            .live
        )
        XCTAssertEqual(
            OptionsCardHeightInput(
                state: .selected("A"), optionCount: 3
            )?.kind,
            .selected
        )
        XCTAssertNil(
            OptionsCardHeightInput(state: .hidden, optionCount: 3)
        )
    }
}
