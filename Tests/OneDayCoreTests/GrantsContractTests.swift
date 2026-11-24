import OneDayCore
import XCTest

/// 命令授权契约钉测（DESIGN §355）：统一清单解码、撤
/// 销请求体组装、失败分类矩阵、回读判定——全部对批 5
/// 真调用实测字面（部署包 1.3.0，执行报告 B1–B7），
/// 不许凭图臆测
final class GrantsContractTests: XCTestCase {

    private func decodeList(_ json: String) throws -> GrantsListResponse {
        try JSONDecoder().decode(
            GrantsListResponse.self, from: Data(json.utf8)
        )
    }

    // MARK: - 清单解码（批 5 B1 实测形态）

    func testListDecodesBothSourcesWithRecoveredProvenance() throws {
        // B1：exec 3＋writegate 2、partial=false；pipe 条
        // 目 granted_at 自决定账恢复（1795329594.1590946）
        // ＋source_decision 决定 id；标记键两字段如实 null
        let response = try decodeList("""
        {
          "object": "hermes.grants",
          "grants": [
            {
              "grant_key": "exec:pipe remote content to shell",
              "source": "exec",
              "pattern_key": "pipe remote content to shell",
              "scope_label": "pipe remote content to shell",
              "granted_at": 1795329594.1590946,
              "source_decision": "cce35d029033494db44be15ba03a65c9",
              "status": "active",
              "expires_at": null,
              "revoke_via": "gateway"
            },
            {
              "grant_key": "exec:zz batch5 test grant marker",
              "source": "exec",
              "pattern_key": "zz batch5 test grant marker",
              "scope_label": "zz batch5 test grant marker",
              "granted_at": null,
              "source_decision": null,
              "status": "active",
              "expires_at": null,
              "revoke_via": "gateway"
            },
            {
              "grant_key": "writegate:rule-1",
              "source": "writegate",
              "rule_id": "rule-1",
              "scope_label": "skills · background_review",
              "granted_at": 1794000000.5,
              "source_decision": null,
              "status": "active",
              "expires_at": null,
              "revoke_via": "writegate-bridge"
            }
          ],
          "exec_count": 2,
          "writegate_count": 1,
          "partial": false,
          "source_errors": [],
          "projection_degraded": false
        }
        """)
        XCTAssertEqual(response.execCount, 2)
        XCTAssertEqual(response.writegateCount, 1)
        XCTAssertFalse(response.partial)
        XCTAssertEqual(response.execEntries.count, 2)
        XCTAssertEqual(response.writegateEntries.count, 1)

        let pipe = response.execEntries[0]
        XCTAssertEqual(pipe.id, "exec:pipe remote content to shell")
        XCTAssertEqual(pipe.patternKey, "pipe remote content to shell")
        XCTAssertEqual(
            pipe.grantedAt,
            Date(timeIntervalSince1970: 1795329594.1590946)
        )
        XCTAssertEqual(
            pipe.sourceDecision, "cce35d029033494db44be15ba03a65c9"
        )
        XCTAssertNil(pipe.expiresAt)
        XCTAssertTrue(pipe.canRevokeHere)

        // 查不到的来源/时间如实留空——不许解码层编造
        let marker = response.execEntries[1]
        XCTAssertNil(marker.grantedAt)
        XCTAssertNil(marker.sourceDecision)

        let rule = response.writegateEntries[0]
        XCTAssertEqual(rule.ruleID, "rule-1")
        XCTAssertEqual(rule.scopeLabel, "skills · background_review")
        XCTAssertEqual(rule.revokeVia, "writegate-bridge")
        // 写闸条目本面不可撤销（管理归桥侧审批规则）
        XCTAssertFalse(rule.canRevokeHere)
    }

    func testListDecodesPartialWithNullCountForFailedSource() throws {
        // 单源败：partial=true、source_errors 点名、失败
        // 半边计数为 null（不是 0——0 会冒充「没有授权」）
        let response = try decodeList("""
        {
          "object": "hermes.grants",
          "grants": [],
          "exec_count": null,
          "writegate_count": 2,
          "partial": true,
          "source_errors": ["exec"],
          "projection_degraded": false
        }
        """)
        XCTAssertTrue(response.partial)
        XCTAssertEqual(response.sourceErrors, ["exec"])
        XCTAssertNil(response.execCount)
        XCTAssertEqual(response.writegateCount, 2)
    }

    func testListDecodesNumericRuleIDAsString() throws {
        // rules.json 的 id 若是数字，服务端原样透传——
        // 客户端宽容收口为字符串，不许整包解码失败
        let response = try decodeList("""
        {
          "object": "hermes.grants",
          "grants": [
            {
              "grant_key": "writegate:42",
              "source": "writegate",
              "rule_id": 42,
              "scope_label": "memory · assistant_tool",
              "granted_at": null,
              "source_decision": null,
              "status": "active",
              "expires_at": null,
              "revoke_via": "writegate-bridge"
            }
          ],
          "exec_count": 0,
          "writegate_count": 1,
          "partial": false,
          "source_errors": [],
          "projection_degraded": false
        }
        """)
        XCTAssertEqual(response.writegateEntries.first?.ruleID, "42")
    }

    // MARK: - 撤销请求组装

    func testRevokeRequestEncodesExecSourceAndPatternKey() throws {
        let request = GrantRevokeRequest.exec(
            patternKey: "pipe remote content to shell"
        )
        let data = try JSONEncoder().encode(request)
        let object = try JSONSerialization.jsonObject(with: data)
            as? [String: Any]
        XCTAssertEqual(object?["source"] as? String, "exec")
        XCTAssertEqual(
            object?["pattern_key"] as? String,
            "pipe remote content to shell"
        )
        XCTAssertEqual(object?.count, 2)
    }

    // MARK: - 撤销回执解码（批 5 B4 实测形态）

    func testRevocationReceiptDecodesRemovedAliases() throws {
        // B4：撤 pipe 键连别名 (curl|wget) 一并删、双自
        // 检过（verified_absent=true、governing null）
        let receipt = try JSONDecoder().decode(
            GrantRevocationReceipt.self,
            from: Data("""
            {
              "object": "hermes.grant_revocation",
              "source": "exec",
              "pattern_key": "pipe remote content to shell",
              "removed": ["(curl|wget)", "pipe remote content to shell"],
              "governing_scope": null,
              "verified_absent": true
            }
            """.utf8)
        )
        XCTAssertEqual(receipt.patternKey, "pipe remote content to shell")
        XCTAssertEqual(
            receipt.removed,
            ["(curl|wget)", "pipe remote content to shell"]
        )
        XCTAssertTrue(receipt.verifiedAbsent)
        XCTAssertNil(receipt.governingScope)
    }

    // MARK: - 失败分类矩阵（批 5 B3 实测码）

    func testRevokeDirectiveMatrix() {
        XCTAssertEqual(
            GrantRevokeDirective.directive(status: 200, serverCode: nil),
            .done
        )
        // B3：不存在的 exec 键 → 404 grant_not_found
        XCTAssertEqual(
            GrantRevokeDirective.directive(
                status: 404, serverCode: "grant_not_found"
            ),
            .notFound
        )
        // B3：写闸误走本端点 → 400 grant_revoke_wrong_channel
        XCTAssertEqual(
            GrantRevokeDirective.directive(
                status: 400, serverCode: "grant_revoke_wrong_channel"
            ),
            .wrongChannel
        )
        // 自检不过 → 409 grant_revoke_unverified
        XCTAssertEqual(
            GrantRevokeDirective.directive(
                status: 409, serverCode: "grant_revoke_unverified"
            ),
            .unverified
        )
        // 其余如实失败：503 配置不可用、400 无效键、未知码
        XCTAssertEqual(
            GrantRevokeDirective.directive(
                status: 503, serverCode: "grant_revoke_failed"
            ),
            .failed
        )
        XCTAssertEqual(
            GrantRevokeDirective.directive(
                status: 400, serverCode: "invalid_pattern_key"
            ),
            .failed
        )
        XCTAssertEqual(
            GrantRevokeDirective.directive(
                status: 500, serverCode: nil
            ),
            .failed
        )
    }

    // MARK: - 回读判定

    func testReadbackConfirmsAbsentOnlyWhenKeyGone() throws {
        let stillThere = try decodeList("""
        {
          "object": "hermes.grants",
          "grants": [
            {
              "grant_key": "exec:pipe remote content to shell",
              "source": "exec",
              "pattern_key": "pipe remote content to shell",
              "scope_label": "pipe remote content to shell",
              "granted_at": null,
              "source_decision": null,
              "status": "active",
              "expires_at": null,
              "revoke_via": "gateway"
            }
          ],
          "exec_count": 1,
          "writegate_count": 0,
          "partial": false,
          "source_errors": [],
          "projection_degraded": false
        }
        """)
        XCTAssertFalse(
            GrantReadback.isConfirmedAbsent(
                grantKey: "exec:pipe remote content to shell",
                in: stillThere
            )
        )
        // B6 终局基线：exec 0 条——回读确认消失
        let emptied = try decodeList("""
        {
          "object": "hermes.grants",
          "grants": [],
          "exec_count": 0,
          "writegate_count": 2,
          "partial": false,
          "source_errors": [],
          "projection_degraded": false
        }
        """)
        XCTAssertTrue(
            GrantReadback.isConfirmedAbsent(
                grantKey: "exec:pipe remote content to shell",
                in: emptied
            )
        )
    }
}
