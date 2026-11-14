import XCTest
@testable import OneDayCore

/// §244 对话内授权流的 Core 纯逻辑闸：①ask/notice
/// 载荷解析（残缺载荷不许成卡）②卡过期口径（非终
/// 态 24h、终态不翻）③注册附加面（agentCall 全件
/// 映射＋能力声明）④resume 回执分型（404/409 不当
/// 业务失败）⑤结果摘要（humanSummary 优先、不编话）
final class DevicePermissionFlowTests: XCTestCase {

    // MARK: - ask 解析

    func testAskParseValid() {
        let ask = PermissionAskRequest.parse(arguments: [
            "source": .string("contacts"),
            "tool": .string("contacts_search"),
            "resumeToken": .string("park-0123abcd"),
        ])
        XCTAssertEqual(ask?.source, .contacts)
        XCTAssertEqual(ask?.tool, "contacts_search")
        XCTAssertEqual(ask?.resumeToken, "park-0123abcd")
    }

    func testAskParseRejectsBrokenPayloads() {
        XCTAssertNil(PermissionAskRequest.parse(arguments: [
            "source": .string("contacts"),
            "tool": .string("contacts_search"),
        ]), "缺 token 不成卡")
        XCTAssertNil(PermissionAskRequest.parse(arguments: [
            "source": .string("contacts"),
            "tool": .string("contacts_search"),
            "resumeToken": .string(""),
        ]), "空 token 不成卡")
        XCTAssertNil(PermissionAskRequest.parse(arguments: [
            "source": .string("no_such_source"),
            "tool": .string("contacts_search"),
            "resumeToken": .string("park-0123abcd"),
        ]), "未知数据源不成卡")
    }

    // MARK: - notice 解析与落卡相位

    func testNoticeParseLayersAndPhases() {
        let denied = PermissionNotice.parse(arguments: [
            "source": .string("calendar"),
            "tool": .string("calendar_list_events"),
            "resumeToken": .string("park-aaaa"),
            "blockerLayer": .string("permission"),
            "state": .string("denied"),
            "parkKind": .string("live"),
        ])
        XCTAssertEqual(denied?.layer, .permission)
        XCTAssertEqual(denied?.state, .denied)
        XCTAssertEqual(denied?.initialPhase, .blocked)
        XCTAssertEqual(denied?.isSyncQuery, false)

        let switchOff = PermissionNotice.parse(arguments: [
            "source": .string("clipboard"),
            "tool": .string("clipboard_get"),
            "resumeToken": .string("park-bbbb"),
            "blockerLayer": .string("agentSwitch"),
            "state": .string("granted"),
            "parkKind": .string("live"),
        ])
        XCTAssertEqual(switchOff?.initialPhase, .switchOff)

        let sync = PermissionNotice.parse(arguments: [
            "source": .string("contacts"),
            "tool": .string("contacts_count"),
            "resumeToken": .string("park-ccCC"),
            "blockerLayer": .string("permission"),
            "state": .string("revoked"),
            "parkKind": .string("sync"),
        ])
        XCTAssertEqual(sync?.isSyncQuery, true)
        // revoked 不是 App 侧状态枚举：解析为 nil 不拦卡
        XCTAssertNil(sync?.state)
        XCTAssertEqual(sync?.initialPhase, .blocked)
    }

    func testNoticeParseRejectsMissingLayer() {
        XCTAssertNil(PermissionNotice.parse(arguments: [
            "source": .string("calendar"),
            "tool": .string("calendar_list_events"),
            "resumeToken": .string("park-aaaa"),
        ]))
    }

    // MARK: - 卡过期口径

    func testCardExpiry() {
        let card = PermissionCard(
            id: "park-1", source: .contacts, tool: "contacts_count",
            layer: .permission, isSyncQuery: true, phase: .blocked,
            createdAt: 1_000
        )
        XCTAssertEqual(card.expiresAt, 1_000 + 24 * 3600)
        XCTAssertFalse(card.isExpired(at: 1_000 + 23 * 3600))
        XCTAssertTrue(card.isExpired(at: 1_000 + 25 * 3600))

        var done = card
        done.phase = .done
        XCTAssertFalse(
            done.isExpired(at: 1_000 + 48 * 3600),
            "终态卡不翻过期"
        )
    }

    // MARK: - 注册附加面

    func testRegistrationExtras() {
        let map = DeviceRegistrationExtras.agentCallMap(
            agentCallEnabled: [.contacts: true, .calendar: false]
        )
        XCTAssertEqual(map.count, DeviceSourceID.allCases.count)
        XCTAssertEqual(map["contacts"], true)
        XCTAssertEqual(map["calendar"], false)
        XCTAssertEqual(
            map["health"], false, "未给的件默认关（与既有口径同）"
        )
        XCTAssertEqual(
            DeviceRegistrationExtras.capabilities,
            ["permission_ask_v1"]
        )
    }

    // MARK: - resume 回执分型

    func testResumeOutcomeTyping() {
        XCTAssertEqual(
            PermissionResumeOutcome.from(httpStatus: 404, body: nil),
            .tokenGone
        )
        XCTAssertEqual(
            PermissionResumeOutcome.from(httpStatus: 409, body: nil),
            .offline
        )
        XCTAssertEqual(
            PermissionResumeOutcome.from(
                httpStatus: 200,
                body: .object([
                    "ok": .bool(true),
                    "result": .object(["total": .number(7)]),
                ])
            ),
            .succeeded(result: .object(["total": .number(7)]))
        )
        XCTAssertEqual(
            PermissionResumeOutcome.from(
                httpStatus: 200,
                body: .object([
                    "ok": .bool(false),
                    "error": .string("sync_copy_empty"),
                    "message": .string("副本里还没有数据。"),
                ])
            ),
            .failed(code: "sync_copy_empty", message: "副本里还没有数据。")
        )
        XCTAssertEqual(
            PermissionResumeOutcome.from(httpStatus: 200, body: nil),
            .failed(code: "bad_response", message: nil)
        )
    }

    // MARK: - 结果摘要

    func testResultSummaryPrefersHumanSummary() {
        XCTAssertEqual(
            PermissionResultSummary.line(for: .object([
                "humanSummary": .string("通讯录里共 7 人。"),
            ])),
            "通讯录里共 7 人。"
        )
        XCTAssertEqual(
            PermissionResultSummary.line(for: .object([:])),
            "已办完。"
        )
        XCTAssertEqual(PermissionResultSummary.line(for: nil), "已办完。")
    }
}
