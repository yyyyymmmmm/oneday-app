import XCTest
@testable import OneDayCore

/// 0.31.0（DESIGN-V4 §58）：/v1/runs 任务制生成的
/// 客户端契约钉死——状态机全转移（提交三路/流断＝
/// 未知/对账收敛/真取消/落定三态）、事件解析（形态
/// 以阶段 A 探针实测为准）、DTO 解码、幂等输入编码、
/// 持久账本、transcript 段落定（锚点/失败段/hidden
/// 排除/思考回填）。
final class RunTurnTests: XCTestCase {

    // MARK: - 状态机：提交三路

    func testAcceptedGoesGenerating() {
        var machine = RunTurnStateMachine()
        XCTAssertEqual(machine.phase, .submitting)
        machine.apply(.submitAccepted)
        XCTAssertEqual(machine.phase, .generating)
        XCTAssertFalse(machine.isSettled)
    }

    func testRejectedIsTerminalFailure() {
        var machine = RunTurnStateMachine()
        machine.apply(.submitRejected)
        XCTAssertEqual(machine.phase, .failed)
        XCTAssertTrue(machine.isSettled)
    }

    func testAmbiguousGoesUnknownNotFailure() {
        // 提交回执丢失：结果未知，绝不定性为失败——
        // 这是本版废除「断线＝网络错误」的核心转移
        var machine = RunTurnStateMachine()
        machine.apply(.submitAmbiguous)
        XCTAssertEqual(machine.phase, .unknown)
        XCTAssertFalse(machine.isSettled)
    }

    // MARK: - 状态机：流断与对账

    func testStreamLostFromGeneratingGoesUnknown() {
        var machine = RunTurnStateMachine()
        machine.apply(.submitAccepted)
        machine.apply(.streamLost)
        XCTAssertEqual(machine.phase, .unknown)
    }

    func testStreamLostIgnoredOutsideGenerating() {
        var machine = RunTurnStateMachine()
        machine.apply(.streamLost)
        XCTAssertEqual(machine.phase, .submitting)
    }

    func testUnknownForegroundedGoesReconciling() {
        var machine = RunTurnStateMachine()
        machine.apply(.submitAmbiguous)
        machine.apply(.foregrounded)
        XCTAssertEqual(machine.phase, .reconciling)
    }

    func testStatusRunningReturnsToGenerating() {
        var machine = RunTurnStateMachine()
        machine.apply(.submitAmbiguous)
        machine.apply(.foregrounded)
        machine.apply(.statusRunning)
        XCTAssertEqual(machine.phase, .generating)
    }

    func testStatusMissingStaysReconciling() {
        var machine = RunTurnStateMachine()
        machine.apply(.submitAmbiguous)
        machine.apply(.foregrounded)
        machine.apply(.statusMissing)
        XCTAssertEqual(machine.phase, .reconciling)
        XCTAssertNil(machine.terminalKind)
    }

    func testTranscriptPendingStaysReconciling() {
        var machine = RunTurnStateMachine()
        machine.apply(.submitAccepted)
        machine.apply(.streamLost)
        machine.apply(.foregrounded)
        machine.apply(.transcriptPending)
        XCTAssertEqual(machine.phase, .reconciling)
    }

    func testSettleExhaustedStaysUnknown() {
        // 预算耗尽只是停手：相位回未知、账本保留，
        // 下次进线程续对账——不许落成失败
        var machine = RunTurnStateMachine()
        machine.apply(.submitAccepted)
        machine.apply(.streamLost)
        machine.apply(.foregrounded)
        machine.apply(.settleExhausted)
        XCTAssertEqual(machine.phase, .unknown)
        XCTAssertFalse(machine.isSettled)
    }

    // MARK: - 状态机：终态与落定三态

    func testCompletedThenSettledIsFinished() {
        var machine = RunTurnStateMachine()
        machine.apply(.submitAccepted)
        machine.apply(.statusTerminal(.completed))
        XCTAssertEqual(machine.phase, .reconciling)
        XCTAssertEqual(machine.terminalKind, .completed)
        machine.apply(.transcriptSettled)
        XCTAssertEqual(machine.phase, .finished)
        XCTAssertTrue(machine.isSettled)
    }

    func testFailedThenSettledIsFailed() {
        var machine = RunTurnStateMachine()
        machine.apply(.submitAccepted)
        machine.apply(.statusTerminal(.failed))
        machine.apply(.transcriptSettled)
        XCTAssertEqual(machine.phase, .failed)
    }

    func testCancelledThenSettledIsCancelled() {
        var machine = RunTurnStateMachine()
        machine.apply(.submitAccepted)
        machine.apply(.stopRequested)
        machine.apply(.statusTerminal(.cancelled))
        machine.apply(.transcriptSettled)
        XCTAssertEqual(machine.phase, .cancelled)
    }

    func testInterruptedTerminalSettlesAsCancelled() {
        // 服务端 interrupted（网关重启类中断终态）：
        // 状态机归 cancelled 相位——transcript 内容照
        // 常落定呈现，只是不走「完成」收尾
        var machine = RunTurnStateMachine()
        machine.apply(.submitAccepted)
        machine.apply(.statusTerminal(.interrupted))
        machine.apply(.transcriptSettled)
        XCTAssertEqual(machine.phase, .cancelled)
    }

    func testSettledIgnoresLateEvents() {
        var machine = RunTurnStateMachine()
        machine.apply(.submitAccepted)
        machine.apply(.statusTerminal(.completed))
        machine.apply(.transcriptSettled)
        machine.apply(.streamLost)
        machine.apply(.statusTerminal(.failed))
        machine.apply(.stopRequested)
        XCTAssertEqual(machine.phase, .finished)
        XCTAssertEqual(machine.terminalKind, .completed)
    }

    func testStopFromSubmittingRecordsIntentThenStops() {
        // 提交窗口内还没有 run 可停：先记意图，相位留
        // submitting；受理落地后直接进 stopping
        var machine = RunTurnStateMachine()
        machine.apply(.stopRequested)
        XCTAssertTrue(machine.stopRequested)
        XCTAssertEqual(machine.phase, .submitting)
        machine.apply(.submitAccepted)
        if case .generating(stopping: true) = machine.phase {
        } else {
            XCTFail("受理后应进 generating(stopping:true)，实际 \(machine.phase)")
        }
    }

    func testStopFromGeneratingMarksStopping() {
        var machine = RunTurnStateMachine()
        machine.apply(.submitAccepted)
        machine.apply(.stopRequested)
        if case .generating(stopping: true) = machine.phase {
        } else {
            XCTFail("生成中停止应标记 stopping，实际 \(machine.phase)")
        }
    }

    func testStopDuringReconcileKeepsReconciling() {
        var machine = RunTurnStateMachine()
        machine.apply(.submitAmbiguous)
        machine.apply(.foregrounded)
        machine.apply(.stopRequested)
        XCTAssertEqual(machine.phase, .reconciling)
        XCTAssertTrue(machine.stopRequested)
    }

    // MARK: - 状态词表

    func testStatusKindClassification() {
        XCTAssertTrue(RunStatusKind.queued.isActive)
        XCTAssertTrue(RunStatusKind.running.isActive)
        XCTAssertTrue(RunStatusKind.waitingForApproval.isActive)
        XCTAssertTrue(RunStatusKind.stopping.isActive)
        XCTAssertTrue(RunStatusKind.completed.isTerminal)
        XCTAssertTrue(RunStatusKind.failed.isTerminal)
        XCTAssertTrue(RunStatusKind.cancelled.isTerminal)
        XCTAssertTrue(RunStatusKind.interrupted.isTerminal)
        XCTAssertFalse(RunStatusKind.unknown.isTerminal)
        XCTAssertFalse(RunStatusKind.unknown.isActive)
    }

    // MARK: - DTO 解码

    func testSubmitResponseDecoding() throws {
        let json = #"{"run_id":"run_abc","status":"started","replayed":true}"#
        let response = try JSONDecoder().decode(
            RunSubmitResponse.self, from: Data(json.utf8)
        )
        XCTAssertEqual(response.runID, "run_abc")
        XCTAssertEqual(response.replayed, true)
    }

    func testStatusResponseDecoding() throws {
        let json = #"{"run_id":"run_abc","status":"waiting_for_approval","output":null,"error":"oops","usage":{"x":1}}"#
        let response = try JSONDecoder().decode(
            RunStatusResponse.self, from: Data(json.utf8)
        )
        XCTAssertEqual(response.status, .waitingForApproval)
        XCTAssertNil(response.output)
        XCTAssertEqual(response.error, "oops")
    }

    func testStatusResponseMissingFields() throws {
        let json = #"{"run_id":"run_abc","status":"completed"}"#
        let response = try JSONDecoder().decode(
            RunStatusResponse.self, from: Data(json.utf8)
        )
        XCTAssertEqual(response.status, .completed)
        XCTAssertNil(response.output)
        XCTAssertNil(response.error)
    }

    // MARK: - 事件解析（探针实测帧形态：data: 行＋
    // event 键，seq 在 JSON 内）

    private func parse(_ line: String) -> RunEventEnvelope? {
        var parser = RunEventParser()
        return parser.consume(line: line)
    }

    func testParseMessageDelta() {
        let envelope = parse(
            #"data: {"event":"message.delta","run_id":"r","seq":3,"delta":"你好"}"#
        )
        XCTAssertEqual(envelope?.seq, 3)
        XCTAssertEqual(envelope?.event, .contentDelta("你好"))
    }

    func testParseInterim() {
        let envelope = parse(
            #"data: {"event":"message.interim","text":"阶段稿"}"#
        )
        XCTAssertEqual(envelope?.event, .interim("阶段稿"))
    }

    func testParseToolStartedAndCompleted() {
        let started = parse(
            #"data: {"event":"tool.started","tool":"terminal","preview":"sleep 30","tool_call_id":"tc1"}"#
        )
        XCTAssertEqual(
            started?.event,
            .toolStarted(id: "tc1", name: "terminal", preview: "sleep 30")
        )
        let completed = parse(
            #"data: {"event":"tool.completed","tool":"terminal","error":true,"tool_call_id":"tc1","preview":"boom"}"#
        )
        XCTAssertEqual(
            completed?.event,
            .toolCompleted(
                id: "tc1", name: "terminal", preview: "boom",
                failed: true
            )
        )
    }

    func testParseRunCompletedTerminal() {
        let envelope = parse(
            #"data: {"event":"run.completed","seq":9,"output":"最终答复"}"#
        )
        XCTAssertEqual(envelope?.seq, 9)
        XCTAssertEqual(
            envelope?.event,
            .terminal(kind: .completed, output: "最终答复")
        )
    }

    func testParseRunFailedTerminal() {
        let envelope = parse(
            #"data: {"event":"run.failed","output":"上游 503"}"#
        )
        XCTAssertEqual(
            envelope?.event,
            .terminal(kind: .failed, output: "上游 503")
        )
    }

    func testParseIgnoresNoise() {
        XCTAssertNil(parse(""))
        XCTAssertNil(parse(": ping"))
        XCTAssertNil(parse("event: message.delta"))
        XCTAssertNil(parse("data: {not json"))
        XCTAssertNil(parse("data: [DONE]"))
        let unknown = parse(
            #"data: {"event":"run.queued"}"#
        )
        XCTAssertEqual(unknown?.event, .other(name: "run.queued"))
    }

    // MARK: - 输入编码（探针契约）

    func testTextInputEncodesAsString() throws {
        let value = try RunInput.text("你好").encodedValue()
        XCTAssertEqual(value as? String, "你好")
    }

    func testMessageInputEncodesAsArray() throws {
        let message = ChatMessage(
            role: "user", text: "这是什么颜色",
            imageDataURLs: ["data:image/png;base64,AAAA"]
        )
        let value = try RunInput.message(message)
            .encodedValue()
        let array = try XCTUnwrap(value as? [[String: Any]])
        XCTAssertEqual(array.count, 1)
        XCTAssertEqual(array.first?["role"] as? String, "user")
    }

    // MARK: - 账本

    private func entry(
        thread: String, runID: String? = "run-1"
    ) -> RunLedgerEntry {
        RunLedgerEntry(
            threadID: thread, sessionID: "oneday-side-x",
            runID: runID, idempotencyKey: "key-1",
            userEntryID: "entry-1",
            submittedAt: Date(timeIntervalSince1970: 1000)
        )
    }

    func testLedgerUpsertReplacesSameThread() {
        var entries: [RunLedgerEntry] = []
        entries = RunLedger.upsert(
            entries, entry(thread: "t1", runID: nil)
        )
        entries = RunLedger.upsert(
            entries, entry(thread: "t1", runID: "run-9")
        )
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(
            RunLedger.entry(forThreadID: "t1", in: entries)?.runID,
            "run-9"
        )
    }

    func testLedgerKeepsThreadsSeparateAndRemoves() {
        var entries: [RunLedgerEntry] = []
        entries = RunLedger.upsert(entries, entry(thread: "t1"))
        entries = RunLedger.upsert(entries, entry(thread: "t2"))
        XCTAssertEqual(entries.count, 2)
        entries = RunLedger.removing(
            threadID: "t1", from: entries
        )
        XCTAssertNil(
            RunLedger.entry(forThreadID: "t1", in: entries)
        )
        XCTAssertNotNil(
            RunLedger.entry(forThreadID: "t2", in: entries)
        )
    }

    func testLedgerEntryCodableRoundTrip() throws {
        let original = entry(thread: "t1")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(
            RunLedgerEntry.self, from: data
        )
        XCTAssertEqual(decoded, original)
    }

    // MARK: - transcript 段落定

    private func message(
        role: String, content: String?,
        reasoningContent: String? = nil,
        toolName: String? = nil,
        toolCallID: String? = nil,
        toolCalls: [SessionToolCall] = [],
        displayKind: String? = nil
    ) -> SessionMessage {
        SessionMessage(
            id: 0, role: role, content: content ?? "",
            toolCalls: toolCalls, toolCallID: toolCallID,
            toolName: toolName,
            reasoningContent: reasoningContent,
            displayKind: displayKind
        )
    }

    func testSettleNoUserRowNotFound() {
        let settled = RunTranscriptSettle.settle(messages: [
            message(role: "assistant", content: "旧答复")
        ])
        XCTAssertFalse(settled.found)
    }

    func testSettlePlainTextTurn() {
        let settled = RunTranscriptSettle.settle(messages: [
            message(role: "user", content: "旧问题"),
            message(role: "assistant", content: "旧答复"),
            message(role: "user", content: "新问题"),
            message(
                role: "assistant", content: "新答复",
                reasoningContent: "想了想"
            )
        ])
        XCTAssertTrue(settled.found)
        XCTAssertEqual(settled.finalText, "新答复")
        XCTAssertEqual(settled.reasoning, "想了想")
        XCTAssertTrue(settled.toolCards.isEmpty)
        XCTAssertFalse(settled.failed)
    }

    func testSettleWaitsWhileTurnIncomplete() {
        // user 行已落、assistant 未 flush：段未落定，
        // 对账继续等而不是拿空段收尾
        let settled = RunTranscriptSettle.settle(messages: [
            message(role: "user", content: "问题")
        ])
        XCTAssertFalse(settled.found)
    }

    func testSettleToolTurnBuildsCardsAndJoinsText() {
        let settled = RunTranscriptSettle.settle(messages: [
            message(role: "user", content: "查一下"),
            message(
                role: "assistant", content: nil,
                reasoningContent: "先查",
                toolCalls: [
                    SessionToolCall(
                        id: "tc1", name: "terminal",
                        arguments: "{}"
                    )
                ]
            ),
            message(
                role: "tool", content: "结果原文",
                toolName: "terminal", toolCallID: "tc1"
            ),
            message(role: "assistant", content: "查完了")
        ])
        XCTAssertTrue(settled.found)
        XCTAssertEqual(settled.toolCards.count, 1)
        XCTAssertEqual(settled.finalText, "查完了")
        XCTAssertEqual(settled.reasoning, "先查")
    }

    func testSettleFailedTurnRow() {
        let settled = RunTranscriptSettle.settle(messages: [
            message(role: "user", content: "问题"),
            message(
                role: "assistant", content: "HTTP 503 上游挂了",
                displayKind: "failed_turn"
            )
        ])
        XCTAssertTrue(settled.found)
        XCTAssertTrue(settled.failed)
        XCTAssertEqual(settled.failureText, "HTTP 503 上游挂了")
        XCTAssertNil(settled.finalText)
    }

    func testSettleExcludesHiddenRows() {
        let settled = RunTranscriptSettle.settle(messages: [
            message(role: "user", content: "sleep"),
            message(
                role: "assistant", content: nil,
                toolCalls: [
                    SessionToolCall(
                        id: "tc1", name: "terminal",
                        arguments: "{}"
                    )
                ]
            ),
            message(
                role: "tool", content: "[Command interrupted]",
                toolName: "terminal", toolCallID: "tc1"
            ),
            message(
                role: "assistant", content: "不许出现",
                displayKind: "hidden"
            )
        ])
        XCTAssertTrue(settled.found)
        XCTAssertNil(settled.finalText)
    }

    func testSettleJoinsMultiPartAssistantText() {
        let settled = RunTranscriptSettle.settle(messages: [
            message(role: "user", content: "写长文"),
            message(role: "assistant", content: "第一段"),
            message(role: "assistant", content: "第二段")
        ])
        XCTAssertTrue(settled.found)
        XCTAssertEqual(settled.finalText, "第一段\n\n第二段")
    }
}
