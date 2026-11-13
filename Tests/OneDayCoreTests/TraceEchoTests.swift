import XCTest
@testable import OneDayCore

/// 留痕回响闸（P0 App 侧＋P2 会话包，2026-11-13）：
/// DTO 解码对桥 _trace_view 原形钉死；呈现范围钉
/// （主线全量／旁聊只认指向自己／失败不被过滤）；
/// 文案钉（动作短句登记、失败原文原样、点达判据）。
final class TraceEchoTests: XCTestCase {

    private func trace(
        id: String = "trc_1",
        action: String = "sessions.create",
        targetID: String = "oneday-ai-abc",
        targetKind: String = "session",
        label: String = "调研竞品定价",
        at: Double = 1_000,
        status: String = "ok",
        result: String? = "已新开旁聊「调研竞品定价」并发出任务简报",
        error: String? = nil
    ) -> BridgeTrace {
        BridgeTrace(
            id: id, action: action, actor: "agent",
            target: BridgeTraceTarget(
                kind: targetKind, id: targetID, label: label,
                ref: "oneday://sessions/\(targetID)"),
            at: at, status: status, result: result, error: error
        )
    }

    // MARK: - DTO 解码（桥回原形）

    func testTraceDecodesBridgeViewVerbatim() throws {
        let json = """
        {"items": [{
            "id": "trc_9f8e7d6c5b4a",
            "action": "sessions.create",
            "actor": "agent",
            "target": {"kind": "session",
                       "id": "oneday-ai-0123456789abcdef",
                       "label": "调研竞品定价",
                       "ref": "oneday://sessions/oneday-ai-0123456789abcdef"},
            "at": 1763095200.5,
            "status": "ok",
            "result": "已新开旁聊「调研竞品定价」并发出任务简报",
            "error": null,
            "detail": {"via": "ai-sessions"}
        }, {
            "id": "trc_aaaa",
            "action": "sessions.create",
            "actor": "agent",
            "target": {"kind": "session", "id": "",
                       "label": "", "ref": "oneday://sessions"},
            "at": 1763095300.0,
            "status": "failed",
            "result": null,
            "error": "taskBrief 不能为空（新旁聊的首帖任务简报）",
            "detail": null
        }]}
        """
        let decoded = try JSONDecoder().decode(
            BridgeTracesResponse.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.items.count, 2)
        let ok = decoded.items[0]
        XCTAssertEqual(ok.id, "trc_9f8e7d6c5b4a")
        XCTAssertEqual(ok.target.kind, "session")
        XCTAssertEqual(ok.target.id, "oneday-ai-0123456789abcdef")
        XCTAssertEqual(ok.at, 1763095200.5)
        XCTAssertFalse(ok.isFailed)
        XCTAssertEqual(ok.date, Date(timeIntervalSince1970: 1763095200.5))
        let failed = decoded.items[1]
        XCTAssertTrue(failed.isFailed)
        XCTAssertEqual(failed.error, "taskBrief 不能为空（新旁聊的首帖任务简报）")
        XCTAssertNil(failed.result)
    }

    /// 宽容解码钉：target 缺失/字段漂移不许整表失败
    /// （留痕面宁可降级呈现、不许整批消失）
    func testTraceDecodesTolerantly() throws {
        let json = """
        {"items": [{"id": "trc_x", "action": "goals.create",
                    "at": 42.0, "status": "ok", "result": "好"}]}
        """
        let decoded = try JSONDecoder().decode(
            BridgeTracesResponse.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.items.count, 1)
        XCTAssertEqual(decoded.items[0].target.id, "")
        XCTAssertEqual(decoded.items[0].actor, "agent")
    }

    // MARK: - 呈现范围（TraceEchoPolicy）

    /// 主线＝总账面：全部留痕按时间正序（新在流尾）
    func testMainlineSeesAllChronological() {
        let older = trace(id: "trc_old", at: 100)
        let newer = trace(
            id: "trc_new", action: "goals.create",
            targetID: "g_1", targetKind: "goal", at: 200)
        let cards = TraceEchoPolicy.cards(
            traces: [newer, older], isMainThread: true,
            currentServerSessionID: "oneday-main-x")
        XCTAssertEqual(cards.map(\\.id), ["trc_old", "trc_new"])
    }

    /// 旁聊只出指向本会话的留痕（出生卡在此），别人
    /// 的动作不许串场
    func testSideChatSeesOnlyOwnTraces() {
        let own = trace(id: "trc_birth", targetID: "oneday-ai-abc")
        let other = trace(id: "trc_other", targetID: "oneday-ai-xyz")
        let goal = trace(
            id: "trc_goal", action: "goals.create",
            targetID: "g_1", targetKind: "goal")
        let cards = TraceEchoPolicy.cards(
            traces: [own, other, goal], isMainThread: false,
            currentServerSessionID: "oneday-ai-abc")
        XCTAssertEqual(cards.map(\\.id), ["trc_birth"])
    }

    /// 无会话上下文（本地线程未关联服务端）一律不出卡
    func testNoSessionContextNoCards() {
        let cards = TraceEchoPolicy.cards(
            traces: [trace()], isMainThread: false,
            currentServerSessionID: nil)
        XCTAssertTrue(cards.isEmpty)
    }

    /// 失败与成功同级：failed 记录在主线与旁聊都不被
    /// 过滤（P0 契约——失败不许静默）
    func testFailedTracesAreNeverFiltered() {
        let boom = trace(
            id: "trc_boom", status: "failed", result: nil,
            error: "在 Hermes 建会话失败（HTTP 500）")
        let main = TraceEchoPolicy.cards(
            traces: [boom], isMainThread: true,
            currentServerSessionID: nil)
        XCTAssertEqual(main.map(\\.id), ["trc_boom"])
        let side = TraceEchoPolicy.cards(
            traces: [boom], isMainThread: false,
            currentServerSessionID: "oneday-ai-abc")
        XCTAssertEqual(side.map(\\.id), ["trc_boom"])
    }

    /// 上限钉：超出 limit 只留最近的（流尾最新）
    func testLimitKeepsMostRecent() {
        let many = (0..<15).map {
            trace(id: "trc_\($0)", at: Double($0))
        }
        let cards = TraceEchoPolicy.cards(
            traces: many, isMainThread: true,
            currentServerSessionID: nil, limit: 10)
        XCTAssertEqual(cards.count, 10)
        XCTAssertEqual(cards.first?.id, "trc_5")
        XCTAssertEqual(cards.last?.id, "trc_14")
    }

    // MARK: - 文案（TraceEchoCopy）

    func testHeadlineUsesRegisteredPhrase() {
        XCTAssertEqual(
            TraceEchoCopy.headline(trace: trace(), agentName: "三狗"),
            "三狗 新开了一个旁聊")
        XCTAssertEqual(
            TraceEchoCopy.headline(
                trace: trace(action: "goals.add_entry"),
                agentName: "三狗"),
            "三狗 给目标写了一条进展")
    }

    /// 未登记动作不许静默：回落中性句式，卡照样出
    func testUnknownActionFallsBackNotSilent() {
        XCTAssertEqual(
            TraceEchoCopy.actionPhrase("automation.cron_create"),
            "做了一件事")
    }

    /// 结果行：成功取 result、失败取 error 原文整句
    func testOutcomeLineIsVerbatim() {
        XCTAssertEqual(
            TraceEchoCopy.outcomeLine(trace()),
            "已新开旁聊「调研竞品定价」并发出任务简报")
        let failedTrace = trace(
            status: "failed", result: nil,
            error: "Hermes 改派了会话 id（api_x），出生证明会失效，已拒绝采用")
        XCTAssertEqual(
            TraceEchoCopy.outcomeLine(failedTrace),
            "Hermes 改派了会话 id（api_x），出生证明会失效，已拒绝采用")
    }

    /// 点达判据：仅 session 类且 id 非空；目标类与
    /// 无 id 的失败痕只呈现不导航
    func testOpenableSessionIDGate() {
        XCTAssertEqual(
            TraceEchoCopy.openableSessionID(trace()),
            "oneday-ai-abc")
        XCTAssertNil(TraceEchoCopy.openableSessionID(
            trace(targetID: "g_1", targetKind: "goal")))
        XCTAssertNil(TraceEchoCopy.openableSessionID(
            trace(targetID: "")))
    }
}
