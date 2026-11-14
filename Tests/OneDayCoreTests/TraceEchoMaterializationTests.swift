import XCTest
@testable import OneDayCore

/// 回响物化规划（§217）：留痕→真条目的规划闸——
/// 去重（按线程 existingKeys）／窗口（最近 10）／
/// 作用域（主线全量、旁聊只认指向自己）／落位时
/// 刻钉死事件时间／失败原文入快照／无时刻不规划
/// ／快照编解码与点达判据。
final class TraceEchoMaterializationTests: XCTestCase {

    private func trace(
        id: String = "trc_1",
        action: String = "sessions.create",
        targetID: String = "oneday-ai-abc",
        targetKind: String = "session",
        label: String = "关于结婚的事情",
        at: Double = 1_000,
        status: String = "ok",
        result: String? = "已新开旁聊「关于结婚的事情」并发出任务简报",
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

    private func plan(
        _ traces: [BridgeTrace],
        isMainThread: Bool = true,
        sessionID: String? = nil,
        existing: Set<String> = []
    ) -> [TraceEchoMaterialization.Planned] {
        TraceEchoMaterialization.plan(
            traces: traces,
            isMainThread: isMainThread,
            currentServerSessionID: sessionID,
            existingKeys: existing,
            agentName: "三狗"
        )
    }

    // MARK: - 落位时刻与去重键

    /// 落位时刻钉死事件时间：昨天的留痕规划出的条
    /// 目时刻就是昨天——今天的新消息（createdAt 更
    /// 晚）经 sortedEntries 必然排在它后面，不再出
    /// 现「昨天的卡挂在今天消息下面」
    func testPlanCreatedAtIsEventTime() {
        let yesterday = 1_763_000_000.0
        let planned = plan([trace(at: yesterday)])
        XCTAssertEqual(planned.count, 1)
        XCTAssertEqual(
            planned[0].createdAt,
            Date(timeIntervalSince1970: yesterday)
        )
        let todaysMessage = Date(timeIntervalSince1970: yesterday + 3600)
        XCTAssertLessThan(planned[0].createdAt, todaysMessage)
    }

    func testPlanKeyIsNamespacedTraceID() {
        let planned = plan([trace(id: "trc_9f8e")])
        XCTAssertEqual(planned.map(\.key), ["trace:trc_9f8e"])
        XCTAssertEqual(
            TraceEchoMaterialization.key(traceID: "trc_9f8e"),
            "trace:trc_9f8e"
        )
    }

    /// 多条按时间正序规划（调用方按序落盘即时间序）
    func testPlanReturnsChronologicalOrder() {
        let planned = plan([
            trace(id: "trc_b", at: 2_000),
            trace(id: "trc_a", at: 1_000),
        ])
        XCTAssertEqual(
            planned.map(\.key), ["trace:trc_a", "trace:trc_b"]
        )
    }

    // MARK: - 去重（已物化不重出）

    func testPlanSkipsExistingKeys() {
        let traces = [trace(id: "trc_1"), trace(id: "trc_2", at: 2_000)]
        let planned = plan(traces, existing: ["trace:trc_1"])
        XCTAssertEqual(planned.map(\.key), ["trace:trc_2"])
    }

    /// 全部已落盘时规划为空——二次刷新不产生重复条目
    func testPlanEmptyWhenAllMaterialized() {
        let traces = [trace(id: "trc_1")]
        let first = plan(traces)
        XCTAssertEqual(first.count, 1)
        let second = plan(traces, existing: Set(first.map(\.key)))
        XCTAssertTrue(second.isEmpty)
    }

    /// 入参自带重复 id（桥回重叠）也只规划一条
    func testPlanDedupesWithinInput() {
        let planned = plan([trace(id: "trc_1"), trace(id: "trc_1")])
        XCTAssertEqual(planned.count, 1)
    }

    // MARK: - 窗口（defaultLimit 改义为物化窗口）

    /// 超过窗口只规划最近 10 条，窗口外的旧留痕不
    /// 追补（与旧呈现「只见最近 10 条」等价）
    func testPlanWindowKeepsMostRecentTen() {
        let traces = (1...15).map {
            trace(id: "trc_\($0)", at: Double($0) * 100)
        }
        let planned = plan(traces)
        XCTAssertEqual(planned.count, 10)
        XCTAssertEqual(planned.first?.key, "trace:trc_6")
        XCTAssertEqual(planned.last?.key, "trace:trc_15")
    }

    // MARK: - 作用域

    /// 主线全量：指向任何会话的留痕都规划
    func testPlanMainThreadTakesAll() {
        let planned = plan([
            trace(id: "trc_1", targetID: "s-1"),
            trace(id: "trc_2", targetID: "s-2", at: 2_000),
        ])
        XCTAssertEqual(planned.count, 2)
    }

    /// 旁聊只认指向本会话的留痕
    func testPlanSideThreadOnlyOwnTargets() {
        let planned = plan(
            [
                trace(id: "trc_1", targetID: "s-1"),
                trace(id: "trc_2", targetID: "s-2", at: 2_000),
            ],
            isMainThread: false, sessionID: "s-2"
        )
        XCTAssertEqual(planned.map(\.key), ["trace:trc_2"])
    }

    /// 旁聊无会话 id 时不规划（无从判作用域）
    func testPlanSideThreadWithoutSessionIDIsEmpty() {
        let planned = plan(
            [trace()], isMainThread: false, sessionID: nil
        )
        XCTAssertTrue(planned.isEmpty)
    }

    // MARK: - 无时刻不规划

    /// at≤0＝没有事件时间、没有位置可归，不许猜
    func testPlanSkipsTimelessTraces() {
        let planned = plan([
            trace(id: "trc_zero", at: 0),
            trace(id: "trc_neg", at: -5),
            trace(id: "trc_ok", at: 10),
        ])
        XCTAssertEqual(planned.map(\.key), ["trace:trc_ok"])
    }

    // MARK: - 快照（失败同级、原文照上）

    /// 失败留痕照样入规划，快照存失败原文整串
    func testPlanFailedTraceKeepsErrorVerbatim() {
        let errorText = "taskBrief 不能为空（新旁聊的首帖任务简报）"
        let planned = plan([trace(
            status: "failed", result: nil, error: errorText
        )])
        XCTAssertEqual(planned.count, 1)
        XCTAssertTrue(planned[0].snapshot.isFailed)
        XCTAssertEqual(planned[0].snapshot.outcome, errorText)
    }

    func testPlanSuccessSnapshotCarriesResult() {
        let planned = plan([trace()])
        XCTAssertFalse(planned[0].snapshot.isFailed)
        XCTAssertEqual(
            planned[0].snapshot.outcome,
            "已新开旁聊「关于结婚的事情」并发出任务简报"
        )
        XCTAssertEqual(planned[0].snapshot.targetLabel, "关于结婚的事情")
    }

    /// 主句经 Copy 登记表单源成句；未登记动作回落
    /// 中性句、实情仍在结果行（不因缺登记而消失）
    func testSnapshotHeadlineUsesCopyRegistry() {
        let known = plan([trace()])
        XCTAssertEqual(known[0].snapshot.headline, "三狗 新开了一个旁聊")
        let unknown = plan([trace(action: "automation.run")])
        XCTAssertEqual(unknown[0].snapshot.headline, "三狗 做了一件事")
        XCTAssertEqual(
            unknown[0].snapshot.outcome,
            "已新开旁聊「关于结婚的事情」并发出任务简报"
        )
    }

    // MARK: - 点达判据与编解码

    /// 点达只给会话类且 id 非空的目标
    func testSnapshotOpenableOnlyForSessionTargets() {
        let session = plan([trace()])
        XCTAssertEqual(
            session[0].snapshot.openableSessionID, "oneday-ai-abc"
        )
        let goal = plan([trace(targetKind: "goal", targetID: "g-1")])
        XCTAssertNil(goal[0].snapshot.openableSessionID)
        let empty = plan([trace(targetID: "")])
        XCTAssertNil(empty[0].snapshot.openableSessionID)
    }

    /// 快照 Codable 往返无损（落盘 traceEchoData 的
    /// 编解码口径）
    func testSnapshotCodableRoundTrip() throws {
        let planned = plan([trace(
            status: "failed", result: nil, error: "网关 502"
        )])
        let snapshot = planned[0].snapshot
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(
            TraceEchoSnapshot.self, from: data
        )
        XCTAssertEqual(decoded, snapshot)
    }
}
