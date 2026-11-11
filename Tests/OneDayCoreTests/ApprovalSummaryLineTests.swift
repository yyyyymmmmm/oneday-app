import XCTest
@testable import OneDayCore

/// 审批卡说明行一行口径钉测（样式二期 S2-02）：卡面
/// 说明收敛为一行——头条为主体；内容预览与头条不同
/// 且未被头条包含时才以「：」衔接，记忆类头条已内
/// 嵌同一预览、不许拼两遍；英文运维摘要永不进说明
/// 行（previewLine 为 nil 时只剩头条）。视图层单行
/// 截断先挤掉的恒是预览尾巴。
final class ApprovalSummaryLineTests: XCTestCase {
    private let decoder = JSONDecoder()
    private let zh = Locale(identifier: "zh-Hans")

    private func makeRecord(_ json: String) throws -> WriteGateRecord {
        try decoder.decode(
            WriteGateRecord.self, from: Data(json.utf8)
        )
    }

    /// 无预览（英文原摘要）：说明行只剩头条本身
    func testHeadlineOnlyWhenNoPreview() throws {
        let record = try makeRecord("""
        {"id": "s1", "subsystem": "skills", "action": "edit",
         "summary": "batch(3 ops: patch, patch, patch) on x",
         "origin": "oneday_app", "created_at": null,
         "op": "batch", "target_name": "personal-data-insights",
         "op_count": 3, "op_kinds": ["patch", "patch", "patch"]}
        """)
        XCTAssertEqual(
            ApprovalCardCopy.summaryLine(for: record, locale: zh),
            "修改技能《personal-data-insights》：共 3 处改动"
        )
    }

    /// 记忆类：头条已内嵌内容预览——预览与头条重复
    /// 时不许再衔接一遍
    func testNoDuplicationWhenHeadlineEmbedsPreview() throws {
        let record = try makeRecord("""
        {"id": "s2", "subsystem": "memory", "action": "add",
         "summary": "add to memory: coffee",
         "origin": "oneday_app", "created_at": null,
         "mem_target": "memory",
         "content_preview": "用户喜欢喝美式咖啡"}
        """)
        let line = ApprovalCardCopy.summaryLine(
            for: record, locale: zh
        )
        XCTAssertEqual(line, "新增一条记忆：用户喜欢喝美式咖啡")
        XCTAssertEqual(
            line.components(separatedBy: "用户喜欢喝美式咖啡").count,
            2
        )
    }

    /// 预览（中文存量摘要）与头条不同：以「：」衔接
    /// 在头条之后，头条在前保证截断时先丢预览尾巴
    func testPreviewAppendedAfterHeadline() throws {
        let record = try makeRecord("""
        {"id": "s3", "subsystem": "skills", "action": "edit",
         "summary": "把技能说明里的安装步骤改成新版命令",
         "origin": "oneday_app", "created_at": null,
         "target_name": "x"}
        """)
        XCTAssertEqual(
            ApprovalCardCopy.summaryLine(for: record, locale: zh),
            "修改技能《x》：把技能说明里的安装步骤改成新版命令"
        )
    }
}
