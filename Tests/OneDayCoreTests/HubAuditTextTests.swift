import XCTest
@testable import OneDayCore

/// §477 审核页人话映射钉测：授权行 scope/来源枚举
/// 全集（子系统 memory/skills × 来源 foreground/
/// background_review/assistant_tool/oneday_app，服务
/// 端实查枚举）逐类有中文落点、未知值回落通用中文
/// 类别词、英文原文绝不上列表；已决行说明与头条不
/// 重复、英文运维串宁缺勿漏
final class HubAuditTextTests: XCTestCase {

    private func grant(
        source: GrantSource, scopeLabel: String,
        grantedAt: Date? = nil
    ) -> GrantEntry {
        GrantEntry(
            grantKey: "k", source: source,
            scopeLabel: scopeLabel, grantedAt: grantedAt,
            revokeVia: "test"
        )
    }

    // MARK: - 写闸授权标题（子系统 × 来源全集）

    func testWritegateTitleFullMatrix() {
        let cases: [(String, String)] = [
            ("memory · background_review", "记忆 · 后台复核"),
            ("memory · assistant_tool", "记忆 · 助手工具调用"),
            ("memory · oneday_app", "记忆 · App 内操作"),
            ("memory · foreground", "记忆 · 对话中"),
            ("skills · background_review", "技能 · 后台复核"),
            ("skills · assistant_tool", "技能 · 助手工具调用"),
            ("skills · oneday_app", "技能 · App 内操作"),
            ("skills · foreground", "技能 · 对话中"),
        ]
        for (label, expected) in cases {
            XCTAssertEqual(
                HubAuditText.grantTitle(
                    grant(source: .writegate, scopeLabel: label)
                ),
                expected, "scope_label=\(label)"
            )
        }
    }

    func testWritegateTitleFallbacksAreChinese() {
        // 未知子系统/来源：回落通用中文类别词，不漏原文
        XCTAssertEqual(
            HubAuditText.grantTitle(
                grant(source: .writegate, scopeLabel: "foo · bar")
            ),
            "写闸规则"
        )
        // 只有子系统：拼类别词
        XCTAssertEqual(
            HubAuditText.grantTitle(
                grant(source: .writegate, scopeLabel: "memory")
            ),
            "记忆写闸规则"
        )
        // 来源未知但子系统已知：同样走类别词、不拼英文
        XCTAssertEqual(
            HubAuditText.grantTitle(
                grant(source: .writegate, scopeLabel: "skills · mystery")
            ),
            "技能写闸规则"
        )
    }

    func testExecTitleIsPatternKey() {
        XCTAssertEqual(
            HubAuditText.grantTitle(
                grant(source: .exec, scopeLabel: "git push *")
            ),
            "git push *"
        )
    }

    // MARK: - 说明与元信息

    func testGrantDescriptionAndMeta() {
        let exec = grant(source: .exec, scopeLabel: "ls *")
        XCTAssertEqual(
            HubAuditText.grantDescription(exec),
            "已授权直接执行匹配的命令，不再逐次询问"
        )
        XCTAssertEqual(
            HubAuditText.grantMeta(exec),
            "始终允许 · 命令授权"
        )
        let gate = grant(
            source: .writegate, scopeLabel: "skills · foreground"
        )
        XCTAssertEqual(
            HubAuditText.grantDescription(gate),
            "命中规则的写入自动放行，不再逐次询问"
        )
        XCTAssertEqual(
            HubAuditText.grantMeta(gate),
            "始终允许 · 写闸规则"
        )
        // 有授予时刻：元信息带相对时间（不编造、真值拼接）
        let timed = grant(
            source: .exec, scopeLabel: "ls *",
            grantedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let meta = HubAuditText.grantMeta(
            timed,
            now: Date(timeIntervalSince1970: 1_700_000_000 + 3600)
        )
        XCTAssertTrue(meta.hasPrefix("始终允许 · 命令授权 · "))
    }

    // MARK: - 已决行说明

    private func record(
        subsystem: WriteGateSubsystem, op: String?,
        summary: String, targetName: String? = nil,
        opCount: Int? = nil, opKinds: [String]? = nil,
        memTarget: String? = nil, contentPreview: String? = nil
    ) -> WriteGateDecisionRecord {
        WriteGateDecisionRecord(
            id: "r1", subsystem: subsystem, action: op ?? "",
            summary: summary, origin: "foreground",
            decision: "approved", decidedAt: nil,
            op: op, targetName: targetName, opCount: opCount,
            opKinds: opKinds, memTarget: memTarget,
            contentPreview: contentPreview
        )
    }

    func testDecisionDescriptionSuppressesHeadlineEmbeddedPreview() {
        // 记忆类头条已内嵌预览（「新增一条个人资料：
        // 位于西安」）——说明行不再重复同一预览
        let rec = record(
            subsystem: .memory, op: "add",
            summary: "add to memory: 位于西安",
            memTarget: "user", contentPreview: "位于西安"
        )
        XCTAssertTrue(rec.headline.hasSuffix("位于西安"))
        XCTAssertNil(HubAuditText.decisionDescription(rec))
    }

    func testDecisionDescriptionUsesPreviewWhenHeadlineLacksIt() {
        // 技能批量头条只有计数——说明行给内容预览
        let rec = record(
            subsystem: .skills, op: "batch",
            summary: "batch(1 ops: patch) on personal-data-insights",
            targetName: "personal-data-insights",
            opCount: 1, opKinds: ["patch"],
            contentPreview: "改了某文件"
        )
        XCTAssertEqual(
            HubAuditText.decisionDescription(rec), "改了某文件"
        )
    }

    func testDecisionDescriptionNeverLeaksEnglishSummary() {
        // 无内容预览＋英文运维串摘要：宁可无说明行
        let rec = record(
            subsystem: .skills, op: "batch",
            summary: "batch(2 ops: patch, patch) on some-skill",
            targetName: "some-skill", opCount: 2,
            opKinds: ["patch", "patch"]
        )
        XCTAssertNil(HubAuditText.decisionDescription(rec))
    }
}
