import XCTest
@testable import OneDayCore

/// 身份对账判定钉测（H1-d，台账 158／G-09 余项）：
/// 认领三项（主线绑定/消息路由/会话目录）的判定纯
/// 函数——一致、不一致、端点缺失（取不到数据降级
/// 「暂无法对账」）三态逐项钉；数据来源口径见
/// OpsIdentity.swift 文件头（没有读面的东西不造
/// 对账，gateway_routing 表本体不在客户端可证范围）。
final class OpsIdentityTests: XCTestCase {

    private func row(
        _ id: String, title: String? = "主线",
        archived: Bool = false, messages: Int? = 10
    ) -> IdentityReconciliationInput.Row {
        .init(
            id: id, title: title,
            isArchived: archived, messageCount: messages
        )
    }

    private func catalog(
        _ rows: [IdentityReconciliationInput.Row],
        note: String? = nil
    ) -> IdentityReconciliationInput.CatalogSnapshot {
        .init(rows: rows, incompleteNote: note)
    }

    private let gatewayOK = IdentityReconciliationInput
        .GatewaySnapshot(
            running: true, state: "running",
            apiServerState: "connected", version: "0.23.0"
        )

    private func input(
        bound: String? = "main-1",
        catalog: IdentityReconciliationInput.CatalogSnapshot?,
        gateway: IdentityReconciliationInput.GatewaySnapshot?,
        localCount: Int? = nil,
        profile: String? = "default"
    ) -> IdentityReconciliationInput {
        .init(
            boundMainSessionID: bound,
            expectedMainTitle: "主线",
            catalog: catalog,
            localProjectionCount: localCount,
            gateway: gateway,
            currentProfile: profile
        )
    }

    // MARK: - 一致

    func testAllConsistentPasses() {
        let result = IdentityReconciler.reconcile(input(
            catalog: catalog([
                row("main-1"), row("side-1", title: "旁聊"),
                row("old-1", title: "旧会话", archived: true),
            ]),
            gateway: gatewayOK
        ))
        XCTAssertEqual(result.verdict, .ok)
        XCTAssertEqual(result.okCount, 3)
        XCTAssertEqual(
            result.item(.mainBinding)?.verdict, .ok
        )
        XCTAssertEqual(result.item(.routing)?.verdict, .ok)
        XCTAssertEqual(result.item(.catalog)?.verdict, .ok)
        XCTAssertTrue(
            result.item(.catalog)?.headline
                .contains("共 3 条") == true
        )
        XCTAssertEqual(result.currentProfile, "default")
        let summary = result.groupSummary
        XCTAssertEqual(summary.verdict, .ok)
        XCTAssertEqual(summary.passCount, 3)
        XCTAssertEqual(summary.warnCount, 0)
        XCTAssertEqual(summary.failCount, 0)
    }

    func testArchivedMainBindingStillConsistent() {
        // 认领口径：归档主线是合法状态，绑定命中且标
        // 题对得上就算一致，只在文案里点明归档
        let result = IdentityReconciler.reconcile(input(
            catalog: catalog([row("main-1", archived: true)]),
            gateway: gatewayOK
        ))
        let binding = result.item(.mainBinding)
        XCTAssertEqual(binding?.verdict, .ok)
        XCTAssertTrue(binding?.headline.contains("归档") == true)
    }

    // MARK: - 不一致

    func testBindingMissingFromCatalogIsProblem() {
        let result = IdentityReconciler.reconcile(input(
            catalog: catalog([row("other-1", title: "主线")]),
            gateway: gatewayOK
        ))
        let binding = result.item(.mainBinding)
        XCTAssertEqual(binding?.verdict, .problem)
        XCTAssertTrue(
            binding?.authorityNote?.contains("以服务端目录为准")
                == true
        )
        XCTAssertEqual(result.verdict, .problem)
        XCTAssertEqual(result.groupSummary.failCount, 1)
        // 其余项不被牵连
        XCTAssertEqual(result.item(.routing)?.verdict, .ok)
        XCTAssertEqual(result.item(.catalog)?.verdict, .ok)
    }

    func testBindingTitleChangedIsAttention() {
        let result = IdentityReconciler.reconcile(input(
            catalog: catalog([row("main-1", title: "改过的名字")]),
            gateway: gatewayOK
        ))
        let binding = result.item(.mainBinding)
        XCTAssertEqual(binding?.verdict, .attention)
        XCTAssertTrue(
            binding?.authorityNote?.contains("标题以服务端为准")
                == true
        )
        XCTAssertEqual(result.verdict, .attention)
    }

    func testGatewayStoppedIsProblem() {
        let result = IdentityReconciler.reconcile(input(
            catalog: catalog([row("main-1")]),
            gateway: .init(
                running: false, state: "stopped",
                apiServerState: nil, version: "0.23.0"
            )
        ))
        XCTAssertEqual(result.item(.routing)?.verdict, .problem)
        XCTAssertEqual(result.verdict, .problem)
    }

    func testGatewayRunningButChannelDownIsProblem() {
        let result = IdentityReconciler.reconcile(input(
            catalog: catalog([row("main-1")]),
            gateway: .init(
                running: true, state: "running",
                apiServerState: "disconnected", version: nil
            )
        ))
        XCTAssertEqual(result.item(.routing)?.verdict, .problem)
    }

    func testCatalogMissingMessageCountsIsAttention() {
        let result = IdentityReconciler.reconcile(input(
            catalog: catalog([
                row("main-1"), row("side-1", messages: nil),
            ]),
            gateway: gatewayOK
        ))
        let catalogItem = result.item(.catalog)
        XCTAssertEqual(catalogItem?.verdict, .attention)
        XCTAssertTrue(
            catalogItem?.headline.contains("1 条没报消息数")
                == true
        )
    }

    func testEmptyCatalogIsAttention() {
        let result = IdentityReconciler.reconcile(input(
            bound: nil, catalog: catalog([]), gateway: gatewayOK
        ))
        XCTAssertEqual(result.item(.catalog)?.verdict, .attention)
    }

    func testLocalProjectionDriftIsNoteOnly() {
        // 本地投影条数与刚拉到的不一致只进提示、不
        // 判罪（缓存新旧不是不一致，判据认服务端目录）
        let result = IdentityReconciler.reconcile(input(
            catalog: catalog([row("main-1"), row("side-1")]),
            gateway: gatewayOK, localCount: 5
        ))
        let catalogItem = result.item(.catalog)
        XCTAssertEqual(catalogItem?.verdict, .ok)
        XCTAssertTrue(
            catalogItem?.authorityNote?
                .contains("以刚拉到的服务端目录为准") == true
        )
    }

    // MARK: - 端点缺失（暂无法对账）

    func testNoBindingIsIncomplete() {
        let result = IdentityReconciler.reconcile(input(
            bound: nil,
            catalog: catalog([row("main-1")]),
            gateway: gatewayOK
        ))
        let binding = result.item(.mainBinding)
        XCTAssertEqual(binding?.verdict, .incomplete)
        XCTAssertTrue(
            binding?.headline.contains("还没有主线绑定") == true
        )
        // 绑定项没跑成不拖垮整组判定口径：组取最重
        // 档＝没跑完，其余两项仍是 ok
        XCTAssertEqual(result.item(.routing)?.verdict, .ok)
        XCTAssertEqual(result.item(.catalog)?.verdict, .ok)
        XCTAssertEqual(result.verdict, .incomplete)
    }

    func testCatalogFetchFailedDegradesTwoItems() {
        let result = IdentityReconciler.reconcile(input(
            catalog: nil, gateway: gatewayOK
        ))
        XCTAssertEqual(
            result.item(.mainBinding)?.verdict, .incomplete
        )
        XCTAssertEqual(result.item(.catalog)?.verdict, .incomplete)
        XCTAssertEqual(result.item(.routing)?.verdict, .ok)
        XCTAssertEqual(result.verdict, .incomplete)
    }

    func testCatalogIncompleteDegradesTwoItems() {
        let result = IdentityReconciler.reconcile(input(
            catalog: catalog(
                [row("main-1")], note: "总数对不上（服务端报 5、实拉 3）"
            ),
            gateway: gatewayOK
        ))
        // 目录没拉全时绑定项不许凭半份名单判「不在
        // 目录」——降级不下结论
        XCTAssertEqual(
            result.item(.mainBinding)?.verdict, .incomplete
        )
        XCTAssertEqual(result.item(.catalog)?.verdict, .incomplete)
    }

    func testGatewayMissingIsIncomplete() {
        let result = IdentityReconciler.reconcile(input(
            catalog: catalog([row("main-1")]), gateway: nil
        ))
        XCTAssertEqual(result.item(.routing)?.verdict, .incomplete)
        XCTAssertEqual(result.item(.mainBinding)?.verdict, .ok)
    }

    func testGatewayFieldsTooThinIsIncomplete() {
        // status 应答了但网关字段全缺：不往好处猜
        let result = IdentityReconciler.reconcile(input(
            catalog: catalog([row("main-1")]),
            gateway: .init(
                running: nil, state: nil,
                apiServerState: nil, version: "0.23.0"
            )
        ))
        XCTAssertEqual(result.item(.routing)?.verdict, .incomplete)
    }

    // MARK: - 留痕合成（并入体检四态）

    func testSummaryWithIdentityRoundTrips() throws {
        let summary = HealthCheckSummary(
            date: Date(timeIntervalSince1970: 1_763_000_000),
            serverBase: "https://a.test",
            doctor: HealthGroupSummary(
                verdict: .ok, headline: "自检通过"
            ),
            identity: HealthGroupSummary(
                verdict: .problem, headline: "身份对账发现 1 项对不上",
                passCount: 2, warnCount: 0, failCount: 1
            )
        )
        XCTAssertEqual(summary.overall, .problem)
        XCTAssertEqual(
            summary.headline, "发现 1 项异常，建议处理"
        )
        let data = try JSONEncoder().encode(summary)
        let decoded = try JSONDecoder().decode(
            HealthCheckSummary.self, from: data
        )
        XCTAssertEqual(decoded, summary)
        XCTAssertEqual(decoded.identity?.failCount, 1)
    }

    func testLegacySummaryWithoutIdentityDecodes() throws {
        // H1-d 之前的留痕 JSON 没有 identity 键：解码
        // 回 nil、合成行为与旧版一致
        let legacy = """
        {"date": 763000000, "serverBase": "https://a.test",
         "doctor": {"verdict": "attention",
                    "headline": "自检有 2 项要注意",
                    "warnCount": 2}}
        """
        let decoded = try JSONDecoder().decode(
            HealthCheckSummary.self, from: Data(legacy.utf8)
        )
        XCTAssertNil(decoded.identity)
        XCTAssertEqual(decoded.overall, .attention)
        XCTAssertEqual(
            decoded.headline, "能用，但有 2 项要注意"
        )
    }

    func testIdentityAttentionCountsIntoHeadline() {
        let summary = HealthCheckSummary(
            date: Date(), serverBase: "https://a.test",
            doctor: HealthGroupSummary(
                verdict: .ok, headline: "自检通过"
            ),
            audit: HealthGroupSummary(
                verdict: .ok, headline: "安全审计通过"
            ),
            identity: HealthGroupSummary(
                verdict: .attention,
                headline: "身份对账有 1 项要注意",
                passCount: 2, warnCount: 1, failCount: 0
            )
        )
        XCTAssertEqual(summary.overall, .attention)
        XCTAssertEqual(
            summary.headline, "能用，但有 1 项要注意"
        )
    }
}
