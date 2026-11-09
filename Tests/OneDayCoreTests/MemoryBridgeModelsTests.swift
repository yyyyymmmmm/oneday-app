import Foundation
import XCTest
@testable import OneDayCore

/// P7 记忆条目桥契约模型（0.13.0）：契约冻结于
/// memory-bridge-contract-20261109.md。服务端路由
/// 组未部署，客户端行为全靠本组 fixture 钉死：
/// 解码宽容、摘要算法、分组/过滤、提案编码形、
/// 落定判定矩阵（待批→裁决→回读验落盘）。
final class MemoryBridgeModelsTests: XCTestCase {
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    // MARK: - 摘要算法（与桥同口径的唯一定义）

    func testSHA256KnownVector() {
        // NIST 已知向量：sha256("abc")
        XCTAssertEqual(
            MemoryDigest.sha256Hex("abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
        XCTAssertEqual(
            MemoryDigest.entryID(forContent: "abc"),
            "mem_ba7816bf8f01cfea"
        )
    }

    func testSHA256EmptyAndChinese() {
        XCTAssertEqual(
            MemoryDigest.sha256Hex(""),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        )
        // 中文按 UTF-8 编码，结果稳定且与 ASCII 不同
        let digest = MemoryDigest.sha256Hex("用户住在西安")
        XCTAssertEqual(digest.count, 64)
        XCTAssertEqual(digest, MemoryDigest.sha256Hex("用户住在西安"))
    }

    // MARK: - 条目解码（fixture 按契约 §2.2 形状）

    func testEntriesResponseDecode() throws {
        let json = """
        {
          "entries": [
            {
              "id": "mem_0123456789abcdef",
              "target": "memory",
              "title": "用户住在西安高陵",
              "summary": "用户住在西安高陵，租约到 2 月 20 日。",
              "updatedAt": 1794200000.5,
              "digest": "aaaa"
            },
            {
              "id": "mem_fedcba9876543210",
              "target": "user",
              "title": "称呼偏好",
              "summary": "喜欢被称作老板。",
              "updatedAt": 1794200000.5,
              "digest": "bbbb"
            }
          ],
          "generatedAt": 1794200100.0
        }
        """
        let response = try decoder.decode(
            BridgeMemoryEntriesResponse.self, from: Data(json.utf8)
        )
        XCTAssertEqual(response.entries.count, 2)
        XCTAssertEqual(response.generatedAt, 1794200100.0)
        let first = response.entries[0]
        XCTAssertEqual(first.target, .memory)
        XCTAssertEqual(first.target.label, "长期记忆")
        XCTAssertEqual(first.title, "用户住在西安高陵")
        XCTAssertEqual(response.entries[1].target, .user)
        XCTAssertEqual(response.entries[1].target.label, "用户档案")
    }

    func testEntryDecodeToleratesMissingOptionals() throws {
        let json = """
        {"id": "mem_x", "target": "other"}
        """
        let entry = try decoder.decode(
            BridgeMemoryEntry.self, from: Data(json.utf8)
        )
        XCTAssertEqual(entry.target, .unknown)
        XCTAssertEqual(entry.target.label, "未注明来源")
        XCTAssertEqual(entry.title, "")
        XCTAssertEqual(entry.digest, "")
        XCTAssertEqual(entry.updatedAt, 0)
    }

    func testEntryDetailDecode() throws {
        let json = """
        {
          "entry": {
            "id": "mem_0123456789abcdef",
            "target": "memory",
            "title": "婚礼日期",
            "summary": "婚礼定于 2026-11-16。",
            "updatedAt": 1794200000.0,
            "digest": "cccc",
            "content": "婚礼定于 2026-11-16 在土基镇西故现村举行，新娘秦源一。"
          }
        }
        """
        let response = try decoder.decode(
            BridgeMemoryDetailResponse.self, from: Data(json.utf8)
        )
        XCTAssertEqual(
            response.entry.content,
            "婚礼定于 2026-11-16 在土基镇西故现村举行，新娘秦源一。"
        )
        XCTAssertEqual(response.entry.target, .memory)
    }

    // MARK: - 呈现（标题兜底/分组/过滤）

    private func entry(
        id: String, target: String, title: String,
        summary: String, digest: String = "d"
    ) -> BridgeMemoryEntry {
        BridgeMemoryEntry(
            id: id, targetRaw: target, title: title,
            summary: summary, updatedAt: 100, digest: digest
        )
    }

    func testDisplayTitleFallbacks() {
        XCTAssertEqual(
            MemoryEntryPresentation.displayTitle(of: entry(
                id: "1", target: "memory", title: "标题", summary: "摘要"
            )),
            "标题"
        )
        XCTAssertEqual(
            MemoryEntryPresentation.displayTitle(of: entry(
                id: "2", target: "memory", title: "  ", summary: "摘要兜底"
            )),
            "摘要兜底"
        )
        XCTAssertEqual(
            MemoryEntryPresentation.displayTitle(of: entry(
                id: "3", target: "memory", title: "", summary: ""
            )),
            "（无标题）"
        )
    }

    func testGroupsOrderingAndStability() {
        let entries = [
            entry(id: "u1", target: "user", title: "U1", summary: ""),
            entry(id: "m1", target: "memory", title: "M1", summary: ""),
            entry(id: "x1", target: "other", title: "X1", summary: ""),
            entry(id: "m2", target: "memory", title: "M2", summary: ""),
            entry(id: "u2", target: "user", title: "U2", summary: ""),
        ]
        let groups = MemoryEntryPresentation.groups(entries)
        XCTAssertEqual(
            groups.map(\.target), [.memory, .user, .unknown]
        )
        // 组内保持桥返回序，不重排
        XCTAssertEqual(groups[0].entries.map(\.id), ["m1", "m2"])
        XCTAssertEqual(groups[1].entries.map(\.id), ["u1", "u2"])
    }

    func testSearchFilter() {
        let entries = [
            entry(id: "1", target: "memory", title: "婚礼日期", summary: "11 月 16 日"),
            entry(id: "2", target: "user", title: "称呼", summary: "喜欢被称作老板"),
            entry(id: "3", target: "memory", title: "服务器", summary: "RackNerd 节点"),
        ]
        // 空查询＝全量
        XCTAssertEqual(
            MemoryEntryPresentation.filtered(entries, query: "  ").count, 3
        )
        // 标题命中
        XCTAssertEqual(
            MemoryEntryPresentation.filtered(entries, query: "婚礼").map(\.id),
            ["1"]
        )
        // 摘要命中
        XCTAssertEqual(
            MemoryEntryPresentation.filtered(entries, query: "老板").map(\.id),
            ["2"]
        )
        // 来源人话命中（用户档案）
        XCTAssertEqual(
            MemoryEntryPresentation.filtered(entries, query: "用户档案").map(\.id),
            ["2"]
        )
        // 无命中
        XCTAssertTrue(
            MemoryEntryPresentation.filtered(entries, query: "不存在").isEmpty
        )
    }

    // MARK: - propose 编码形（契约 §2.3）

    func testProposeCreateEncodingOmitsEntryFields() throws {
        let request = BridgeMemoryProposeRequest.create(
            target: .memory, content: "用户喜欢喝美式咖啡。"
        )
        let object = try jsonObject(request)
        XCTAssertEqual(object["operation"] as? String, "create")
        XCTAssertEqual(object["target"] as? String, "memory")
        XCTAssertEqual(object["content"] as? String, "用户喜欢喝美式咖啡。")
        XCTAssertNil(object["entryId"])
        XCTAssertNil(object["baseDigest"])
    }

    func testProposeUpdateAndDeleteCarryDigest() throws {
        let target = entry(
            id: "mem_1", target: "user", title: "T",
            summary: "S", digest: "deadbeef"
        )
        let update = try jsonObject(
            BridgeMemoryProposeRequest.update(
                entry: target, content: "新内容"
            )
        )
        XCTAssertEqual(update["operation"] as? String, "update")
        XCTAssertEqual(update["entryId"] as? String, "mem_1")
        XCTAssertEqual(update["baseDigest"] as? String, "deadbeef")
        XCTAssertEqual(update["target"] as? String, "user")

        let delete = try jsonObject(
            BridgeMemoryProposeRequest.delete(entry: target)
        )
        XCTAssertEqual(delete["operation"] as? String, "delete")
        XCTAssertEqual(delete["entryId"] as? String, "mem_1")
        XCTAssertEqual(delete["baseDigest"] as? String, "deadbeef")
        XCTAssertNil(delete["content"])
    }

    func testProposeResponseDecode() throws {
        let json = """
        {"pendingId": "p_123", "operation": "create", "target": "memory"}
        """
        let response = try decoder.decode(
            BridgeMemoryProposeResponse.self, from: Data(json.utf8)
        )
        XCTAssertEqual(response.pendingId, "p_123")
        XCTAssertEqual(response.operation, "create")
    }

    func testGateActionMapping() {
        XCTAssertEqual(MemoryProposeOperation.create.gateAction, "add")
        XCTAssertEqual(MemoryProposeOperation.update.gateAction, "replace")
        XCTAssertEqual(MemoryProposeOperation.delete.gateAction, "remove")
    }

    // MARK: - 已决记录解码

    func testDecisionsDecode() throws {
        let json = """
        {
          "decisions": [
            {
              "id": "p_123", "subsystem": "memory", "action": "add",
              "summary": "把一条内容写入长期记忆",
              "origin": "oneday_app",
              "created_at": "2026-11-09T07:00:00+00:00",
              "decided_at": "2026-11-09T07:05:00+00:00",
              "decision": "approved"
            },
            {
              "id": "p_124", "subsystem": "skills", "action": "edit",
              "summary": "修订技能", "origin": "assistant_tool",
              "created_at": null, "decided_at": null,
              "decision": "rejected"
            }
          ]
        }
        """
        let response = try decoder.decode(
            WriteGateDecisionsResponse.self, from: Data(json.utf8)
        )
        XCTAssertEqual(response.decisions.count, 2)
        let first = response.decisions[0]
        XCTAssertTrue(first.isApproved)
        XCTAssertFalse(first.isRejected)
        XCTAssertEqual(first.subsystem, .memory)
        XCTAssertNotNil(first.decidedAt)
        XCTAssertTrue(response.decisions[1].isRejected)
        XCTAssertNil(response.decisions[1].decidedAt)
    }

    // MARK: - 表单校验

    func testProposalValidation() {
        XCTAssertNotNil(MemoryProposalValidation.problem(
            operation: .create, content: "   "
        ))
        XCTAssertNil(MemoryProposalValidation.problem(
            operation: .create, content: "有内容"
        ))
        XCTAssertNotNil(MemoryProposalValidation.problem(
            operation: .update, content: "原文",
            originalContent: "原文"
        ))
        XCTAssertNil(MemoryProposalValidation.problem(
            operation: .update, content: "改后",
            originalContent: "原文"
        ))
        XCTAssertNil(MemoryProposalValidation.problem(
            operation: .delete, content: nil
        ))
    }

    // MARK: - 待批匹配（payload → 条目 digest）

    func testTargetedDigestFromPayload() {
        let payload: JSONValue = .object([
            "action": .string("replace"),
            "target": .string("memory"),
            "old_text": .string("旧条目原文"),
            "content": .string("新条目原文"),
        ])
        XCTAssertEqual(
            MemoryPendingMatching.targetedDigest(payload: payload),
            MemoryDigest.sha256Hex("旧条目原文")
        )
        // add 无单一目标条目 → nil
        let addPayload: JSONValue = .object([
            "action": .string("add"),
            "content": .string("新条目原文"),
        ])
        XCTAssertNil(MemoryPendingMatching.targetedDigest(payload: addPayload))
        // matched_entry 兜底键
        let removePayload: JSONValue = .object([
            "action": .string("remove"),
            "matched_entry": .string("要删的原文"),
        ])
        XCTAssertEqual(
            MemoryPendingMatching.targetedDigest(payload: removePayload),
            MemoryDigest.sha256Hex("要删的原文")
        )
        // 无 payload / 非对象 → nil
        XCTAssertNil(MemoryPendingMatching.targetedDigest(payload: nil))
        XCTAssertNil(MemoryPendingMatching.targetedDigest(payload: .string("x")))
    }

    // MARK: - 落定判定矩阵

    private func proposal(
        operation: MemoryProposeOperation,
        pendingId: String = "p_1",
        baseDigest: String? = nil,
        proposedContent: String? = nil
    ) -> MemoryProposal {
        MemoryProposal(
            pendingId: pendingId, operation: operation,
            targetRaw: "memory", entryId: "mem_x",
            baseDigest: baseDigest, proposedContent: proposedContent
        )
    }

    private func landedEntry(content: String) -> BridgeMemoryEntry {
        let digest = MemoryDigest.sha256Hex(content)
        return BridgeMemoryEntry(
            id: MemoryDigest.entryID(forContent: content),
            targetRaw: "memory", title: "T", summary: "S",
            updatedAt: 100, digest: digest
        )
    }

    func testResolutionStillPending() {
        let item = proposal(operation: .create, proposedContent: "新内容")
        XCTAssertEqual(
            MemoryProposalResolution.status(
                of: item, pendingIDs: ["p_1"], decisions: [:], entries: []
            ),
            .pending
        )
    }

    func testResolutionRejected() {
        let item = proposal(operation: .delete, baseDigest: "old")
        XCTAssertEqual(
            MemoryProposalResolution.status(
                of: item, pendingIDs: [],
                decisions: ["p_1": "rejected"],
                entries: [landedEntry(content: "无关")]
            ),
            .rejected
        )
    }

    func testResolutionCreateLandedAndUnconfirmed() {
        let item = proposal(operation: .create, proposedContent: "新内容")
        XCTAssertEqual(
            MemoryProposalResolution.status(
                of: item, pendingIDs: [],
                decisions: ["p_1": "approved"],
                entries: [landedEntry(content: "新内容")]
            ),
            .landed
        )
        XCTAssertEqual(
            MemoryProposalResolution.status(
                of: item, pendingIDs: [],
                decisions: ["p_1": "approved"], entries: []
            ),
            .approvedUnconfirmed
        )
    }

    func testResolutionUpdateRequiresOldGone() {
        let oldContent = "旧内容"
        let item = proposal(
            operation: .update,
            baseDigest: MemoryDigest.sha256Hex(oldContent),
            proposedContent: "改后内容"
        )
        // 新旧都在（替换还没落）→ 未确认
        XCTAssertEqual(
            MemoryProposalResolution.status(
                of: item, pendingIDs: [],
                decisions: ["p_1": "approved"],
                entries: [
                    landedEntry(content: oldContent),
                    landedEntry(content: "改后内容"),
                ]
            ),
            .approvedUnconfirmed
        )
        // 新在旧无 → 落定
        XCTAssertEqual(
            MemoryProposalResolution.status(
                of: item, pendingIDs: [],
                decisions: ["p_1": "approved"],
                entries: [landedEntry(content: "改后内容")]
            ),
            .landed
        )
    }

    func testResolutionDeleteLanded() {
        let oldContent = "要删的内容"
        let item = proposal(
            operation: .delete,
            baseDigest: MemoryDigest.sha256Hex(oldContent)
        )
        XCTAssertEqual(
            MemoryProposalResolution.status(
                of: item, pendingIDs: [],
                decisions: ["p_1": "approved"], entries: []
            ),
            .landed
        )
        XCTAssertEqual(
            MemoryProposalResolution.status(
                of: item, pendingIDs: [],
                decisions: ["p_1": "approved"],
                entries: [landedEntry(content: oldContent)]
            ),
            .approvedUnconfirmed
        )
    }

    func testResolutionUnresolvedWithoutDecision() {
        let item = proposal(operation: .create, proposedContent: "新内容")
        // 不在待批、又没有裁决记录 → 如实未确认，不猜
        XCTAssertEqual(
            MemoryProposalResolution.status(
                of: item, pendingIDs: [], decisions: [:],
                entries: [landedEntry(content: "新内容")]
            ),
            .unresolved
        )
        // 裁决值不在已知两值内 → 同样未确认
        XCTAssertEqual(
            MemoryProposalResolution.status(
                of: item, pendingIDs: [],
                decisions: ["p_1": "something-else"], entries: []
            ),
            .unresolved
        )
    }

    // MARK: - helpers

    private func jsonObject<T: Encodable>(
        _ value: T
    ) throws -> [String: Any] {
        let data = try encoder.encode(value)
        let object = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(object as? [String: Any])
    }
}
