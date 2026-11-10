import XCTest
@testable import OneDayCore

/// 审批文案人话化钉测（0.36.21，宪法 §8 收口，P-16）：
/// 头条由结构化字段拼中文模板——四类真实串形态（用
/// 户 2026-11-11 真机截图：batch 多 op／create／add
/// to memory／remove from user profile）对应的结构化
/// 输入必须拼出可读中文，且任何情况下原始英文运维
/// 串不许当头条；桥未给结构化字段时退通用中文句。
final class ApprovalCopyTests: XCTestCase {
    private let decoder = JSONDecoder()

    // MARK: - 四类真实形态（结构化字段 → 中文头条）

    func testBatchHeadline() {
        // 截图原串："batch(3 ops: patch, patch, patch)
        // on hermes-agent, personal-data-insights"
        let title = ApprovalHeadline.title(
            subsystem: .skills, op: "batch",
            targetName: "personal-data-insights",
            opCount: 3, opKinds: ["patch", "patch", "patch"],
            memTarget: nil, contentPreview: nil
        )
        XCTAssertEqual(title, "修改技能《personal-data-insights》：共 3 处改动")
    }

    func testBatchMixedAndCreateKinds() {
        XCTAssertEqual(
            ApprovalHeadline.title(
                subsystem: .skills, op: "batch", targetName: "x",
                opCount: 2, opKinds: ["patch", "create"],
                memTarget: nil, contentPreview: nil
            ),
            "修改技能《x》：共 2 处改动"
        )
        XCTAssertEqual(
            ApprovalHeadline.title(
                subsystem: .skills, op: "batch", targetName: "x",
                opCount: 2, opKinds: ["create", "create"],
                memTarget: nil, contentPreview: nil
            ),
            "新建技能《x》：共 2 项"
        )
        // 无计数（桥旧数据）：批量通用句，仍是中文
        XCTAssertEqual(
            ApprovalHeadline.title(
                subsystem: .skills, op: "batch", targetName: "x",
                opCount: nil, opKinds: nil,
                memTarget: nil, contentPreview: nil
            ),
            "批量修改技能《x》"
        )
    }

    func testCreateSkillHeadline() {
        XCTAssertEqual(
            ApprovalHeadline.title(
                subsystem: .skills, op: "create", targetName: "新技能",
                opCount: nil, opKinds: nil,
                memTarget: nil, contentPreview: nil
            ),
            "新建技能《新技能》"
        )
        XCTAssertEqual(
            ApprovalHeadline.title(
                subsystem: .skills, op: "write_file", targetName: "x",
                opCount: nil, opKinds: nil,
                memTarget: nil, contentPreview: nil
            ),
            "修改技能《x》的文件"
        )
        XCTAssertEqual(
            ApprovalHeadline.title(
                subsystem: .skills, op: "delete", targetName: "x",
                opCount: nil, opKinds: nil,
                memTarget: nil, contentPreview: nil
            ),
            "删除技能《x》"
        )
    }

    func testAddMemoryHeadline() {
        // 截图原串："add to memory: M1 regression-gate
        // test memory, reject immediately"
        XCTAssertEqual(
            ApprovalHeadline.title(
                subsystem: .memory, op: "add", targetName: nil,
                opCount: nil, opKinds: nil, memTarget: "memory",
                contentPreview: "用户喜欢喝美式咖啡"
            ),
            "新增一条记忆：用户喜欢喝美式咖啡"
        )
        // 长预览截断收口（30 字＋省略号），不整串上屏
        let long = ApprovalHeadline.title(
            subsystem: .memory, op: "add", targetName: nil,
            opCount: nil, opKinds: nil, memTarget: "memory",
            contentPreview: "M1 regression-gate test memory, reject immediately"
        )
        XCTAssertTrue(long.hasPrefix("新增一条记忆：M1 regression-gate test memory"))
        XCTAssertTrue(long.hasSuffix("…"))
    }

    func testRemoveFromProfileHeadline() {
        // 截图原串："remove from user profile：…"
        XCTAssertEqual(
            ApprovalHeadline.title(
                subsystem: .memory, op: "remove", targetName: nil,
                opCount: nil, opKinds: nil, memTarget: "user",
                contentPreview: "旧的联系方式"
            ),
            "从个人资料删除：旧的联系方式"
        )
        XCTAssertEqual(
            ApprovalHeadline.title(
                subsystem: .memory, op: "replace", targetName: nil,
                opCount: nil, opKinds: nil, memTarget: "user",
                contentPreview: nil
            ),
            "修改个人资料"
        )
    }

    // MARK: - 兜底：无结构化字段也必须是中文

    func testFallbackHeadlinesWithoutStructuredFields() {
        XCTAssertEqual(
            ApprovalHeadline.title(
                subsystem: .skills, op: "edit", targetName: nil,
                opCount: nil, opKinds: nil,
                memTarget: nil, contentPreview: nil
            ),
            "修改一个技能"
        )
        XCTAssertEqual(
            ApprovalHeadline.title(
                subsystem: .memory, op: "add", targetName: nil,
                opCount: nil, opKinds: nil,
                memTarget: nil, contentPreview: nil
            ),
            "新增一条记忆"
        )
        XCTAssertEqual(
            ApprovalHeadline.title(
                subsystem: .unknown, op: "run", targetName: nil,
                opCount: nil, opKinds: nil,
                memTarget: nil, contentPreview: nil
            ),
            "其他写入"
        )
    }

    // MARK: - 记录级：英文原串永不当头条

    func testRecordHeadlineNeverRawEnglishSummary() throws {
        let record = try decoder.decode(WriteGateRecord.self, from: Data("""
        {"id": "r1", "subsystem": "skills", "action": "batch",
         "summary": "batch(3 ops: patch, patch, patch) on hermes-agent, personal-data-insights",
         "origin": "oneday_app", "created_at": null,
         "op": "batch", "target_name": "personal-data-insights",
         "op_count": 3, "op_kinds": ["patch", "patch", "patch"]}
        """.utf8))
        XCTAssertEqual(
            record.headline(locale: Locale(identifier: "zh-Hans")), "修改技能《personal-data-insights》：共 3 处改动"
        )
        // 无内容预览＋英文摘要：说明行宁缺毋滥（nil）
        XCTAssertNil(record.previewLine)
        XCTAssertEqual(record.originLabel(locale: Locale(identifier: "zh-Hans")), "本机 App")
        XCTAssertEqual(record.effectiveOp, "batch")
    }

    func testRecordPreviewLineUsesChineseSummary() throws {
        let record = try decoder.decode(WriteGateRecord.self, from: Data("""
        {"id": "r2", "subsystem": "memory", "action": "append",
         "summary": "把一条新的巡检结论写入长期记忆",
         "origin": "background_review", "created_at": null}
        """.utf8))
        // 存量中文摘要作说明行保留，头条仍走模板
        XCTAssertEqual(record.previewLine, "把一条新的巡检结论写入长期记忆")
        XCTAssertEqual(record.headline(locale: Locale(identifier: "zh-Hans")), "新增一条记忆")
    }

    // MARK: - 已决记录：via_rule 与同模板头条

    func testDecisionRecordViaRuleAndHeadline() throws {
        let item = try decoder.decode(WriteGateDecisionRecord.self, from: Data("""
        {"id": "d1", "subsystem": "memory", "action": "add",
         "summary": "add to memory: something english",
         "origin": "oneday_app", "decision": "approved",
         "decided_at": "2026-11-10T16:00:00Z",
         "via_rule": "rule_abc123", "op": "add",
         "mem_target": "memory", "content_preview": "出差时住公司附近"}
        """.utf8))
        XCTAssertTrue(item.isRuleApproved)
        XCTAssertEqual(item.headline(locale: Locale(identifier: "zh-Hans")), "新增一条记忆：出差时住公司附近")
        // 无 via_rule 的旧账本条目解码不受影响
        let plain = try decoder.decode(WriteGateDecisionRecord.self, from: Data("""
        {"id": "d2", "subsystem": "skills", "action": "edit",
         "summary": "s", "origin": "cli", "decision": "rejected",
         "decided_at": null}
        """.utf8))
        XCTAssertFalse(plain.isRuleApproved)
        XCTAssertNil(plain.viaRule)
    }

    // MARK: - 就地卡问句与范围（ApprovalCardCopy）

    private func makeRecord(
        subsystem: String, action: String, op: String? = nil,
        origin: String = "oneday_app"
    ) throws -> WriteGateRecord {
        let opField = op.map { ", \"op\": \"\($0)\"" } ?? ""
        return try decoder.decode(WriteGateRecord.self, from: Data("""
        {"id": "q", "subsystem": "\(subsystem)", "action": "\(action)",
         "summary": "raw", "origin": "\(origin)", "created_at": null\(opField)}
        """.utf8))
    }

    func testQuestionTemplates() throws {
        XCTAssertEqual(
            ApprovalCardCopy.question(for: try makeRecord(
                subsystem: "memory", action: "add"), locale: Locale(identifier: "zh-Hans")),
            "允许智能体新增一条长期记忆？"
        )
        XCTAssertEqual(
            ApprovalCardCopy.question(for: try makeRecord(
                subsystem: "skills", action: "create"), locale: Locale(identifier: "zh-Hans")),
            "允许智能体新建一个技能？"
        )
        XCTAssertEqual(
            ApprovalCardCopy.question(for: try makeRecord(
                subsystem: "skills", action: "delete"), locale: Locale(identifier: "zh-Hans")),
            "允许智能体删除整个技能？"
        )
        XCTAssertEqual(
            ApprovalCardCopy.question(for: try makeRecord(
                subsystem: "tools", action: "run"), locale: Locale(identifier: "zh-Hans")),
            "允许智能体执行这项写入？"
        )
    }

    func testQuestionPrefersStructuredOp() throws {
        // 顶层 action 与 payload op 不一致时以 op 为准
        // （桥结构化字段是真实动作）
        let record = try makeRecord(
            subsystem: "skills", action: "edit", op: "batch"
        )
        XCTAssertEqual(
            ApprovalCardCopy.question(for: record, locale: Locale(identifier: "zh-Hans")),
            "允许智能体批量修改技能文件？"
        )
    }

    func testConsequenceAndScope() throws {
        let record = try makeRecord(subsystem: "memory", action: "remove")
        XCTAssertTrue(
            ApprovalCardCopy.consequence(for: record, locale: Locale(identifier: "zh-Hans")).contains("驳回")
        )
        XCTAssertEqual(
            ApprovalCardCopy.alwaysAllowScope(for: record, locale: Locale(identifier: "zh-Hans")),
            "记忆 · 本机 App"
        )
    }

    // MARK: - 规则模型

    func testRuleDecodeAndScopeLabel() throws {
        let response = try decoder.decode(
            WriteGateRulesResponse.self, from: Data("""
            {"rules": [{"id": "rule_1", "subsystem": "memory",
             "origin": "oneday_app", "created_at": 1760000000.0}]}
            """.utf8)
        )
        XCTAssertEqual(response.rules.count, 1)
        XCTAssertEqual(response.rules[0].scopeLabel(locale: Locale(identifier: "zh-Hans")), "记忆 · 本机 App")
        XCTAssertNotNil(response.rules[0].createdAt)
    }

    // MARK: - 相对时间中文化

    func testRelativeTimeChinese() {
        let now = Date(timeIntervalSince1970: 1_760_100_000)
        let text = ApprovalTimeText.relative(
            now.addingTimeInterval(-44 * 60), now: now,
            locale: Locale(identifier: "zh-Hans")
        )
        XCTAssertTrue(text.contains("44"), "实际输出：\(text)")
        XCTAssertTrue(text.contains("分钟"), "实际输出：\(text)")
        XCTAssertFalse(text.contains("minutes"), "实际输出：\(text)")
    }
}
