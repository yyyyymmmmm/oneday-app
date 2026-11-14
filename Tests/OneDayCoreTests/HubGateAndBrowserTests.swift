import OneDayCore
import XCTest

/// write-gate 契约解码＋审核段状态机＋computer-use 宽容
/// 提取（桥方案 §3／数据设计 §5、§6）：核心红线是诚实
/// 三态——裸空列表不许冒充「无待批」，未知不许压成
/// 未就绪，未知子系统不许开放裁决。
final class HubGateAndBrowserTests: XCTestCase {
    private let decoder = JSONDecoder()

    func testGateStatusDecode() throws {
        let status = try decoder.decode(WriteGateStatus.self, from: Data("""
        {"supported": true, "gate": {"memory": true, "skills": false},
         "counts": {"memory": 2, "skills": 0}}
        """.utf8))
        XCTAssertTrue(status.supported)
        XCTAssertTrue(status.memoryGateEnabled)
        XCTAssertFalse(status.skillsGateEnabled)
        XCTAssertEqual(status.totalCount, 2)
    }

    func testRecordDecodeAndFallbackSummary() throws {
        let record = try decoder.decode(WriteGateRecord.self, from: Data("""
        {"id": "abc", "subsystem": "skills", "action": "edit",
         "summary": "", "origin": "background_review",
         "created_at": "2026-11-09T02:00:00Z"}
        """.utf8))
        XCTAssertEqual(record.subsystem, .skills)
        XCTAssertEqual(record.displaySummary(locale: Locale(identifier: "zh-Hans")), "修改一个技能")
        XCTAssertEqual(record.originLabel(locale: Locale(identifier: "zh-Hans")), "后台自检")
        XCTAssertTrue(record.canDecide)
        XCTAssertNotNil(record.createdAt)
    }

    func testUnknownSubsystemCannotDecide() throws {
        let record = try decoder.decode(WriteGateRecord.self, from: Data("""
        {"id": "x", "subsystem": "tools", "action": "run", "summary": "s",
         "origin": "somewhere_new", "created_at": null}
        """.utf8))
        XCTAssertEqual(record.subsystem, .unknown)
        XCTAssertFalse(record.canDecide)
        // 未知来源给通用中文兜底（0.36.21 用户点名修
        // 订，覆盖旧「回落原始值」口径）：原始标识是
        // 内部记账名、不许当标签漏给用户；卡不丢弃
        XCTAssertEqual(record.originLabel(locale: Locale(identifier: "zh-Hans")), "其他来源")
    }

    /// origin 实测取值 assistant_tool（桥侧实测，取值域
    /// 比上游 docstring 的 foreground/background 更宽）
    func testOriginAssistantTool() throws {
        let record = try decoder.decode(WriteGateRecord.self, from: Data("""
        {"id": "y", "subsystem": "memory", "action": "append",
         "summary": "记一条", "origin": "assistant_tool",
         "created_at": null}
        """.utf8))
        XCTAssertEqual(record.originLabel(locale: Locale(identifier: "zh-Hans")), "智能体工具调用")
    }

    /// §234：blocked_reason 解码——带原因即防呆态
    /// （isBlocked），可裁决性本身不变（驳回仍开）；
    /// 无字段/空白串都按无结论
    func testRecordBlockedReasonDecode() throws {
        let blocked = try decoder.decode(WriteGateRecord.self, from: Data("""
        {"id": "62927061", "subsystem": "skills", "action": "batch",
         "summary": "s", "origin": "background_review",
         "created_at": "2026-11-11T14:58:53Z",
         "blocked_reason": "Description is 82 chars; over the 60-char budget."}
        """.utf8))
        XCTAssertEqual(
            blocked.blockedReason,
            "Description is 82 chars; over the 60-char budget."
        )
        XCTAssertTrue(blocked.isBlocked)
        XCTAssertTrue(blocked.canDecide)

        let plain = try decoder.decode(WriteGateRecord.self, from: Data("""
        {"id": "z", "subsystem": "skills", "action": "create",
         "summary": "s", "origin": "foreground", "created_at": null}
        """.utf8))
        XCTAssertNil(plain.blockedReason)
        XCTAssertFalse(plain.isBlocked)

        let blank = try decoder.decode(WriteGateRecord.self, from: Data("""
        {"id": "w", "subsystem": "skills", "action": "create",
         "summary": "s", "origin": "foreground", "created_at": null,
         "blocked_reason": "  "}
        """.utf8))
        XCTAssertNil(blank.blockedReason)
        XCTAssertFalse(blank.isBlocked)
    }

    /// §234：failure_reason 解码——失败回执带结构化
    /// 原因；成功回执与旧桥回执（无字段）恒 nil
    func testDecisionResponseFailureReasonDecode() throws {
        let failed = try decoder.decode(
            WriteGateDecisionResponse.self, from: Data("""
            {"success": false, "output": "Failed:\\n  abc: boom",
             "decision": "approved", "failure_reason": "boom"}
            """.utf8))
        XCTAssertFalse(failed.success)
        XCTAssertEqual(failed.failureReason, "boom")

        let ok = try decoder.decode(
            WriteGateDecisionResponse.self, from: Data("""
            {"success": true, "output": "", "decision": "approved"}
            """.utf8))
        XCTAssertTrue(ok.success)
        XCTAssertNil(ok.failureReason)
    }

    func testSectionStateResolve() {
        let off = WriteGateStatus(
            supported: true, memoryGateEnabled: false,
            skillsGateEnabled: false, memoryCount: 0, skillsCount: 0
        )
        XCTAssertEqual(
            ApprovalSectionState.resolve(status: off, records: nil),
            .gateDisabled
        )
        let on = WriteGateStatus(
            supported: true, memoryGateEnabled: true,
            skillsGateEnabled: false, memoryCount: 0, skillsCount: 0
        )
        // 闸门开＋空列表才是真「暂无待批」
        XCTAssertEqual(
            ApprovalSectionState.resolve(status: on, records: []),
            .ready([])
        )
        // 无 status 证据只能落通道未接通，不许断言没开闸
        XCTAssertEqual(
            ApprovalSectionState.resolve(status: nil, records: []),
            .bridgeUnavailable
        )
        let unsupported = WriteGateStatus(
            supported: false, memoryGateEnabled: true,
            skillsGateEnabled: true, memoryCount: 1, skillsCount: 1
        )
        XCTAssertEqual(
            ApprovalSectionState.resolve(status: unsupported, records: []),
            .bridgeUnavailable
        )
    }

    func testReviewDisplayDiffFallback() throws {
        let detail = try decoder.decode(WriteGateDetail.self, from: Data("""
        {"record": {"id": "m1", "subsystem": "memory", "action": "append",
                    "summary": "记一条", "origin": "chat",
                    "created_at": "2026-11-09T02:00:00Z"},
         "review": {"subsystem": "memory", "targetLabel": "memory",
                    "language": "json", "current": "",
                    "proposed": "{\\"k\\": 1}", "diff": "",
                    "requestedOldString": null,
                    "notes": [{"type": "patchOldStringMissing"}]}}
        """.utf8))
        // memory 的 diff 为空时回落 proposed（payload 文本）
        XCTAssertEqual(detail.review.displayDiff, "{\"k\": 1}")
        XCTAssertEqual(detail.review.noteLabels.count, 1)
        XCTAssertTrue(detail.review.noteLabels[0].contains("定位文本已不存在"))
    }

    func testComputerUseExtraction() throws {
        func readiness(_ json: String) throws -> ComputerUseReadiness {
            try decoder.decode(ComputerUseStatus.self, from: Data(json.utf8))
                .readiness
        }
        XCTAssertEqual(try readiness(#"{"ready": true}"#), .ready)
        XCTAssertEqual(try readiness(#"{"status": "needs_permission"}"#), .notReady)
        XCTAssertEqual(
            try readiness(#"{"computer_use": {"available": false}}"#),
            .notReady
        )
        // 子工具的 ready 不许冒充整体就绪（只进指定嵌套键）
        XCTAssertEqual(
            try readiness(#"{"other_tool": {"ready": true}}"#),
            .unknown
        )
        // 200 空包络＝未确认，不压成未就绪
        XCTAssertEqual(try readiness(#"{}"#), .unknown)
    }

    // 浏览器段状态行测试已随 0.9.0 改源迁往
    // BoxBridgeTests（BrowserHubState 读 9119 错位源、
    // 已退役）；本文件的 computer-use 宽容提取测试
    // 保留——该端点仍供设置详情如实标注本机状态。
}
